import type { GlobalState } from '../../types';
import { SettingsState } from '../../types';

import { addActionHandler } from '../../index';

addActionHandler('openCustomizeWalletModal', (global, actions, payload): GlobalState => {
  return {
    ...global,
    isCustomizeWalletModalOpen: true,
    customizeWalletReturnTo: payload?.returnTo,
  };
});

addActionHandler('closeCustomizeWalletModal', (global, actions): GlobalState => {
  const returnTo = global.customizeWalletReturnTo;

  if (returnTo === 'settings') {
    actions.setSettingsState({ state: SettingsState.Appearance });
  } else if (returnTo === 'accountSelector') {
    actions.openAccountSelector();
  }

  return {
    ...global,
    isCustomizeWalletModalOpen: undefined,
    customizeWalletReturnTo: undefined,
  };
});
