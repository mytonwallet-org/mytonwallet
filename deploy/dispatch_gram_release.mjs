import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const TARGET = 'ton-blockchain/ton-wallet';
const WORKFLOW = 'gram-release.yml';
const API = `https://api.github.com/repos/${TARGET}/actions`;
const SHA = /^[0-9a-f]{40}$/;
const VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

export async function dispatchGramRelease(input, {
  fetchImpl = fetch,
  now = Date.now,
  sleep: wait = sleep,
  onDispatched = () => {},
  pollIntervalMs = 15000,
  timeoutMs = 90 * 60 * 1000,
} = {}) {
  if (input.repository !== 'mytonwallet-org/mytonwallet') throw new Error('Use the public repository');
  if (input.ref !== 'refs/heads/master') throw new Error('Dispatch from public master');
  if (!['push', 'workflow_dispatch'].includes(input.eventName)) throw new Error('Unsupported release event');
  if (!SHA.test(input.sha)) throw new Error('Invalid full source SHA');

  const manual = input.eventName === 'workflow_dispatch';
  if (!manual && (input.enabled !== 'true' || /\[skip ci\]/i.test(input.headMessage ?? ''))) {
    return { skipped: true };
  }
  if (manual && (!SHA.test(input.expectedSha) || input.expectedSha !== input.sha)) {
    throw new Error('expected_sha must match the dispatched public master SHA');
  }
  const mode = manual ? input.mode : 'stage';
  if (!['check', 'stage'].includes(mode)) throw new Error('Invalid release mode');
  if (mode === 'stage' && input.enabled !== 'true') throw new Error('Gram release is not enabled');
  if (!VERSION.test(input.version)) throw new Error('Invalid release version');
  const percentage = input.rolloutPercentage || '5';
  if (!/^([1-9]|[1-9][0-9]|100)$/.test(percentage)) throw new Error('Invalid rollout percentage');
  if (!input.token?.trim()) throw new Error('TON_WALLET_ACTIONS_TOKEN is required');

  const deadline = now() + timeoutMs;
  async function request(url, method, body, context) {
    let response;
    try {
      response = await fetchImpl(url, {
        method,
        redirect: 'error',
        signal: AbortSignal.timeout(Math.max(1, Math.min(30000, deadline - now()))),
        headers: {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${input.token}`,
          'X-GitHub-Api-Version': '2026-03-10',
          'Content-Type': 'application/json',
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      throw new Error(`${context}: request failed; inspect the receiver before retrying`);
    }
    if (response.status !== 200) throw new Error(`${context}: HTTP ${response.status}`);
    try {
      return await response.json();
    } catch {
      throw new Error(`${context}: missing JSON response; inspect the receiver before retrying`);
    }
  }

  // A lost dispatch response can still mean a started publisher; never repeat this POST automatically.
  const dispatched = await request(`${API}/workflows/${WORKFLOW}/dispatches`, 'POST', {
    ref: 'master',
    return_run_details: true,
    inputs: {
      source_sha: input.sha,
      version: input.version,
      mode,
      rollout_percentage: percentage,
    },
  }, 'Receiver dispatch');
  const runId = dispatched.workflow_run_id;
  if (!Number.isSafeInteger(runId) || runId <= 0) {
    throw new Error('Receiver dispatch returned no exact run ID; inspect the receiver before retrying');
  }
  const receipt = { runId, runUrl: `https://github.com/${TARGET}/actions/runs/${runId}` };
  onDispatched(receipt);

  while (now() < deadline) {
    const run = await request(`${API}/runs/${runId}`, 'GET', undefined, `Receiver run ${runId}`);
    if (run.id !== runId || run.run_attempt !== 1 || run.head_branch !== 'master'
      || run.event !== 'workflow_dispatch' || run.path !== `.github/workflows/${WORKFLOW}`
      || run.repository?.full_name !== TARGET) {
      throw new Error(`Receiver identity changed for run ${runId}`);
    }
    if (run.status === 'completed') {
      if (run.conclusion !== 'success') {
        throw new Error(`Receiver run ${runId} concluded ${run.conclusion}; inspect ${receipt.runUrl}`);
      }
      return { ...receipt, conclusion: run.conclusion };
    }
    await wait(Math.min(pollIntervalMs, deadline - now()));
  }
  throw new Error(`Receiver timed out for run ${runId}; it may still be active: ${receipt.runUrl}`);
}

async function main() {
  const env = process.env;
  const { version } = JSON.parse(readFileSync('package.json', 'utf8'));
  const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const result = await dispatchGramRelease({
    repository: env.GITHUB_REPOSITORY,
    ref: env.GITHUB_REF,
    eventName: env.GITHUB_EVENT_NAME,
    sha: env.GITHUB_SHA,
    expectedSha: env.EXPECTED_SHA,
    mode: env.RELEASE_MODE,
    rolloutPercentage: env.ROLLOUT_PERCENTAGE,
    enabled: env.GRAM_RELEASE_ENABLED,
    token: env.TON_WALLET_ACTIONS_TOKEN,
    headMessage: event.head_commit?.message,
    version,
  }, {
    onDispatched: ({ runId, runUrl }) => {
      console.log(`Receiver run ${runId}: ${runUrl}`);
      if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `receiver_run_id=${runId}\nreceiver_run_url=${runUrl}\n`);
      if (env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `Gram release receiver: [run ${runId}](${runUrl}).\n`);
      }
    },
  });
  console.log(result.skipped ? 'Gram release dispatch is disabled or skipped.' : 'Gram release receiver completed successfully.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
