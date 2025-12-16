import nacl from 'tweetnacl';

import type { Theme } from '../../global/types';
import type { StorageKey } from '../storages/types';
import type { ApiAnyDisplayError, ApiBaseCurrency, ApiChain } from '../types';

import { setIsAppFocused } from '../../util/focusAwareDelay';
import { getLogs, logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import chains from '../chains';
import { fetchStoredAccounts, fetchStoredWallet, updateStoredWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { hexToBytes } from '../common/utils';
import { SEC } from '../constants';
import { handleServerError } from '../errors';
import { storage } from '../storages';

const SIGN_MESSAGE = Buffer.from('MyTonWallet_AuthToken_n6i0k4w8pb');

export async function getBackendAuthToken(accountId: string, password: string) {
  const accountWallet = await fetchStoredWallet(accountId, 'ton');
  let { authToken } = accountWallet;
  const { publicKey, isInitialized } = accountWallet;

  if (!authToken) {
    const privateKey = await chains.ton.fetchPrivateKeyString(accountId, password);
    const signature = nacl.sign.detached(SIGN_MESSAGE, hexToBytes(privateKey!));
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

export { setIsAppFocused, getLogs };

export async function getMoonpayOnrampUrl(chain: ApiChain, address: string, theme: Theme, currency: ApiBaseCurrency) {
  try {
    return await callBackendGet<{ url: string }>('/onramp-url', {
      chain,
      address,
      theme,
      currency: currency.toLowerCase(),
    });
  } catch (err) {
    logDebugError('getMoonpayOnrampUrl', err);

    return handleServerError(err);
  }
}

export async function getMoonpayOfframpUrl(
  chain: ApiChain,
  address: string,
  theme: Theme,
  currency: ApiBaseCurrency,
  amount: string,
  baseUrl: string,
) {
  try {
    return await callBackendGet<{ url: string }>('/offramp-url', {
      chain,
      address,
      theme,
      currency: currency.toLowerCase(),
      amount,
      baseUrl,
    });
  } catch (err) {
    logDebugError('getMoonpayOfframpUrl', err);

    return handleServerError(err);
  }
}

export function waitForLedgerApp(chain: ApiChain, options: {
  timeout?: number;
  attemptPause?: number;
} = {}): Promise<boolean | { error: ApiAnyDisplayError }> {
  const {
    timeout = 1.25 * SEC,
    attemptPause = 0.125 * SEC,
  } = options;

  let hasTimedOut = false;

  const waitForDeadline = async () => {
    await pause(timeout);
    hasTimedOut = true;
    return false;
  };

  const checkApp = async () => {
    while (!hasTimedOut) {
      try {
        const result = await chains[chain].getIsLedgerAppOpen();
        if (typeof result === 'object' && 'error' in result) return result;

        if (result) {
          return true;
        }
      } catch (err) {
        logDebugError('waitForLedgerApp', chain, err);
      }

      await pause(attemptPause);
    }

    return false;
  };

  return Promise.race([waitForDeadline(), checkApp()]);
}
