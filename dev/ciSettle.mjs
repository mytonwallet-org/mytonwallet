import { readFile } from 'node:fs/promises';

const CONFIG_URL = new URL('../.github/ci-settle.json', import.meta.url);
// Leaves headroom under the 15-minute limit of `ubuntu-slim`
const SLIM_RUNNER_MAX_SECONDS = 780;
const MAX_DELAY_SECONDS = 60;
const HEAD_CHECK_ATTEMPTS = 2;

export async function settlePullRequest({
  github, context, core, job, maxSeconds = SLIM_RUNNER_MAX_SECONDS, configUrl = CONFIG_URL,
}) {
  const pullRequest = context.payload.pull_request;
  let seconds = await readSettleSeconds({ core, job, logins: [pullRequest.user?.login, context.actor], configUrl });
  if (seconds > maxSeconds) {
    core.warning(`The ${job} wait exceeds the runner limit; using ${maxSeconds}`);
    seconds = maxSeconds;
  }
  if (!seconds) {
    return true;
  }
  core.info(`Waiting ${seconds} seconds without a new push`);
  await waitSeconds(seconds);

  let isCurrent = true;
  for (let attempt = 1; attempt <= HEAD_CHECK_ATTEMPTS; attempt += 1) {
    try {
      const { data: current } = await github.rest.pulls.get({ ...context.repo, pull_number: pullRequest.number });
      isCurrent = current.head.sha === pullRequest.head.sha;
      break;
    } catch (err) {
      if (attempt === HEAD_CHECK_ATTEMPTS) {
        core.warning(`Could not check the pull request head after ${attempt} attempts; running the jobs: ${err.message}`);
      }
    }
  }
  if (!isCurrent) {
    core.notice('The pull request head moved; skipping the heavy jobs');
  }
  return isCurrent;
}

async function readSettleSeconds({ core, job, logins, configUrl }) {
  let config;
  try {
    config = JSON.parse(await readFile(configUrl, 'utf8'))[job];
    validateConfig(config);
  } catch (err) {
    core.warning(`Invalid ${job} entry in the settle config; not waiting: ${err.message}`);
    return 0;
  }
  if (!config.logins?.length) {
    core.info(`No wait: no logins listed for ${job}`);
    return 0;
  }
  const allowedLogins = new Set(config.logins.map((login) => login.toLowerCase()));
  if (!logins.some((login) => login && allowedLogins.has(login.toLowerCase()))) {
    core.info(`No wait for ${logins.filter(Boolean).join(', ')}: not listed for ${job}`);
    return 0;
  }
  return config.seconds;
}

async function waitSeconds(seconds) {
  let remainingSeconds = seconds;
  while (remainingSeconds > 0) {
    const delaySeconds = Math.min(remainingSeconds, MAX_DELAY_SECONDS);
    await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));
    remainingSeconds -= delaySeconds;
  }
}

function validateConfig(config) {
  if (!config || typeof config !== 'object') {
    throw new Error('missing');
  }
  if (!Number.isFinite(config.seconds) || config.seconds < 0) {
    throw new Error('`seconds` must be a non-negative number');
  }
  if (config.logins !== undefined
    && (!Array.isArray(config.logins) || config.logins.some((login) => typeof login !== 'string' || !login))) {
    throw new Error('`logins` must be a list of GitHub logins');
  }
}
