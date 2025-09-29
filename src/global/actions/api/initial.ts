import { AirAppLauncher } from '@mytonwallet/air-app-launcher';

import { DEFAULT_PRICE_CURRENCY, IS_CAPACITOR, IS_EXTENSION } from '../../../config';
import { logDebug } from '../../../util/logs';
import {
  IS_ANDROID_APP, IS_DELEGATED_BOTTOM_SHEET, IS_ELECTRON, IS_IOS_APP,
} from '../../../util/windowEnvironment';
import { callApi, initApi } from '../../../api';
import { addActionHandler, getGlobal } from '../../index';
import { selectNewestActivityTimestamps } from '../../selectors';

addActionHandler('initApi', async (global, actions) => {
  logDebug('initApi action called');
  const accountIds = global.accounts?.byId ? Object.keys(global.accounts.byId) : [];
  initApi(actions.apiUpdate, {
    isElectron: IS_ELECTRON,
    isNativeBottomSheet: IS_DELEGATED_BOTTOM_SHEET,
    isIosApp: IS_IOS_APP,
    isAndroidApp: IS_ANDROID_APP,
    referrer: new URLSearchParams(window.location.search).get('r') ?? undefined,
    accountIds,
  });

  await callApi('waitDataPreload');

  const { currentAccountId } = getGlobal();

  if (!currentAccountId) {
    return;
  }

  const newestActivityTimestamps = selectNewestActivityTimestamps(global, currentAccountId);

  void callApi('activateAccount', currentAccountId, newestActivityTimestamps);
});

addActionHandler('resetApiSettings', (global, actions, params) => {
  const isDefaultEnabled = !params?.areAllDisabled;

  if (IS_EXTENSION) {
    actions.toggleTonMagic({ isEnabled: false });
    actions.toggleTonProxy({ isEnabled: false });
  }
  if (IS_EXTENSION || IS_ELECTRON) {
    actions.toggleDeeplinkHook({ isEnabled: isDefaultEnabled });
  }
  actions.changeBaseCurrency({ currency: DEFAULT_PRICE_CURRENCY });
  if (IS_CAPACITOR) void AirAppLauncher.setBaseCurrency({ currency: DEFAULT_PRICE_CURRENCY });
});
