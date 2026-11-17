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

// [changes, exit code of `pr`, exit code of `master`]; `null` deletes a file
const CASES = {
  'Agent component': [{ 'src/components/agent/Y.tsx': '\n' }, 1, 1],
  agentV2: [{ 'src/components/agentV2/X.tsx': '\n' }, 1, 1],
  'Agent API': [{ 'src/api/agentV2/runtime.ts': '\n' }, 1, 1],
  'Agent global state': [{ 'src/global/agentV2/x.ts': '\n' }, 1, 1],
  'Agent util': [{ 'src/util/agentV2Updates.ts': '\n' }, 1, 1],
  'Agent unit test': [{ 'src/components/agentV2/X.test.tsx': '\n', 'src/api/agentV2/x.test.ts': '\n' }, 0, 0],
  'Agent notes': [{ 'src/components/agent/AGENTS.md': '\n' }, 0, 0],
  suite: [{ 'tests/playwright/agent-v2/x.spec.ts': '\n' }, 1, 1],
  'suite test file': [{ 'tests/playwright/agent-v2/x.test.ts': '\n' }, 1, 1],
  'suite notes': [{ 'tests/playwright/agent-v2/README.md': '\n' }, 1, 1],
  'suite config': [{ 'playwright.agent-v2.config.ts': '\n' }, 1, 1],
  'Agent dev script': [{ 'dev/agentV2/x.sh': '\n' }, 1, 1],
  'suite workflow': [{ '.github/workflows/agent-v2-e2e.yml': '\n' }, 1, 1],
  'test workflow': [{ '.github/workflows/test.yml': '\n' }, 0, 0],
  dependencies: [{ 'package-lock.json': '{}\n' }, 1, 1],
  'Vite config': [{ 'vite.config.ts': '\n' }, 1, 1],
  plugin: [{ 'plugins/x.ts': '\n' }, 1, 1],
  patch: [{ 'patches/x.patch': '\n' }, 1, 1],
  'dist copy script': [{ 'deploy/copy_to_dist.sh': '\n' }, 1, 1],
  'environment loader': [{ 'dev/loadEnv.ts': '\n' }, 1, 1],
  'locale dev script': [{ 'dev/locales/x.js': '\n' }, 1, 1],
  'app entry': [{ 'src/index.tsx': '\n' }, 1, 1],
  app: [{ 'src/components/App.tsx': '\n' }, 0, 1],
  ui: [{ 'src/components/ui/X.tsx': '\n' }, 0, 1],
  main: [{ 'src/components/main/X.tsx': '\n' }, 0, 1],
  receive: [{ 'src/components/receive/X.tsx': '\n' }, 0, 1],
  common: [{ 'src/components/common/X.tsx': '\n' }, 0, 1],
  'settings container': [{ 'src/components/settings/Settings.tsx': '\n' }, 0, 1],
  'settings styles': [{ 'src/components/settings/Settings.module.scss': '\n' }, 0, 1],
  settings: [{ 'src/components/settings/X.tsx': '\n' }, 0, 0],
  global: [{ 'src/global/x.ts': '\n' }, 0, 1],
  util: [{ 'src/util/x.ts': '\n' }, 0, 1],
  api: [{ 'src/api/x.ts': '\n' }, 0, 1],
  styles: [{ 'src/styles/x.scss': '\n' }, 0, 1],
  config: [{ 'src/config.ts': '\n' }, 1, 1],
  'fetch logging': [{ 'src/util/fetchLogging.ts': '\n' }, 1, 1],
  'public asset': [{ 'public/x.txt': '\n' }, 1, 1],
  'source asset': [{ 'src/assets/x.svg': '\n' }, 0, 1],
  'quoted path': [{ 'src/x"y.ts': '\n' }, 1, 1],
  'English locale': [{ 'src/i18n/en.yaml': '\n' }, 0, 1],
  'non-English locale': [{ 'src/i18n/ru.yaml': '\n' }, 0, 0],
  'shared unit test': [{ 'src/util/x.test.ts': '\n' }, 0, 0],
  'other screen': [{ 'src/components/swap/X.tsx': '\n' }, 0, 0],
  'Web E2E suite': [{ 'tests/playwright/web/x.spec.ts': '\n' }, 0, 0],
  'native sources': [{ 'mobile/y.swift': '\n' }, 0, 0],
  'native E2E flows': [{ 'maestro/ios/x.yaml': '\n', 'maestro/scripts/x.js': '\n' }, 0, 0],
  'other workflow': [{ '.github/workflows/ios-tests.yml': '\n' }, 0, 0],
  'unrelated dev script': [{ 'dev/mfa/x.sh': '\n' }, 0, 0],
  'root markdown': [{ 'README.md': '# Updated fixture\n' }, 0, 0],
  'native and Agent sources': [{ 'mobile/x.swift': '\n', 'src/components/agentV2/Z.tsx': '\n' }, 1, 1],
  'deleted Agent component': [{ 'src/components/agent/X.tsx': null }, 1, 1],
};

test('each mode runs Agent E2E only for the paths it covers', (t) => {
  const repo = createRepo(t);
  let base = repo.base;
  for (const [name, [changes, prExpected, masterExpected]] of Object.entries(CASES)) {
    const head = repo.commit(changes);
    assert.equal(run(repo.root, 'pr', base, head), prExpected, `pr: ${name}`);
    assert.equal(run(repo.root, 'master', base, head), masterExpected, `master: ${name}`);
    base = head;
  }
});

test('an unknown base, an empty diff and an unknown mode run Agent E2E', (t) => {
  const repo = createRepo(t);
  const head = repo.commit({ 'README.md': '# Updated fixture\n' });
  assert.equal(run(repo.root, 'pr', '0'.repeat(40), head), 1, 'unknown base');
  assert.equal(run(repo.root, 'pr', head, head), 1, 'empty diff');
  assert.equal(run(repo.root, 'push', repo.base, head), 1, 'unknown mode');
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
