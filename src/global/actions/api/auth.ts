import { NativeBiometric } from '@capgo/capacitor-native-biometric';

import type { ApiNetwork } from '../../../api/types';
import type { GlobalState } from '../../types';
import { ApiAuthError, ApiCommonError } from '../../../api/types';
import { AppState, AuthState, BiometricsState } from '../../types';

import {
  APP_NAME, IS_BIP39_MNEMONIC_ENABLED, IS_TELEGRAM_APP, MNEMONIC_CHECK_COUNT, MNEMONIC_COUNT,
} from '../../../config';
import { parseAccountId } from '../../../util/account';
import authApi from '../../../util/authApi';
import { verifyIdentity as verifyTelegramBiometricIdentity } from '../../../util/authApi/telegram';
import webAuthn from '../../../util/authApi/webAuthn';
import { getDoesUsePinPad, getIsNativeBiometricAuthSupported } from '../../../util/biometrics';
import { copyTextToClipboard } from '../../../util/clipboard';
import { vibrateOnError, vibrateOnSuccess } from '../../../util/haptics';
import isEmptyObject from '../../../util/isEmptyObject';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { cloneDeep, compact } from '../../../util/iteratees';
import { getTranslation } from '../../../util/langProvider';
import { callActionInMain, callActionInNative } from '../../../util/multitab';
import { clearPoisoningCache, updatePoisoningCacheFromGlobalState } from '../../../util/poisoningHash';
import { pause } from '../../../util/schedulers';
import {
  IS_BIOMETRIC_AUTH_SUPPORTED,
  IS_DELEGATED_BOTTOM_SHEET,
  IS_DELEGATING_BOTTOM_SHEET,
  IS_ELECTRON,
} from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import {
  addActionHandler, getActions, getGlobal, setGlobal,
} from '../..';
import { INITIAL_STATE } from '../../initialState';
import {
  clearIsPinAccepted,
  createAccount,
  createAccountsFromGlobal,
  setIsPinAccepted,
  switchAccountAndClearGlobal,
  updateAccounts,
  updateAuth,
  updateBiometrics,
  updateCurrentAccountId,
  updateCurrentAccountState,
  updateSettings,
} from '../../reducers';
import {
  selectAccount,
  selectAccounts,
  selectCurrentNetwork,
  selectIsOneAccount,
  selectIsPasswordPresent,
  selectNetworkAccountsMemoized,
  selectNewestActivityTimestamps,
} from '../../selectors';

const CREATING_DURATION = 3300;
const NATIVE_BIOMETRICS_PAUSE_MS = 750;

export async function switchAccount(global: GlobalState, accountId: string, newNetwork?: ApiNetwork) {
  if (accountId === global.currentAccountId) {
    return;
  }

  const actions = getActions();

  const newestActivityTimestamps = selectNewestActivityTimestamps(global, accountId);
  await callApi('activateAccount', accountId, newestActivityTimestamps);

  global = getGlobal();
  setGlobal(switchAccountAndClearGlobal(global, accountId));

  clearPoisoningCache();

  // Load poisoning cache for the new account
  global = getGlobal();
  updatePoisoningCacheFromGlobalState(global);

  if (newNetwork) {
    actions.changeNetwork({ network: newNetwork });
  }
}

addActionHandler('resetAuth', (global) => {
  if (global.currentAccountId) {
    global = { ...global, appState: AppState.Main };

    // Restore the network when refreshing the page during the switching networks
    global = updateSettings(global, {
      isTestnet: parseAccountId(global.currentAccountId!).network === 'testnet',
    });
  }

  global = { ...global, auth: cloneDeep(INITIAL_STATE.auth) };

  setGlobal(global);
});

