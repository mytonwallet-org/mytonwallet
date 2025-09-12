import type { ApiChain, ApiNetwork } from '../../api/types';
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

export function selectCurrentNetwork(global: GlobalState) {
  return global.settings.isTestnet ? 'testnet' : 'mainnet';
}

export function selectCurrentAccount(global: GlobalState) {
  return selectAccount(global, global.currentAccountId!);
}

export function selectAccount(global: GlobalState, accountId: string) {
  return selectAccounts(global)?.[accountId];
}

export function selectAccountOrAuthAccount(global: GlobalState, accountId: string) {
  const account = selectAccount(global, accountId);
  if (account) {
    return account;
  }

  for (const account of [global.auth.firstNetworkAccount, global.auth.secondNetworkAccount]) {
    if (account?.accountId === accountId) {
      return account;
    }
  }

  return undefined;
}

export function selectCurrentAccountState(global: GlobalState) {
  return selectAccountState(global, global.currentAccountId!);
}

export function selectAccountState(global: GlobalState, accountId: string): AccountState | undefined {
  return global.byAccountId[accountId];
}

export function selectAccountSettings(global: GlobalState, accountId: string): AccountSettings | undefined {
  return global.settings.byAccountId[accountId];
}

export function selectCurrentAccountSettings(global: GlobalState) {
  return selectAccountSettings(global, global.currentAccountId!);
}

function isHardwareAccount(account: Account) {
  return account.type === 'hardware';
}

export function selectIsHardwareAccount(global: GlobalState): boolean; // To prevent passing accountId=undefined by accident
export function selectIsHardwareAccount(global: GlobalState, accountId: string): boolean;
export function selectIsHardwareAccount(global: GlobalState, accountId?: string) {
  const account = selectAccount(global, accountId ?? global.currentAccountId!);
  return Boolean(account) && isHardwareAccount(account);
}

export function selectAllHardwareAccounts(global: GlobalState, network: ApiNetwork) {
  const accounts = selectAccounts(global);

  return Object.entries(accounts ?? {}).reduce<Account[]>((accounts, [accountId, account]) => {
    if (isHardwareAccount(account) && parseAccountId(accountId).network === network) {
      accounts.push(account);
    }
    return accounts;
  }, []);
}

export function selectIsOneAccount(global: GlobalState) {
  return Object.keys(selectAccounts(global) || {}).length === 1;
}

export const selectEnabledTokensCountMemoizedFor = withCache((accountId: string) => memoize((tokens?: UserToken[]) => {
  return (tokens ?? []).filter(({ isDisabled }) => !isDisabled).length;
}));

export function selectLedgerAccountIndexToImport(global: GlobalState, network: ApiNetwork) {
  const hardwareAccounts = selectAllHardwareAccounts(global, network);
  const hardwareAccountIndexes = hardwareAccounts?.map((account) => account.ledger!.index)
    .sort((a, b) => a - b);

  if (hardwareAccountIndexes.length === 0 || hardwareAccountIndexes[0] !== 0) {
    return -1;
  }

  if (hardwareAccountIndexes.length === 1) {
    return 0;
  }

  for (let i = 1; i < hardwareAccountIndexes.length; i++) {
    if (hardwareAccountIndexes[i] - hardwareAccountIndexes[i - 1] !== 1) {
      return i - 1;
    }
  }

  return hardwareAccountIndexes.length - 1;
}

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
  return selectAccountNftByAddress(global, global.currentAccountId!, nftAddress);
}

export function selectAccountNftByAddress(global: GlobalState, accountId: string, nftAddress: string) {
  return selectAccountState(global, accountId)?.nfts?.byAddress?.[nftAddress];
}

export function selectIsMultichainAccount(global: GlobalState, accountId: string) {
  const byChain = selectAccount(global, accountId)?.byChain;
  return Boolean(byChain) && isKeyCountGreater(byChain, 1);
}

export function selectIsMultisigAccount(global: GlobalState, accountId: string, chain: ApiChain) {
  const account = selectAccount(global, accountId);
  return Boolean(account?.byChain[chain]?.isMultisig);
}

export function selectHasSession(global: GlobalState) {
  return Boolean(global.currentAccountId);
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

export function selectDoesAccountSupportNft(global: GlobalState) {
  const account = selectCurrentAccount(global);
  return Boolean(account?.byChain.ton);
}
