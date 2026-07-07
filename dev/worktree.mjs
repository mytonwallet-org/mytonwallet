#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const optionsWithValues = new Set(['--base', '--branch', '--path']);
const defaultBranchPrefix = 'ios/';

function getPositionals() {
  const positionals = [];

  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];

    if (optionsWithValues.has(value)) {
      index += 1;
      continue;
    }

    if (value.startsWith('-')) {
      continue;
    }

    positionals.push(value);
  }

  return positionals;
}

const positionals = getPositionals();

function printHelp() {
  console.log(`
Usage:
  node dev/worktree.mjs new <name> [options]
  node dev/worktree.mjs add <ref> [options]
  node dev/worktree.mjs prep [path] [options]
  node dev/worktree.mjs list

Commands:
  new <name>    Fetch origin/master and create an ios/<name> branch.
  add <ref>     Create a worktree from an existing branch/ref.
  prep [path]   Link shared node_modules, copy .env if needed, and run iOS prep.
  list          Show registered git worktrees.

Options:
  --base <ref>             Base ref for "new" (default: origin/master).
  --branch <name>          Branch name for "add".
  --path <name-or-path>    Worktree path or name under worktrees/.
  --detach                 Create detached worktree for "add".
  --no-fetch               Skip fetch before "new".
  --no-prep                Create/add worktree without running prep.
  --deps-only              For "prep", only link node_modules and copy .env.
  --own-node-modules       Do not create a shared node_modules symlink.
  --allow-deps-drift       Allow package files to differ from the deps host.
  -h, --help               Show this help.

Environment:
  MTW_SHARED_NODE_MODULES  Override shared node_modules path.
`);
}

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function hasFlag(name) {
  return args.includes(`--${name}`);
}

function getArg(name) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) {
    return undefined;
  }
  const value = args[index + 1];
  if (!value || value.startsWith('-')) {
    fail(`--${name} requires a value`);
  }
  return value;
}

function runGit(gitArgs, options = {}) {
  return execFileSync('git', gitArgs, {
    cwd: options.cwd ?? process.cwd(),
    encoding: options.encoding ?? 'utf8',
    stdio: options.stdio ?? ['inherit', 'pipe', 'pipe'],
  }).trim();
}