addActionHandler('startCreatingWallet', async (global, actions) => {
  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);
  const isPasswordPresent = selectIsPasswordPresent(global);
  const nextAuthState = isPasswordPresent
    ? AuthState.createBackup
    : (isFirstAccount
      ? AuthState.createWallet
      // The app only has hardware wallets accounts, which means we need to create a password or biometrics
      : getDoesUsePinPad()
        ? AuthState.createPin
        : (IS_BIOMETRIC_AUTH_SUPPORTED ? AuthState.createBiometrics : AuthState.createPassword)
    );

  global = getGlobal();

  if (isPasswordPresent && !global.auth.password) {
    setGlobal(updateAuth(global, {
      state: AuthState.checkPassword,
      error: undefined,
    }));
    return;
  }

  const promiseCalls = [
    callApi('generateMnemonic', IS_BIP39_MNEMONIC_ENABLED && !global.auth.forceAddingTonOnlyAccount),
    ...(!isPasswordPresent ? [pause(CREATING_DURATION)] : []),
  ] as [Promise<Promise<string[]> | undefined>, Promise<void> | undefined];

  setGlobal(
    updateAuth(global, {
      state: nextAuthState,
      method: 'createAccount',
      error: undefined,
    }),
  );

  const [mnemonic] = await Promise.all(promiseCalls);

  global = updateAuth(getGlobal(), {
    mnemonic,
    mnemonicCheckIndexes: selectMnemonicForCheck(mnemonic?.length ?? MNEMONIC_COUNT),
  });

  if (isPasswordPresent) {
    setGlobal(global);
    actions.afterCreatePassword({ password: global.auth.password! });

    return;
  }

  setGlobal(updateAuth(global, {
    state: getDoesUsePinPad()
      ? AuthState.createPin
      : (IS_BIOMETRIC_AUTH_SUPPORTED ? AuthState.createBiometrics : AuthState.createPassword),
  }));

  if (isFirstAccount) {
    actions.requestConfetti();
    void vibrateOnSuccess();
  }
});

addActionHandler('startCreatingBiometrics', (global) => {
  global = updateAuth(global, {
    state: global.auth.method !== 'createAccount'
      ? AuthState.importWalletConfirmBiometrics
      : AuthState.confirmBiometrics,
    biometricsStep: 1,
  });
  setGlobal(global);
});

addActionHandler('cancelCreateBiometrics', (global) => {
  global = updateAuth(global, {
    state: AuthState.createBiometrics,
    biometricsStep: undefined,
  });
  setGlobal(global);
});

addActionHandler('createPin', (global, actions, { pin, isImporting }) => {
  global = updateAuth(global, {
    state: isImporting ? AuthState.importWalletConfirmPin : AuthState.confirmPin,
    password: pin,
  });
  setGlobal(global);
});

addActionHandler('confirmPin', (global, actions, { isImporting }) => {
  if (getIsNativeBiometricAuthSupported()) {
    global = updateAuth(global, {
      state: isImporting ? AuthState.importWalletCreateNativeBiometrics : AuthState.createNativeBiometrics,
    });
    setGlobal(global);
  } else {
    actions.skipCreateNativeBiometrics();
  }
});

addActionHandler('cancelConfirmPin', (global, actions, { isImporting }) => {
  global = updateAuth(global, {
    state: isImporting ? AuthState.importWalletCreatePin : AuthState.createPin,
  });
  setGlobal(global);
});

addActionHandler('cancelDisclaimer', (global) => {
  setGlobal(updateAuth(global, {
    state: getDoesUsePinPad()
      ? AuthState.createPin
      : (IS_BIOMETRIC_AUTH_SUPPORTED ? AuthState.createBiometrics : AuthState.createPassword),
  }));
});

addActionHandler('afterCreatePassword', (global, actions, { password, isPasswordNumeric }) => {
  setGlobal(updateAuth(global, { isLoading: true }));

  const { method } = getGlobal().auth;

  const isImporting = method !== 'createAccount';
  const isHardware = method === 'importHardwareWallet';

  if (isHardware) {
    actions.createHardwareAccounts();
    return;
  }

  actions.createAccount({ password, isImporting, isPasswordNumeric });
});

