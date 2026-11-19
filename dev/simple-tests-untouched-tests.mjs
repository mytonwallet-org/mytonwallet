import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(new URL('./simple-tests-untouched.sh', import.meta.url));
const ROOT = fileURLToPath(new URL('../', import.meta.url));

// Run from a git hook, the inherited GIT_DIR would point every command below at this repository
const GIT_ENV = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));

const INITIAL_TREE = {
  'src/index.ts': 'export {};\n',
  'README.md': '# Readme\n',
};

// Paths from the pull requests and pushes the Simple tests job ran for nothing
const SKIPPED_PATHS = [
  'maestro/android/cases/send/ton_intercepted.yaml',
  'maestro/android/scripts/guard_baseline.js',
  'mobile/android/app/src/main/java/App.kt',
  'mobile/ios/Air/SubModules/WalletCore/Bridge.ts',
  'docs/technical/agent.md',
  'changelogs/26.11.4.txt',
  '.agents/skills/maestro-e2e/SKILL.md',
  '.husky/pre-commit',
  '.milkignore',
  'netlify.toml',
  'AGENTS.md',
  '.github/workflows/android-e2e.yml',
  '.github/CODEOWNERS',
  'dev/e2eQueue.mjs',
  'dev/bugReport/core/render.mjs',
  'deploy/ios_sign/sign_ipa.sh',
  'deploy/gram-release.md',
  'docs/notes with spaces [draft].md',
];

const RUN_PATHS = [
  'src/util/url.ts',
  'src/i18n/en.yaml',
  'tests/playwright/agent-v2/conversation.spec.ts',
  'plugins/langPacks.ts',
  'public/manifest.json',
  'patches/a.patch',
  'vite.config.ts',
  'package-lock.json',
  'eslint.config.mjs',
  'mobile/ios/Air/web/style.css',
  'maestro/scripts/report.test.js',
  'maestro/scripts/test.js',
  'dev/foo/spec.ts',
  'deploy/build_sdk.test.ts',
  'deploy/report_sdk_assets.mjs',
  'deploy/build_sdk.sh',
  'deploy/copy_to_dist.sh',
  '.agents/skills/x/run.mjs',
  'docs/example.ts',
  '.husky/check.js',
  'docs/a.mjsx',
  'mobile/__mocks__/axios.js',
  'maestro/__mocks__/axios.js',
  'docs/__mocks__/axios.json',
  '.github/__mocks__/axios.js',
  'dev/mfa/mnemonic.ts',
  'dev/locales/buildDefault.js',
  'dev/agentV2/e2e-untouched.sh',
  'dev/gramReleaseDispatchTests.mjs',
  'dev/loadEnv.ts',
  'dev/fileNamingPlugin.mjs',
  'dev/broadcastGuard.mjs',
  'dev/ciSettle.mjs',
  'dev/web-untouched.sh',
  'dev/simple-tests-untouched.sh',
  'dev/jestForChanges.mjs',
  '.github/workflows/test.yml',
  '.github/workflows/ios-signing-expiry-backstop.yml',
  '.github/ci-settle.json',
  'newRootFile.json',
  'tools/script.py',
];

for (const file of SKIPPED_PATHS) {
  test(`a change to ${file} alone skips Simple tests`, (t) => {
    const repo = createRepo(t);
    assert.equal(run(repo.root, repo.base, repo.commit({ [file]: 'x\n' })), 0);
  });
}

for (const file of RUN_PATHS) {
  test(`a change to ${file} runs Simple tests`, (t) => {
    const repo = createRepo(t);
    assert.equal(run(repo.root, repo.base, repo.commit({ [file]: 'x\n', 'docs/guide.md': 'x\n' })), 1);
  });
}

test('a web source moved into a skipped directory runs Simple tests', (t) => {
  const repo = createRepo(t);
  assert.equal(run(repo.root, repo.base, repo.commit({ 'src/index.ts': null, 'docs/index.ts': 'export {};\n' })), 1);
});

test('a range it cannot read runs Simple tests', (t) => {
  const repo = createRepo(t);
  const head = repo.commit({ 'docs/guide.md': '# Guide v2\n' });
  assert.equal(run(repo.root, repo.base, head), 0, 'the docs-only range itself must be skippable');
  assert.equal(run(repo.root, head, head), 1, 'same revision on both ends');
  assert.equal(run(repo.root, '', head), 1, 'empty base');
  assert.equal(run(repo.root, '0'.repeat(40), head), 1, 'base missing from the clone');
  assert.equal(run(repo.root, repo.base, ''), 1, 'empty head');
  assert.equal(run(repo.root), 1, 'no arguments');
});

test('every `dev/` file the job runs is a path that runs Simple tests', (t) => {
  for (const file of listJobDevPaths()) {
    const repo = createRepo(t);
    assert.equal(run(repo.root, repo.base, repo.commit({ [file]: `${file}\n` })), 1, file);
  }
});

// Follows the job's `run:` lines through the npm scripts they call
function listJobDevPaths() {
  const workflow = fs.readFileSync(path.join(ROOT, '.github/workflows/test.yml'), 'utf8');
  const job = workflow.split(/^  test:$/m)[1].split(/^  [\w-]+:$/m)[0];
  const { scripts } = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  const paths = new Set();
  const seen = new Set();
  const visit = (command) => {
    for (const [, file] of command.matchAll(/\b(dev\/[\w./-]+\.\w+)/g)) paths.add(file);
    for (const [, runName, testName] of command.matchAll(/\bnpm (?:run (\S+)|(test)\b)/g)) {
      const name = runName ?? testName;
      if (scripts[name] && !seen.has(name)) {
        seen.add(name);
        visit(scripts[name]);
      }
    }
  };
  visit(job);
  assert.ok(paths.size > 5, 'the job must be found and run `dev/` files');
  return [...paths];
}

function run(cwd, ...args) {
  return spawnSync('bash', [SCRIPT, ...args], { cwd, env: GIT_ENV }).status;
}

function createRepo(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'simple-tests-untouched-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env: GIT_ENV, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Test');
  git('config', 'user.email', 'test@example.com');
  git('config', 'commit.gpgsign', 'false');

  const commit = (changes) => {
    for (const [file, contents] of Object.entries(changes)) {
      const target = path.join(root, file);
      if (contents === null) {
        fs.rmSync(target);
      } else {
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, contents);
      }
    }
    git('add', '-A');
    git('commit', '-q', '-m', 'change');
    return git('rev-parse', 'HEAD');
  };

  return { root, base: commit(INITIAL_TREE), commit };
}
