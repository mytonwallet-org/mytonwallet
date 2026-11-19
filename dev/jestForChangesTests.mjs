import assert from 'node:assert/strict';
import test from 'node:test';

import { findUntracedEntries, MAX_RELATED_FILES, pickJestRun } from './jestForChanges.mjs';

const ALWAYS_PRESENT = () => true;

test('code changes run only the related tests', () => {
  const paths = ['src/util/url.ts', 'src/components/ui/Button.tsx', 'dev/ciSettle.mjs', 'docs/guide.md'];
  assert.deepEqual(pickJestRun(paths, ALWAYS_PRESENT), {
    mode: 'related', files: ['src/util/url.ts', 'src/components/ui/Button.tsx', 'dev/ciSettle.mjs'],
  });
});

test('stylesheets, assets and Markdown alone reach no test', () => {
  const paths = [
    'src/components/ui/Button.module.scss', 'src/assets/logo.svg', 'src/styles/font.woff2', 'src/assets/lottie/a.tgs',
    'src/mfa/README.md', 'maestro/a.yaml',
  ];
  assert.deepEqual(pickJestRun(paths, ALWAYS_PRESENT), { mode: 'none' });
});

test('a Playwright spec reaches no Jest test through its data', () => {
  assert.deepEqual(pickJestRun(['tests/playwright/agent-v2/fixtures/a.json'], ALWAYS_PRESENT), { mode: 'none' });
});

for (const path of [
  'package.json', 'package-lock.json', 'jest.config.js', 'babel.config.js', 'tsconfig.json', '.npmrc', '.node-version',
  '.github/workflows/test.yml',
  'tests/init.ts', 'tests/staticFileMock.js', 'patches/a.patch', 'src/lib/tlottie/__mocks__/TLottie.ts',
  'mobile/__mocks__/axios.js', 'dev/locales/buildDefault.js', 'dev/locales/convertI18nYamlToJson.js',
]) {
  test(`a change to ${path} runs every test`, () => {
    assert.deepEqual(pickJestRun(['src/util/url.ts', path], ALWAYS_PRESENT), { mode: 'full', reason: path });
  });
}

for (const path of [
  'src/i18n/en.yaml', 'src/api/agentV2/generated/schema.json', 'src/api/chains/ton/testData/a.json',
  'tests/fixtures/a.json', 'deploy/build_sdk.sh', 'dev/mfa/words.txt',
]) {
  test(`a data file ${path} runs every test`, () => {
    assert.deepEqual(pickJestRun([path], ALWAYS_PRESENT), { mode: 'full', reason: path });
  });
}

test('a deleted module runs every test', () => {
  const run = pickJestRun(['src/util/url.ts', 'src/util/gone.ts'], (path) => path !== 'src/util/gone.ts');
  assert.deepEqual(run, { mode: 'full', reason: 'src/util/gone.ts' });
});

test('an empty or unreadable range runs every test', () => {
  assert.deepEqual(pickJestRun([], ALWAYS_PRESENT), { mode: 'full' });
  assert.deepEqual(pickJestRun(undefined, ALWAYS_PRESENT), { mode: 'full' });
});

test('a change to .browserslistrc runs every test', () => {
  assert.deepEqual(pickJestRun(['.browserslistrc'], ALWAYS_PRESENT), { mode: 'full', reason: '.browserslistrc' });
});

test('too many changed modules run every test', () => {
  const paths = Array.from({ length: MAX_RELATED_FILES + 1 }, (_, index) => `src/util/module${index}.ts`);
  assert.equal(pickJestRun(paths, ALWAYS_PRESENT).mode, 'full');
});

test('the probe sees what every test loads and what a test starts as a child process', () => {
  assert.deepEqual(findUntracedEntries(['tests/initGlobal.ts']), ['tests/init.ts']);
  assert.deepEqual(findUntracedEntries(['src/api/storages/nodeFile.ts']), [
    'src/api/storages/nodeFile.concurrent-writer.js',
  ]);
  assert.deepEqual(findUntracedEntries(['src/util/url.ts']), []);
});