addActionHandler('afterCreateBiometrics', async (global, actions) => {
  const withCredential = !IS_ELECTRON;
  global = updateAuth(global, {
    isLoading: true,
    error: undefined,
    biometricsStep: withCredential ? 1 : undefined,
  });
  setGlobal(global);

  try {
    const credential = withCredential
      ? await webAuthn.createCredential()
      : undefined;
    global = getGlobal();
    global = updateAuth(global, { biometricsStep: withCredential ? 2 : undefined });
    setGlobal(global);
    const result = await authApi.setupBiometrics({ credential });

    global = getGlobal();
    global = updateAuth(global, {
      isLoading: false,
      biometricsStep: undefined,
    });

    if (!result) {
      global = updateAuth(global, { error: 'Biometric setup failed.' });
      setGlobal(global);

      return;
    }

    global = updateSettings(global, { authConfig: result.config });
    setGlobal(global);

    actions.afterCreatePassword({ password: result.password });
  } catch (err: any) {
    const error = err?.message.includes('privacy-considerations-client')
      ? 'Biometric setup failed.'
      : (err?.message || 'Biometric setup failed.');
    global = getGlobal();
    global = updateAuth(global, {
      isLoading: false,
      error,
      biometricsStep: undefined,
    });
    setGlobal(global);
  }
});

addActionHandler('skipCreateBiometrics', (global) => {
  global = updateAuth(global, { state: AuthState.createPassword });
  setGlobal(global);
});

addActionHandler('afterCreateNativeBiometrics', async (global, actions) => {
  global = updateAuth(global, {
    isLoading: true,
    error: undefined,
  });
  setGlobal(global);

  try {
    const { password } = global.auth;
    const result = await authApi.setupNativeBiometrics(password!);

    global = getGlobal();
    global = updateAuth(global, { isLoading: false });
    global = updateSettings(global, { authConfig: result.config });
    setGlobal(global);

    actions.afterCreatePassword({ password: password!, isPasswordNumeric: true });
  } catch (err: any) {
    const error = err?.message.includes('privacy-considerations-client')
      ? 'Biometric setup failed.'
      : (err?.message || 'Biometric setup failed.');
    global = getGlobal();
    global = updateAuth(global, {
      isLoading: false,
      error,
    });
    setGlobal(global);
  }
});

addActionHandler('skipCreateNativeBiometrics', (global, actions) => {
  const { password } = global.auth;

  global = updateAuth(global, { isLoading: false, error: undefined });
  global = updateSettings(global, {
    authConfig: { kind: 'password' },
    isPasswordNumeric: true,
  });
  setGlobal(global);

  actions.afterCreatePassword({ password: password!, isPasswordNumeric: true });
});

addActionHandler('createAccount', async (global, actions, {
  password, isImporting, isPasswordNumeric, version,
}) => {
  setGlobal(updateAuth(global, { isLoading: true }));

  const network = selectCurrentNetwork(getGlobal());

  const result = await callApi(
    isImporting ? 'importMnemonic' : 'createWallet',
    network,
    global.auth.mnemonic!,
    password,
    version,
  );

  global = getGlobal();

  if (!result || 'error' in result) {
    setGlobal(updateAuth(global, { isLoading: undefined }));
    actions.showError({ error: result?.error });
    return;
  }

  const { accountId, byChain, secondNetworkAccount } = result;

  if (!isImporting) {
    global = { ...global, appState: AppState.Auth, isAddAccountModalOpen: undefined };
  }
  global = updateAuth(global, {
    isLoading: undefined,
    password: undefined,
    firstNetworkAccount: {
      byChain,
      accountId,
    },
    secondNetworkAccount,
    ...(isPasswordNumeric && { isPasswordNumeric: true }),
  });
  global = clearIsPinAccepted(global);

  if (isImporting) {
    const hasAccounts = Object.keys(selectAccounts(global) || {}).length > 0;
    if (hasAccounts) {
      setGlobal(global);
      actions.afterConfirmDisclaimer();

      return;
    } else {
      global = updateAuth(global, { state: AuthState.disclaimer });
    }
  } else {
    const accounts = selectAccounts(global) ?? {};
    const isFirstAccount = isEmptyObject(accounts);
    global = updateAuth(global, {
      state: isFirstAccount ? AuthState.disclaimerAndBackup : AuthState.createBackup,
    });
  }

  setGlobal(global);
});

