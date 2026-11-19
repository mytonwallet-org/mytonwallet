import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// These shape every test run, so a change to them can break a test that imports nothing they changed
const FULL_RUN_PATTERN = new RegExp([
  '^package(-lock)?\\.json$',
  '^jest\\.config\\.js$',
  '^babel\\.config\\.js$',
  '^\\.browserslistrc$',
  '^tsconfig\\.json$',
  '^\\.npmrc$',
  '^\\.node-version$',
  '^\\.github/workflows/test\\.yml$',
  '^tests/init\\.ts$',
  '^tests/staticFileMock\\.js$',
  // The job builds the default translations with these before Jest, and tests import only the output
  '^dev/locales/(?:buildDefault|convertI18nYamlToJson)\\.js$',
  '^patches/',
  '(?:^|/)__mocks__/',
].join('|'));
const CODE_PATTERN = /\.(?:[cm]?[jt]sx?)$/;
// Jest stubs the assets, and no test reads Markdown
const STUBBED_PATTERN = /\.(?:css|scss|svg|png|jpe?g|gif|webp|eot|otf|ttf|woff2?|mp4|webm|wav|mp3|m4a|aac|oga|tgs|md)$/;
const DATA_ROOT_PATTERN = /^(?:src|deploy|dev\/mfa|tests(?!\/playwright))\//;
// Keeps the file list well under the argument size limit of a single command
export const MAX_RELATED_FILES = 500;
// Scripts a test starts as a child process, which Jest's import graph does not follow
const SPAWNED_SCRIPTS = {
  'src/api/storages/nodeFile.concurrent-writer.js': 'src/api/storages/nodeFile.concurrent.test.ts',
};
const ROOT = fileURLToPath(new URL('../', import.meta.url));
const SETUP_FILES = (createRequire(import.meta.url)('../jest.config.js').setupFilesAfterEnv ?? [])
  .map((file) => path.relative(ROOT, path.resolve(ROOT, file.replace('<rootDir>', '.'))));
// Nothing imports a mock, so a module it imports reaches tests only through the mock
const MOCK_FILES = execFileSync('git', ['ls-files', '-z', '--', ':(glob)**/__mocks__/**'], { cwd: ROOT, encoding: 'utf8' })
  .split('\0').filter((file) => CODE_PATTERN.test(file));
const UNTRACED_ENTRIES = [...SETUP_FILES, ...MOCK_FILES, ...Object.keys(SPAWNED_SCRIPTS)];

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [base, head] = process.argv.slice(2);
  process.exit(runJest(listChangedPaths(base, head)));
}

function runJest(paths) {
  const run = pickJestRun(paths, (file) => existsSync(path.join(ROOT, file)));
  if (run.mode === 'related') {
    const untraced = findUntracedEntries(run.files);
    if (!untraced) {
      run.mode = 'full';
      run.reason = 'an unreadable import graph';
    } else if (untraced.some((file) => !SPAWNED_SCRIPTS[file])) {
      run.mode = 'full';
      run.reason = 'a module the Jest setup or a mock loads';
    } else {
      run.files.push(...untraced.map((file) => SPAWNED_SCRIPTS[file]));
    }
  }
  if (run.mode === 'none') {
    console.log('No changed module can reach a Jest test');
    return 0;
  }
  const args = run.mode === 'related' ? ['--findRelatedTests', '--passWithNoTests', ...run.files] : [];
  console.log(run.mode === 'related'
    ? `Running the Jest tests related to ${run.files.length} changed module(s)`
    : `Running every Jest test${run.reason ? ` because of ${run.reason}` : ''}`);
  const { status } = spawnSync('npm', ['test', '--', ...args], { cwd: ROOT, stdio: 'inherit' });
  return status ?? 1;
}

// `--findRelatedTests` traces only test files, so the setup files, mocks and spawned scripts stand in for them.
// Returns the entries the files reach, or nothing when that cannot be told.
export function findUntracedEntries(files) {
  if (!UNTRACED_ENTRIES.every((file) => existsSync(path.join(ROOT, file)))) {
    return undefined;
  }
  const { status, stdout } = spawnSync('npx', [
    '--no-install', 'jest', '--listTests', '--json', '--findRelatedTests', ...files,
    '--testMatch', ...UNTRACED_ENTRIES.map((file) => `<rootDir>/${file}`),
  ], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], env: { ...process.env, APP_ENV: 'test' } });
  if (status !== 0) {
    return undefined;
  }
  try {
    return JSON.parse(stdout).map((file) => path.relative(ROOT, file));
  } catch {
    return undefined;
  }
}

export function pickJestRun(paths, isPresent) {
  // With no readable range every test runs
  if (!paths?.length) {
    return { mode: 'full' };
  }
  const files = [];
  for (const file of paths) {
    if (FULL_RUN_PATTERN.test(file)) {
      return { mode: 'full', reason: file };
    }
    if (CODE_PATTERN.test(file)) {
      // Jest cannot trace the importers of a deleted module
      if (!isPresent(file)) {
        return { mode: 'full', reason: file };
      }
      files.push(file);
      if (files.length > MAX_RELATED_FILES) {
        return { mode: 'full', reason: `more than ${MAX_RELATED_FILES} changed modules` };
      }
    } else if (DATA_ROOT_PATTERN.test(file) && !STUBBED_PATTERN.test(file)) {
      // Locales, fixtures and scripts reach tests outside the import graph
      return { mode: 'full', reason: file };
    }
  }
  return files.length ? { mode: 'related', files } : { mode: 'none' };
}

function listChangedPaths(base, head) {
  try {
    const output = execFileSync('git', ['diff', '-z', '--name-only', '--no-renames', base, head], {
      cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'],
    });
    return output.split('\0').filter(Boolean);
  } catch {
    return [];
  }
}
