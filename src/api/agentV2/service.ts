import type { ApiChain, OnApiUpdate } from '../types';
import type { ClientTimingEvent } from './developmentTelemetry';
import type {
  AgentAnswerFeedbackV2,
  AgentThreadCreateRequestV2,
  AgentThreadListRequestV2,
} from './protocol/types';
import type {
  AgentV2HintWalletState,
  AgentV2HostContextSnapshot,
  AgentV2NewsFeedRequest,
  AgentV2ProblemReport,
  AgentV2RunCommand,
  AgentV2RuntimeStatus,
  AgentV2ThreadUpdate,
  AgentV2Transcription,
} from './types';

import { AGENT_API_URL } from '../../config';
import { parseAccountId } from '../../util/account';
import { logDebug } from '../../util/logs';
import { chains } from '../chains';
import { getTokenBySlug } from '../common/tokens';
import { getEnvironment } from '../environment';
import { fetchActivityDetails, fetchPastActivities } from '../methods/activities';
import { storage } from '../storages';
import contractManifest from './generated/manifest.json';
import { runSafeAgentV2Operation } from './mutation';
import { clearAgentV2PersistentState } from './persistentState';
import { AgentV2Runtime } from './runtime';
import { isRetryableWalletSourceError } from './walletQueryErrors';
import { createAgentV2WalletSession } from './walletSession';
import { AgentV2WalletToolDispatcher } from './walletTools';

let runtime: AgentV2Runtime | undefined;
let latestRuntimeGeneration = 0;
let lifecycleQueue: Promise<void> | undefined;
let lifecycleTransitionCount = 0;
let hasLoggedWiring = false;
const WALLET_REFRESH_CONCURRENCY = 4;

export function getAgentV2RuntimeStatus(): AgentV2RuntimeStatus {
  return {
    enabled: getEnvironment().isAgentV2Enabled,
  };
}

/**
 * Which Agent this build talks to, and which protocol it speaks. Both are fixed when the bundle is
 * built - the host by `defineEnv`, the protocol by the generated contract manifest - so a running
 * app has no way to state either, and an installed build that was one protocol behind, against a
 * host nobody had named, spent a day looking like a network fault. Logged once per runtime, and
 * only the origin: the path, the wallet and the user are not part of it.
 */
function logAgentV2Wiring(baseUrl: string) {
  if (hasLoggedWiring) return;
  hasLoggedWiring = true;

  let origin: string;
  try {
    origin = new URL(baseUrl).origin;
  } catch {
    // A base URL that does not parse is exactly the case worth seeing, so keep it as configured.
    origin = baseUrl;
  }

  logDebug(`AgentV2 wiring: origin=${origin} protocol=${contractManifest.protocolVersion}`);
}

export async function initAgentV2(onUpdate: OnApiUpdate) {
  let activatedRuntime: AgentV2Runtime | undefined;
  let activatedGeneration: number | undefined;
  await enqueueLifecycleTransition(async () => {
    const previousRuntime = runtime;
    runtime = undefined;
    await previousRuntime?.destroy();

    let nextRuntime: AgentV2Runtime | undefined;
    try {
      const walletSession = await createAgentV2WalletSession();
      const baseUrl = `${AGENT_API_URL.replace(/\/$/u, '')}/v2`;
      logAgentV2Wiring(baseUrl);
      nextRuntime = new AgentV2Runtime({
        storage,
        baseUrl,
        fetch: globalThis.fetch.bind(globalThis),
        onUpdate(update) {
          if (!isActiveRuntime(nextRuntime)) return;
          onUpdate({ type: 'agentV2', update });
        },
        walletSession,
      });
      const instance = nextRuntime;
      instance.setToolExecutor(new AgentV2WalletToolDispatcher({
        session: walletSession,
        getConsent: () => instance.getConsent(),
        fetchPastActivities,
        fetchActivityDetails,
        getTokenBySlug,
        refreshWalletHoldings: refreshAgentWalletHoldings,
      }));
      const generation = latestRuntimeGeneration + 1;
      runtime = instance;
      latestRuntimeGeneration = generation;
      activatedRuntime = instance;
      activatedGeneration = generation;
    } catch (error) {
      await nextRuntime?.destroy().catch(() => undefined);
      throw error;
    }
  });

  if (
    activatedRuntime
    && isActiveRuntime(activatedRuntime)
  ) {
    onUpdate({
      type: 'agentV2',
      update: { kind: 'runtimeReady', generation: activatedGeneration! },
    });
  }
}

