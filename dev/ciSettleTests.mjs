import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

import { settlePullRequest } from './ciSettle.mjs';

const JOBS = ['ios', 'android', 'simpleTests'];
const CONTEXT = {
  repo: { owner: 'mytonwallet-org', repo: 'mytonwallet-dev' },
  actor: 'pusher',
  payload: { pull_request: { number: 7, head: { sha: 'head' }, user: { login: 'author' } } },
};

test('the repository config is valid for every job', async (t) => {
  for (const job of JOBS) {
    const waits = mockTimers(t);
    const core = makeCore();
    await settlePullRequest({ github: makeGithub({ waits }), context: CONTEXT, core, job, maxSeconds: Infinity });
    assert.deepEqual(core.warnings, [], job);
  }
});

test('each job waits for its own seconds', async (t) => {
  const config = {
    ios: { seconds: 300, logins: ['author'] },
    android: { seconds: 120, logins: ['author'] },
    simpleTests: { seconds: 0, logins: ['author'] },
  };
  for (const [job, expectedMilliseconds] of [['ios', 300000], ['android', 120000], ['simpleTests', 0]]) {
    const waits = mockTimers(t);
    await settle({ config, job, waits });
    assert.equal(waits.totalMilliseconds, expectedMilliseconds, job);
  }
});

test('a login list limits the wait to the PR author or the triggering actor, ignoring case', async (t) => {
  for (const [author, actor, expectedMilliseconds] of [
    ['agent-bot', 'someone', 60000],
    ['someone', 'AGENT-BOT', 60000],
    [undefined, 'someone', 0],
  ]) {
    const waits = mockTimers(t);
    const context = {
      ...CONTEXT, actor, payload: { pull_request: { ...CONTEXT.payload.pull_request, user: author && { login: author } } },
    };
    await settle({ config: { android: { seconds: 60, logins: ['Agent-Bot'] } }, job: 'android', waits, context });
    assert.equal(waits.totalMilliseconds, expectedMilliseconds, `${author} / ${actor}`);
  }
});

test('an entry without logins waits for nobody', async (t) => {
  for (const entry of [{ seconds: 600 }, { seconds: 600, logins: [] }]) {
    const waits = mockTimers(t);
    const { core, isCurrent, github } = await settle({ config: { ios: entry }, job: 'ios', waits });
    assert.equal(isCurrent, true);
    assert.equal(waits.totalMilliseconds, 0);
    assert.equal(github.headCheckCount, 0);
    assert.deepEqual(core.warnings, []);
  }
});

test('a missing or invalid entry warns and disables the wait', async (t) => {
  for (const entry of [
    undefined, null, 'x', [], {}, { seconds: -1 }, { seconds: '600' }, { seconds: null },
    { seconds: 600, logins: 'author' }, { seconds: 600, logins: [''] }, { seconds: 600, logins: [1] },
  ]) {
    const waits = mockTimers(t);
    const { core, isCurrent, github } = await settle({ config: { ios: entry }, job: 'ios', waits });
    assert.equal(isCurrent, true);
    assert.equal(waits.totalMilliseconds, 0);
    assert.equal(github.headCheckCount, 0);
    assert.equal(core.warnings.length, 1, JSON.stringify(entry));
  }
  const core = makeCore();
  const waits = mockTimers(t);
  await settlePullRequest({
    github: makeGithub({ waits }), context: CONTEXT, core, job: 'ios', configUrl: pathToFileURL('/nonexistent/settle.json'),
  });
  assert.equal(core.warnings.length, 1);
});

test('the wait elapses in steps before a single head check', async (t) => {
  const waits = mockTimers(t);
  const { core, isCurrent, github } = await settle({
    config: { android: { seconds: 150, logins: ['author'] } }, job: 'android', waits,
  });
  assert.equal(isCurrent, true);
  assert.deepEqual(waits.delays, [60000, 60000, 30000]);
  assert.equal(github.headCheckCount, 1);
  assert.equal(github.waitedBeforeCheck, 150000);
  assert.deepEqual(core.notices, []);
});

