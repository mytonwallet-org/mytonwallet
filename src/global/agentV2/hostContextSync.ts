import { addCallback, removeCallback } from '../../lib/teact/teactn';
import { getGlobal } from '../../global';

import type {
  AgentV2HostContextSnapshot,
  AgentV2HostContextUpdate,
  AgentV2OperationResult,
} from '../../api/agentV2/types';
import type { GlobalState } from '../../global/types';

import {
  cancelAgentV2ActiveRunReplays,
  getLatestAgentV2RuntimeGeneration,
  subscribeToAgentV2RuntimeReady,
} from '../../util/agentV2Updates';
import { areDeepEqual } from '../../util/areDeepEqual';
import { callApi } from '../../api';
import { selectAgentV2HostContext } from './buildHostContext';

const HOST_CONTEXT_UPDATE_DELAY_MS = 5_000;
const HOST_CONTEXT_RETRY_INITIAL_DELAY_MS = 250;
const HOST_CONTEXT_RETRY_MAX_DELAY_MS = 4_000;
const HOST_CONTEXT_RETRY_MAX_EXPONENT = Math.log2(
  HOST_CONTEXT_RETRY_MAX_DELAY_MS / HOST_CONTEXT_RETRY_INITIAL_DELAY_MS,
);

export interface AgentV2HostContextDeliveryState {
  generation: number;
  isReady: boolean;
}

export interface AgentV2HostContextDeliveryNotifier {
  getCurrent(): AgentV2HostContextDeliveryState;
  subscribe(listener: (state: AgentV2HostContextDeliveryState) => void): () => void;
}

interface AgentV2HostContextDeliveryController {
  destroy(): void;
  updateSnapshot(): void;
}

interface AgentV2HostContextDeliveryControllerOptions {
  getSnapshot(): AgentV2HostContextSnapshot;
  deliver(snapshot: AgentV2HostContextSnapshot): Promise<AgentV2HostContextDeliveryResult | undefined>;
  notifier: AgentV2HostContextDeliveryNotifier;
}

type AgentV2HostContextDeliveryResult = AgentV2OperationResult<AgentV2HostContextUpdate>;

const DEFAULT_DELIVERY_NOTIFIER: AgentV2HostContextDeliveryNotifier = {
  getCurrent: () => {
    const generation = getLatestAgentV2RuntimeGeneration();
    return {
      generation: generation ?? 0,
      isReady: generation !== undefined,
    };
  },
  subscribe: (listener) => subscribeToAgentV2RuntimeReady((generation) => {
    listener({ generation, isReady: true });
  }),
};

export function startAgentV2HostContextSync(
  deliveryNotifier: AgentV2HostContextDeliveryNotifier = DEFAULT_DELIVERY_NOTIFIER,
): NoneToVoidFunction {
  const controller = createAgentV2HostContextDeliveryController({
    getSnapshot: () => selectAgentV2HostContext(getGlobal()),
    deliver: updateHostContext,
    notifier: deliveryNotifier,
  });
  let previousGlobal = getGlobal();
  // Projection and delivery run in their own task, outside global callbacks and UI rendering.
  let updateTimer: ReturnType<typeof setTimeout> | undefined = setTimeout(updateSnapshot, 0);

  function updateSnapshot() {
    updateTimer = undefined;
    controller.updateSnapshot();
  }

  function onGlobalChange(global: GlobalState) {
    // Wallet authority and user settings must not wait for the polling batch.
    const shouldUpdatePromptly = global.currentAccountId !== previousGlobal.currentAccountId
      || global.accounts?.byId !== previousGlobal.accounts?.byId
      || global.settings !== previousGlobal.settings
      || global.restrictions !== previousGlobal.restrictions
      || Object.keys(global.byAccountId).some((id) => (
        global.byAccountId[id]?.savedAddresses !== previousGlobal.byAccountId[id]?.savedAddresses
      ));
    previousGlobal = global;

    if (updateTimer !== undefined) {
      if (!shouldUpdatePromptly) return;
      clearTimeout(updateTimer);
    }

    // Do not restart this delay on each update: continuous polling must still make progress.
    updateTimer = setTimeout(updateSnapshot, shouldUpdatePromptly ? 0 : HOST_CONTEXT_UPDATE_DELAY_MS);
  }

  addCallback(onGlobalChange);

  return () => {
    removeCallback(onGlobalChange);
    clearTimeout(updateTimer);
    controller.destroy();
  };
}

