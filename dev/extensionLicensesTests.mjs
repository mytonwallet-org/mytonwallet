import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const PROJECT_ROOT = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(import.meta.url);
const PACKAGE = require('webextension-polyfill/package.json');
const BUILD_SCRIPT = `
  require('@babel/register')({ extensions: ['.js', '.ts', '.tsx'] });
  const webpack = require('webpack');
  const config = require('./webpack.config.ts').default({}, { mode: 'production' });
  config.entry = { main: require.resolve('webextension-polyfill') };
  config.output = { path: process.env.LICENSE_TEST_OUTPUT, filename: 'main.js' };
  config.plugins = config.plugins.filter(plugin =>
    ['CopyPlugin', 'BannerPlugin'].includes(plugin.constructor.name));
  webpack(config, (error, stats) => {
    if (error || stats.hasErrors()) {
      console.error(error || stats.toString({ all: false, errors: true }));
      process.exitCode = 1;
    }
  });
`;

for (const [target, flags] of [
  ['Chrome', {}],
  ['Firefox', { IS_FIREFOX_EXTENSION: '1' }],
  ['Firefox staging', { IS_FIREFOX_EXTENSION: '1', APP_ENV: 'staging' }],
  ['Opera', { IS_OPERA_EXTENSION: '1' }],
  ['Gram', { IS_GRAM_WALLET: '1' }],
]) {
  test(`${target} extension distributes the installed polyfill license and readable source`, (context) => {
    const output = buildAssets(context, { IS_EXTENSION: '1', ...flags });
    const notice = readFileSync(path.join(output, 'THIRD_PARTY_NOTICES.txt'), 'utf8');
    assert.ok(notice.includes(`webextension-polyfill ${PACKAGE.version}`));
    assert.ok(notice.includes(`https://github.com/mozilla/webextension-polyfill/tree/${PACKAGE.version}`));
    assert.ok(notice.includes("The application's license does not restrict your rights"));
    assert.ok(!notice.includes('{{VERSION}}'));
    assert.match(readBundleNotices(output), /see THIRD_PARTY_NOTICES\.txt/);

    for (const filename of ['LICENSE', 'dist/browser-polyfill.js', 'dist/browser-polyfill.js.map']) {
      assert.deepEqual(
        readFileSync(path.join(output, 'third-party-licenses/webextension-polyfill', path.basename(filename))),
        readFileSync(require.resolve(`webextension-polyfill/${filename}`)),
      );
    }
  });
}

test('ordinary web builds omit extension-specific notices and source copies', (context) => {
  const output = buildAssets(context, {});
  assert.equal(existsSync(path.join(output, 'THIRD_PARTY_NOTICES.txt')), false);
  assert.equal(existsSync(path.join(output, 'third-party-licenses')), false);
  assert.doesNotMatch(readBundleNotices(output), /see THIRD_PARTY_NOTICES\.txt/);
});

function readBundleNotices(output) {
  const bundle = readFileSync(path.join(output, 'main.js'), 'utf8');
  const licenseReference = bundle.match(/For license information please see ([^\s]+\.LICENSE\.txt)/);
  return licenseReference
    ? `${bundle}\n${readFileSync(path.join(output, licenseReference[1]), 'utf8')}`
    : bundle;
}

function buildAssets(context, flags) {
  const output = mkdtempSync(path.join(os.tmpdir(), 'extension-licenses-'));
  context.after(() => rmSync(output, { recursive: true, force: true }));
  execFileSync(process.execPath, ['-e', BUILD_SCRIPT], {
    cwd: PROJECT_ROOT,
    env: {
      ...process.env,
      APP_ENV: 'production',
      IS_EXTENSION: '',
      IS_FIREFOX_EXTENSION: '',
      IS_OPERA_EXTENSION: '',
      IS_GRAM_WALLET: '',
      LICENSE_TEST_OUTPUT: output,
      ...flags,
    },
    stdio: 'pipe',
    timeout: 60000,
  });
  return output;
}
