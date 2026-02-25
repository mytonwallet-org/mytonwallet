import type { AccountChain } from '../../global/types';
import type { StorageKey } from '../storages/types';
import type {
  ApiAccountAny,
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiChain,
  ApiNetwork,
  ApiWalletByChain,
} from '../types';

import { buildAccountId, parseAccountId } from '../../util/account';
import { mapValues } from '../../util/iteratees';
import { storage } from '../storages';

const MIN_ACCOUNT_NUMBER = 0;

export let loginResolve: AnyFunction;
const loginPromise = new Promise<void>((resolve) => {
  loginResolve = resolve;
});

export async function getAccountIds(): Promise<string[]> {
  return Object.keys(await storage.getItem('accounts') || {});
}

export async function getAccountWithMnemonic() {
  const byId = await fetchStoredAccounts();

  return Object.entries(byId)
    .find(([, { type }]) => type !== 'ledger' && type !== 'view') as [string, ApiAccountWithMnemonic] | undefined;
}

export async function getNewAccountId(network: ApiNetwork, preferredId?: number) {
  const ids = (await getAccountIds()).map((accountId) => parseAccountId(accountId).id);
  const id = preferredId !== undefined && !ids.includes(preferredId)
    ? preferredId
    : ids.length === 0 ? MIN_ACCOUNT_NUMBER : Math.max(...ids) + 1;
  return buildAccountId({ id, network });
}

export async function fetchStoredAddress(accountId: string, chain: ApiChain): Promise<string> {
  return (await fetchStoredChainAccount(accountId, chain)).byChain[chain].address;
}

export async function fetchStoredWallet<T extends ApiChain>(accountId: string, chain: T) {
  return (await fetchStoredChainAccount(accountId, chain)).byChain[chain] as ApiWalletByChain[T];
}

export function fetchMaybeStoredAccount<T extends ApiAccountAny>(accountId: string): Promise<T | undefined> {
  return getAccountValue(accountId, 'accounts');
}

export async function fetchStoredAccount<T extends ApiAccountAny>(accountId: string): Promise<T> {
  const account = await fetchMaybeStoredAccount<T>(accountId);
  if (account) return account;
  throw new Error(`Account ${accountId} doesn't exist`);
}

export async function fetchStoredChainAccount<T extends ApiChain>(accountId: string, chain: T) {
  const account = await fetchStoredAccount(accountId);
  if (account.byChain[chain]) return account as ApiAccountWithChain<T>;
  throw new Error(`${chain} wallet missing in account ${accountId}`);
}

export async function getAccountIdByAddress<T extends ApiChain>(address: string, chain: T) {
  const accounts = await fetchStoredAccounts();
  const found = Object.entries(accounts).find((e) => e[1].byChain[chain]?.address === address && e[1].type !== 'view');
  if (!found) {
    throw new Error(`${chain} account missing by address ${address}`);
  }
  return found[0];
}

export async function fetchStoredAccounts(): Promise<Record<string, ApiAccountAny>> {
  return (await storage.getItem('accounts')) ?? {};
}

export async function updateStoredAccount<T extends ApiAccountAny>(
  accountId: string,
  partial: Partial<T>,
): Promise<void> {
  const account = await fetchStoredAccount<T>(accountId);
  return setAccountValue(accountId, 'accounts', {
    ...account,
    ...partial,
  });
}

export async function updateStoredWallet<T extends ApiChain>(
  accountId: string,
  chain: T,
  partial: Partial<ApiWalletByChain[T]>,
): Promise<void> {
  const account = await fetchStoredChainAccount(accountId, chain);
  return updateStoredAccount(accountId, {
    byChain: {
      ...account.byChain,
      [chain]: {
        ...account.byChain[chain],
        ...partial,
      },
    },
  });
}

export async function getAccountValue(accountId: string, key: StorageKey) {
  return (await storage.getItem(key))?.[accountId];
}

export async function removeAccountValue(accountId: string, key: StorageKey) {
  const data = await storage.getItem(key);
  if (!data) return;

  const { [accountId]: removedValue, ...restData } = data;
  await storage.setItem(key, restData);
}

export async function setAccountValue(accountId: string, key: StorageKey, value: any) {
  const data = await storage.getItem(key);
  await storage.setItem(key, { ...data, [accountId]: value });
}

export async function removeNetworkAccountsValue(network: string, key: StorageKey) {
  const data = await storage.getItem(key);
  if (!data) return;

  for (const accountId of Object.keys(data)) {
    if (parseAccountId(accountId).network === network) {
      delete data[accountId];
    }
  }

  await storage.setItem(key, data);
}

export async function getCurrentNetwork() {
  const accountId = await getCurrentAccountId();
  if (!accountId) return undefined;
  return parseAccountId(accountId).network;
}

export async function getCurrentAccountIdOrFail() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    throw new Error('The user is not authorized in the wallet');
  }
  return accountId;
}

export function getCurrentAccountId(): Promise<string | undefined> {
  return storage.getItem('currentAccountId');
}

export function waitLogin() {
  return loginPromise;
}

export function getAccountChains(account: ApiAccountAny): Partial<Record<ApiChain, AccountChain>> {
  return mapValues(account.byChain, (wallet) => ({
    address: wallet.address,
  }));
}

export function doesAccountHaveChain<T extends ApiChain>(
  account: ApiAccountAny,
  chain: T,
): account is ApiAccountWithChain<T> {
  return !!account.byChain[chain];
}