async function refreshAgentWalletHoldings(
  accounts: AgentV2HostContextSnapshot['accounts'],
  signal: AbortSignal,
) {
  const results = new Map<string, {
    byChain: Partial<Record<ApiChain, Record<string, bigint>>>;
    failedChains: ApiChain[];
  }>();
  const tasks = accounts.flatMap((account) => account.chains.flatMap((chain) => {
    const address = account.addresses[chain];
    return address ? [{ account, chain: chain as ApiChain, address }] : [];
  }));
  await runWithConcurrency(tasks, WALLET_REFRESH_CONCURRENCY, async ({ account, chain, address }) => {
    if (signal.aborted) throw signal.reason;
    const entry = results.get(account.accountId) ?? { byChain: {}, failedChains: [] };
    results.set(account.accountId, entry);
    try {
      entry.byChain[chain] = await chains[chain].getWalletAssets(
        parseAccountId(account.accountId).network,
        address,
        () => {},
        { signal },
      );
    } catch (error) {
      if (signal.aborted) throw signal.reason ?? error;
      if (!isRetryableWalletSourceError(error)) throw error;
      entry.failedChains.push(chain);
    }
  });
  return results;
}

async function runWithConcurrency<T>(
  values: T[],
  concurrency: number,
  operation: (value: T) => Promise<void>,
) {
  let nextIndex = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (nextIndex < values.length) {
      const value = values[nextIndex];
      nextIndex += 1;
      await operation(value);
    }
  }));
}

export function getAgentV2Runtime() {
  if (lifecycleTransitionCount || !runtime) throw new Error('Agent V2 SDK is not initialized');
  return runtime;
}

export function getAgentV2Consent() {
  return getAgentV2Runtime().getConsent();
}

export function acceptAgentV2Consent() {
  return getAgentV2Runtime().acceptConsent();
}

export function updateAgentV2HostContext(snapshot?: AgentV2HostContextSnapshot) {
  const instance = getAgentV2Runtime();
  return runSafeAgentV2Operation(async () => {
    const runGeneration = instance.getRunLifecycleGeneration();
    const authorityChanged = await instance.updateHostContext(snapshot);
    if (!isActiveRuntime(instance)) {
      throw new Error('Agent V2 runtime changed during host-context delivery');
    }
    return {
      authorityChanged,
      generation: latestRuntimeGeneration,
      ...(authorityChanged && runGeneration === instance.getRunLifecycleGeneration()
        ? { preservesActiveRuns: true as const } : {}),
    };
  });
}

export function getAgentV2Hints(langCode?: string) {
  return getAgentV2Runtime().getHints(langCode);
}

export function getAgentV2StarterHints(walletState?: AgentV2HintWalletState, host?: AgentV2HostContextSnapshot) {
  return getAgentV2Runtime().getStarterHints(walletState, host);
}

export function getAgentV2Availability() {
  return getAgentV2Runtime().getAvailability();
}

export function getAgentV2UserQuota() {
  return getAgentV2Runtime().getUserQuota();
}

export function getAgentV2ProblemReportAvailability() {
  return getAgentV2Runtime().getProblemReportAvailability();
}

export function getAgentV2DefaultThread() {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().getDefaultThread());
}

export function listAgentV2Threads(params: AgentThreadListRequestV2 = {}) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().listThreads(params));
}

