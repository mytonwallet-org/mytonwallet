import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { applyFileRenamePlan, createFileRenamePlan } from './fixFileNames.mjs';

test('renames a component family and updates module references, styles, scripts, and documentation', async (t) => {
  const root = createProject(t, {
    'src/components/widget-card.tsx': "import styles from './widget-card.module.scss';\n"
      + 'export default function WidgetCard() {}\n',
    'src/components/widget-card.test.tsx': "import Card from './widget-card';\njest.mock('./widget-card');\n",
    'src/components/widget-card.module.scss': '.card { color: red; }\n',
    'src/components/Other.module.scss': '@use "widget-card.module.scss";\n',
    'src/main.ts': [
      "import Card from './components/widget-card';",
      "export { default } from './components/widget-card';",
      "const card = import('./components/widget-card');",
      "const required = require('./components/widget-card');",
      "const resolved = require.resolve('./components/widget-card');",
      "jest.mock('./components/widget-card');",
      "vi.doMock('./components/widget-card');",
      "const actual = jest.requireActual('./components/widget-card');",
      "const url = new URL('./components/widget-card.tsx', import.meta.url);",
      "const contents = fs.readFileSync('src/components/widget-card.tsx');",
      "const fixture = 'src/components/widget-card.tsx';",
      "const label = 'widget-card';",
      "const endpoint = '/widget-card';",
      "const escaped = './components/widget\\u002dcard';",
    ].join('\n'),
    'package.json': JSON.stringify({ scripts: { test: 'jest src/components/widget-card.test.tsx' } }),
    'README.md': 'See [component](src/components/widget-card.tsx).\nhttps://example.com/src/components/widget-card.tsx\n',
  });
  const before = readProject(root);
  const index = readIndex(root);
  const plan = await createFileRenamePlan(root);
  assert.equal(plan.renames.size, 3);
  assert.deepEqual(readProject(root), before, 'planning must not write files');
  applyFileRenamePlan(plan);
  assert.equal(fs.existsSync(path.join(root, 'src/components/widget-card.tsx')), false);
  assert.equal(read(root, 'src/components/WidgetCard.tsx'),
    "import styles from './WidgetCard.module.scss';\nexport default function WidgetCard() {}\n");
  assert.equal(read(root, 'src/components/WidgetCard.test.tsx'),
    "import Card from './WidgetCard';\njest.mock('./WidgetCard');\n");
  assert.equal(read(root, 'src/components/WidgetCard.module.scss'), '.card { color: red; }\n');
  assert.equal(read(root, 'src/components/Other.module.scss'), '@use "WidgetCard.module.scss";\n');
  const code = read(root, 'src/main.ts');
  assert.equal((code.match(/\.\/components\/WidgetCard/g) || []).length, 9);
  assert.ok(code.includes("fs.readFileSync('src/components/WidgetCard.tsx')"));
  assert.ok(code.includes("const fixture = 'src/components/widget-card.tsx'"));
  assert.ok(code.includes("const label = 'widget-card'"));
  assert.ok(code.includes("const endpoint = '/widget-card'"));
  assert.ok(code.includes("const escaped = './components/widget\\u002dcard'"));
  assert.equal(JSON.parse(read(root, 'package.json')).scripts.test, 'jest src/components/WidgetCard.test.tsx');
  assert.equal(read(root, 'README.md'),
    'See [component](src/components/WidgetCard.tsx).\nhttps://example.com/src/components/widget-card.tsx\n');
  assert.equal(readIndex(root), index, 'the command must not stage changes');
  assert.equal((await createFileRenamePlan(root)).renames.size, 0, 'a second run must be a no-op');
});

test('uses ESLint overrides and TypeScript aliases, and leaves same-name files in other directories alone', async (t) => {
  const root = createProject(t, {
    'src/util/request-cache.ts': 'export const cache = {};',
    'src/lib/request-cache.ts': 'export const cache = {};',
    'src/main.ts': "import { cache } from '@util/request-cache';\n"
      + "import { cache as other } from './lib/request-cache';\nimport 'request-cache';\n",
    'tsconfig.json': JSON.stringify({ compilerOptions: { baseUrl: '.', paths: {
      '@util/*': ['src/util/*'], 'request-cache': ['./src/util/request-cache'],
    } } }),
  });
  fs.writeFileSync(path.join(root, 'eslint.config.mjs'), read(root, 'eslint.config.mjs').replace(
    'export default config;',
    "export default [...config, { files: ['src/util/*.ts'], rules: { 'file-naming/case': ['error', 'pascalCase'] } }];",
  ));
  const plan = await createFileRenamePlan(root);
  assert.deepEqual([...plan.renames.values()].map((file) => path.relative(root, file)), ['src/util/RequestCache.ts']);
  applyFileRenamePlan(plan);
  assert.equal(read(root, 'src/main.ts'),
    "import { cache } from '@util/RequestCache';\n"
      + "import { cache as other } from './lib/request-cache';\nimport 'request-cache';\n");
  assert.deepEqual(JSON.parse(read(root, 'tsconfig.json')).compilerOptions.paths['request-cache'], ['./src/util/RequestCache']);
});

