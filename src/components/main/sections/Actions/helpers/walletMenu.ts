import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import getTestId from '../../../../../util/getTestId';
import { vibrate } from '../../../../../util/haptics';

export type MenuHandler = 'rename' | 'customize' | 'manage' | 'remove';

export const WALLET_CONTEXT_MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  name: 'Rename',
  fontIcon: 'menu-rename',
  value: 'rename',
  testId: getTestId('wallet_name_menu_rename'),
}, {
  name: 'Customize',
  fontIcon: 'menu-magic',
  value: 'customize',
  testId: getTestId('wallet_name_menu_customize'),
}, {
  name: 'Manage Wallets',
  fontIcon: 'menu-list',
  value: 'manage',
  testId: getTestId('wallet_name_menu_manage'),
}, {
  name: 'Remove',
  fontIcon: 'menu-trash',
  value: 'remove',
  isDangerous: true,
}];

export const SETTINGS_WALLET_MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  name: 'Rename Wallet',
  fontIcon: 'menu-rename',
  value: 'rename',
  testId: getTestId('settings_menu_rename'),
}, {
  name: 'Remove Wallet',
  fontIcon: 'menu-trash',
  value: 'remove',
  isDangerous: true,
}];

export function handleWalletMenuItemClick(
  value: MenuHandler,
  accountId: string,
  onRemove: (accountId: string) => void,
) {
  const {
    openWalletRenameModal, switchAccount, openCustomizeWalletModal, openAccountSelector,
  } = getActions();

  vibrate();

  switch (value) {
    case 'rename':
      openWalletRenameModal({ accountId });
      break;

    case 'customize':
      switchAccount({ accountId });
      // There is no parent modal to return to
      openCustomizeWalletModal({ returnTo: undefined });
      break;

    case 'manage':
      openAccountSelector();
      break;

    case 'remove':
      onRemove(accountId);
      break;
  }
}
