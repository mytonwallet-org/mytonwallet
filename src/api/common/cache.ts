import type { ApiBackendConfig, ApiStakingCommonData } from '../types';

import Deferred from '../../util/Deferred';

export type AccountCache = { stakedAt?: number };

let stakingCommonCache: ApiStakingCommonData | undefined;
const stakingCommonCacheDeferred = new Deferred();

const accountCache: Record<string, AccountCache> = {};

let backendConfig: ApiBackendConfig | undefined;
const configDeferred = new Deferred();

export function getAccountCache(accountId: string, address: string) {
  return accountCache[`${accountId}:${address}`] ?? {};
}

export function updateAccountCache(accountId: string, address: string, partial: Partial<AccountCache>) {
  const key = `${accountId}:${address}`;
  accountCache[key] = { ...accountCache[key], ...partial };
}

export function setStakingCommonCache(data: ApiStakingCommonData) {
  stakingCommonCache = data;
  stakingCommonCacheDeferred.resolve();
}

export async function getStakingCommonCache() {
  await stakingCommonCacheDeferred.promise;
  return stakingCommonCache!;
}

export function setBackendConfigCache(config: ApiBackendConfig) {
  backendConfig = config;
  configDeferred.resolve();
}

/** Returns the config provided by the backend */
export async function getBackendConfigCache() {
  await configDeferred.promise;
  return backendConfig!;
}

/** Synchronous variant: returns the config only if it has already arrived, otherwise `undefined`. */
export function getBackendConfigCacheSync() {
  return backendConfig;
}

/**
 * Feature flag for the L1 retry-break (negative-verdict cache + EVM untrackable registry).
 * Reads synchronously; before the backend config arrives (or if it never does) this is `false`,
 * so the safe legacy behavior stays in force. Flipping the backend field kills it fleet-wide.
 */
export function getIsNegVerdictCacheEnabled() {
  return backendConfig?.isNegVerdictCacheEnabled ?? false;
}