addActionHandler('createHardwareAccounts', async (global, actions) => {
  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);

  setGlobal(updateAuth(global, { isLoading: true }));

  const { hardwareSelectedIndices = [] } = getGlobal().auth;
  const network = selectCurrentNetwork(getGlobal());

  const ledgerApi = await import('../../../util/ledger');
  const wallets = await Promise.all(
    hardwareSelectedIndices.map(
      (wallet) => ledgerApi.importLedgerWallet(network, wallet),
    ),
  );

  if (IS_DELEGATED_BOTTOM_SHEET && !isFirstAccount) {
    callActionInMain('addHardwareAccounts', { wallets });
    return;
  }

  actions.addHardwareAccounts({ wallets });
});

addActionHandler('addHardwareAccounts', (global, actions, { wallets }) => {
  const isFirstAccount = !global.currentAccountId;
  const nextActiveAccountId = wallets[0]?.accountId;
  if (nextActiveAccountId) {
    void callApi('activateAccount', nextActiveAccountId);
  }

  const updatedGlobal = wallets.reduce((currentGlobal, wallet) => {
    if (!wallet) {
      return currentGlobal;
    }
    const { accountId, address, walletInfo } = wallet;
    const byChain = { ton: { address } };

    currentGlobal = updateCurrentAccountId(currentGlobal, accountId);
    currentGlobal = createAccount({
      global: currentGlobal,
      accountId,
      byChain,
      type: 'hardware',
      partial: {
        ...(walletInfo && {
          ledger: {
            driver: walletInfo.driver,
            index: walletInfo.index,
          },
        }),
      },
    });

    return currentGlobal;
  }, getGlobal());

  if (nextActiveAccountId) {
    global = updateCurrentAccountId(updatedGlobal, nextActiveAccountId);
  }
  global = updateAuth(global, { isLoading: false });
  global = {
    ...global,
    shouldForceAccountEdit: true,
  };
  setGlobal(global);

  if (getGlobal().areSettingsOpen) {
    actions.closeSettings();
  }

  wallets.forEach((hardwareWallet) => {
    if (hardwareWallet?.accountId) {
      actions.tryAddNotificationAccount({ accountId: hardwareWallet?.accountId });
    }
  });

  actions.afterSignIn();
  if (isFirstAccount) {
    actions.resetApiSettings();
    actions.requestConfetti();
    void vibrateOnSuccess();
  }
});

addActionHandler('afterCheckMnemonic', (global, actions) => {
  global = createAccountsFromGlobal(global);
  global = updateCurrentAccountId(global, global.auth.firstNetworkAccount!.accountId);
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId: global.auth.firstNetworkAccount!.accountId });

  actions.afterSignIn();
  if (selectIsOneAccount(global)) {
    actions.resetApiSettings();
  }
});

addActionHandler('restartCheckMnemonicIndexes', (global, actions, { worldsCount }) => {
  setGlobal(
    updateAuth(global, {
      mnemonicCheckIndexes: selectMnemonicForCheck(worldsCount),
    }),
  );
});

addActionHandler('skipCheckMnemonic', (global, actions) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('skipCheckMnemonic');
    return;
  }

  global = createAccountsFromGlobal(global);
  global = updateCurrentAccountId(global, global.auth.firstNetworkAccount!.accountId);
  global = updateCurrentAccountState(global, { isBackupRequired: true });
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId: global.auth.firstNetworkAccount!.accountId });

  actions.afterSignIn();
  if (selectIsOneAccount(global)) {
    actions.resetApiSettings();
  }
});

