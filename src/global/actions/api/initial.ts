import { DEFAULT_PRICE_CURRENCY, IS_EXTENSION } from '../../../config';
import { logDebug } from '../../../util/logs';
import { IS_ELECTRON } from '../../../util/windowEnvironment';
import { callApi, initApi } from '../../../api';
import { removeTemporaryAccount } from '../../helpers/auth';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { selectNewestActivityTimestamps } from '../../selectors';

addActionHandler('initApi', async (global, actions) => {
  logDebug('initApi action called');
  const accountIds = global.accounts?.byId
    ? Object.keys(global.accounts.byId).filter((accountId) => accountId !== global.currentTemporaryViewAccountId)
    : [];
  initApi(actions.apiUpdate, {
    isElectron: IS_ELECTRON,
    isIosApp: false,
    isAndroidApp: false,
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

  if (!global.isDerivationsSynced) {
    // Migration to add derivations to the client
    const isDerivationsMigrationNeeded = Object.values(global.accounts?.byId ?? {})
      .filter((e) => Object.values(e.byChain).length > 1)
      .some((account) => Object.entries(account.byChain)
        .some(([_, acc]) => !acc?.derivation));

    if (isDerivationsMigrationNeeded) {
      await callApi('loadAccountsDerivations');
      global = getGlobal();
    }

    global = { ...global, isDerivationsSynced: true };
    setGlobal(global);
  }

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
});
