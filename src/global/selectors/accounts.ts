import type { ApiChain, ApiLedgerAccountInfo, ApiNetwork } from '../../api/types';
import type {
  Account, AccountSettings, AccountState, GlobalState, UserToken,
} from '../types';

import { parseAccountId } from '../../util/account';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount from '../../util/isViewAccount';
import memoize from '../../util/memoize';
import withCache from '../../util/withCache';

export function selectAccounts(global: GlobalState) {
  return global.accounts?.byId;
}

export const selectNetworkAccountsMemoized = memoize((network: ApiNetwork, accountsById?: Record<string, Account>) => {
  if (!accountsById) {
    return undefined;
  }

  return Object.fromEntries(
    Object.entries(accountsById).filter(([accountId]) => parseAccountId(accountId).network === network),
  );
});

export function selectNetworkAccounts(global: GlobalState) {
  return selectNetworkAccountsMemoized(selectCurrentNetwork(global), global.accounts?.byId);
}

export function selectCurrentNetwork(global: GlobalState): ApiNetwork {
  return global.settings.isTestnet ? 'testnet' : 'mainnet';
}

export function selectCurrentAccountId(global: GlobalState) {
  return global.currentTemporaryViewAccountId ?? global.currentAccountId;
}

export function selectCurrentAccount(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccount(global, accountId) : undefined;
}

export function selectAccount(global: GlobalState, accountId: string) {
  return selectAccounts(global)?.[accountId];
}

export function selectAccountOrAuthAccount(global: GlobalState, accountId: string) {
  const account = selectAccount(global, accountId);
  if (account) {
    return account;
  }

  for (const account of global.auth.accounts ?? []) {
    if (account.accountId === accountId) {
      return account;
    }
  }

  return undefined;
}

export function selectCurrentAccountState(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountState(global, accountId) : undefined;
}

export function selectAccountState(global: GlobalState, accountId: string): AccountState | undefined {
  return global.byAccountId[accountId];
}

export function selectAccountSettings(global: GlobalState, accountId: string): AccountSettings | undefined {
  return global.settings.byAccountId[accountId];
}

export function selectCurrentAccountSettings(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountSettings(global, accountId) : undefined;
}

function isHardwareAccount(account: Account) {
  return account.type === 'hardware';
}

export function selectIsHardwareAccount(global: GlobalState): boolean; // To prevent passing accountId=undefined by accident
export function selectIsHardwareAccount(global: GlobalState, accountId: string): boolean;
export function selectIsHardwareAccount(global: GlobalState, accountId?: string) {
  const resolvedAccountId = accountId ?? selectCurrentAccountId(global);
  if (!resolvedAccountId) {
    return false;
  }

  const account = selectAccount(global, resolvedAccountId);
  return Boolean(account) && isHardwareAccount(account);
}

export function selectIsOneAccount(global: GlobalState) {
  return Object.keys(selectAccounts(global) || {}).length === 1;
}

export const selectEnabledTokensCountMemoizedFor = withCache((accountId: string) => memoize((tokens?: UserToken[]) => {
  return (tokens ?? []).filter(({ isDisabled }) => !isDisabled).length;
}));

function isMnemonicAccount(account: Account) {
  return account.type === 'mnemonic';
}

export function selectIsMnemonicAccount(global: GlobalState) {
  const account = selectCurrentAccount(global);
  return Boolean(account) && isMnemonicAccount(account);
}

const selectIsPasswordPresentMemoized = memoize((accounts: Record<string, Account> | undefined) => {
  return Object.values(accounts ?? {}).some(isMnemonicAccount);
});

export function selectIsPasswordPresent(global: GlobalState) {
  return selectIsPasswordPresentMemoized(selectAccounts(global));
}

export function selectAccountIdByAddress(
  global: GlobalState,
  chain: ApiChain,
  address: string,
): string | undefined {
  const accounts = selectAccounts(global);

  if (!accounts) return undefined;

  const requiredAccount = Object.entries(accounts)
    .find(([, account]) => account.byChain[chain]?.address === address);

  return requiredAccount?.[0];
}

