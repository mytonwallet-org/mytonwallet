import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const HOSTED_RUNNER = 'xcode-27';
// Far above the release workflow's numbers, which App Store Connect accepts in any order but
// TestFlight ranks by size, so these builds reach testers as the newest from the first one.
const BUILD_OFFSET = 10_000_000;
const ATTEMPTS_PER_RUN = 10;
// The compare API stops listing files here, and the ones it leaves out may be anywhere.
const COMPARE_FILE_LIMIT = 300;

export function computeBuildNumber({ runNumber, runAttempt }) {
  if (!/^\d+$/.test(runNumber ?? '')) throw new Error(`GITHUB_RUN_NUMBER=${runNumber} is not a bare integer`);
  if (!/^\d+$/.test(runAttempt ?? '')) throw new Error(`GITHUB_RUN_ATTEMPT=${runAttempt} is not a bare integer`);
  const attempt = Number(runAttempt);
  if (attempt < 1 || attempt > ATTEMPTS_PER_RUN) {
    throw new Error(`attempt ${attempt} does not fit the ${ATTEMPTS_PER_RUN} one run holds, dispatch a new run`);
  }
  return BUILD_OFFSET + Number(runNumber) * ATTEMPTS_PER_RUN + attempt - 1;
}

export function pickArchiveRunner({ archiveOnHosted, runsOn }) {
  return archiveOnHosted || !runsOn ? HOSTED_RUNNER : runsOn;
}

export function checkRangeTouchesIos(files) {
  return files.length === 0 || files.some((file) => !file.startsWith('mobile/android/'));
}

export async function planBuild({ github, context, core, env }) {
  if (context.ref !== 'refs/heads/master') {
    throw new Error(`cadence Preview builds run from master only, not ${context.ref}`);
  }
  const { version } = JSON.parse(readFileSync(join(env.GITHUB_WORKSPACE, 'package.json'), 'utf8'));
  const build = computeBuildNumber({ runNumber: env.GITHUB_RUN_NUMBER, runAttempt: env.GITHUB_RUN_ATTEMPT });
  const runner = pickArchiveRunner({ archiveOnHosted: env.ARCHIVE_ON_HOSTED === 'true', runsOn: env.ARCHIVE_RUNS_ON });
  const shouldBuild = await checkIosChangedSince({ github, context, core, since: env.SINCE_SHA });

  core.setOutput('version', version);
  core.setOutput('build', build);
  core.setOutput('runner', runner);
  core.setOutput('build_ios', shouldBuild ? 'true' : 'false');
  core.info(`Preview ${version} (${build}) on ${runner}, ${shouldBuild ? 'building' : 'nothing for iOS in the range'}`);
}

async function checkIosChangedSince({ github, context, core, since }) {
  if (!since) return true;
  let comparison;
  try {
    ({ data: comparison } = await github.rest.repos.compareCommits({ ...context.repo, base: since, head: context.sha }));
  } catch (error) {
    core.warning(`could not read the range since ${since} (${error.status ?? error.message}), building`);
    return true;
  }
  if (comparison.status !== 'ahead' && comparison.status !== 'identical') {
    core.warning(`baseline ${since} does not precede this commit (status=${comparison.status}), building`);
    return true;
  }
  const files = comparison.files ?? [];
  if (files.length >= COMPARE_FILE_LIMIT) return true;
  return checkRangeTouchesIos(files.map((file) => file.filename));
}
