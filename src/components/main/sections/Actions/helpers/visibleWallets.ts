import type { Account } from '../../../../../global/types';

const MAX_VISIBLE_WALLETS = 16;
const MAX_SETTINGS_WALLETS_WITHOUT_SHOW_ALL = 6;
const SETTINGS_WALLETS_WITH_SHOW_ALL = 5;

export function getVisibleWallets(
  orderedAccounts: Array<[string, Account]>,
  currentAccountId: string | undefined,
  isInSettings: boolean,
) {
  if (!isInSettings) {
    return {
      visibleWallets: orderedAccounts.slice(0, MAX_VISIBLE_WALLETS),
      hasExcessWallets: orderedAccounts.length > MAX_VISIBLE_WALLETS,
    };
  }

  // The current wallet is shown by the header above the list
  const otherWallets = orderedAccounts.filter(([accountId]) => accountId !== currentAccountId);
  const hasExcessWallets = otherWallets.length > MAX_SETTINGS_WALLETS_WITHOUT_SHOW_ALL;

  return {
    visibleWallets: hasExcessWallets ? otherWallets.slice(0, SETTINGS_WALLETS_WITH_SHOW_ALL) : otherWallets,
    hasExcessWallets,
  };
}
