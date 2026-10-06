import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { dispatchGramRelease } from '../deploy/dispatch_gram_release.mjs';

globalThis.fetch = () => { throw new Error('Live network is forbidden in dispatcher tests'); };

const SOURCE_SHA = 'a'.repeat(40);
const API = 'https://api.github.com/repos/ton-blockchain/ton-wallet/actions';
const RUN_URL = 'https://github.com/ton-blockchain/ton-wallet/actions/runs/123';
const input = {
  repository: 'mytonwallet-org/mytonwallet',
  ref: 'refs/heads/master',
  eventName: 'workflow_dispatch',
  sha: SOURCE_SHA,
  expectedSha: SOURCE_SHA,
  mode: 'check',
  rolloutPercentage: '5',
  enabled: 'false',
  version: '26.9.11',
  token: 'synthetic-token',
};
const response = (body, status = 200) => new Response(JSON.stringify(body), { status });
const dispatched = () => response({
  workflow_run_id: 123, run_url: `${API}/runs/123`, html_url: RUN_URL,
});
const run = (status, conclusion = null, overrides = {}) => response({
  id: 123, run_attempt: 1, head_branch: 'master', event: 'workflow_dispatch',
  path: '.github/workflows/gram-release.yml', repository: { full_name: 'ton-blockchain/ton-wallet' },
  status, conclusion, ...overrides,
});

function transport(replies) {
  const requests = [];
  const receipts = [];
  let clock = 0;
  return {
    requests, receipts,
    options: {
      fetchImpl: async (url, options) => {
        requests.push({ url, ...options });
        const reply = replies.shift();
        if (reply instanceof Error) throw reply;
        assert.ok(reply, `Unexpected request ${options.method} ${url}`);
        return reply;
      },
      now: () => clock,
      sleep: async (ms) => { clock += ms; },
      pollIntervalMs: 10,
      timeoutMs: 30,
      onDispatched: (receipt) => receipts.push(receipt),
    },
  };
}

test('dispatches immutable source and waits only for the returned receiver run', async () => {
  const fixture = transport([dispatched(), run('queued'), run('in_progress'), run('completed', 'success')]);
  const result = await dispatchGramRelease(input, fixture.options);
  assert.equal(result.conclusion, 'success');
  assert.equal(result.runId, 123);
  assert.equal(fixture.receipts[0].runUrl, RUN_URL);
  assert.deepEqual(JSON.parse(fixture.requests[0].body), {
    ref: 'master', return_run_details: true,
    inputs: { source_sha: SOURCE_SHA, version: '26.9.11', mode: 'check', rollout_percentage: '5' },
  });
  assert.deepEqual(fixture.requests.map(({ method, url }) => `${method} ${url}`), [
    `POST ${API}/workflows/gram-release.yml/dispatches`,
    `GET ${API}/runs/123`, `GET ${API}/runs/123`, `GET ${API}/runs/123`,
  ]);
  assert.ok(fixture.requests.every(({ redirect }) => redirect === 'error'));
});

test('normal enabled public master push requests stage', async () => {
  const fixture = transport([dispatched(), run('completed', 'success')]);
  await dispatchGramRelease({ ...input, eventName: 'push', enabled: 'true', mode: undefined }, fixture.options);
  assert.equal(JSON.parse(fixture.requests[0].body).inputs.mode, 'stage');
});

test('disabled push and skip-ci push make no network request', async () => {
  for (const change of [{ enabled: 'false' }, { enabled: 'true', headMessage: 'release [skip ci]' }]) {
    const fixture = transport([]);
    const result = await dispatchGramRelease({ ...input, eventName: 'push', ...change }, fixture.options);
    assert.equal(result.skipped, true);
    assert.equal(fixture.requests.length, 0);
  }
});

test('explicit manual check can run for a skipped release before activation', async () => {
  const fixture = transport([dispatched(), run('completed', 'success')]);
  await dispatchGramRelease({ ...input, headMessage: '[skip ci]' }, fixture.options);
  assert.equal(fixture.requests.length, 2);
});

test('manual stage requires the enable switch', async () => {
  const fixture = transport([]);
  await assert.rejects(dispatchGramRelease({ ...input, mode: 'stage' }, fixture.options), /enabled/i);
  assert.equal(fixture.requests.length, 0);
});

test('rejects invalid source identity, version, mode, percentage and absent token before dispatch', async () => {
  const cases = [
    [{ repository: 'mytonwallet-org/mytonwallet-dev' }, /public repository/i],
    [{ ref: 'refs/heads/release/26.9.11' }, /master/i],
    [{ eventName: 'pull_request' }, /event/i],
    [{ sha: 'abc' }, /source SHA/i],
    [{ expectedSha: '' }, /expected_sha/i],
    [{ expectedSha: 'b'.repeat(40) }, /expected_sha/i],
    [{ version: '26.9.11-beta' }, /version/i],
    [{ version: '26.09.11' }, /version/i],
    [{ mode: 'publish' }, /mode/i],
    [{ rolloutPercentage: '0' }, /percentage/i],
    [{ rolloutPercentage: '101' }, /percentage/i],
    [{ rolloutPercentage: '5.5' }, /percentage/i],
    [{ token: '' }, /token/i],
  ];
  for (const [changes, error] of cases) {
    const fixture = transport([]);
    await assert.rejects(dispatchGramRelease({ ...input, ...changes }, fixture.options), error);
    assert.equal(fixture.requests.length, 0);
  }
});

