import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import { MYTONWALLET_MULTISEND_DAPP_URL } from '../../../../../config';
import { vibrate } from '../../../../../util/haptics';
import { getTranslation } from '../../../../../util/langProvider';
import { openUrl } from '../../../../../util/openUrl';
import { getHostnameFromUrl } from '../../../../../util/url';

import { getIsPortrait } from '../../../../../hooks/useDeviceScreen';

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

export function handleSendMenuItemClick(value: MenuHandler) {
  switch (value) {
    case 'send':
      void vibrate();
      getActions().startTransfer({ isPortrait: getIsPortrait() });
      break;

    case 'multisend':
      void vibrate();
      void openUrl(MYTONWALLET_MULTISEND_DAPP_URL, {
        title: getTranslation('Multisend'),
        subtitle: getHostnameFromUrl(MYTONWALLET_MULTISEND_DAPP_URL),
      });
      break;

    case 'sell':
      void vibrate();
      getActions().openOffRampWidgetModal();
      break;
  }
}
