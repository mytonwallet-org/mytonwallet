import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(new URL('./web-untouched.sh', import.meta.url));
const NETLIFY_SCRIPT = fileURLToPath(new URL('./netlify-ignore.sh', import.meta.url));

// Run from a git hook, the inherited GIT_DIR would point every command below at this repository
const GIT_ENV = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));

const INITIAL_TREE = {
  'src/index.ts': 'export {};\n',
  'docs/guide.md': '# Guide\n',
  'mobile/android/App.kt': 'class App\n',
  '.github/workflows/test.yml': 'name: Test\n',
  'README.md': '# Readme\n',
};

// [changes, exit code for netlify, exit code for actions]; `null` deletes a file
const CASES = {
  'docs only': [{ 'docs/guide.md': '# Guide v2\n' }, 0, 0],
  'native sources only': [{ 'mobile/android/App.kt': 'class App2\n' }, 0, 0],
  'agent tooling only': [{ '.agents/skills/x/SKILL.md': 'x\n', '.claude/commands/x.md': 'x\n' }, 0, 0],
  'root markdown only': [{ 'README.md': '# Readme v2\n' }, 0, 0],
  'a workflow': [{ '.github/workflows/test.yml': 'name: Test 2\n' }, 0, 1],
  'web sources': [{ 'src/index.ts': 'export const a = 1;\n' }, 1, 1],
  'docs together with web sources': [{ 'docs/guide.md': '# Guide v2\n', 'src/index.ts': 'export const a = 1;\n' }, 1, 1],
  'markdown inside src': [{ 'src/notes.md': 'x\n' }, 1, 1],
  'a new root file': [{ 'netlify.toml': '[build]\n' }, 1, 1],
  'a deleted web source': [{ 'src/index.ts': null }, 1, 1],
  'a web source moved into docs': [{ 'src/index.ts': null, 'docs/index.ts': 'export {};\n' }, 1, 1],
};

// Every extension eslint, stylelint and jest pick up, each placed where a Netlify build may skip it
const TOOLED_FILES = [
  'docs/a.js', 'docs/a.mjs', 'docs/a.cjs', 'docs/a.jsx', 'docs/a.mjsx',
  'mobile/a.ts', 'mobile/a.mts', 'mobile/a.cts', 'mobile/a.tsx', 'mobile/a.mtsx',
  '.agents/a.css', '.claude/a.scss',
];

const SKIPPABLE_DIRS = ['mobile', 'docs', '.agents', '.claude', '.codex', '.cursor', '.github'];

for (const [name, [changes, netlify, actions]] of Object.entries(CASES)) {
  test(`a change to ${name} exits ${netlify} for netlify and ${actions} for actions`, (t) => {
    const repo = createRepo(t);
    const head = repo.commit(changes);
    assert.equal(run(repo.root, 'netlify', repo.base, head), netlify);
    assert.equal(run(repo.root, 'actions', repo.base, head), actions);
  });
}

test('a script or stylesheet outside src skips only the Netlify build', (t) => {
  const repo = createRepo(t);
  let previous = repo.base;
  for (const file of TOOLED_FILES) {
    const head = repo.commit({ [file]: '\n' });
    assert.equal(run(repo.root, 'netlify', previous, head), 0, file);
    assert.equal(run(repo.root, 'actions', previous, head), 1, file);
    previous = head;
  }
});

test('a directory that only starts like a skippable one runs everything', (t) => {
  const repo = createRepo(t);
  let previous = repo.base;
  for (const dir of SKIPPABLE_DIRS) {
    const head = repo.commit({ [`${dir}-site/notes.md`]: 'x\n' });
    assert.equal(run(repo.root, 'netlify', previous, head), 1, dir);
    assert.equal(run(repo.root, 'actions', previous, head), 1, dir);
    previous = head;
  }
});

test('a range it cannot read runs everything', (t) => {
  const repo = createRepo(t);
  const head = repo.commit({ 'docs/guide.md': '# Guide v2\n' });
  assert.equal(run(repo.root, 'netlify', repo.base, head), 0, 'the docs-only range itself must be skippable');

  for (const scope of ['netlify', 'actions']) {
    assert.equal(run(repo.root, scope, head, head), 1, 'same revision on both ends');
    assert.equal(run(repo.root, scope, '', head), 1, 'empty base');
    assert.equal(run(repo.root, scope, '0'.repeat(40), head), 1, 'base missing from the clone');
    assert.equal(run(repo.root, scope, repo.base, ''), 1, 'empty head');
  }
  assert.equal(run(repo.root, 'web', repo.base, head), 1, 'unknown scope');
  assert.equal(run(repo.root), 1, 'no arguments');
});

test('the Netlify ignore command cancels only a deploy preview of an untouched range', (t) => {
  const repo = createRepo(t);
  const docs = repo.commit({ 'docs/guide.md': '# Guide v2\n' });
  const web = repo.commit({ 'src/index.ts': 'export const a = 1;\n' });
  const ignore = (env) => spawnSync('bash', [NETLIFY_SCRIPT], { cwd: repo.root, env: { ...GIT_ENV, ...env } }).status;

  assert.equal(ignore({ CONTEXT: 'deploy-preview', CACHED_COMMIT_REF: repo.base, COMMIT_REF: docs }), 0);
  assert.equal(ignore({ CONTEXT: 'deploy-preview', CACHED_COMMIT_REF: docs, COMMIT_REF: web }), 1);
  assert.equal(ignore({ CONTEXT: 'deploy-preview', CACHED_COMMIT_REF: docs, COMMIT_REF: docs }), 1, 'no build cache');
  assert.equal(ignore({ CONTEXT: 'deploy-preview', COMMIT_REF: docs }), 1, 'no cached revision');
  for (const context of ['production', 'branch-deploy', '']) {
    assert.equal(ignore({ CONTEXT: context, CACHED_COMMIT_REF: repo.base, COMMIT_REF: docs }), 1, `${context} context`);
  }
});

function run(cwd, ...args) {
  return spawnSync('bash', [SCRIPT, ...args], { cwd, env: GIT_ENV }).status;
}

function createRepo(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'web-untouched-'));
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