export function createAgentV2HostContextDeliveryController({
  getSnapshot,
  deliver,
  notifier,
}: AgentV2HostContextDeliveryControllerOptions): AgentV2HostContextDeliveryController {
  let deliveryState = notifier.getCurrent();
  let latestSnapshot: AgentV2HostContextSnapshot | undefined;
  let pendingSnapshot: AgentV2HostContextSnapshot | undefined;
  let acknowledgedSnapshot: AgentV2HostContextSnapshot | undefined;
  let acknowledgedGeneration: number | undefined;
  let inFlightSnapshot: AgentV2HostContextSnapshot | undefined;
  let retryTimer: ReturnType<typeof setTimeout> | undefined;
  let retryExponent = 0;
  let deliveryEpoch = 0;
  let isDestroyed = false;

  const unsubscribe = notifier.subscribe(updateDeliveryState);

  return {
    destroy,
    updateSnapshot,
  };

  function updateSnapshot() {
    const snapshot = getSnapshot();
    if (latestSnapshot === snapshot) return;
    if (latestSnapshot && areDeepEqual(latestSnapshot, snapshot)) return;

    latestSnapshot = snapshot;
    retryExponent = 0;
    clearRetryTimer();
    if (
      !inFlightSnapshot
      && acknowledgedGeneration === deliveryState.generation
      && acknowledgedSnapshot
      && areDeepEqual(acknowledgedSnapshot, snapshot)
    ) {
      pendingSnapshot = undefined;
      return;
    }

    pendingSnapshot = snapshot;
    deliverPendingSnapshot(snapshot);
  }

  function updateDeliveryState(nextState: AgentV2HostContextDeliveryState) {
    deliveryState = nextState;
    deliveryEpoch += 1;
    acknowledgedSnapshot = undefined;
    acknowledgedGeneration = undefined;
    pendingSnapshot = latestSnapshot;
    retryExponent = 0;
    clearRetryTimer();
    deliverPendingSnapshot();
  }

  function deliverPendingSnapshot(currentSnapshot?: AgentV2HostContextSnapshot) {
    if (
      isDestroyed
      || !deliveryState.isReady
      || inFlightSnapshot
      || retryTimer !== undefined
      || !pendingSnapshot
    ) return;

    // Retries and runtime recovery must include changes still waiting for the polling batch
    const snapshot = currentSnapshot ?? getSnapshot();
    latestSnapshot = snapshot;
    const generation = deliveryState.generation;
    const epoch = deliveryEpoch;
    pendingSnapshot = undefined;
    inFlightSnapshot = snapshot;
    void deliver(snapshot).then(
      (result) => settleDelivery(snapshot, generation, epoch, result),
      () => settleDelivery(snapshot, generation, epoch, undefined),
    );
  }

  function settleDelivery(
    snapshot: AgentV2HostContextSnapshot,
    generation: number,
    epoch: number,
    result: AgentV2HostContextDeliveryResult | undefined,
  ) {
    if (inFlightSnapshot !== snapshot) return;

    inFlightSnapshot = undefined;
    if (isDestroyed) return;

    const isCurrentGeneration = generation === deliveryState.generation
      && epoch === deliveryEpoch
      && deliveryState.isReady;
    if (result?.ok && result.value.generation === generation && isCurrentGeneration) {
      acknowledgedSnapshot = snapshot;
      acknowledgedGeneration = generation;
      retryExponent = 0;
      if (pendingSnapshot && areDeepEqual(pendingSnapshot, snapshot)) pendingSnapshot = undefined;
      if (!pendingSnapshot && latestSnapshot && !areDeepEqual(latestSnapshot, snapshot)) {
        pendingSnapshot = latestSnapshot;
      }
      deliverPendingSnapshot();
      return;
    }

    acknowledgedSnapshot = undefined;
    acknowledgedGeneration = undefined;
    pendingSnapshot = latestSnapshot;
    if (generation !== deliveryState.generation || epoch !== deliveryEpoch) {
      retryExponent = 0;
      deliverPendingSnapshot();
      return;
    }
    scheduleRetry();
  }

  function scheduleRetry() {
    if (isDestroyed || !deliveryState.isReady || retryTimer !== undefined || !pendingSnapshot) return;

    const delay = HOST_CONTEXT_RETRY_INITIAL_DELAY_MS * (2 ** retryExponent);
    retryExponent = Math.min(retryExponent + 1, HOST_CONTEXT_RETRY_MAX_EXPONENT);
    retryTimer = setTimeout(() => {
      retryTimer = undefined;
      deliverPendingSnapshot();
    }, delay);
  }

  function clearRetryTimer() {
    if (retryTimer === undefined) return;
    clearTimeout(retryTimer);
    retryTimer = undefined;
  }

  function destroy() {
    if (isDestroyed) return;
    isDestroyed = true;
    clearRetryTimer();
    unsubscribe();
  }
}

async function updateHostContext(hostContext: AgentV2HostContextSnapshot) {
  const result = await callApi('updateAgentV2HostContext', hostContext);
  if (result?.ok && result.value.authorityChanged && !result.value.preservesActiveRuns) {
    cancelAgentV2ActiveRunReplays();
  }
  return result;
}
