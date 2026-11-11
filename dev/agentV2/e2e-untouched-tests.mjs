import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(new URL('./e2e-untouched.sh', import.meta.url));
// Run from a git hook, the inherited GIT_DIR would point every command below at this repository
const GIT_ENV = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));

const INITIAL_TREE = {
  'src/components/agent/X.tsx': 'export {};\n',
  'README.md': '# Fixture\n',
};

// [changes, exit code]; `null` deletes a file
const CASES = {
  settings: [{ 'src/components/settings/X.tsx': '\n' }, 0],
  'settings container': [{ 'src/components/settings/Settings.tsx': '\n' }, 1],
  'appearance settings': [{ 'src/components/settings/SettingsAppearance.tsx': '\n' }, 1],
  'settings header': [{ 'src/components/settings/SettingsHeader.tsx': '\n' }, 1],
  'settings styles': [{ 'src/components/settings/Settings.module.scss': '\n' }, 1],
  agentV2: [{ 'src/components/agentV2/X.tsx': '\n' }, 1],
  ui: [{ 'src/components/ui/X.tsx': '\n' }, 1],
  main: [{ 'src/components/main/X.tsx': '\n' }, 1],
  app: [{ 'src/components/App.tsx': '\n' }, 1],
  receive: [{ 'src/components/receive/X.tsx': '\n' }, 1],
  common: [{ 'src/components/common/X.tsx': '\n' }, 1],
  'non-English locale': [{ 'src/i18n/ru.yaml': '\n' }, 0],
  'English locale': [{ 'src/i18n/en.yaml': '\n' }, 1],
  'iOS workflow': [{ '.github/workflows/ios-tests.yml': '\n' }, 0],
  'test workflow': [{ '.github/workflows/test.yml': '\n' }, 1],
  'unrelated dev script': [{ 'dev/mfa/x.sh': '\n' }, 0],
  'environment loader': [{ 'dev/loadEnv.ts': '\n' }, 1],
  'build stamp': [{ 'dev/buildStamp.ts': '\n' }, 1],
  'Agent dev script': [{ 'dev/agentV2/x.sh': '\n' }, 1],
  'locale dev script': [{ 'dev/locales/x.js': '\n' }, 1],
  'unrelated deploy script': [{ 'deploy/x.sh': '\n' }, 0],
  'dist copy script': [{ 'deploy/copy_to_dist.sh': '\n' }, 1],
  api: [{ 'src/api/x.ts': '\n' }, 1],
  global: [{ 'src/global/x.ts': '\n' }, 1],
  dependencies: [{ 'package-lock.json': '{}\n' }, 1],
  plugin: [{ 'plugins/x.ts': '\n' }, 1],
  'native and shared sources': [{ 'mobile/x.swift': '\n', 'src/util/x.ts': '\n' }, 1],
  'native sources only': [{ 'mobile/y.swift': '\n' }, 0],
  'native E2E flows': [{
    'maestro/ios/x.yaml': '\n',
    'maestro/scripts/x.js': '\n',
    'maestro/panel/package.json': '{}\n',
    'maestro/WRITING_FLOWS.md': '\n',
  }, 0],
  'agent skills': [{ '.agents/skills/x/SKILL.md': '\n', '.claude/commands/x.md': '\n', 'AGENTS.md': '\n' }, 0],
  'maestro lookalike': [{ 'maestrox/x.yaml': '\n' }, 1],
  'native E2E flows and shared sources': [{ 'maestro/android/x.yaml': '\n', 'src/util/y.ts': '\n' }, 1],
  'root markdown': [{ 'README.md': '# Updated fixture\n' }, 0],
  'unknown nested markdown': [{ 'src/unknown/notes.md': '\n' }, 1],
  'deleted agent component': [{ 'src/components/agent/X.tsx': null }, 1],
};

test('only proven unrelated paths skip Agent E2E', (t) => {
  const repo = createRepo(t);
  let base = repo.base;
  for (const [name, [changes, expected]] of Object.entries(CASES)) {
    const head = repo.commit(changes);
    assert.equal(run(repo.root, base, head), expected, name);
    base = head;
  }
});

test('an unknown base and an empty diff run Agent E2E', (t) => {
  const repo = createRepo(t);
  const head = repo.commit({ 'README.md': '# Updated fixture\n' });
  assert.equal(run(repo.root, '0'.repeat(40), head), 1, 'unknown base');
  assert.equal(run(repo.root, head, head), 1, 'empty diff');
});

function run(cwd, ...args) {
  return spawnSync('bash', [SCRIPT, ...args], { cwd, env: GIT_ENV }).status;
}

function createRepo(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-e2e-untouched-'));
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
