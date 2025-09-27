import { addCallback } from '../../../lib/teact/teactn';

import type { GlobalState } from '../../types';
import { SettingsState } from '../../types';

import { setInMemoryPasswordSignal } from '../../../util/authApi/inMemoryPasswordStore';
import { getChainsSupportingLedger } from '../../../util/chain';
import { setLanguage } from '../../../util/langProvider';
import { callActionInMain, callActionInNative } from '../../../util/multitab';
import switchTheme from '../../../util/switchTheme';
import { IS_DELEGATED_BOTTOM_SHEET, IS_DELEGATING_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler, setGlobal } from '../..';
import { resetHardware, updateAccountSettings, updateSettings } from '../../reducers';
import { selectIsBiometricAuthEnabled } from '../../selectors';

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
  const accountId = global.currentAccountId!;

  return updateAccountSettings(global, accountId, {
    isAllowSuspiciousActions: isEnabled || undefined,
  });
});

addActionHandler('setInMemoryPassword', (global, actions, { password, isFinalCall, force }) => {
  // `global` is not loaded in the NBS until it's opened for the first time, so `isAutoConfirmEnabled` may be
  // incorrectly `undefined` when Auto Confirm is actually enabled. To mitigate that, we skip checking the setting
  // when `isFinalCall` is `true`, because in this case the action is fired by the main WebView only when Auto Confirm is enabled.
  if (!(global.settings.isAutoConfirmEnabled || isFinalCall || force)) {
    return global;
  }

  // If biometrics are enabled, we don't need to set the password in memory
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  if (isBiometricAuthEnabled) {
    return global;
  }

  setInMemoryPasswordSignal(password);

  if (!isFinalCall) {
    if (IS_DELEGATING_BOTTOM_SHEET) {
      void callActionInNative('setInMemoryPassword', { password, isFinalCall: true });
    }
    if (IS_DELEGATED_BOTTOM_SHEET) {
      void callActionInMain('setInMemoryPassword', { password, isFinalCall: true });
    }
  }

  return global;
});

addActionHandler('openSettingsHardwareWallet', (global) => {
  global = resetHardware(global, getChainsSupportingLedger()[0], true); // todo: Add a chain selector screen for Ledger auth
  global = updateSettings(global, { state: SettingsState.LedgerConnectHardware });

  setGlobal(global);
});