export function getAgentV2CachedThreads() {
  return runtime && isActiveRuntime(runtime) ? runtime.getCachedThreads() : Promise.resolve(undefined);
}

export function getAgentV2CachedMessages(threadId: string) {
  return runtime && isActiveRuntime(runtime) ? runtime.getCachedMessages(threadId) : Promise.resolve(undefined);
}

export function getAgentV2NewsFeed(params: AgentV2NewsFeedRequest) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().getNewsFeed(params));
}

/**
 * News and digest threads include a server-created post. Opening them does not require starting a run.
 */
export function createAgentV2Thread(params: Omit<AgentThreadCreateRequestV2, 'protocolVersion'> = {}) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().createThread(params));
}

export function updateAgentV2Thread(threadId: string, update: AgentV2ThreadUpdate) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().updateThread(threadId, update));
}

export function deleteAgentV2Thread(threadId: string) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().deleteThread(threadId));
}

export function getAgentV2Messages(threadId: string, cursor?: string, limit?: number) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().getMessages(threadId, cursor, limit));
}

export function startAgentV2Run(command: AgentV2RunCommand) {
  return getAgentV2Runtime().startRun(command);
}

export function retryAgentV2Run(clientRunId: string) {
  return getAgentV2Runtime().retryRun(clientRunId);
}

export function cancelAgentV2Run(runId: string) {
  return getAgentV2Runtime().cancelRun(runId);
}

/** Stops every answer of the thread at once; the runtime cancels them on the server by itself */
export function stopAgentV2Run(threadId: string) {
  return getAgentV2Runtime().stopRun(threadId);
}

export function clearAgentV2Thread(threadId: string, expectedRevision: number) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().clearThread(threadId, expectedRevision));
}

export function reportAgentV2Problem(threadId: string, report: AgentV2ProblemReport) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().reportProblem(threadId, report));
}

export function transcribeAgentV2Audio(transcription: AgentV2Transcription) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().transcribe(transcription));
}

export function setAgentV2MessageFeedback(threadId: string, messageId: string, feedback?: AgentAnswerFeedbackV2) {
  return runSafeAgentV2Operation(() => getAgentV2Runtime().setMessageFeedback(threadId, messageId, feedback));
}

export function resolveAgentV2Action(messageId: string, actionId: string) {
  return getAgentV2Runtime().resolveAction(messageId, actionId);
}

export function getAgentV2ActionPresentation(messageId: string, actionId: string) {
  return getAgentV2Runtime().getActionPresentation(messageId, actionId);
}

export function destroyAgentV2({
  shouldClearPersistentIdentity = false,
}: { shouldClearPersistentIdentity?: boolean } = {}) {
  return enqueueLifecycleTransition(async () => {
    const currentRuntime = runtime;
    runtime = undefined;
    try {
      await currentRuntime?.destroy({ shouldClearPersistentIdentity });
    } finally {
      if (shouldClearPersistentIdentity) await clearAgentV2PersistentState(storage);
    }
  });
}

function isActiveRuntime(instance?: AgentV2Runtime): instance is AgentV2Runtime {
  return lifecycleTransitionCount === 0 && runtime === instance;
}

function enqueueLifecycleTransition(operation: () => Promise<void>) {
  lifecycleTransitionCount += 1;
  const execute = async () => {
    try {
      await operation();
    } finally {
      lifecycleTransitionCount -= 1;
      if (!lifecycleTransitionCount) lifecycleQueue = undefined;
    }
  };
  const transition = lifecycleQueue ? lifecycleQueue.then(execute) : execute();
  lifecycleQueue = transition.catch(() => undefined);
  return transition;
}

export function recordAgentV2Telemetry(events: ClientTimingEvent[]) {
  runtime?.recordDevelopmentTelemetry(events);
}

export function setAgentV2ChatActive(isActive: boolean) {
  return getAgentV2Runtime().setChatActive(isActive);
}