test('handles case-only renames, untracked consumers, and ignores deleted paths in the index', async (t) => {
  const root = createProject(t, {
    'src/components/profileCard.tsx': 'export default function ProfileCard() {}',
    'src/util/deleted-file.ts': 'export {};',
  });
  fs.unlinkSync(path.join(root, 'src/util/deleted-file.ts'));
  fs.writeFileSync(path.join(root, 'src/main.ts'), "import Card from './components/profileCard';");
  const plan = await createFileRenamePlan(root);
  applyFileRenamePlan(plan);
  assert.deepEqual(fs.readdirSync(path.join(root, 'src/components')), ['ProfileCard.tsx']);
  assert.equal(read(root, 'src/main.ts'), "import Card from './components/ProfileCard';");
});

test('the CLI previews without writes and applies renames when invoked from a subdirectory', (t) => {
  const root = createProject(t, {
    'src/util/request-cache.ts': 'export const cache = {};',
    'src/main.ts': "import { cache } from './util/request-cache';",
  });
  const script = fileURLToPath(new URL('./fixFileNames.mjs', import.meta.url));
  const before = readProject(root);
  const options = { cwd: path.join(root, 'src'), encoding: 'utf8' };
  const preview = execFileSync(process.execPath, [script, '--dry-run'], options);
  assert.match(preview, /Planned 1 files/);
  assert.deepEqual(readProject(root), before);
  const output = execFileSync(process.execPath, [script], options);
  assert.match(output, /Renamed 1 files/);
  assert.equal(read(root, 'src/main.ts'), "import { cache } from './util/requestCache';");
});

test('rejects conflicting destinations before changing any source or consumer', async (t) => {
  for (const conflicting of ['src/components/WidgetCard.tsx', 'src/components/widget_card.tsx']) {
    const root = createProject(t, {
      'src/components/widget-card.tsx': 'export default function WidgetCard() {}',
      [conflicting]: 'export default function Existing() {}',
      'src/main.ts': "import Card from './components/widget-card';",
    });
    const before = readProject(root);
    await assert.rejects(createFileRenamePlan(root), /collision/);
    assert.deepEqual(readProject(root), before);
  }
});

test('refuses ambiguous names and symbolic-link sources', async (t) => {
  const root = createProject(t, { 'src/util/1request.ts': 'export {};' });
  const before = readProject(root);
  await assert.rejects(createFileRenamePlan(root), /Cannot infer/);
  assert.deepEqual(readProject(root), before);
  fs.unlinkSync(path.join(root, 'src/util/1request.ts'));
  fs.writeFileSync(path.join(root, 'external.ts'), 'export {};');
  fs.symlinkSync(path.join(root, 'external.ts'), path.join(root, 'src/util/request-cache.ts'));
  await assert.rejects(createFileRenamePlan(root), /symbolic link/);
  assert.equal(read(root, 'external.ts'), 'export {};');
});

test('rejects stale plans and destinations created after planning', async (t) => {
  const root = createProject(t, {
    'src/util/request-cache.ts': 'export const value = 1;',
    'src/main.ts': "import { value } from './util/request-cache';",
  });
  const plan = await createFileRenamePlan(root);
  fs.writeFileSync(path.join(root, 'src/main.ts'), '// User edit');
  assert.throws(() => applyFileRenamePlan(plan), /changed while planning/);
  assert.equal(read(root, 'src/main.ts'), '// User edit');
  assert.equal(fs.existsSync(path.join(root, 'src/util/request-cache.ts')), true);
  const nextPlan = await createFileRenamePlan(root);
  fs.writeFileSync(path.join(root, 'src/util/requestCache.ts'), '// User file');
  assert.throws(() => applyFileRenamePlan(nextPlan), /collision/);
  assert.equal(read(root, 'src/util/requestCache.ts'), '// User file');
});

test('restores original names and contents if writing a renamed file fails', async (t) => {
  const root = createProject(t, {
    'src/util/first-value.ts': 'export const first = 1;',
    'src/util/second-value.ts': 'export const second = 2;',
    'src/main.ts': "import { first } from './util/first-value';",
  });
  const before = readProject(root);
  const plan = await createFileRenamePlan(root);
  const writeFileSync = fs.writeFileSync;
  let writes = 0;
  t.mock.method(fs, 'writeFileSync', (...args) => {
    const result = writeFileSync(...args);
    if (typeof args[0] === 'number' && ++writes === 2) throw new Error('Simulated disk failure');
    return result;
  });
  assert.throws(() => applyFileRenamePlan(plan), /Simulated disk failure/);
  assert.deepEqual(readProject(root), before);
});

function createProject(t, files) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'wallet-file-naming-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '--quiet'], { cwd: root });
  const configUrl = new URL('./fileNamingConfig.mjs', import.meta.url).href;
  fs.writeFileSync(path.join(root, 'eslint.config.mjs'),
    `import config from ${JSON.stringify(configUrl)};\nexport default config;\n`);
  for (const [file, content] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.writeFileSync(path.join(root, file), content);
  }
  execFileSync('git', ['add', '.'], { cwd: root });
  return root;
}

function read(root, file) {
  return fs.readFileSync(path.join(root, file), 'utf8');
}

function readIndex(root) {
  return execFileSync('git', ['ls-files', '--stage', '-z'], { cwd: root, encoding: 'utf8' });
}

function readProject(root) {
  const files = fs.readdirSync(root, { recursive: true }).filter((file) =>
    !file.startsWith('.git') && fs.lstatSync(path.join(root, file)).isFile());
  return Object.fromEntries(files.sort().map((file) => [file, read(root, file)]));
}
