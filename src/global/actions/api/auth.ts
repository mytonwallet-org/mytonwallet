import type { ApiChain, ApiNetwork } from '../../../api/types';
import type { Account, GlobalState } from '../../types';
import { ApiAuthError, ApiCommonError } from '../../../api/types';
import { AppState, AuthState, BiometricsState } from '../../types';

import {
  IS_CORE_WALLET,
  IS_EXPLORER,
  MNEMONIC_CHECK_COUNT,
  MNEMONIC_COUNT,
  SHOULD_GENERATE_TON_MNEMONIC,
  TEMPORARY_ACCOUNT_NAME,
} from '../../../config';
import { generateAccountTitle, generateNextSubwalletTitle, parseAccountId } from '../../../util/account';
import authApi from '../../../util/authApi';
import { verifyIdentity as verifyTelegramBiometricIdentity } from '../../../util/authApi/telegram';
import webAuthn from '../../../util/authApi/webAuthn';
import { getDoesUsePinPad, getIsNativeBiometricAuthSupported } from '../../../util/biometrics';
import { copyTextToClipboard } from '../../../util/clipboard';
import { vibrateOnError, vibrateOnSuccess } from '../../../util/haptics';
import isEmptyObject from '../../../util/isEmptyObject';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { cloneDeep, compact, unique } from '../../../util/iteratees';
import { getTranslation } from '../../../util/langProvider';
import { logDebugError } from '../../../util/logs';
import { clearPoisoningCache, updatePoisoningCacheFromGlobalState } from '../../../util/poisoningHash';
import { pause } from '../../../util/schedulers';
import {
  IS_ANDROID,
  IS_BIOMETRIC_AUTH_SUPPORTED,
  IS_ELECTRON,
  IS_IOS,
} from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../..';
import {
  handleExplorerMode,
  handleStandardMode,
  removeTemporaryAccount,
} from '../../helpers/auth';
import { isErrorTransferResult } from '../../helpers/transfer';
import { INITIAL_STATE } from '../../initialState';
import {
  clearIsPinAccepted,
  createAccount,
  createAccountsFromGlobal,
  setIsPinAccepted,
  switchAccountAndClearGlobal,
  updateAccount,
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
  selectCurrentAccountId,
  selectCurrentNetwork,
  selectIsOneAccount,
  selectIsPasswordPresent,
  selectNetworkAccounts,
  selectNetworkAccountsMemoized,
  selectNewestActivityTimestamps,
  selectSelectedHardwareAccountsSlow,
} from '../../selectors';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

const CREATING_DURATION = 3300;
const NATIVE_BIOMETRICS_PAUSE_MS = 750;
const SWITHCHING_ACCOUNT_DURATION_MS = IS_IOS ? 450 : IS_ANDROID ? 350 : 300;

