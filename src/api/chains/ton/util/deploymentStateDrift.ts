import { logDebug } from '../../../../util/logs';

// The stored flag only ever moves to true, so the chain answering anything but active is the one
// direction in which the two can disagree.
export function logDeploymentStateDrift(
  address: string,
  storedIsInitialized: boolean | undefined,
  isInitializedOnChain: boolean,
) {
  if (storedIsInitialized && !isInitializedOnChain) {
    logDebug('The stored wallet deployment state disagrees with the chain', { address });
  }
}
