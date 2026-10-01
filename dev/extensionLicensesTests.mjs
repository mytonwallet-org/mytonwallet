import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const PROJECT_ROOT = fileURLToPath(new URL('../', import.meta.url));
const VITE_BIN = path.join(PROJECT_ROOT, 'node_modules/vite/bin/vite.js');
const BUILD_TIMEOUT = 180000;
const require = createRequire(import.meta.url);
const PACKAGE = require('webextension-polyfill/package.json');

for (const [target, flags] of [
  ['Chrome', {}],
  ['Firefox', { IS_FIREFOX_EXTENSION: '1' }],
  ['Firefox staging', { IS_FIREFOX_EXTENSION: '1', APP_ENV: 'staging' }],
  ['Opera', { IS_OPERA_EXTENSION: '1' }],
  ['Gram', { IS_GRAM_WALLET: '1' }],
]) {
  test(`${target} extension distributes the installed polyfill license and readable source`, (context) => {
    const output = build(context, { IS_EXTENSION: '1', ...flags });
    const notice = readFileSync(path.join(output, 'THIRD_PARTY_NOTICES.txt'), 'utf8');
    assert.ok(notice.includes(`webextension-polyfill ${PACKAGE.version}`));
    assert.ok(notice.includes(`https://github.com/mozilla/webextension-polyfill/tree/${PACKAGE.version}`));
    assert.ok(notice.includes("The application's license does not restrict your rights"));
    assert.ok(!notice.includes('{{VERSION}}'));

    const scripts = listScripts(output);
    assert.ok(scripts.includes('extensionServiceWorker.js'));
    for (const script of scripts) {
      assert.match(readFileSync(path.join(output, script), 'utf8'), /see THIRD_PARTY_NOTICES\.txt/, script);
    }

    for (const filename of ['LICENSE', 'dist/browser-polyfill.js', 'dist/browser-polyfill.js.map']) {
      assert.deepEqual(
        readFileSync(path.join(output, 'third-party-licenses/webextension-polyfill', path.basename(filename))),
        readFileSync(require.resolve(`webextension-polyfill/${filename}`)),
      );
    }
  });
}

test('ordinary web builds omit extension-specific notices and source copies', (context) => {
  const output = build(context, {});
  assert.equal(existsSync(path.join(output, 'THIRD_PARTY_NOTICES.txt')), false);
  assert.equal(existsSync(path.join(output, 'third-party-licenses')), false);
  for (const script of listScripts(output)) {
    assert.doesNotMatch(readFileSync(path.join(output, script), 'utf8'), /see THIRD_PARTY_NOTICES\.txt/, script);
  }
});

function listScripts(output) {
  return readdirSync(output).filter((filename) => filename.endsWith('.js'));
}

function build(context, flags) {
  const output = mkdtempSync(path.join(os.tmpdir(), 'extension-licenses-'));
  context.after(() => rmSync(output, { recursive: true, force: true }));
  execFileSync(process.execPath, [VITE_BIN, 'build', '--outDir', output, '--logLevel', 'error'], {
    cwd: PROJECT_ROOT,
    env: {
      ...process.env,
      APP_ENV: 'production',
      IS_EXTENSION: '',
      IS_FIREFOX_EXTENSION: '',
      IS_OPERA_EXTENSION: '',
      IS_GRAM_WALLET: '',
      ...flags,
    },
    stdio: 'pipe',
    timeout: BUILD_TIMEOUT,
  });
  return output;
}
