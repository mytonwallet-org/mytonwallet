import * as tonWebMnemonic from 'tonweb-mnemonic';
import type { SignDataRpcResponseSuccess } from '@tonconnect/protocol';

import type { ApiDappRequestConfirmation } from '../tonConnect/types';
import type { ApiAccountWithMnemonic, ApiAnyDisplayError, ApiChain, ApiNetwork, ApiSignedTransfer } from '../types';

import chains from '../chains';
import * as ton from '../chains/ton';
import {
  fetchStoredAccount,
  fetchStoredAccounts,
  fetchStoredAddress,
  getAccountWithMnemonic,
} from '../common/accounts';
import * as dappPromises from '../common/dappPromises';
import { getMnemonic } from '../common/mnemonic';

export async function fetchPrivateKey(accountId: string, password: string) {
  const account = await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
  const privateKey = await ton.fetchPrivateKey(accountId, password, account);

  return Buffer.from(privateKey!).toString('hex');
}

export async function fetchMnemonic(accountId: string, password: string) {
  const account = await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
  return getMnemonic(accountId, password, account);
}

export function getMnemonicWordList() {
  return tonWebMnemonic.wordlists.default;
}

export async function checkWorkerStorageIntegrity(): Promise<boolean> {
  /*
    This method is intended to check if the worker storage is corrupted due to known
    behavior of browsers (at least Chromium-based ones).
    Several users reported that their storage was corrupted on Android too.
  */
  try {
    const accounts = await fetchStoredAccounts();
    return !!accounts && typeof accounts === 'object' && Object.keys(accounts).length > 0;
  } catch {
    return false;
  }
}

export async function verifyPassword(password: string): Promise<boolean> {
  try {
    const [accountId, account] = (await getAccountWithMnemonic()) ?? [];
    if (!accountId || !account) {
      return false;
    }

    const mnemonic = await getMnemonic(accountId, password, account);
    return Boolean(mnemonic);
  } catch {
    return false;
  }
}

export function confirmDappRequest(promiseId: string, password?: string) {
  dappPromises.resolveDappPromise(promiseId, password);
}

export function confirmDappRequestConnect(promiseId: string, data: ApiDappRequestConfirmation) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function confirmDappRequestSendTransaction(promiseId: string, data: ApiSignedTransfer[]) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function confirmDappRequestSignData(promiseId: string, signedData: SignDataRpcResponseSuccess['result']) {
  dappPromises.resolveDappPromise(promiseId, signedData);
}

export function cancelDappRequest(promiseId: string, reason?: string) {
  dappPromises.rejectDappPromise(promiseId, reason);
}

export function fetchAddress(accountId: string, chain: ApiChain) {
  return fetchStoredAddress(accountId, chain);
}

export async function getAddressInfo(chain: ApiChain, network: ApiNetwork, address: string) {
  return await chains[chain].getAddressInfo(network, address);
}

/**
 * Shows the wallet address on the Ledger screen.
 * Returns the address if the user accepts the verification.
 */
export function verifyLedgerWalletAddress(
  accountId: string,
  chain: ApiChain,
): Promise<string | { error: ApiAnyDisplayError }> {
  return chains[chain].verifyLedgerWalletAddress(accountId);
}
