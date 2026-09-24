import { DEFAULT_PRICE_CURRENCY, IS_AIR_APP, IS_EXTENSION } from '../../../config';
import { getAgentOverride } from '../../../util/agent/agentProtocolVersion';
import { captureBrowserAttribution } from '../../../util/installAttribution';
import { logDebug } from '../../../util/logs';
import { IS_ELECTRON, IS_WEB } from '../../../util/windowEnvironment';
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
    agentOverride: getAgentOverride(),
    langCode: global.settings.langCode,
    referrer: new URLSearchParams(window.location.search).get('r') ?? undefined,
    ...(IS_WEB && !IS_AIR_APP && ['http:', 'https:'].includes(location.protocol)
      ? captureBrowserAttribution()
      : { channel: new URLSearchParams(window.location.search).get('utm_source') ?? undefined }),
    accountIds,
  });

  // The repair clears broken auth tokens, the detection below flags accounts missing one.
  // If the detection ran first, the just-cleaned accounts would stay unflagged until the next launch.
  // Both read only the storage, so they run ahead of the data preload and a password entered right after startup
  // already budgets for the upgrade. They are awaited because the repair rewrites stored accounts, and so do the
  // migrations below. The detection covers only the accounts known here: a record left only in the storage,
  // e.g. an import whose secret was never saved, has no secret to read and would abort the upgrade.
  await callApi('repairInvalidBip39TonAuthTokens');
  const candidateIds = await callApi('getMultichainUpgradeCandidateIds', accountIds);
  if (candidateIds?.length) {
    setGlobal({
      ...getGlobal(),
      multichainUpgradeAccountIds: candidateIds,
    });
  }

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
