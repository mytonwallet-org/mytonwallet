import type { Account, AccountSettings } from '../../../../global/types';

// Common props for AccountsGridView and AccountsListView components
export type AccountsViewCommonProps = {
  isActive: boolean;
  isTestnet?: boolean;
  filteredAccounts: Array<[string, Account]>;
  activeTab: AccountTab;
  balancesByAccountId: Record<string, string>;
  settingsByAccountId: Record<string, AccountSettings>;
  currentAccountId: string;
  isSensitiveDataHidden?: true;
  onScrollInitialize: NoneToVoidFunction;
  onScroll: AnyToVoidFunction;
  onSwitchAccount: (accountId: string) => void;
  onRename: (accountId: string) => void;
  onReorder: NoneToVoidFunction;
  onLogOut: (accountId: string) => void;
};

export const enum AccountTab {
  All,
  My,
  Ledger,
  View,
}

export const TAB_TITLES = {
  [AccountTab.All]: 'All',
  [AccountTab.My]: 'My',
  [AccountTab.Ledger]: 'Ledger',
  [AccountTab.View]: '$view_accounts',
};

export const DEFAULT_TAB = AccountTab.All;

export const OPEN_CONTEXT_MENU_CLASS_NAME = 'open-context-menu';
