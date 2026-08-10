import type { ApiChain, ApiLedgerAccountInfo, ApiNetwork } from '../../api/types';
import type { LegacyAuthConfig } from '../../enclave';
import type { Account, AccountSettings, AccountState, GlobalState, UserToken } from '../types';

import { parseAccountId } from '../../util/account';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount, { getIsViewAccountDisabled } from '../../util/isViewAccount';
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

export function selectHasMultipleAccounts(global: GlobalState) {
  const accountsById = global.accounts?.byId;

  return Boolean(accountsById && isKeyCountGreater(accountsById, 1));
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

/** Whether the Enclave holds an auth method, i.e. whether it can decrypt anything at all. */
export function selectHasAuth(global: GlobalState) {
  return Boolean(global.authTypes?.length);
}

/**
 * Whether the user already owns a password - either an Enclave auth or a legacy pre-Enclave one that the
 * next `PasswordForm` migrates. Routing that picks between creating the first credential and asking for
 * the existing one must use this: a not-yet-migrated user has no Enclave auth yet still has a password,
 * and offering to create another one mints a master key that strands their secrets.
 */
export function selectHasPassword(global: GlobalState) {
  return selectHasAuth(global) || selectIsLegacyPasswordPresent(global);
}

/** Checks if there are any legacy accounts (memoized) */
const selectIsLegacyPasswordPresentMemoized = memoize((accounts: Record<string, Account> | undefined) => {
  return Object.values(accounts ?? {}).some(isMnemonicAccount);
});

/** Checks if there are any legacy accounts */
export function selectIsLegacyPasswordPresent(global: GlobalState) {
  return selectIsLegacyPasswordPresentMemoized(selectAccounts(global));
}

/**
 * Checks if migration from legacy auth to Enclave is needed: the user holds a pre-Enclave password but no
 * Enclave auth yet. Only mnemonic accounts count - a hardware-only or view-only wallet has no password to
 * migrate, and treating it as pending would send it into a migration that finds nothing to decrypt.
 */
export function selectShouldMigrate(global: GlobalState) {
  return !selectHasAuth(global) && selectIsLegacyPasswordPresent(global);
}

/**
 * Gets the legacy auth config from settings.
 * Returns `undefined` if no legacy config exists.
 */
export function selectLegacyAuthConfig(global: GlobalState) {
  return (global.settings as any).authConfig as LegacyAuthConfig | undefined;
}

/**
 * Checks if user had biometrics enabled in the legacy auth system.
 * This is used during migration to prompt user to re-enable biometrics.
 */
export function selectHasLegacyBiometrics(global: GlobalState) {
  const legacyAuthConfig = selectLegacyAuthConfig(global);
  return Boolean(legacyAuthConfig && legacyAuthConfig.kind !== 'password');
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

/**
 * @deprecated Use only for legacy (pre-Enclave) auth detection
 */
function selectIsLegacyBiometricAuthEnabled(global: GlobalState): boolean {
  const legacyAuthConfig = (global.settings as any).authConfig as
    | { kind: 'password' | 'webauthn' | 'native-biometrics' | 'electron-safe-storage' }
    | undefined;

  return Boolean(legacyAuthConfig && legacyAuthConfig.kind !== 'password');
}

export function selectIsBiometricAuthEnabled(global: GlobalState) {
  // New Enclave format
  if (global.authTypes?.length) {
    return global.authTypes.includes('biometric');
  }

  // Legacy format
  return selectIsLegacyBiometricAuthEnabled(global);
}

export function selectIsAllowSuspiciousActions(global: GlobalState, accountId: string) {
  const accountSettings = selectAccountSettings(global, accountId);

  return accountSettings?.isAllowSuspiciousActions ?? false;
}

export function selectIsCurrentAccountViewMode(global: GlobalState) {
  const account = selectCurrentAccount(global);

  return account ? getIsViewAccountDisabled(account) : isViewAccount();
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
