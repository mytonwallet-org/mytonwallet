import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { checkRangeTouchesIos, computeBuildNumber, pickArchiveRunner, planBuild } from './iosCadenceBuild.mjs';

const MASTER = 'refs/heads/master';
const SINCE = 'a'.repeat(40);
const HEAD = 'b'.repeat(40);

test('the build number takes the run and the attempt above the release workflow range', () => {
  assert.equal(computeBuildNumber({ runNumber: '1', runAttempt: '1' }), 10_000_010);
  assert.equal(computeBuildNumber({ runNumber: '1', runAttempt: '10' }), 10_000_019);
  assert.equal(computeBuildNumber({ runNumber: '42', runAttempt: '3' }), 10_000_422);
});

test('the build number refuses an eleventh attempt and anything but bare integers', () => {
  assert.throws(() => computeBuildNumber({ runNumber: '1', runAttempt: '11' }), /dispatch a new run/);
  assert.throws(() => computeBuildNumber({ runNumber: '1a', runAttempt: '1' }), /GITHUB_RUN_NUMBER/);
  assert.throws(() => computeBuildNumber({ runNumber: '1', runAttempt: '' }), /GITHUB_RUN_ATTEMPT/);
});

test('the archive goes to the hosted runner when asked to or when no label is set', () => {
  assert.equal(pickArchiveRunner({ archiveOnHosted: true, runsOn: 'ios-cadence-archive' }), 'xcode-27');
  assert.equal(pickArchiveRunner({ archiveOnHosted: false, runsOn: '' }), 'xcode-27');
  assert.equal(pickArchiveRunner({ archiveOnHosted: false, runsOn: 'ios-cadence-archive' }), 'ios-cadence-archive');
});

test('only a range entirely inside the Android tree leaves iOS nothing to build', () => {
  assert.equal(checkRangeTouchesIos(['mobile/android/a.kt']), false);
  assert.equal(checkRangeTouchesIos(['mobile/android/a.kt', 'src/x.ts']), true);
  assert.equal(checkRangeTouchesIos([]), true);
});

test('the plan refuses any ref but master', async () => {
  const run = makeRun({ ref: 'refs/heads/release/26.11' });
  await assert.rejects(planBuild(run.args), /master only/);
});

test('an Android-only range plans no iOS build', async () => {
  const run = makeRun({ compare: { status: 'ahead', files: [{ filename: 'mobile/android/a.kt' }] } });
  await planBuild(run.args);
  assert.deepEqual(run.outputs, { version: '26.11.2', build: '10000070', runner: 'xcode-27', build_ios: 'false' });
});

test('a range touching iOS plans a build on the configured runner', async () => {
  const run = makeRun({
    compare: { status: 'ahead', files: [{ filename: 'src/x.ts' }] },
    env: { ARCHIVE_RUNS_ON: 'ios-cadence-archive' },
  });
  await planBuild(run.args);
  assert.equal(run.outputs.build_ios, 'true');
  assert.equal(run.outputs.runner, 'ios-cadence-archive');
});

test('an unreadable or unordered range builds and says why', async () => {
  for (const compare of [new Error('boom'), { status: 'diverged', files: [] }]) {
    const run = makeRun({ compare });
    await planBuild(run.args);
    assert.equal(run.outputs.build_ios, 'true');
    assert.equal(run.warnings.length, 1);
  }
});

test('a truncated file list builds, since the missing files may touch iOS', async () => {
  const files = Array.from({ length: 300 }, (_, index) => ({ filename: `mobile/android/${index}.kt` }));
  const run = makeRun({ compare: { status: 'ahead', files } });
  await planBuild(run.args);
  assert.equal(run.outputs.build_ios, 'true');
});

test('no baseline builds without asking for a range', async () => {
  const run = makeRun({ env: { SINCE_SHA: '' } });
  await planBuild(run.args);
  assert.equal(run.outputs.build_ios, 'true');
  assert.equal(run.compareCalls, 0);
});

function makeRun({ ref = MASTER, compare = { status: 'identical', files: [] }, env = {} } = {}) {
  const workspace = mkdtempSync(join(tmpdir(), 'ios-cadence-build-'));
  writeFileSync(join(workspace, 'package.json'), JSON.stringify({ version: '26.11.2' }));
  const run = { outputs: {}, warnings: [], compareCalls: 0 };
  const github = {
    rest: {
      repos: {
        compareCommits: async () => {
          run.compareCalls += 1;
          if (compare instanceof Error) throw compare;
          return { data: compare };
        },
      },
    },
  };
  const core = {
    setOutput: (name, value) => { run.outputs[name] = String(value); },
    warning: (message) => { run.warnings.push(message); },
    info: () => {},
  };
  run.args = {
    github,
    core,
    context: { ref, sha: HEAD, repo: { owner: 'o', repo: 'r' } },
    env: {
      GITHUB_WORKSPACE: workspace,
      GITHUB_RUN_NUMBER: '7',
      GITHUB_RUN_ATTEMPT: '1',
      SINCE_SHA: SINCE,
      ARCHIVE_ON_HOSTED: 'false',
      ARCHIVE_RUNS_ON: '',
      ...env,
    },
  };
  return run;
}
