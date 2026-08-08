import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import { vibrate } from '../../../../../util/haptics';

export type MenuHandler = 'rename' | 'customize' | 'remove';

export const WALLET_CONTEXT_MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  name: 'Rename',
  fontIcon: 'menu-rename',
  value: 'rename',
}, {
  name: 'Customize',
  fontIcon: 'menu-magic',
  value: 'customize',
}, {
  name: 'Remove',
  fontIcon: 'menu-trash',
  value: 'remove',
  isDangerous: true,
}];

export function handleWalletMenuItemClick(
  value: MenuHandler,
  accountId: string,
  onRemove: (accountId: string) => void,
) {
  const { openWalletRenameModal, switchAccount, openCustomizeWalletModal } = getActions();

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

    case 'remove':
      onRemove(accountId);
      break;
  }
}
