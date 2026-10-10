import type { AgentProtocolVersion } from '../../util/agent/agentOverride';
import type { OnApiUpdate } from '../types';

import { destroyAgentV2, initAgentV2 } from '../agentV2/service';
import { getEnvironment, resolveIsAgentV2Enabled, setIsAgentV2Enabled } from '../environment';

let agentV2UpdateCallback: OnApiUpdate | undefined;
let reconciliationQueue: Promise<void> | undefined;
let reconciliationCount = 0;

export async function initAgentV2IfEnabled(onUpdate: OnApiUpdate) {
  agentV2UpdateCallback = onUpdate;
  if (!getEnvironment().isAgentV2Enabled) return;
  await initAgentV2(onUpdate);
}

export function reconcileAgentV2ProtocolVersion(backendVersion?: AgentProtocolVersion) {
  return requestAgentV2State({
    isAgentV2Enabled: resolveAgentV2Enabled(backendVersion),
    shouldClearPersistentIdentity: false,
  });
}

export function resolveAgentV2ProtocolVersionForRouting(
  backendVersion?: AgentProtocolVersion,
): AgentProtocolVersion {
  if (getEnvironment().isAndroidApp) return 'v2';
  return resolveAgentV2Enabled(backendVersion) && getEnvironment().isAgentV2Enabled ? 'v2' : 'v1';
}

export function destroyAgentV2IfEnabled({
  shouldClearPersistentIdentity = false,
}: { shouldClearPersistentIdentity?: boolean } = {}) {
  if (!getEnvironment().isAgentV2Enabled && !reconciliationCount) return;
  return requestAgentV2State({ isAgentV2Enabled: false, shouldClearPersistentIdentity });
}

export function resetAgentV2() {
  return enqueueAgentV2Lifecycle(async () => {
    const isAgentV2Enabled = getEnvironment().isAgentV2Enabled;
    await destroyAgentV2({ shouldClearPersistentIdentity: true });
    if (isAgentV2Enabled) await initAgentV2(agentV2UpdateCallback!);
  });
}

async function applyAgentV2State({
  isAgentV2Enabled,
  shouldClearPersistentIdentity,
}: AgentV2StateRequest) {
  if (isAgentV2Enabled === getEnvironment().isAgentV2Enabled) return;

  if (isAgentV2Enabled) {
    await initAgentV2(agentV2UpdateCallback!);
    setIsAgentV2Enabled(true);
    return;
  }

  setIsAgentV2Enabled(false);
  await destroyAgentV2({ shouldClearPersistentIdentity });
}

function requestAgentV2State(target: AgentV2StateRequest) {
  return enqueueAgentV2Lifecycle(() => applyAgentV2State(target));
}

function enqueueAgentV2Lifecycle(operation: () => Promise<void>) {
  reconciliationCount += 1;
  const execute = async () => {
    try {
      await operation();
    } finally {
      reconciliationCount -= 1;
      if (!reconciliationCount) reconciliationQueue = undefined;
    }
  };
  const reconciliation = reconciliationQueue ? reconciliationQueue.then(execute) : execute();
  reconciliationQueue = reconciliation.catch(() => undefined);
  return reconciliation;
}

function resolveAgentV2Enabled(backendVersion?: AgentProtocolVersion) {
  const environment = getEnvironment();
  return resolveIsAgentV2Enabled(
    environment.agentOverride,
    backendVersion,
    environment.isAndroidApp,
    environment.isIosApp,
  );
}

type AgentV2StateRequest = {
  isAgentV2Enabled: boolean;
  shouldClearPersistentIdentity: boolean;
};