addActionHandler('startImportingWallet', (global) => {
  const isPasswordPresent = selectIsPasswordPresent(global);
  const state = isPasswordPresent && !global.auth.password
    ? AuthState.importWalletCheckPassword
    : AuthState.importWallet;

  setGlobal(
    updateAuth(global, {
      state,
      error: undefined,
      method: 'importMnemonic',
    }),
  );
});

addActionHandler('openAbout', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.about, error: undefined }));
});

addActionHandler('closeAbout', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.none, error: undefined }));
});

addActionHandler('afterImportMnemonic', async (global, actions, { mnemonic }) => {
  mnemonic = compact(mnemonic);

  if (!isMnemonicPrivateKey(mnemonic)) {
    if (!await callApi('validateMnemonic', mnemonic)) {
      setGlobal(updateAuth(getGlobal(), {
        error: ApiAuthError.InvalidMnemonic,
      }));

      return;
    }
  }

  global = getGlobal();

  const isPasswordPresent = selectIsPasswordPresent(global);
  const hasAccounts = Object.keys(selectAccounts(global) || {}).length > 0;
  const state = getDoesUsePinPad()
    ? AuthState.importWalletCreatePin
    : (IS_BIOMETRIC_AUTH_SUPPORTED
      ? AuthState.importWalletCreateBiometrics
      : AuthState.importWalletCreatePassword);

  global = updateAuth(global, {
    mnemonic,
    error: undefined,
    ...(!isPasswordPresent && { state }),
  });
  setGlobal(global);

  if (!isPasswordPresent) {
    if (!hasAccounts) {
      actions.requestConfetti();
    }

    void vibrateOnSuccess();
  } else {
    actions.confirmDisclaimer();
  }
});

addActionHandler('confirmDisclaimer', (global, actions) => {
  const isPasswordPresent = selectIsPasswordPresent(global);

  if (isPasswordPresent) {
    setGlobal(global);
    actions.afterCreatePassword({ password: global.auth.password! });

    return;
  }

  actions.afterConfirmDisclaimer();
});

addActionHandler('afterConfirmDisclaimer', (global, actions) => {
  const { firstNetworkAccount } = global.auth;

  global = createAccountsFromGlobal(global, true);
  global = updateCurrentAccountId(global, firstNetworkAccount!.accountId);
  global = updateAuth(global, { state: AuthState.ready });
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId: firstNetworkAccount!.accountId });

  actions.afterSignIn();
  if (selectIsOneAccount(global)) {
    actions.resetApiSettings();
  }
});

addActionHandler('cleanAuthError', (global) => {
  setGlobal(updateAuth(global, { error: undefined }));
});

export function selectMnemonicForCheck(worldsCount: number) {
  return Array(worldsCount)
    .fill(0)
    .map((_, i) => ({ i, rnd: Math.random() }))
    .sort((a, b) => a.rnd - b.rnd)
    .map((i) => i.i)
    .slice(0, Math.min(MNEMONIC_CHECK_COUNT, worldsCount))
    .sort((a, b) => a - b);
}

addActionHandler('startChangingNetwork', (global, actions, { network }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('startChangingNetwork', { network });
  }

  const accountIds = Object.keys(selectNetworkAccountsMemoized(network, global.accounts!.byId)!);

  if (accountIds.length) {
    const accountId = accountIds[0];
    actions.switchAccount({ accountId, newNetwork: network });
  } else {
    setGlobal({
      ...global,
      areSettingsOpen: false,
      appState: AppState.Auth,
    });
    actions.changeNetwork({ network });
  }
});

addActionHandler('switchAccount', async (global, actions, payload) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('switchAccount', payload);
    return;
  }

  const { accountId, newNetwork } = payload;
  await switchAccount(global, accountId, newNetwork);
});

