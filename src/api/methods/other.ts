import nacl from 'tweetnacl';

import type { Theme } from '../../global/types';
import type { AccountCache } from '../common/cache';
import type { StorageKey } from '../storages/types';
import type { ApiChain, ApiNetwork } from '../types';

import { setIsAppFocused } from '../../util/focusAwareDelay';
import { getLogs, logDebugError } from '../../util/logs';
import chains from '../chains';
import { fetchStoredAccounts, fetchStoredWallet, updateStoredWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { updateAccountCache } from '../common/cache';
import { handleServerError } from '../errors';
import { storage } from '../storages';

const SIGN_MESSAGE = Buffer.from('MyTonWallet_AuthToken_n6i0k4w8pb');

export function checkApiAvailability(chain: ApiChain, network: ApiNetwork) {
  return chains[chain].checkApiAvailability(network);
}

export async function getBackendAuthToken(accountId: string, password: string) {
  const accountWallet = await fetchStoredWallet(accountId, 'ton');
  let { authToken } = accountWallet;
  const { publicKey, isInitialized } = accountWallet;

  if (!authToken) {
    const privateKey = await chains.ton.fetchPrivateKey(accountId, password);
    const signature = nacl.sign.detached(SIGN_MESSAGE, privateKey!);
    authToken = Buffer.from(signature).toString('base64');

    await updateStoredWallet(accountId, 'ton', {
      authToken,
    });
  }

  if (!isInitialized) {
    authToken += `:${publicKey}`;
  }

  return authToken;
}

export async function fetchAccountConfigForDebugPurposesOnly() {
  try {
    const [accounts, stateVersion, mnemonicsEncrypted] = await Promise.all([
      fetchStoredAccounts(),
      storage.getItem('stateVersion'),
      storage.getItem('mnemonicsEncrypted' as StorageKey),
    ]);

    return JSON.stringify({ accounts, stateVersion, mnemonicsEncrypted });
  } catch (err) {
    logDebugError('fetchAccountConfigForDebugPurposesOnly', err);

    return undefined;
  }
}

export function ping() {
  return true;
}

export function updateAccountMemoryCache(accountId: string, address: string, partial: Partial<AccountCache>) {
  updateAccountCache(accountId, address, partial);
}

export { setIsAppFocused, getLogs };

export async function getMoonpayOnrampUrl(chain: ApiChain, address: string, theme: Theme) {
  try {
    return await callBackendGet<{ url: string }>('/onramp-url', {
      chain,
      address,
      theme,
    });
  } catch (err) {
    logDebugError('getMoonpayOnrampUrl', err);

    return handleServerError(err);
  }
}
