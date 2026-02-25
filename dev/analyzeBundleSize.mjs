#!/usr/bin/env node

/**
 * Local bundle size comparison vs master branch.
 * Replicates the statoscope CI pipeline from .github/workflows/statoscope.yml:
 *
 *   1. Build current branch  → dist/statoscope-build-statistics.json  (input)
 *   2. Build base branch     → statoscope-reference.json              (reference)
 *      Uses git worktree + node_modules symlink to avoid touching the working tree.
 *   3. Compute size diff directly from webpack stats JSON (asset sizes)
 *   4. Run statoscope validate  (mirrors CI's `npm run statoscope:validate-diff`)
 *   5. Print diff in PR-comment style
 *
 * Usage:
 *   node dev/analyzeBundleSize.mjs [options]
 *
 * Options:
 *   --branch <name>        Base branch to compare against (default: master)
 *   --skip-current-build   Reuse existing dist/statoscope-build-statistics.json
 *   --skip-master-build    Reuse existing statoscope-reference.json
 *   --compressed           Use gzip sizes (matches CI PR comment numbers)
 *   --open                 Open statoscope HTML report in browser
 *   -h, --help
 */

import { execSync, spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist');

const STATS_FILENAME = 'statoscope-build-statistics.json';
const CURRENT_STATS = path.join(DIST, STATS_FILENAME);
const REFERENCE_FILE = path.join(ROOT, 'statoscope-reference.json');
const REPORT_FILE = path.join(DIST, 'statoscope-report.html');

const args = process.argv.slice(2);

// Support both:
//   node dev/analyzeBundleSize.mjs --flag        (direct)
//   npm run analyze:bundle -- --flag             (npm with separator)
//   npm run analyze:bundle --flag                (npm without separator, sets npm_config_flag)
function hasFlag(name) {
  return args.includes(`--${name}`) || process.env[`npm_config_${name.replace(/-/g, '_')}`] !== undefined;
}
function getArg(name) {
  const idx = args.indexOf(`--${name}`);
  if (idx !== -1) return args[idx + 1];
  return process.env[`npm_config_${name.replace(/-/g, '_')}`] || undefined;
}

const shouldSkipCurrentBuild = hasFlag('skip-current-build');
const shouldSkipMasterBuild = hasFlag('skip-master-build');
const shouldOpen = hasFlag('open');
const shouldShowHelp = hasFlag('help') || args.includes('-h');
const useCompressed = hasFlag('compressed');
const baseBranch = getArg('branch') ?? 'master';

if (shouldShowHelp) {
  console.log(`
Usage: node dev/analyzeBundleSize.mjs [options]

Options:
  --branch <name>        Base branch to compare against (default: master)
  --skip-current-build   Reuse existing dist/${STATS_FILENAME}
  --skip-master-build    Reuse existing statoscope-reference.json
  --compressed           Use gzip sizes (matches CI PR comment numbers)
  --open                 Open statoscope HTML report in browser
  -h, --help             Show this help

Examples (npm):
  npm run analyze:bundle
  npm run analyze:bundle --compressed
  npm run analyze:bundle --skip-master-build
  npm run analyze:bundle --skip-master-build --compressed
  npm run analyze:bundle --branch origin/master
  npm run analyze:bundle --skip-current-build --skip-master-build --open

Examples (node):
  node dev/analyzeBundleSize.mjs
  node dev/analyzeBundleSize.mjs --branch origin/master --compressed
  node dev/analyzeBundleSize.mjs --skip-master-build --compressed
  `);
  process.exit(0);
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function run(cmd, opts = {}) {
  return execSync(cmd, { cwd: ROOT, stdio: 'inherit', ...opts });
}

function capture(cmd, opts = {}) {
  return execSync(cmd, { cwd: ROOT, encoding: 'utf-8', stdio: ['inherit', 'pipe', 'pipe'], ...opts }).trim();
}

function formatBytes(bytes) {
  if (bytes == null || isNaN(bytes)) return 'n/a';
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${bytes} B`;
}

function formatDiff(before, after) {
  if (before == null || after == null) return '⚪  n/a';
  const diff = after - before;
  const pct = before > 0 ? ((diff / before) * 100).toFixed(2) : '∞';
  const sign = diff >= 0 ? '+' : '';
  const icon = diff > 0.01 * before ? '🔴' : diff < -0.01 * before ? '🟢' : '⚪';
  return `${icon} ${sign}${formatBytes(diff)} (${sign}${pct}%)`;
}

/**
 * Reads gzip sizes from the @statoscope/stats-extension-compressed payload.
 * Returns a Map<filename, gzipSize> or null if the extension is absent.
 *
 * Stats format:
 *   raw.__statoscope.extensions[n]
 *     .descriptor.name === '@statoscope/stats-extension-compressed'
 *     .payload.compilations[0].resources[].{ id, size.size }
 */
function readGzipMap(statsPath) {
  const raw = JSON.parse(fs.readFileSync(statsPath, 'utf-8'));
  const extensions = raw?.__statoscope?.extensions;
  if (!extensions) return null;

  const compressedExt = Object.values(extensions).find(
    (e) => e?.descriptor?.name === '@statoscope/stats-extension-compressed',
  );
  if (!compressedExt) return null;

  const gzipMap = new Map();
  for (const comp of compressedExt.payload?.compilations ?? []) {
    for (const resource of comp.resources ?? []) {
      if (resource.id && resource.size?.size != null) {
        gzipMap.set(resource.id, resource.size.size);
      }
    }
  }
  return gzipMap.size > 0 ? gzipMap : null;
}

/**
 * Parses a statoscope/webpack stats JSON and returns bundle size metrics.
 *
 * Uses asset.size (actual output file size on disk) rather than chunk.size
 * (which is the unminified module source size, not useful for comparison).
 *
 * initialSize    = sum of sizes of assets belonging to initial chunks
 * totalSize      = sum of sizes of all emitted assets (.js + .css)
 * entryPoints    = per-entry-point sizes from compilation.entrypoints
 *
 * When compressed=true, substitutes raw sizes with gzip sizes from the
 * @statoscope/stats-extension-compressed extension (matches CI PR comment).
 */
function parseStats(statsPath, { compressed = false } = {}) {
  const raw = JSON.parse(fs.readFileSync(statsPath, 'utf-8'));
  const compilation = raw.compilations?.[0] ?? raw;

  const gzipMap = compressed ? readGzipMap(statsPath) : null;
  if (compressed && !gzipMap) {
    console.warn('  ⚠️   Gzip data not found in stats — falling back to raw sizes.');
  }

  // Build a map: filename → size (raw or gzip)
  const assetSizeMap = new Map();
  for (const asset of compilation.assets ?? []) {
    const size = gzipMap?.get(asset.name) ?? asset.size ?? 0;
    assetSizeMap.set(asset.name, size);
  }

  // Initial chunk files
  const initialFiles = new Set();
  for (const chunk of compilation.chunks ?? []) {
    if (chunk.initial) {
      for (const file of chunk.files ?? []) initialFiles.add(file);
    }
  }

  let initialSize = 0;
  let totalSize = 0;

  for (const [name, size] of assetSizeMap) {
    if (!name.endsWith('.js') && !name.endsWith('.css')) continue;
    totalSize += size;
    if (initialFiles.has(name)) initialSize += size;
  }

  // Per-entry-point sizes: sum of all assets belonging to each named entry.
  // compilation.entrypoints maps entry name → { assets: [{name, size}] }
  const entryPoints = new Map();
  for (const [entryName, group] of Object.entries(compilation.entrypoints ?? {})) {
    let entrySize = 0;
    for (const assetInfo of group.assets ?? []) {
      const assetName = typeof assetInfo === 'string' ? assetInfo : assetInfo.name;
      if (!assetName.endsWith('.js') && !assetName.endsWith('.css')) continue;
      entrySize += assetSizeMap.get(assetName) ?? 0;
    }
    entryPoints.set(entryName, entrySize);
  }

  // Top assets by size (js only)
  const jsAssets = [...assetSizeMap.entries()]
    .filter(([n]) => n.endsWith('.js'))
    .map(([name, size]) => ({ name, size }))
    .sort((a, b) => b.size - a.size);

  return { initialSize, totalSize, jsAssets, entryPoints };
}

function sep(char = '─', len = 70) {
  return char.repeat(len);
}

// ─── Step 1: Build current branch ────────────────────────────────────────────

if (!shouldSkipCurrentBuild) {
  console.log(`\n${sep('═')}`);
  console.log('  STEP 1/3  Building current branch…');
  console.log(sep('═'));

  try {
    run('npx webpack', { env: { ...process.env, IS_STATOSCOPE: '1' } });
  } catch {
    console.error('\n❌  Current branch build failed.');
    process.exit(1);
  }
} else {
  console.log('\n⏭   Skipping current branch build (--skip-current-build)');
}

if (!fs.existsSync(CURRENT_STATS)) {
  console.error(`\n❌  Stats file not found: ${CURRENT_STATS}`);
  console.error('    Run without --skip-current-build first.');
  process.exit(1);
}

// ─── Step 2: Build base branch via git worktree ──────────────────────────────

if (!shouldSkipMasterBuild) {
  console.log(`\n${sep('═')}`);
  console.log(`  STEP 2/3  Building ${baseBranch}…`);
  console.log(sep('═'));

  let resolvedRef;
  try {
    resolvedRef = capture(`git rev-parse --verify ${baseBranch}`);
  } catch {
    console.error(`\n❌  Cannot resolve branch: ${baseBranch}`);
    console.error('    Try: --branch origin/master');
    process.exit(1);
  }

  const worktreeDir = path.join(os.tmpdir(), `mtw-statoscope-ref-${Date.now()}`);
  const worktreeNodeModules = path.join(worktreeDir, 'node_modules');
  const worktreeDist = path.join(worktreeDir, 'dist');
  let usedSymlink = false;

  try {
    console.log(`\n  git worktree → ${worktreeDir}`);
    run(`git worktree add --detach "${worktreeDir}" ${resolvedRef}`);

    // Check if node_modules can be safely symlinked
    const packageLockDiff = spawnSync(
      'git', ['diff', '--quiet', resolvedRef, '--', 'package-lock.json'],
      { cwd: ROOT },
    );
    const packageLockDiffers = packageLockDiff.status !== 0;

    if (packageLockDiffers) {
      console.warn('\n  ⚠️   package-lock.json differs — running npm ci in worktree…');
      run('npm ci --prefer-offline', { cwd: worktreeDir });
    } else {
      console.log('  node_modules unchanged — symlinking…');
      fs.symlinkSync(path.join(ROOT, 'node_modules'), worktreeNodeModules);
      usedSymlink = true;
    }

    run('npx webpack', {
      cwd: worktreeDir,
      env: { ...process.env, IS_STATOSCOPE: '1' },
    });

    fs.copyFileSync(path.join(worktreeDist, STATS_FILENAME), REFERENCE_FILE);
    console.log(`\n✅  Reference stats saved → ${path.relative(ROOT, REFERENCE_FILE)}`);
  } finally {
    try {
      if (usedSymlink && fs.existsSync(worktreeNodeModules)) {
        fs.unlinkSync(worktreeNodeModules);
      }
      run(`git worktree remove --force "${worktreeDir}"`);
    } catch {
      console.warn('  ⚠️   Could not clean up worktree. Run: git worktree prune');
    }
  }
} else {
  console.log('\n⏭   Skipping base branch build (--skip-master-build)');
  if (!fs.existsSync(REFERENCE_FILE)) {
    console.error(`\n❌  Reference file not found: ${REFERENCE_FILE}`);
    console.error('    Run without --skip-master-build first.');
    process.exit(1);
  }
}

// ─── Step 3: Compare ─────────────────────────────────────────────────────────

console.log(`\n${sep('═')}`);
console.log('  STEP 3/3  Comparing…');
console.log(sep('═'));

const current = parseStats(CURRENT_STATS, { compressed: useCompressed });
const reference = parseStats(REFERENCE_FILE, { compressed: useCompressed });

// Run statoscope validate (mirrors CI's `npm run statoscope:validate-diff`)
// Rename files to match the CI convention expected by validate
const INPUT_FILE = path.join(ROOT, 'input.json');
const REF_COPY = path.join(ROOT, 'reference.json');
fs.copyFileSync(CURRENT_STATS, INPUT_FILE);
fs.copyFileSync(REFERENCE_FILE, REF_COPY);

const validateResult = spawnSync(
  'npx',
  ['--no-install', 'statoscope', 'validate', '--input', INPUT_FILE, '--reference', REF_COPY],
  { cwd: ROOT, stdio: 'inherit', shell: true },
);
const validationPassed = validateResult.status === 0;

fs.unlinkSync(INPUT_FILE);
fs.unlinkSync(REF_COPY);

// ─── Output ──────────────────────────────────────────────────────────────────

const currentBranch = (() => {
  try { return capture('git rev-parse --abbrev-ref HEAD'); } catch { return 'current'; }
})();

const sizeLabel = useCompressed ? 'gzip' : 'raw';

console.log(`\n${sep('═')}`);
console.log(`  📦  STATOSCOPE BUNDLE DIFF  (${sizeLabel})`);
console.log(`  ${currentBranch}  vs  ${baseBranch}`);
console.log(sep('═'));

// ─── Per-entry-point table ────────────────────────────────────────────────────

const COL_NAME = 28;
const COL_SIZE = 12;
const COL_DIFF = 26;

function tableRow(name, before, after) {
  const nameCol = name.length > COL_NAME ? '…' + name.slice(-(COL_NAME - 1)) : name;
  const beforeCol = formatBytes(before).padStart(COL_SIZE);
  const afterCol = formatBytes(after).padStart(COL_SIZE);
  const diffCol = formatDiff(before, after);
  return `  ${nameCol.padEnd(COL_NAME)}  ${beforeCol}  ${afterCol}  ${diffCol}`;
}

const tableHeader = `  ${'Entry point'.padEnd(COL_NAME)}  ${'Before'.padStart(COL_SIZE)}  ${'After'.padStart(COL_SIZE)}  Diff`;

console.log(`\n${tableHeader}`);
console.log(`  ${sep('─', COL_NAME + COL_SIZE * 2 + COL_DIFF + 6)}`);

// Collect all entry point names from both builds
const allEntries = new Set([...current.entryPoints.keys(), ...reference.entryPoints.keys()]);
for (const name of [...allEntries].sort()) {
  const before = reference.entryPoints.get(name) ?? null;
  const after = current.entryPoints.get(name) ?? null;
  console.log(tableRow(name, before, after));
}

console.log(`  ${sep('─', COL_NAME + COL_SIZE * 2 + COL_DIFF + 6)}`);
console.log(tableRow('TOTAL initial', reference.initialSize, current.initialSize));
console.log(tableRow('TOTAL bundle', reference.totalSize, current.totalSize));

console.log(`\n  🕵️  Validation: ${validationPassed ? '✅  passed' : '❌  FAILED (see output above)'}`);

console.log(`\n${sep('═')}\n`);

if (shouldOpen && fs.existsSync(REPORT_FILE)) {
  console.log('🌐  Opening statoscope report…');
  const openCmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
  run(`${openCmd} "${REPORT_FILE}"`);
} else if (shouldOpen) {
  console.warn(`⚠️   Report not found: ${REPORT_FILE}`);
}