addActionHandler('afterSelectHardwareWallets', (global, actions, { hardwareSelectedIndices }) => {
  setGlobal(updateAuth(global, {
    method: 'importHardwareWallet',
    hardwareSelectedIndices,
    error: undefined,
  }));

  actions.afterCreatePassword({ password: '' });
});

addActionHandler('enableBiometrics', async (global, actions, { password }) => {
  if (!(await callApi('verifyPassword', password))) {
    global = getGlobal();
    global = updateBiometrics(global, { error: 'Wrong password, please try again.' });
    setGlobal(global);

    return;
  }

  global = getGlobal();
  global = updateBiometrics(global, {
    error: undefined,
    state: BiometricsState.TurnOnRegistration,
  });
  global = updateAuth(global, { isLoading: true });
  setGlobal(global);

  try {
    const credential = IS_ELECTRON
      ? undefined
      : await webAuthn.createCredential();

    global = getGlobal();
    global = updateBiometrics(global, { state: BiometricsState.TurnOnVerification });
    setGlobal(global);

    const result = await authApi.setupBiometrics({ credential });

    global = getGlobal();
    if (!result) {
      global = updateBiometrics(global, {
        error: 'Biometric setup failed.',
        state: BiometricsState.TurnOnPasswordConfirmation,
      });
      setGlobal(global);

      return;
    }
    global = updateBiometrics(global, { state: BiometricsState.TurnOnComplete });
    setGlobal(global);

    await callApi('changePassword', password, result.password);

    global = getGlobal();
    global = updateSettings(global, { authConfig: result.config });

    setGlobal(global);
    actions.setInMemoryPassword({ password: undefined, force: true });
  } catch (err: any) {
    const error = err?.message.includes('privacy-considerations-client')
      ? 'Biometric setup failed.'
      : (err?.message || 'Biometric setup failed.');
    global = getGlobal();
    global = updateBiometrics(global, {
      error,
      state: BiometricsState.TurnOnPasswordConfirmation,
    });
    setGlobal(global);
  } finally {
    global = getGlobal();
    global = updateAuth(global, { isLoading: undefined });
    setGlobal(global);
  }
});

addActionHandler('disableBiometrics', async (global, actions, { password, isPasswordNumeric }) => {
  const { password: oldPassword } = global.biometrics;

  if (!password || !oldPassword) {
    global = updateBiometrics(global, { error: 'Biometric confirmation failed.' });
    setGlobal(global);

    return;
  }

  global = getGlobal();
  global = updateAuth(global, { isLoading: true });
  setGlobal(global);

  try {
    await callApi('changePassword', oldPassword, password);
  } catch (err: any) {
    global = getGlobal();
    global = updateBiometrics(global, { error: err?.message || 'Failed to disable biometrics.' });
    setGlobal(global);

    return;
  } finally {
    global = getGlobal();
    global = updateAuth(global, { isLoading: undefined });
    setGlobal(global);
  }

  global = getGlobal();
  global = updateBiometrics(global, {
    state: BiometricsState.TurnOffComplete,
    error: undefined,
  });
  global = updateSettings(global, {
    authConfig: { kind: 'password' },
    isPasswordNumeric,
  });
  setGlobal(global);
});

addActionHandler('closeBiometricSettings', (global) => {
  global = { ...global, biometrics: cloneDeep(INITIAL_STATE.biometrics) };

  setGlobal(global);
});

addActionHandler('openBiometricsTurnOn', (global) => {
  global = updateBiometrics(global, { state: BiometricsState.TurnOnPasswordConfirmation });

  setGlobal(global);
});

addActionHandler('openBiometricsTurnOffWarning', (global) => {
  global = updateBiometrics(global, { state: BiometricsState.TurnOffWarning });

  setGlobal(global);
});

addActionHandler('openBiometricsTurnOff', async (global) => {
  global = updateBiometrics(global, { state: BiometricsState.TurnOffBiometricConfirmation });
  setGlobal(global);

  const password = await authApi.getPassword(global.settings.authConfig!);
  global = getGlobal();

  if (!password) {
    global = updateBiometrics(global, { error: 'Biometric confirmation failed.' });
  } else {
    global = updateBiometrics(global, {
      state: BiometricsState.TurnOffCreatePassword,
      password,
    });
  }

  setGlobal(global);
});

