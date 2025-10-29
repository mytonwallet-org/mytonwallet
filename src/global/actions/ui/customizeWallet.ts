import type { GlobalState } from '../../types';
import { SettingsState } from '../../types';

import { callActionInMain } from '../../../util/multitab';
import { IS_DELEGATED_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler } from '../../index';

addActionHandler('openCustomizeWalletModal', (global, actions, payload): GlobalState => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openCustomizeWalletModal', payload);
    return global;
  }
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
