import { AirAppLauncher } from '@mytonwallet/air-app-launcher';

import { DEFAULT_PRICE_CURRENCY, IS_CAPACITOR, IS_EXTENSION } from '../../../config';
import { logDebug } from '../../../util/logs';
import {
  IS_ANDROID_APP, IS_ELECTRON, IS_IOS_APP,
} from '../../../util/windowEnvironment';
import { callApi, initApi } from '../../../api';
import { removeTemporaryAccount } from '../../helpers/auth';
import { addActionHandler, getGlobal } from '../../index';
import { selectNewestActivityTimestamps } from '../../selectors';

addActionHandler('initApi', async (global, actions) => {
  logDebug('initApi action called');
  const accountIds = global.accounts?.byId
    ? Object.keys(global.accounts.byId).filter((accountId) => accountId !== global.currentTemporaryViewAccountId)
    : [];
  initApi(actions.apiUpdate, {
    isElectron: IS_ELECTRON,
    isIosApp: IS_IOS_APP,
    isAndroidApp: IS_ANDROID_APP,
    langCode: global.settings.langCode,
    referrer: new URLSearchParams(window.location.search).get('r') ?? undefined,
    accountIds,
  });

  await callApi('waitDataPreload');
  // Properly handle temporary account cleanup
  if (global.currentTemporaryViewAccountId) {
    await removeTemporaryAccount(global.currentTemporaryViewAccountId);
  }
  global = getGlobal();

  const { currentAccountId } = global;

  if (!currentAccountId) return;

  const newestActivityTimestamps = selectNewestActivityTimestamps(global, currentAccountId);

  void callApi('activateAccount', currentAccountId, newestActivityTimestamps);
});

addActionHandler('resetApiSettings', (global, actions, params) => {
  const isDefaultEnabled = !params?.areAllDisabled;

  if (IS_EXTENSION) {
    actions.toggleTonProxy({ isEnabled: false });
  }
  if (IS_EXTENSION || IS_ELECTRON) {
    actions.toggleDeeplinkHook({ isEnabled: isDefaultEnabled });
  }
  actions.changeBaseCurrency({ currency: DEFAULT_PRICE_CURRENCY });
  if (IS_CAPACITOR) void AirAppLauncher.setBaseCurrency({ currency: DEFAULT_PRICE_CURRENCY });
});