// Slow, not to be used in `withGlobal`
export function selectVestingPartsReadyToUnfreeze(global: GlobalState, accountId: string) {
  const vesting = selectAccountState(global, accountId)?.vesting?.info || [];

  return vesting.reduce((acc, currentVesting) => {
    currentVesting.parts.forEach((part) => {
      if (part.status === 'ready') {
        acc.push({
          id: currentVesting.id,
          partId: part.id,
        });
      }
    });

    return acc;
  }, [] as { id: number; partId: number }[]);
}

export function selectCurrentAccountNftByAddress(global: GlobalState, nftAddress: string) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountNftByAddress(global, accountId, nftAddress) : undefined;
}

export function selectAccountNftByAddress(global: GlobalState, accountId: string, nftAddress: string) {
  return selectAccountState(global, accountId)?.nfts?.byAddress?.[nftAddress];
}

export function selectIsMultichainAccount(global: GlobalState, accountId: string) {
  const byChain = selectAccount(global, accountId)?.byChain;
  return Boolean(byChain) && isKeyCountGreater(byChain, 1);
}

export function selectIsMultisigAccount(global: GlobalState, accountId: string) {
  const account = selectAccount(global, accountId);
  return Object.values(account?.byChain ?? {}).some((wallet) => wallet.isMultisig);
}

export function selectIsMultisigWallet(global: GlobalState, accountId: string, chain: ApiChain) {
  const account = selectAccount(global, accountId);
  return Boolean(account?.byChain[chain]?.isMultisig);
}

export function selectHasSession(global: GlobalState) {
  return Boolean(selectCurrentAccountId(global));
}

export function selectIsBiometricAuthEnabled(global: GlobalState) {
  const { authConfig } = global.settings;

  return !!authConfig && authConfig.kind !== 'password';
}

export function selectIsNativeBiometricAuthEnabled(global: GlobalState) {
  const { authConfig } = global.settings;

  return !!authConfig && authConfig.kind === 'native-biometrics';
}

export function selectIsAllowSuspiciousActions(global: GlobalState, accountId: string) {
  const accountSettings = selectAccountSettings(global, accountId);

  return accountSettings?.isAllowSuspiciousActions ?? false;
}

export function selectIsCurrentAccountViewMode(global: GlobalState) {
  const { type } = selectCurrentAccount(global) || {};

  return isViewAccount(type);
}

export function selectSelectedHardwareAccountsSlow(global: GlobalState): ApiLedgerAccountInfo[] {
  const selectedIndices = new Set(global.auth.hardwareSelectedIndices ?? []);
  const { chain, hardwareWallets } = global.hardware;

  return (hardwareWallets ?? [])
    .filter((wallet) => selectedIndices.has(wallet.wallet.index))
    .map(({ wallet, balance, ...rest }) => ({
      ...rest,
      byChain: { [chain]: wallet },
    }));
}

/**
 * Since the `orderedAccountIds` array may be incomplete (the user did not sort the accounts;
 * added new ones after sorting, etc.), the function must first return all accounts
 * from `orderedAccountIds`, and then all other accounts from `accounts`.
 */
export const selectOrderedAccountsMemoized = memoize((
  orderedAccountIds: string[] | undefined,
  accounts: Record<string, Account> | undefined,
): Array<[string, Account]> => {
  if (!accounts) return [];

  const entries = Object.entries(accounts).filter(([, account]) => !account.isTemporary);
  if (!orderedAccountIds?.length) return entries;

  const accountsMap = new Map(entries);

  return [
    ...orderedAccountIds
      .map((id) => {
        const account = accountsMap.get(id);
        accountsMap.delete(id);

        return !account || account.isTemporary
          ? undefined
          : [id, account] as [string, Account];
      })
      .filter(Boolean),
    ...accountsMap.entries(),
  ];
});

export function selectOrderedAccounts(global: GlobalState) {
  const { orderedAccountIds } = global.settings;
  const accounts = selectNetworkAccounts(global);

  return selectOrderedAccountsMemoized(orderedAccountIds, accounts);
}