addActionHandler('disableNativeBiometrics', (global) => {
  global = updateSettings(global, {
    authConfig: { kind: 'password' },
    isPasswordNumeric: true,
  });
  setGlobal(global);
});

addActionHandler('enableNativeBiometrics', async (global, actions, { password }) => {
  if (!(await callApi('verifyPassword', password))) {
    global = getGlobal();
    global = {
      ...global,
      nativeBiometricsError: 'Incorrect code, please try again.',
    };
    global = clearIsPinAccepted(global);
    setGlobal(global);

    return;
  }

  global = getGlobal();

  global = setIsPinAccepted(global);
  global = {
    ...global,
    nativeBiometricsError: undefined,
  };
  setGlobal(global);

  try {
    let isVerified: boolean;

    if (IS_TELEGRAM_APP) {
      const verificationResult = await verifyTelegramBiometricIdentity();
      isVerified = verificationResult.success;
    } else {
      isVerified = await NativeBiometric.verifyIdentity({
        title: APP_NAME,
        subtitle: '',
        maxAttempts: 1,
      })
        .then(() => true)
        .catch(() => false);
    }

    if (!isVerified) {
      global = getGlobal();
      global = {
        ...global,
        nativeBiometricsError: 'Failed to enable biometrics.',
      };
      global = clearIsPinAccepted(global);
      setGlobal(global);
      void vibrateOnError();

      return;
    }

    const result = await authApi.setupNativeBiometrics(password);

    await pause(NATIVE_BIOMETRICS_PAUSE_MS);

    global = getGlobal();
    global = updateSettings(global, { authConfig: result.config });
    global = { ...global, nativeBiometricsError: undefined };
    setGlobal(global);
    actions.setInMemoryPassword({ password: undefined, force: true });

    void vibrateOnSuccess();
  } catch (err: any) {
    global = getGlobal();
    global = {
      ...global,
      nativeBiometricsError: err?.message || 'Failed to enable biometrics.',
    };
    global = clearIsPinAccepted(global);
    setGlobal(global);

    void vibrateOnError();
  }
});

addActionHandler('clearNativeBiometricsError', (global) => {
  return {
    ...global,
    nativeBiometricsError: undefined,
  };
});

addActionHandler('openAuthBackupWalletModal', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openAuthBackupWalletModal');
    return;
  }

  global = updateAuth(global, { state: AuthState.safetyRules });
  setGlobal(global);
});

addActionHandler('openMnemonicPage', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openMnemonicPage');
    return;
  }

  global = updateAuth(global, { state: AuthState.mnemonicPage });
  setGlobal(global);
});

addActionHandler('openCreateBackUpPage', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openCreateBackUpPage');
    return;
  }

  const accounts = selectAccounts(global) ?? {};

  const isFirstAccount = isEmptyObject(accounts);
  global = updateAuth(global, {
    state: isFirstAccount ? AuthState.disclaimerAndBackup : AuthState.createBackup,
  });

  setGlobal(global);
});

addActionHandler('openCheckWordsPage', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openCheckWordsPage');
    return;
  }

  global = updateAuth(global, { state: AuthState.checkWords });
  setGlobal(global);
});

addActionHandler('closeCheckWordsPage', (global, actions, props) => {
  const { isBackupCreated } = props || {};

  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('closeCheckWordsPage', props);
  }

  if (!IS_DELEGATED_BOTTOM_SHEET && isBackupCreated) {
    actions.afterCheckMnemonic();
  }
});

