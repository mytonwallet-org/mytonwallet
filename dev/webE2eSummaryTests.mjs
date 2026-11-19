import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { buildJobSummary } from './webE2eSummary.mjs';

const SOURCE_URL = 'https://github.com/mytonwallet-org/mytonwallet-dev/blob/abc/tests/playwright/web';
const TIMEOUT_MESSAGE = '\u001b[31mError: locator.click: Test timeout of 90000ms exceeded.\u001b[39m\n'
  + 'Call log:\n  - waiting for getByTestId(\'send_button\')\n\n  1 | code frame';

test('failed, skipped and flaky cases are listed in full and passed ones are folded', () => {
  const summary = buildJobSummary(buildReport(), { project: 'mobile-chromium' });

  assert.match(summary, /^### 🔴 mobile-chromium: 1 failed, 1 flaky, 2 skipped, 1 passed · 1m 05s$/m);
  const failedAt = summary.indexOf('**🔴 Failed: 1**');
  const skippedAt = summary.indexOf('**⚪ Skipped: 2**');
  const flakyAt = summary.indexOf('**🟡 Flaky, passed on a retry: 1**');
  const passedAt = summary.indexOf('<details><summary>🟢 Passed: 1</summary>');
  assert.ok(failedAt > 0 && failedAt < skippedAt && skippedAt < flakyAt && flakyAt < passedAt);
  assert.ok(summary.indexOf('Home — balance shows') > passedAt);
  assert.ok(summary.indexOf('</details>') > summary.indexOf('Home — balance shows'));
});

test('a failure keeps the first line of its last error and the element it waited for', () => {
  const summary = buildJobSummary(buildReport(), { project: 'mobile-chromium' });

  assert.match(summary, /\| send \| Send — sends \| locator\.click: Test timeout of 90000ms exceeded\. · - waiting for getByTestId\('send_button'\) \|/);
  assert.doesNotMatch(summary, /code frame|\u001b/);
});

test('a skip names its reason, and a case behind a failed setup reads as not run', () => {
  const summary = buildJobSummary(buildReport(), { project: 'mobile-chromium' });

  assert.match(summary, /\| send \| Send — tops up \| Skipped: Wallet cannot pay \|/);
  assert.match(summary, /\| wallets \| Wallets — renames \| Not run: a setup it needs failed or the run stopped \|/);
});

test('a flaky case shows its first failure', () => {
  const summary = buildJobSummary(buildReport(), { project: 'mobile-chromium' });

  assert.match(summary, /\| settings \| Settings — dark theme \| expect\(locator\)\.toBeVisible\(\) failed · Locator: getByTestId\('theme'\) \|/);
});

test('an interrupted case and a fixme one name why they did not finish', () => {
  const report = buildReport();
  report.suites.push(
    buildSuite('send/itShouldSwap.spec.ts', 'Send — swaps', 'skipped', [{ status: 'interrupted' }]),
    buildSuite('send/itShouldBurn.spec.ts', 'Send — burns', 'skipped', [{ status: 'skipped' }], [{ type: 'fixme' }]),
  );
  const summary = buildJobSummary(report, { project: 'mobile-chromium' });

  assert.match(summary, /\| send \| Send — swaps \| Interrupted \|/);
  assert.match(summary, /\| send \| Send — burns \| Fixme \|/);
});

test('a wallet job hides the error texts and skip descriptions, which may quote its pages', () => {
  const report = buildReport();
  report.errors = [{ message: 'Error: page showed something' }];
  const summary = buildJobSummary(report, { project: 'testnet-mobile-chromium', noReasons: true });

  assert.doesNotMatch(summary, /locator\.click|toBeVisible|Wallet cannot pay|page showed/);
  assert.match(summary, /\| send \| Send — sends \| Hidden in a wallet job \|/);
  assert.match(summary, /\| send \| Send — tops up \| Skipped \|/);
  assert.match(summary, /\| wallets \| Wallets — renames \| Not run: a setup it needs failed or the run stopped \|/);
  assert.match(summary, /^- Hidden in a wallet job$/m);
});

test('titles link to their source line and cannot break the table', () => {
  const report = buildReport();
  report.suites[0].specs[0].title = 'Home — a | b <i> [c]';
  const summary = buildJobSummary(report, { project: 'mobile-chromium', sourceUrl: SOURCE_URL });

  assert.ok(summary.includes(`| home | [Home — a \\| b &lt;i> \\[c\\]](${SOURCE_URL}/home/itShouldShowBalance.spec.ts#L5) |`));
});

test('a run error makes the job red', () => {
  const report = {
    stats: { expected: 0, unexpected: 0, flaky: 0, skipped: 0, duration: 60000 },
    errors: [{ message: 'Error: Timed out waiting 60000ms from config.webServer.' }],
    suites: [],
  };
  const summary = buildJobSummary(report, { project: 'desktop-chromium' });

  assert.match(summary, /^### 🔴 desktop-chromium: 0 failed, 0 flaky, 0 skipped, 0 passed, 1 run errors · 1m 00s$/m);
  assert.match(summary, /^- Timed out waiting 60000ms from config\.webServer\.$/m);
});

test('a missing or truncated report reads as no results', () => {
  const directory = mkdtempSync(join(tmpdir(), 'web-e2e-summary-'));
  try {
    const file = join(directory, 'results.json');
    writeFileSync(file, '{');
    for (const path of [file, join(directory, 'missing.json')]) {
      const { status, stdout } = spawnSync(process.execPath,
        [new URL('./webE2eSummary.mjs', import.meta.url).pathname, path, '--project', 'desktop-chromium'],
        { encoding: 'utf8' });
      assert.equal(status, 0);
      assert.match(stdout, /^### 🔴 desktop-chromium: no results$/m);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('a job of passed cases only is green', () => {
  const report = buildReport();
  report.suites = [report.suites[0]];
  report.stats = { expected: 1, unexpected: 0, flaky: 0, skipped: 0, duration: 4000 };
  const summary = buildJobSummary(report, { project: 'mobile-chromium' });

  assert.match(summary, /^### 🟢 mobile-chromium: 0 failed, 0 flaky, 0 skipped, 1 passed · 4s$/m);
  assert.doesNotMatch(summary, /Failed|Skipped|Flaky/);
});

function buildReport() {
  return {
    stats: { expected: 1, unexpected: 1, flaky: 1, skipped: 2, duration: 65000 },
    errors: [],
    suites: [
      buildSuite('home/itShouldShowBalance.spec.ts', 'Home — balance shows', 'expected', [{ status: 'passed' }]),
      {
        title: 'send',
        suites: [
          buildSuite('send/itShouldSend.spec.ts', 'Send — sends', 'unexpected', [
            { status: 'failed', errors: [{ message: 'Error: first attempt' }] },
            { status: 'failed', errors: [{ message: TIMEOUT_MESSAGE }] },
          ]),
          buildSuite('send/itShouldTopUp.spec.ts', 'Send — tops up', 'skipped', [{ status: 'skipped' }],
            [{ type: 'low-balance', description: 'GRAM 0.1' }, { type: 'skip', description: 'Wallet cannot pay' }]),
        ],
      },
      buildSuite('settings/itShouldSwitchTheme.spec.ts', 'Settings — dark theme', 'flaky', [
        { status: 'failed', errors: [{ message: 'Error: expect(locator).toBeVisible() failed\n\nLocator: getByTestId(\'theme\')\nExpected: visible' }] },
        { status: 'passed' },
      ]),
      buildSuite('wallets/itShouldRename.spec.ts', 'Wallets — renames', 'skipped', []),
    ],
  };
}

function buildSuite(file, title, status, results, annotations = []) {
  return {
    title: file,
    specs: [{
      title,
      file,
      line: 5,
      tests: [{
        status,
        annotations,
        results: results.map((result) => ({ duration: 0, errors: [], ...result })),
      }],
    }],
  };
}