test('accepted dispatch alone is not success and failed receiver preserves its link', async () => {
  for (const conclusion of ['failure', 'cancelled', 'timed_out', 'skipped', 'neutral']) {
    const fixture = transport([dispatched(), run('completed', conclusion)]);
    await assert.rejects(dispatchGramRelease(input, fixture.options), new RegExp(conclusion));
    assert.equal(fixture.receipts[0].runUrl, RUN_URL);
  }
});

test('times out queued receiver instead of reporting dispatch as success', async () => {
  const fixture = transport([dispatched(), run('queued'), run('queued'), run('queued')]);
  await assert.rejects(dispatchGramRelease(input, fixture.options), /timed out.*123/i);
  assert.equal(fixture.requests.filter(({ method }) => method === 'POST').length, 1);
});

test('ambiguous or refused dispatch is never retried', async () => {
  for (const reply of [new Error('connection lost'), response({}, 503), response({}), new Response(null, { status: 204 })]) {
    const fixture = transport([reply]);
    await assert.rejects(dispatchGramRelease(input, fixture.options), /dispatch/i);
    assert.equal(fixture.requests.length, 1);
  }
});

test('does not follow a forged response URL or substitute another run or rerun', async () => {
  const fixture = transport([
    response({ workflow_run_id: 123, run_url: 'https://attacker.invalid', html_url: 'https://attacker.invalid' }),
    run('completed', 'success'),
  ]);
  await dispatchGramRelease(input, fixture.options);
  assert.equal(fixture.requests[1].url, `${API}/runs/123`);
  assert.equal(fixture.receipts[0].runUrl, RUN_URL);
  for (const overrides of [
    { id: 124 }, { run_attempt: 2 }, { head_branch: 'other' }, { event: 'push' },
    { path: '.github/workflows/other.yml' }, { repository: { full_name: 'other/repo' } },
  ]) {
    const wrong = transport([dispatched(), run('completed', 'success', overrides)]);
    await assert.rejects(dispatchGramRelease(input, wrong.options), /receiver identity/i);
  }
});

test('receiver API failure reports the recorded run rather than dispatching again', async () => {
  const fixture = transport([dispatched(), response({}, 403)]);
  await assert.rejects(dispatchGramRelease(input, fixture.options), /receiver.*123.*403/i);
  assert.equal(fixture.requests.filter(({ method }) => method === 'POST').length, 1);
});

test('CLI uses checked-out package version and records receiver ID before completion', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'gram-dispatch-'));
  try {
    writeFileSync(path.join(directory, 'package.json'), JSON.stringify({ version: '26.9.12' }));
    writeFileSync(path.join(directory, 'event.json'), '{}');
    writeFileSync(path.join(directory, 'transport.mjs'), `
      import assert from 'node:assert/strict';
      import { readFileSync } from 'node:fs';
      globalThis.fetch = async (url, options) => {
        if (options.method === 'POST') {
          assert.equal(url, '${API}/workflows/gram-release.yml/dispatches');
          assert.deepEqual(JSON.parse(options.body).inputs, {
            source_sha: '${SOURCE_SHA}', version: '26.9.12', mode: 'check', rollout_percentage: '7',
          });
          return Response.json({ workflow_run_id: 123 });
        }
        assert.equal(url, '${API}/runs/123');
        assert.match(readFileSync(process.env.GITHUB_OUTPUT, 'utf8'), /receiver_run_id=123/);
        return Response.json({
          id: 123, run_attempt: 1, head_branch: 'master', event: 'workflow_dispatch',
          path: '.github/workflows/gram-release.yml', repository: { full_name: 'ton-blockchain/ton-wallet' },
          status: 'completed', conclusion: 'success',
        });
      };
    `);
    const output = execFileSync(process.execPath, [
      '--import', path.join(directory, 'transport.mjs'),
      fileURLToPath(new URL('../deploy/dispatch_gram_release.mjs', import.meta.url)),
    ], {
      cwd: directory,
      encoding: 'utf8',
      env: {
        PATH: process.env.PATH,
        GITHUB_REPOSITORY: input.repository, GITHUB_REF: input.ref,
        GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_SHA: SOURCE_SHA,
        GITHUB_EVENT_PATH: path.join(directory, 'event.json'), EXPECTED_SHA: SOURCE_SHA,
        RELEASE_MODE: 'check', ROLLOUT_PERCENTAGE: '7', GRAM_RELEASE_ENABLED: 'false',
        TON_WALLET_ACTIONS_TOKEN: 'synthetic-token',
        GITHUB_OUTPUT: path.join(directory, 'output'), GITHUB_STEP_SUMMARY: path.join(directory, 'summary'),
      },
    });
    assert.match(output, /completed successfully/);
    assert.ok(readFileSync(path.join(directory, 'summary'), 'utf8').includes(RUN_URL));
    assert.ok(!output.includes('synthetic-token'));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