test('a moved head skips the jobs with a notice', async (t) => {
  const waits = mockTimers(t);
  const { core, isCurrent } = await settle({
    config: { ios: { seconds: 1, logins: ['author'] } }, job: 'ios', waits, currentSha: 'new-head',
  });
  assert.equal(isCurrent, false);
  assert.equal(core.notices.length, 1);
});

test('the head check retries once and runs the jobs when the API stays unavailable', async (t) => {
  for (const [failureCount, isCurrent, warningCount] of [[1, false, 0], [2, true, 1]]) {
    const waits = mockTimers(t);
    const result = await settle({
      config: { ios: { seconds: 1, logins: ['author'] } }, job: 'ios', waits, currentSha: 'new-head', failureCount,
    });
    assert.equal(result.isCurrent, isCurrent);
    assert.equal(result.core.warnings.length, warningCount);
    assert.equal(result.github.headCheckCount, 2);
  }
});

test('the wait is capped at the slim runner limit unless the caller lifts it', async (t) => {
  for (const [maxSeconds, expectedMilliseconds, warningCount] of [[undefined, 780000, 1], [Infinity, 1000000, 0]]) {
    const waits = mockTimers(t);
    const { core } = await settle({
      config: { ios: { seconds: 1000, logins: ['author'] } }, job: 'ios', waits, maxSeconds,
    });
    assert.equal(waits.totalMilliseconds, expectedMilliseconds);
    assert.equal(core.warnings.length, warningCount);
  }
});

test('Simple tests run after a failed or skipped wait and skip only a confirmed moved head', () => {
  const workflow = readFileSync(new URL('../.github/workflows/test.yml', import.meta.url), 'utf8');
  const match = workflow.match(/^  test:\n[\s\S]*?^    if: >-\n((?:^      .*\n)+)/m);
  assert.ok(match, 'Simple tests condition exists');
  const condition = match[1].trim().replace(/^\$\{\{|\}\}$/g, '')
    // Job names with dashes are valid in Actions expressions but not in JavaScript
    .replace(/needs\.([\w-]+)/g, "needs['$1']");
  for (const [result, current, shouldRun] of [
    ['failure', '', true], ['skipped', '', true], ['success', 'true', true], ['success', 'false', false], ['success', '', false],
  ]) {
    const isRun = runInNewContext(condition, {
      cancelled() { return false; },
      needs: {
        'detect-changes': { outputs: { web: 'true' } },
        'settle-simple-tests': { result, outputs: { current } },
      },
    });
    assert.equal(isRun, shouldRun, `Wait result: ${result}, current: ${current}`);
  }
});

async function settle({ config, job, waits, context = CONTEXT, maxSeconds, currentSha, failureCount }) {
  const directory = mkdtempSync(join(tmpdir(), 'ci-settle-'));
  try {
    const configPath = join(directory, 'ci-settle.json');
    writeFileSync(configPath, JSON.stringify(config));
    const core = makeCore();
    const github = makeGithub({ waits, currentSha, failureCount });
    const isCurrent = await settlePullRequest({
      github, context, core, job, configUrl: pathToFileURL(configPath), maxSeconds,
    });
    return { core, github, isCurrent };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function mockTimers(t) {
  const waits = { delays: [], totalMilliseconds: 0 };
  t.mock.method(globalThis, 'setTimeout', (resolve, milliseconds) => {
    waits.delays.push(milliseconds);
    waits.totalMilliseconds += milliseconds;
    resolve();
  });
  return waits;
}

function makeGithub({ waits, currentSha = 'head', failureCount = 0 }) {
  const github = {
    headCheckCount: 0,
    waitedBeforeCheck: undefined,
    rest: {
      pulls: {
        async get(params) {
          assert.equal(params.pull_number, 7);
          github.waitedBeforeCheck ??= waits.totalMilliseconds;
          github.headCheckCount += 1;
          if (github.headCheckCount <= failureCount) {
            throw new Error('API unavailable');
          }
          return { data: { head: { sha: currentSha } } };
        },
      },
    },
  };
  return github;
}

function makeCore() {
  const core = { warnings: [], notices: [] };
  core.info = () => {};
  core.warning = (message) => core.warnings.push(message);
  core.notice = (message) => core.notices.push(message);
  return core;
}
