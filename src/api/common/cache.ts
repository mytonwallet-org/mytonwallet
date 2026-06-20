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