export async function switchAccount(global: GlobalState, accountId: string, newNetwork?: ApiNetwork) {
  const currentActiveAccountId = selectCurrentAccountId(global);
  const currentNetwork = selectCurrentNetwork(global);
  if (accountId === currentActiveAccountId && newNetwork === currentNetwork) {
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

  actions.closeSettings();
  if (newNetwork) {
    actions.changeNetwork({ network: newNetwork });
  }
}

addActionHandler('resetAuth', (global) => {
  if (selectCurrentAccountId(global)) {
    global = { ...global, appState: AppState.Main };

    // Restore the network when refreshing the page during the switching networks
    global = updateSettings(global, {
      isTestnet: parseAccountId(selectCurrentAccountId(global)!).network === 'testnet',
    });
  }

  global = { ...global, auth: cloneDeep(INITIAL_STATE.auth) };

  setGlobal(global);
});

addActionHandler('startCreatingWallet', async (global, actions) => {
  if (IS_EXPLORER) return;

  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);
  const isPasswordPresent = selectIsPasswordPresent(global);
  const nextAuthState = isPasswordPresent
    ? AuthState.safetyRules
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

  const isBip39 = !SHOULD_GENERATE_TON_MNEMONIC && !global.auth.forceAddingTonOnlyAccount;
  const mnemonicPromise = callApi('generateMnemonic', isBip39);
  const pausePromise = isPasswordPresent ? Promise.resolve() : pause(CREATING_DURATION);

  setGlobal(
    updateAuth(global, {
      state: nextAuthState,
      method: 'createAccount',
      error: undefined,
    }),
  );

  const [mnemonic] = await Promise.all([mnemonicPromise, pausePromise]);

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

addActionHandler('skipCreateBiometrics', (global, actions, { isImporting }) => {
  global = updateAuth(global, { state: isImporting ? AuthState.importWalletCreatePassword : AuthState.createPassword });
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
  password, isImporting, isPasswordNumeric,
}) => {
  if (IS_EXPLORER) return;

  setGlobal(updateAuth(global, { isLoading: true }));

  const mnemonic = global.auth.mnemonic!;
  const mainNetwork = selectCurrentNetwork(getGlobal());
  const networks: ApiNetwork[] = [mainNetwork];

  if (IS_CORE_WALLET) {
    networks.push(mainNetwork === 'testnet' ? 'mainnet' : 'testnet');
  }

  const accounts = isMnemonicPrivateKey(mnemonic)
    // todo: Create a separate screen for private key importing, where users will choose the chain
    ? await callApi('importPrivateKey', 'ton', networks, mnemonic[0], password)
    : await callApi('importMnemonic', networks, mnemonic, password, !isImporting);

  global = getGlobal();

  if (isErrorTransferResult(accounts)) {
    setGlobal(updateAuth(global, { isLoading: undefined }));
    actions.showError({ error: accounts?.error });
    return;
  }

  if (isImporting) {
    await refreshImportedAccountsMfa(accounts, password);
    global = getGlobal();
  }

  if (!isImporting) {
    global = { ...global, appState: AppState.Auth, isAccountSelectorOpen: undefined };
  }
  global = updateAuth(global, {
    isLoading: undefined,
    password: undefined,
    accounts,
    ...(isPasswordNumeric && { isPasswordNumeric: true }),
  });
  global = clearIsPinAccepted(global);

  if (isImporting) {
    global = updateAuth(global, { state: AuthState.importCongratulations });
  } else {
    global = updateAuth(global, { state: AuthState.safetyRules });
  }

  setGlobal(global);
});

async function refreshImportedAccountsMfa(
  accounts: { accountId: string; byChain: Account['byChain'] }[],
  password: string,
) {
  await Promise.all(accounts.map(async (account) => {
    if (!account.byChain.ton) return;

    try {
      const result = await callApi('refreshMfaState', account.accountId, password);
      if (result?.mfa) {
        account.byChain.ton.mfa = result.mfa;
      }
    } catch (err) {
      logDebugError('refreshImportedAccountsMfa', err);
    }
  }));
}

addActionHandler('createHardwareAccounts', async (global, actions) => {
  const network = selectCurrentNetwork(global);
  const selectedAccounts = selectSelectedHardwareAccountsSlow(global);

  setGlobal(updateAuth(global, { isLoading: true }));

  const importedAccounts = compact(await Promise.all(
    selectedAccounts.map(
      (account) => callApi('importLedgerAccount', network, account),
    ),
  ));

  actions.addHardwareAccounts({ accounts: importedAccounts });
});

addActionHandler('addHardwareAccounts', (global, actions, { accounts }) => {
  const nextActiveAccountId = accounts[0]?.accountId;

  if (nextActiveAccountId) {
    void callApi('activateAccount', nextActiveAccountId);
    global = updateCurrentAccountId(global, nextActiveAccountId);
  }

  global = accounts.reduce((currentGlobal, account) => {
    return createAccount({
      ...account,
      global: currentGlobal,
      type: 'hardware',
    });
  }, global);

  global = updateAuth(global, { isLoading: false });
  setGlobal(global);

  if (getGlobal().areSettingsOpen) {
    actions.closeSettings();
  }

  accounts.forEach((hardwareWallet) => {
    if (hardwareWallet?.accountId) {
      actions.tryAddNotificationAccount({ accountId: hardwareWallet?.accountId });
    }
  });

  global = updateAuth(getGlobal(), { state: AuthState.congratulations });
  setGlobal(global);
});

addActionHandler('afterCheckMnemonic', (global) => {
  global = createAccountsFromGlobal(global);
  global = updateAuth(global, { state: AuthState.congratulations });
  global = updateCurrentAccountId(global, global.auth.accounts![0].accountId);
  setGlobal(global);
});

addActionHandler('afterCongratulations', (global, actions, { isImporting }) => {
  if (isImporting) {
    actions.afterConfirmDisclaimer();
  } else {
    if (global.auth.accounts?.[0]) {
      actions.tryAddNotificationAccount({ accountId: global.auth.accounts[0].accountId });
    }
    actions.afterSignIn();

    if (selectIsOneAccount(global)) {
      actions.resetApiSettings();
    } else {
      actions.showToast({
        message: getTranslation('Wallet Created'),
        icon: 'icon-wallet-add',
        action: 'openRenameWallet',
        actionText: getTranslation('Set Name'),
      });
    }
  }
});

addActionHandler('restartCheckMnemonicIndexes', (global, actions, { wordsCount, preserveIndexes }) => {
  const nextIndexes = unique([
    ...(preserveIndexes ?? []),
    ...selectMnemonicForCheck(wordsCount),
  ])
    .slice(0, MNEMONIC_CHECK_COUNT)
    .sort((a, b) => a - b);

  setGlobal(
    updateAuth(global, {
      mnemonicCheckIndexes: nextIndexes,
    }),
  );
});

addActionHandler('skipCheckMnemonic', (global, actions) => {
  global = createAccountsFromGlobal(global);
  global = updateCurrentAccountId(global, global.auth.accounts![0].accountId);
  global = updateCurrentAccountState(global, { isBackupRequired: true });
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId: global.auth.accounts![0].accountId });

  actions.afterSignIn();
  if (selectIsOneAccount(global)) {
    actions.resetApiSettings();
  } else {
    actions.showToast({
      message: getTranslation('Wallet Created'),
      icon: 'icon-wallet-add',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
  }
});

addActionHandler('startImportingWallet', (global, actions) => {
  if (IS_EXPLORER) return;

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

  if (isPasswordPresent) {
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
  const accountId = global.auth.accounts![0].accountId;

  global = createAccountsFromGlobal(global, true);
  global = updateCurrentAccountId(global, accountId);
  global = updateAuth(global, { state: AuthState.ready });
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId });

  actions.afterSignIn();
  if (selectIsOneAccount(global)) {
    actions.resetApiSettings();
  } else {
    actions.showToast({
      message: getTranslation('Wallet Imported'),
      icon: 'icon-wallet-add',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
  }
});

export function selectMnemonicForCheck(wordsCount: number) {
  return Array(wordsCount)
    .fill(0)
    .map((_, i) => ({ i, rnd: Math.random() }))
    .sort((a, b) => a.rnd - b.rnd)
    .map((i) => i.i)
    .slice(0, Math.min(MNEMONIC_CHECK_COUNT, wordsCount))
    .sort((a, b) => a - b);
}

addActionHandler('startChangingNetwork', (global, actions, { network }) => {
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
  const { accountId, newNetwork } = payload;
  if (global.currentTemporaryViewAccountId) {
    await removeTemporaryAccount(global.currentTemporaryViewAccountId);
    global = getGlobal();
  }

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
    const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
    global = updateBiometrics(global, { error });
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
    const { success: isVerified } = await verifyTelegramBiometricIdentity();

    if (!isVerified) {
      global = getGlobal();
      global = {
        ...global,
        nativeBiometricsError: 'Failed to enable biometrics.',
      };
      global = clearIsPinAccepted(global);
      setGlobal(global);
      vibrateOnError();

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

    vibrateOnError();
  }
});

addActionHandler('clearNativeBiometricsError', (global) => {
  return {
    ...global,
    nativeBiometricsError: undefined,
  };
});

addActionHandler('openAuthBackupWalletModal', (global) => {
  global = updateAuth(global, { state: AuthState.safetyRules });
  setGlobal(global);
});

addActionHandler('openMnemonicPage', (global) => {
  const { mnemonic } = global.auth;

  global = updateAuth(global, {
    state: AuthState.mnemonicPage,
    mnemonicCheckIndexes: selectMnemonicForCheck(mnemonic?.length ?? MNEMONIC_COUNT),
  });
  setGlobal(global);
});

addActionHandler('openCheckWordsPage', (global) => {
  global = updateAuth(global, { state: AuthState.checkWords });
  setGlobal(global);
});

addActionHandler('closeCheckWordsPage', (global, actions, props) => {
  const { isBackupCreated } = props || {};

  if (isBackupCreated) {
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

    actions.showToast({ message: getTranslation('Copied') });
  } else {
    actions.showError({ error: ApiCommonError.Unexpected });
  }
});

addActionHandler('importAccountByVersion', async (global, actions, { version, isTestnetSubwalletId }) => {
  const accountId = selectCurrentAccountId(global)!;

  const wallet = (await callApi('importNewWalletVersion', accountId, version, isTestnetSubwalletId))!;
  global = getGlobal();

  if (!wallet.isNew) {
    actions.switchAccount({ accountId: wallet.accountId });
    return;
  }

  const { title: currentWalletTitle, type } = selectAccount(global, accountId)!;

  global = createAccount({
    global,
    accountId: wallet.accountId,
    type,
    byChain: wallet.byChain,
    partial: { title: currentWalletTitle },
    titlePostfix: version,
  });
  global = updateCurrentAccountId(global, wallet.accountId);
  setGlobal(global);

  await callApi('activateAccount', wallet.accountId);

  actions.tryAddNotificationAccount({ accountId: wallet.accountId });
});

addActionHandler('createSubWallet', async (global, actions, { password }) => {
  const accountId = selectCurrentAccountId(global)!;

  const result = await callApi('createSubWallet', accountId, password);

  global = getGlobal();
  global = clearIsPinAccepted(global);
  setGlobal(global);

  if (!result || 'error' in result) {
    actions.showError({ error: result?.error ?? ApiCommonError.Unexpected });
    return;
  }

  if (!result.isNew) {
    actions.switchAccount({ accountId: result.accountId });
    actions.showToast({
      message: getTranslation('Subwallet Switched'),
      icon: 'icon-subwallet-changed',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
    return;
  }

  const currentAccount = selectAccount(global, accountId)!;

  if (currentAccount.title) {
    global = getGlobal();

    const baseTitle = currentAccount.title.replace(/\.\d+$/, '');
    const accounts = selectNetworkAccounts(global) || {};
    const title = generateNextSubwalletTitle(baseTitle, accounts);

    global = createAccount({
      global,
      accountId: result.accountId,
      byChain: result.byChain,
      type: currentAccount.type,
      partial: { title },
    });

    global = updateCurrentAccountId(global, result.accountId);
    setGlobal(global);

    void actions.tryAddNotificationAccount({ accountId: result.accountId });
  }

  actions.showToast({
    message: getTranslation('Subwallet Created'),
    icon: 'icon-subwallet-added',
    action: 'openRenameWallet',
    actionText: getTranslation('Set Name'),
  });
});

addActionHandler('addSubWallet', async (global, actions, { group }) => {
  const accountId = selectCurrentAccountId(global)!;

  const partialByChain = Object.fromEntries(
    (Object.keys(group.byChain) as ApiChain[]).map((chain) => {
      const entry = group.byChain[chain]!;
      return [chain, entry.wallet];
    }),
  );

  const result = await callApi('addSubWallet', accountId, partialByChain);

  global = getGlobal();
  global = clearIsPinAccepted(global);
  setGlobal(global);

  if (!result) {
    actions.showError({ error: ApiCommonError.Unexpected });
    return;
  }

  if ('error' in result) {
    actions.showError({ error: result.error });
    return;
  }

  if (!result.isNew) {
    actions.switchAccount({ accountId: result.accountId });
    actions.showToast({
      message: getTranslation('Subwallet Switched'),
      icon: 'icon-subwallet-changed',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
    return;
  }

  const currentAccount = selectAccount(global, accountId);

  if (currentAccount?.title) {
    global = getGlobal();

    const baseTitle = currentAccount.title.replace(/\.\d+$/, '');
    const accounts = selectNetworkAccounts(global) || {};
    const title = generateNextSubwalletTitle(baseTitle, accounts);

    global = createAccount({
      global,
      accountId: result.accountId,
      byChain: result.byChain,
      type: currentAccount.type,
      partial: { title },
    });

    global = updateCurrentAccountId(global, result.accountId);
    setGlobal(global);

    void actions.tryAddNotificationAccount({ accountId: result.accountId });
  }

  actions.showToast({
    message: getTranslation('Subwallet Added'),
    icon: 'icon-subwallet-added',
    action: 'openRenameWallet',
    actionText: getTranslation('Set Name'),
  });
});

addActionHandler('addAllFoundSubwallets', async (global, actions, { foundSubwallets }) => {
  const accountId = selectCurrentAccountId(global)!;

  const partialByChainList = foundSubwallets.map((group) => Object.fromEntries(
    (Object.keys(group.byChain) as ApiChain[]).map((chain) => {
      const entry = group.byChain[chain]!;
      return [chain, entry.wallet];
    }),
  ));

  const result = await callApi('addAllFoundSubwallets', accountId, partialByChainList);

  global = getGlobal();
  global = clearIsPinAccepted(global);
  setGlobal(global);

  if (!result) {
    actions.showError({ error: ApiCommonError.Unexpected });
    return;
  }

  if ('error' in result) {
    actions.showError({ error: result.error });
    return;
  }

  const currentAccount = selectAccount(global, accountId);
  const baseTitle = currentAccount?.title && currentAccount.title.replace(/\.\d+$/, '');
  const { results } = result;

  for (let i = 0; i < results.length; i++) {
    const entry = results[i];
    if (!entry) continue;

    const isLast = i === results.length - 1;

    if (entry.isNew && baseTitle && currentAccount) {
      global = getGlobal();

      const accounts = selectNetworkAccounts(global) || {};
      const title = generateNextSubwalletTitle(baseTitle, accounts);

      global = createAccount({
        global,
        accountId: entry.accountId,
        byChain: entry.byChain,
        type: currentAccount.type,
        partial: { title },
      });

      if (isLast) {
        global = updateCurrentAccountId(global, entry.accountId);
      }

      setGlobal(global);

      void actions.tryAddNotificationAccount({ accountId: entry.accountId });
    } else if (isLast && !entry.isNew) {
      actions.switchAccount({ accountId: entry.accountId });
    }
  }

  const lastEntry = results.at(-1);

  if (lastEntry?.isNew) {
    actions.showToast({
      message: getTranslation('Subwallet Added'),
      icon: 'icon-subwallet-added',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
  } else if (lastEntry) {
    actions.showToast({
      message: getTranslation('Subwallet Switched'),
      icon: 'icon-subwallet-changed',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
  }
});

addActionHandler('setIsAuthLoading', (global, actions, { isLoading }) => {
  global = updateAuth(global, { isLoading });
  setGlobal(global);
});

addActionHandler('importViewAccount', async (global, actions, { addressByChain }) => {
  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);
  const network = selectCurrentNetwork(getGlobal());
  if (isFirstAccount) {
    global = updateAuth(global, { isLoading: true });
  } else {
    global = updateAccounts(global, { isLoading: true });
  }
  setGlobal(global);

  const result = await callApi('importViewAccount', network, addressByChain);

  global = getGlobal();
  if (isFirstAccount) {
    global = updateAuth(global, { isLoading: undefined });
  } else {
    global = updateAccounts(global, { isLoading: undefined });
  }
  setGlobal(global);

  if (isErrorTransferResult(result)) {
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
    actions.showToast({
      message: getTranslation('View Wallet Added'),
      icon: 'icon-wallet-view',
      action: 'openRenameWallet',
      actionText: getTranslation('Set Name'),
    });
  }
  void vibrateOnSuccess();
});

addActionHandler('openTemporaryViewAccount', async (global, actions, { addressByChain }) => {
  if (!Object.keys(addressByChain).length) {
    actions.showError({ error: '$no_valid_view_addresses' });
    return;
  }

  const network = selectCurrentNetwork(global);

  if (IS_EXPLORER) {
    await handleExplorerMode(global, actions, network, addressByChain, SWITHCHING_ACCOUNT_DURATION_MS);
  } else {
    await handleStandardMode(
      global,
      actions,
      network,
      addressByChain,
      SWITHCHING_ACCOUNT_DURATION_MS,
      getIsPortrait,
    );
  }
});

addActionHandler('saveTemporaryAccount', (global, actions) => {
  if (IS_EXPLORER) return;

  const newAccountId = global.currentTemporaryViewAccountId!;
  const network = selectCurrentNetwork(global);
  const accounts = selectNetworkAccounts(global) || {};
  const account = accounts[newAccountId];
  const title = account?.title && account.title !== getTranslation(TEMPORARY_ACCOUNT_NAME)
    ? account.title
    : generateAccountTitle({
      accounts,
      accountType: 'view',
      network,
    });

  global = updateAccount(global, newAccountId, {
    isTemporary: undefined,
    title,
  });
  global = updateCurrentAccountId(global, newAccountId);
  global = {
    ...global,
    currentTemporaryViewAccountId: undefined,
  };
  setGlobal(global);

  actions.tryAddNotificationAccount({ accountId: newAccountId });
  actions.showToast({ message: getTranslation('Account Saved'), icon: 'icon-check' });
  void vibrateOnSuccess();
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
