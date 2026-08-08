import { addCallback } from '../../../lib/teact/teactn';

import type { AuthType, GlobalState } from '../../types';
import { SettingsState } from '../../types';

import { getChainsSupportingLedger } from '../../../util/chain';
import { setLanguage } from '../../../util/langProvider';
import switchTheme from '../../../util/switchTheme';
import { callApi } from '../../../api';
import { enclave } from '../../../enclave';
import { addActionHandler, getGlobal, setGlobal } from '../..';
import { resetHardware, updateAccountSettings, updateAuth, updateSettings } from '../../reducers';
import { selectCurrentAccountId, selectEnclaveToken } from '../../selectors';
import { selectNotificationAddressesSlow } from '../../selectors/notifications';

let prevGlobal: GlobalState | undefined;

addCallback((global: GlobalState) => {
  if (!prevGlobal || !(prevGlobal as AnyLiteral).settings) {
    prevGlobal = global;
    return;
  }

  const { settings: prevSettings } = prevGlobal;
  const { settings } = global;

  if (settings.theme !== prevSettings.theme) {
    switchTheme(settings.theme);
  }

  if (settings.langCode !== prevSettings.langCode) {
    void setLanguage(settings.langCode);
    void callApi('setLangCode', settings.langCode);
    const {
      userToken, platform, enabledAccounts,
    } = global.pushNotifications;
    if (userToken && platform && enabledAccounts.length) {
      void callApi('subscribeNotifications', {
        userToken,
        platform,
        langCode: settings.langCode,
        addresses: Object.values(selectNotificationAddressesSlow(global, enabledAccounts)).flat(),
      });
    }
  }

  prevGlobal = global;
});

addActionHandler('setAppLockValue', (global, actions, { value, isEnabled }) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      autolockValue: value,
      isAppLockEnabled: isEnabled,
    },
  };
});

addActionHandler('setIsManualLockActive', (global, actions, { isActive, shouldHideBiometrics }) => {
  return {
    ...global,
    isManualLockActive: isActive,
    appLockHideBiometrics: shouldHideBiometrics,
  };
});

addActionHandler('setIsAutoConfirmEnabled', (global, actions, { isEnabled }) => {
  return {
    ...global,
    ...(!isEnabled && { enclaveSession: undefined }),
    settings: {
      ...global.settings,
      isAutoConfirmEnabled: isEnabled || undefined,
    },
  };
});

addActionHandler('setOverviewCellSize', (global, actions, { size }) => {
  const accountId = selectCurrentAccountId(global)!;

  return updateAccountSettings(global, accountId, {
    overviewCellSize: size,
  });
});

addActionHandler('setIsAllowSuspiciousActions', (global, actions, { isEnabled }) => {
  const accountId = selectCurrentAccountId(global)!;

  return updateAccountSettings(global, accountId, {
    isAllowSuspiciousActions: isEnabled || undefined,
  });
});

addActionHandler('openSettingsHardwareWallet', (global) => {
  global = resetHardware(global, getChainsSupportingLedger()[0], true); // todo: Add a chain selector screen for Ledger auth
  global = updateSettings(global, { state: SettingsState.LedgerConnectHardware });

  setGlobal(global);
});

addActionHandler('changePasscode', async (global, actions, { passcode, onSuccess }) => {
  // TODO Settings should have nothing to do with "auth"
  global = updateAuth(global, { isLoading: true });
  setGlobal(global);

  try {
    const currentEnclaveToken = selectEnclaveToken(global);
    if (!currentEnclaveToken) {
      throw new Error('Enclave session expired');
    }
    const newEnclaveSession = await enclave.migrateAuth(currentEnclaveToken, 'passcode', passcode, true);
    if (!newEnclaveSession) throw new Error('Failed to setup auth');

    global = getGlobal();
    // Ensure 'passcode' is in authTypes: keep as-is if already present, otherwise append it
    const authTypes: AuthType[] = global.authTypes?.includes('passcode')
      ? global.authTypes
      : [...(global.authTypes || []), 'passcode'];
    global = { ...global, authTypes, enclaveSession: newEnclaveSession };
    setGlobal(global);

    // Changing the passcode reads no secret of its own, so the session this minted goes back rather
    // than sitting there as a read nobody asked for - a counted session would keep it until the lock
    actions.releaseEnclaveSession({ enclaveToken: newEnclaveSession.token });

    onSuccess();
  } catch (err: any) {
    const error = err?.message || 'Failed to setup auth';

    global = getGlobal();
    global = updateAuth(global, { error });
    setGlobal(global);
  } finally {
    global = getGlobal();
    global = updateAuth(global, { isLoading: false });
    setGlobal(global);
  }
});
