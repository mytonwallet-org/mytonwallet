import { addCallback } from '../../../lib/teact/teactn';

import type { GlobalState } from '../../types';
import { SettingsState } from '../../types';

import { setInMemoryPasswordSignal } from '../../../util/authApi/inMemoryPasswordStore';
import { getChainsSupportingLedger } from '../../../util/chain';
import { setLanguage } from '../../../util/langProvider';
import switchTheme from '../../../util/switchTheme';
import { callApi } from '../../../api';
import { addActionHandler, setGlobal } from '../..';
import { resetHardware, updateAccountSettings, updateSettings } from '../../reducers';
import { selectCurrentAccountId, selectIsBiometricAuthEnabled } from '../../selectors';
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
  if (!isEnabled) {
    actions.setInMemoryPassword({ password: undefined, force: true });
  }

  return {
    ...global,
    settings: {
      ...global.settings,
      isAutoConfirmEnabled: isEnabled || undefined,
    },
  };
});

addActionHandler('setIsAllowSuspiciousActions', (global, actions, { isEnabled }) => {
  const accountId = selectCurrentAccountId(global)!;

  return updateAccountSettings(global, accountId, {
    isAllowSuspiciousActions: isEnabled || undefined,
  });
});

addActionHandler('setInMemoryPassword', (global, actions, { password, force }) => {
  if (!(global.settings.isAutoConfirmEnabled || force)) {
    return global;
  }

  // If biometrics are enabled, we don't need to set the password in memory
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  if (isBiometricAuthEnabled) {
    return global;
  }

  setInMemoryPasswordSignal(password);

  return global;
});

addActionHandler('openSettingsHardwareWallet', (global) => {
  global = resetHardware(global, getChainsSupportingLedger()[0], true); // todo: Add a chain selector screen for Ledger auth
  global = updateSettings(global, { state: SettingsState.LedgerConnectHardware });

  setGlobal(global);
});
