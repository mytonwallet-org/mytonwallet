#!/usr/bin/env node

/**
 * Local bundle size comparison with a base branch, the way `.github/workflows/bundle-stats.yml` does it:
 *
 *   1. Build the base branch in a temporary git worktree with `npm run build:stats`, which writes its stats
 *      as a baseline. The worktree reuses `node_modules` when `package-lock.json` is the same.
 *   2. Build the current branch against that baseline, which adds the HTML comparison report.
 *   3. Print the diff as the PR comment shows it.
 *
 * Usage:
 *   node dev/analyzeBundleSize.mjs [options]
 *
 * Options:
 *   --branch <name>        Base branch to compare against (default: master)
 *   --skip-master-build    Reuse the baseline from the previous run
 *   --open                 Open the HTML comparison report in the browser
 *   -h, --help
 */

import { execFileSync, spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

import { createCommentBody } from './createBundleStatsComment.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REFERENCE_FILE = path.join(ROOT, 'bundle-stats-reference.json');
const CURRENT_STATS = path.join(ROOT, 'dist/bundle-stats/baseline.json');
const REPORT_FILE = path.join(ROOT, 'dist/bundle-stats/bundle-stats.html');

const args = process.argv.slice(2);

// Supports `npm run analyze:bundle -- --flag`, and `npm run analyze:bundle --flag` which npm passes as
// `npm_config_flag`
function hasFlag(name) {
  return args.includes(`--${name}`) || process.env[`npm_config_${name.replace(/-/g, '_')}`] !== undefined;
}

function getArg(name) {
  const index = args.indexOf(`--${name}`);
  if (index !== -1) return args[index + 1];
  return process.env[`npm_config_${name.replace(/-/g, '_')}`] || undefined;
}

if (hasFlag('help') || args.includes('-h')) {
  console.log(`
Usage: node dev/analyzeBundleSize.mjs [options]

Options:
  --branch <name>        Base branch to compare against (default: master)
  --skip-master-build    Reuse ${path.basename(REFERENCE_FILE)} from the previous run
  --open                 Open the HTML comparison report in the browser
  -h, --help             Show this help

Examples:
  npm run analyze:bundle
  npm run analyze:bundle --branch origin/master
  npm run analyze:bundle --skip-master-build --open
  `);
  process.exit(0);
}

const baseBranch = getArg('branch') ?? 'master';

if (!hasFlag('skip-master-build')) {
  buildReference(baseBranch);
} else if (!fs.existsSync(REFERENCE_FILE)) {
  console.error(`× ${REFERENCE_FILE} not found. Run without --skip-master-build first.`);
  process.exit(1);
}

console.log('\nBuilding the current branch...');
execFileSync('npm', ['run', 'build:stats'], {
  cwd: ROOT,
  stdio: 'inherit',
  env: { ...process.env, BUNDLE_STATS_BASELINE_PATH: REFERENCE_FILE },
});

console.log(`\n${createCommentBody({ baselineStatsPath: REFERENCE_FILE, currentStatsPath: CURRENT_STATS, reportUrl: '' })}\n`);

if (hasFlag('open')) {
  const opener = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
  spawnSync(opener, [REPORT_FILE], { stdio: 'inherit', shell: process.platform === 'win32' });
}

function buildReference(branch) {
  console.log(`\nBuilding ${branch}...`);
  const ref = execFileSync('git', ['rev-parse', '--verify', branch], { cwd: ROOT, encoding: 'utf8' }).trim();
  const worktreeDir = path.join(os.tmpdir(), `mtw-bundle-stats-ref-${Date.now()}`);
  const worktreeNodeModules = path.join(worktreeDir, 'node_modules');

  try {
    execFileSync('git', ['worktree', 'add', '--detach', worktreeDir, ref], { cwd: ROOT, stdio: 'inherit' });

    const isLockfileSame = spawnSync('git', ['diff', '--quiet', ref, '--', 'package-lock.json'], { cwd: ROOT })
      .status === 0;
    if (isLockfileSame) {
      fs.symlinkSync(path.join(ROOT, 'node_modules'), worktreeNodeModules);
    } else {
      console.warn('package-lock.json differs, installing dependencies in the worktree...');
      execFileSync('npm', ['ci', '--prefer-offline'], { cwd: worktreeDir, stdio: 'inherit' });
    }

    execFileSync('npm', ['run', 'build:stats'], { cwd: worktreeDir, stdio: 'inherit' });
    fs.copyFileSync(path.join(worktreeDir, 'dist/bundle-stats/baseline.json'), REFERENCE_FILE);
  } finally {
    if (fs.lstatSync(worktreeNodeModules, { throwIfNoEntry: false })?.isSymbolicLink()) {
      fs.unlinkSync(worktreeNodeModules);
    }
    spawnSync('git', ['worktree', 'remove', '--force', worktreeDir], { cwd: ROOT, stdio: 'inherit' });
  }
}
