import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import { vibrate } from '../../../../../util/haptics';
import { openMultisend } from '../../../../../util/openMultisend';

export type MenuHandler = 'send' | 'sell' | 'multisend';

export const SEND_CONTEXT_MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  name: 'Send',
  fontIcon: 'menu-send',
  value: 'send',
}, {
  name: 'Multisend',
  fontIcon: 'menu-multisend',
  value: 'multisend',
}, {
  name: 'Sell',
  fontIcon: 'menu-sell',
  value: 'sell',
}];

export const SEND_CONTEXT_MENU_ITEMS_WITHOUT_SELL = SEND_CONTEXT_MENU_ITEMS
  .filter(({ value }) => value !== 'sell');

export function handleSendMenuItemClick(value: MenuHandler) {
  switch (value) {
    case 'send':
      vibrate();
      getActions().startTransfer();
      break;

    case 'multisend':
      vibrate();
      void openMultisend();
      break;

    case 'sell':
      vibrate();
      getActions().openOffRampWidgetModal();
      break;
  }
}
