import * as tonWebMnemonic from 'tonweb-mnemonic';

import type { DappProtocolType, DappSignDataResult } from '../dappProtocols';
import type { ApiDappRequestConfirmation } from '../dappProtocols/adapters/tonConnect/types';
import type { ApiRevokeWalletPermissionOptions, ApiTonPlugin, ApiWalletPermission } from '../types/misc';
import {
  type ApiAnyDisplayError,
  type ApiChain,
  type ApiNetwork,
  type ApiSignedTransfer,
} from '../types';

import { parseAccountId } from '../../util/account';
import chains from '../chains';
import {
  fetchStoredAddress,
} from '../common/accounts';
import * as dappPromises from '../common/dappPromises';
import { getMnemonic } from '../common/mnemonic';

export function fetchPrivateKey(accountId: string, chain: ApiChain, enclaveToken: string) {
  return chains[chain].fetchPrivateKeyString(accountId, enclaveToken);
}

export async function fetchMnemonic(accountId: string, enclaveToken: string) {
  return getMnemonic(accountId, enclaveToken);
}

export function getMnemonicWordList() {
  return tonWebMnemonic.wordlists.default;
}

export function confirmDappRequest(promiseId: string, enclaveToken?: string) {
  dappPromises.resolveDappPromise(promiseId, enclaveToken);
}

export function confirmDappRequestConnect(promiseId: string, data: ApiDappRequestConfirmation) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function confirmDappRequestSendTransaction<T extends DappProtocolType>(
  promiseId: string,
  data: ApiSignedTransfer<T>[] | { mfaRequestHash: string },
) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function confirmDappRequestSignData<T extends DappProtocolType>(
  promiseId: string,
  signedData: DappSignDataResult<T>,
) {
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

export async function fetchWalletPermissions(accountId: string, chain: ApiChain): Promise<ApiWalletPermission[]> {
  const { network } = parseAccountId(accountId);
  const address = await fetchStoredAddress(accountId, chain);

  return chains[chain].fetchWalletPermissions(network, address);
}

export async function fetchWalletPlugins(accountId: string): Promise<ApiTonPlugin[]> {
  const { network } = parseAccountId(accountId);
  const address = await fetchStoredAddress(accountId, 'ton');

  return chains.ton.fetchWalletPlugins(network, address);
}

export async function revokeWalletPermission(
  chain: ApiChain,
  options: ApiRevokeWalletPermissionOptions,
): Promise<{ txId: string } | { error: ApiAnyDisplayError }> {
  return chains[chain].revokeWalletPermission(options);
}