addActionHandler('copyStorageData', async (global, actions) => {
  const accountConfigJson = await callApi('fetchAccountConfigForDebugPurposesOnly');

  if (accountConfigJson) {
    const storageData = JSON.stringify({
      ...JSON.parse(accountConfigJson),
      global: reduceGlobalForDebug(),
    });

    await copyTextToClipboard(storageData);

    actions.showNotification({ message: getTranslation('Copied') });
  } else {
    actions.showError({ error: ApiCommonError.Unexpected });
  }
});

addActionHandler('importAccountByVersion', async (global, actions, { version }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('importAccountByVersion', { version });
    return;
  }

  const accountId = global.currentAccountId!;

  const wallet = (await callApi('importNewWalletVersion', accountId, version))!;
  global = getGlobal();

  if (!wallet.isNew) {
    actions.switchAccount({ accountId: wallet.accountId });
    return;
  }

  const { title: currentWalletTitle, type } = selectAccount(global, accountId)!;
  const byChain = { ton: { address: wallet.address } };
  global = updateCurrentAccountId(global, wallet.accountId);

  const ledgerInfo = wallet.ledger ? {
    ledger: wallet.ledger,
  } : undefined;

  global = createAccount({
    global,
    accountId: wallet.accountId,
    type,
    byChain,
    partial: { ...ledgerInfo, title: currentWalletTitle },
    titlePostfix: version,
  });
  setGlobal(global);

  await callApi('activateAccount', wallet.accountId);

  actions.tryAddNotificationAccount({ accountId: wallet.accountId });
});

addActionHandler('setIsAuthLoading', (global, actions, { isLoading }) => {
  global = updateAuth(global, { isLoading });
  setGlobal(global);
});

addActionHandler('importViewAccount', async (global, actions, { addressByChain }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('importViewAccount', { addressByChain });
    return;
  }

  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);
  const network = selectCurrentNetwork(getGlobal());
  if (isFirstAccount) {
    global = updateAuth(global, { isLoading: true });
  } else {
    global = updateAccounts(global, { isLoading: true });
    if (IS_DELEGATING_BOTTOM_SHEET) {
      callActionInNative('setIsAccountLoading', { isLoading: true });
    }
  }
  setGlobal(global);

  const result = await callApi('importViewAccount', network, addressByChain);

  global = getGlobal();
  if (isFirstAccount) {
    global = updateAuth(global, { isLoading: undefined });
  } else {
    global = updateAccounts(global, { isLoading: undefined });
    if (IS_DELEGATING_BOTTOM_SHEET) {
      callActionInNative('setIsAccountLoading', { isLoading: undefined });
    }
  }
  setGlobal(global);

  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  global = getGlobal();
  global = createAccount({
    global,
    accountId: result.accountId,
    byChain: result.byChain,
    type: 'view',
    partial: { title: result.title },
  });
  global = updateCurrentAccountId(global, result.accountId);
  setGlobal(global);

  if (getGlobal().areSettingsOpen) {
    actions.closeSettings();
  }

  actions.tryAddNotificationAccount({ accountId: result.accountId });

  actions.afterSignIn();
  if (isFirstAccount) {
    actions.resetApiSettings();
    actions.requestConfetti();
  } else {
    actions.closeAddAccountModal();
  }
  void vibrateOnSuccess();
});

addActionHandler('startImportViewAccount', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.importViewAccount, error: undefined }));
});

addActionHandler('closeImportViewAccount', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.none, error: undefined }));
});

addActionHandler('openAuthImportWalletModal', (global) => {
  global = updateAuth(global, { isImportModalOpen: true });
  setGlobal(global);
});

addActionHandler('closeAuthImportWalletModal', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('closeAuthImportWalletModal');
  }

  global = updateAuth(global, { isImportModalOpen: undefined });
  setGlobal(global);
});

function reduceGlobalForDebug() {
  const reduced = cloneDeep(getGlobal());

  reduced.tokenInfo = {} as any;
  reduced.swapTokenInfo = {} as any;
  Object.entries(reduced.byAccountId).forEach(([, state]) => {
    state.activities = {} as any;
  });

  return reduced;
}