function run(command, commandArgs, cwd) {
  const result = spawnSync(command, commandArgs, {
    cwd,
    env: { ...process.env },
    stdio: 'inherit',
  });

  if (result.error) {
    fail(result.error.message);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function parseWorktreeList(output) {
  const worktrees = [];
  let current = null;

  for (const line of output.split('\n')) {
    if (line.startsWith('worktree ')) {
      current = { path: line.slice('worktree '.length) };
      worktrees.push(current);
      continue;
    }

    if (!current) {
      continue;
    }

    if (line.startsWith('branch ')) {
      current.branch = line.slice('branch '.length);
    } else if (line.startsWith('HEAD ')) {
      current.head = line.slice('HEAD '.length);
    } else if (line === 'detached') {
      current.detached = true;
    } else if (line === 'bare') {
      current.bare = true;
    }
  }

  return worktrees;
}

function getCurrentRoot() {
  try {
    return runGit(['rev-parse', '--show-toplevel']);
  } catch {
    fail('run this from inside the repository');
  }
}

function getHostRoot(currentRoot) {
  const output = runGit(['worktree', 'list', '--porcelain'], { cwd: currentRoot });
  const worktrees = parseWorktreeList(output);
  const mainWorktree = worktrees.find((worktree) => {
    try {
      return fs.statSync(path.join(worktree.path, '.git')).isDirectory();
    } catch {
      return false;
    }
  });

  return mainWorktree?.path ?? currentRoot;
}

const currentRoot = getCurrentRoot();
const hostRoot = getHostRoot(currentRoot);
const worktreesDir = path.join(hostRoot, 'worktrees');
const sharedNodeModules = path.resolve(
  process.env.MTW_SHARED_NODE_MODULES ?? path.join(hostRoot, 'node_modules'),
);

function resolveWorktreePath(input) {
  if (!input) {
    fail('worktree path is required');
  }

  if (path.isAbsolute(input) || input.includes('/')) {
    return path.resolve(input);
  }

  return path.join(worktreesDir, input);
}

function pathNameForBranch(branch) {
  return branch
    .replace(/^refs\/heads\//, '')
    .replace(/^origin\//, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizeBranchName(input) {
  const branchName = input
    .replace(/^refs\/heads\//, '')
    .replace(/^origin\//, '');

  if (branchName.startsWith(defaultBranchPrefix)) {
    return branchName;
  }

  if (branchName.startsWith('codex/')) {
    return `${defaultBranchPrefix}${branchName.slice('codex/'.length)}`;
  }

  return `${defaultBranchPrefix}${branchName}`;
}

function worktreeNameForBranch(branch) {
  const branchName = branch.startsWith(defaultBranchPrefix)
    ? branch.slice(defaultBranchPrefix.length)
    : branch;

  return pathNameForBranch(branchName);
}

function ensureWorktreesDir() {
  fs.mkdirSync(worktreesDir, { recursive: true });
}

function hashFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return 'missing';
  }

  return crypto
    .createHash('sha256')
    .update(fs.readFileSync(filePath))
    .digest('hex');
}

function dependencySignature(root) {
  const files = ['package.json', 'package-lock.json', '.npmrc', '.node-version'];
  return Object.fromEntries(files.map((fileName) => [fileName, hashFile(path.join(root, fileName))]));
}

function assertDependencyFilesMatch(targetRoot) {
  if (hasFlag('allow-deps-drift') || hasFlag('own-node-modules')) {
    return;
  }

  const hostSignature = dependencySignature(hostRoot);
  const targetSignature = dependencySignature(targetRoot);
  const changedFiles = Object.keys(hostSignature).filter(
    (fileName) => hostSignature[fileName] !== targetSignature[fileName],
  );

  if (!changedFiles.length) {
    return;
  }

  fail([
    `dependency files differ from deps host ${hostRoot}:`,
    ...changedFiles.map((fileName) => `  - ${fileName}`),
    '',
    'Use --allow-deps-drift for read-only/review work with shared node_modules,',
    'or --own-node-modules when this worktree needs its own npm install.',
  ].join('\n'));
}

function linkNodeModules(targetRoot) {
  if (hasFlag('own-node-modules')) {
    console.log('Skipping shared node_modules symlink (--own-node-modules).');
    return;
  }

  if (!fs.existsSync(sharedNodeModules)) {
    fail(`shared node_modules not found at ${sharedNodeModules}`);
  }

  const targetNodeModules = path.join(targetRoot, 'node_modules');

  if (path.resolve(targetNodeModules) === sharedNodeModules) {
    return;
  }

  if (fs.existsSync(targetNodeModules)) {
    const stat = fs.lstatSync(targetNodeModules);
    if (!stat.isSymbolicLink()) {
      fail(`${targetNodeModules} already exists and is not a symlink`);
    }

    const currentTarget = path.resolve(targetRoot, fs.readlinkSync(targetNodeModules));
    if (currentTarget !== sharedNodeModules) {
      fail(`${targetNodeModules} points to ${currentTarget}, expected ${sharedNodeModules}`);
    }

    return;
  }

  fs.symlinkSync(sharedNodeModules, targetNodeModules, 'dir');
  console.log(`Linked node_modules -> ${sharedNodeModules}`);
}

function copyEnv(targetRoot) {
  const source = path.join(hostRoot, '.env');
  const destination = path.join(targetRoot, '.env');

  if (!fs.existsSync(source) || fs.existsSync(destination)) {
    return;
  }

  fs.copyFileSync(source, destination);
  console.log('Copied .env from deps host.');
}

function runWithEnv(command, commandArgs, cwd, extraEnv) {
  const result = spawnSync(command, commandArgs, {
    cwd,
    env: { ...process.env, ...extraEnv },
    stdio: 'inherit',
  });

  if (result.error) {
    fail(result.error.message);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function prepIos(targetRoot) {
  assertDependencyFilesMatch(targetRoot);
  linkNodeModules(targetRoot);
  copyEnv(targetRoot);

  if (hasFlag('deps-only')) {
    return;
  }

  runWithEnv('npm', ['run', 'mobile:build:dev'], targetRoot, { CAP_PLATFORM: 'ios' });
}

function createNewWorktree() {
  const inputBranch = positionals[1];
  if (!inputBranch || inputBranch.startsWith('-')) {
    fail('new requires a branch name');
  }

  const branch = normalizeBranchName(inputBranch);
  const base = getArg('base') ?? 'origin/master';
  const targetPath = resolveWorktreePath(getArg('path') ?? worktreeNameForBranch(branch));

  ensureWorktreesDir();

  if (!hasFlag('no-fetch')) {
    run('git', ['fetch', 'origin', 'master:refs/remotes/origin/master'], hostRoot);
  }

  run('git', ['worktree', 'add', '-b', branch, targetPath, base], hostRoot);

  if (!hasFlag('no-prep')) {
    prepIos(targetPath);
  }

  console.log(`Worktree ready: ${targetPath}`);
}

function addWorktree() {
  const ref = positionals[1];
  if (!ref || ref.startsWith('-')) {
    fail('add requires a branch or ref');
  }

  const rawBranch = getArg('branch');
  const branch = rawBranch ? normalizeBranchName(rawBranch) : undefined;
  const detach = hasFlag('detach');
  const targetPath = resolveWorktreePath(getArg('path') ?? (branch ? worktreeNameForBranch(branch) : pathNameForBranch(ref)));

  if (branch && detach) {
    fail('--branch and --detach cannot be used together');
  }

  ensureWorktreesDir();

  const worktreeArgs = ['worktree', 'add'];
  if (branch) {
    worktreeArgs.push('-b', branch);
  }
  if (detach) {
    worktreeArgs.push('--detach');
  }
  worktreeArgs.push(targetPath, ref);

  run('git', worktreeArgs, hostRoot);

  if (!hasFlag('no-prep')) {
    prepIos(targetPath);
  }

  console.log(`Worktree ready: ${targetPath}`);
}

function prepExistingWorktree() {
  const inputPath = positionals[1];
  const targetRoot = inputPath ? resolveWorktreePath(inputPath) : currentRoot;

  if (!fs.existsSync(path.join(targetRoot, 'package.json'))) {
    fail(`not a repo root: ${targetRoot}`);
  }

  prepIos(targetRoot);
  console.log(`Worktree prepared: ${targetRoot}`);
}

function listWorktrees() {
  run('git', ['worktree', 'list'], hostRoot);
}

if (hasFlag('help') || args.includes('-h') || args.length === 0) {
  printHelp();
  process.exit(0);
}

const command = positionals[0];

switch (command) {
  case 'new':
    createNewWorktree();
    break;
  case 'add':
    addWorktree();
    break;
  case 'prep':
    prepExistingWorktree();
    break;
  case 'list':
    listWorktrees();
    break;
  default:
    fail(`unknown command "${command}"`);
}
