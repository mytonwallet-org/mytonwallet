import type { ApiChain, ApiNetwork } from '../../../api/types';
import type { Account, AuthType, GlobalState, MigrationErrorPresentation } from '../../types';
import { ApiAuthError, ApiCommonError } from '../../../api/types';
import { AppState, AuthState, BiometricsState } from '../../types';

import {
  IS_EXPLORER,
  IS_FEATURE_LIMITED,
  MNEMONIC_CHECK_COUNT,
  MNEMONIC_COUNT,
  SHOULD_CLEANUP_LEGACY_AUTH,
  SHOULD_GENERATE_TON_MNEMONIC,
  TEMPORARY_ACCOUNT_NAME,
} from '../../../config';
import { generateAccountTitle, generateNextSubwalletTitle, parseAccountId } from '../../../util/account';
import { getDoesUsePinPad, getIsBiometricAuthSupported } from '../../../util/biometrics';
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
  CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY,
  IS_ANDROID,
  IS_IOS,
} from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import {
  checkIsMigrationFailure,
  describeThrownError,
  enclave,
  legacyAuth,
  type LegacyAuthConfig,
  type MigrationStep,
} from '../../../enclave';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../..';
import {
  clearAbortDappConnectWalletCreation,
  peekAbortDappConnectWalletCreation,
  takeAbortDappConnectWalletCreationIfRequested,
} from '../../helpers/abortDappConnectWalletCreation';
import {
  handleExplorerMode,
  handleStandardMode,
  removeTemporaryAccount,
} from '../../helpers/auth';
import { dropEnclaveSessionHold, holdEnclaveSession, withEnclaveSessionRelease } from '../../helpers/enclave';
import { presentMigrationFailure } from '../../helpers/migrationFailure';
import { isErrorTransferResult } from '../../helpers/transfer';
import { INITIAL_STATE } from '../../initialState';
import {
  clearDappConnectRequest,
  clearIsPinAccepted,
  createAccount,
  createAccountsFromGlobal,
  switchAccountAndClearGlobal,
  updateAccount,
  updateAccounts,
  updateAccountState,
  updateAuth,
  updateBiometrics,
  updateCurrentAccountId,
  updateDappConnectRequest,
  updateSettings,
} from '../../reducers';
import {
  selectAccount,
  selectAccounts,
  selectCurrentAccountId,
  selectCurrentNetwork,
  selectEnclaveToken,
  selectHasPassword,
  selectIsEnclaveSessionValid,
  selectIsOneAccount,
  selectNetworkAccounts,
  selectNetworkAccountsMemoized,
  selectNewestActivityTimestamps,
  selectSelectedHardwareAccountsSlow,
} from '../../selectors';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

const CREATING_DURATION = 3300;
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

function finalizeDappConnectWalletCreationAbort() {
  let nextGlobal = getGlobal();

  nextGlobal = updateAuth(nextGlobal, { isLoading: undefined });
  nextGlobal = updateAccounts(nextGlobal, { isLoading: undefined });

  setGlobal(nextGlobal);
  getActions().resetAuth();
}

async function rollbackDappConnectWalletCreationIfPersisted(
  createdAccounts: Array<{ accountId: string }>,
): Promise<boolean> {
  if (!peekAbortDappConnectWalletCreation()) {
    return false;
  }

  const global = getGlobal();
  const previousAccountId = selectCurrentAccountId(global);
  const accountIds = unique(compact(createdAccounts.map(({ accountId }) => accountId)));

  const timestamps = previousAccountId
    ? selectNewestActivityTimestamps(global, previousAccountId)
    : undefined;

  try {
    for (const accountId of accountIds) {
      await callApi('removeAccount', accountId, previousAccountId, timestamps);
    }
  } finally {
    clearAbortDappConnectWalletCreation();
    finalizeDappConnectWalletCreationAbort();
  }

  return true;
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

addActionHandler('startCreatingWallet', async (global, actions, payload) => {
  if (IS_EXPLORER) return;

  const { enclaveToken } = payload ?? {};

  const accounts = selectAccounts(global) ?? {};
  const isFirstAccount = isEmptyObject(accounts);
  const hasPassword = selectHasPassword(global);
  const nextAuthState = hasPassword
    ? AuthState.safetyRules
    : (
      isFirstAccount
        ? AuthState.createWallet
        // The app only has hardware wallets accounts, which means we need to create a password
        : getDoesUsePinPad()
          ? AuthState.createPin
          : CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
            ? AuthState.createBiometrics
            : AuthState.createPassword
    );

  global = getGlobal();

  if (hasPassword && !enclaveToken && !selectIsEnclaveSessionValid(global)) {
    // The password screen lives in the auth flow, so the app has to be showing it - otherwise the request
    // for a password renders nowhere and the caller waits forever.
    global = { ...global, appState: AppState.Auth };
    setGlobal(updateAuth(global, {
      state: AuthState.checkPassword,
      error: undefined,
    }));
    return;
  }

  const generateMnemonicPromise = callApi(
    'generateMnemonic', !SHOULD_GENERATE_TON_MNEMONIC && !global.auth.forceAddingTonOnlyAccount,
  );

  setGlobal(
    updateAuth(global, {
      state: nextAuthState,
      method: 'createAccount',
      error: undefined,
    }),
  );

  const [mnemonic] = await Promise.all(
    hasPassword ? [generateMnemonicPromise] : [generateMnemonicPromise, pause(CREATING_DURATION)],
  );

  if (takeAbortDappConnectWalletCreationIfRequested()) {
    finalizeDappConnectWalletCreationAbort();
    return;
  }

  global = updateAuth(getGlobal(), {
    mnemonic,
    mnemonicCheckIndexes: selectMnemonicForCheck(mnemonic?.length ?? MNEMONIC_COUNT),
  });

  if (hasPassword) {
    setGlobal(global);

    actions.createAccount();

    return;
  }

  setGlobal(updateAuth(global, {
    state: getDoesUsePinPad()
      ? AuthState.createPin
      : CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
        ? AuthState.createBiometrics
        : AuthState.createPassword,
  }));
});

addActionHandler('createPin', (global, actions, { pin, isImporting }) => {
  global = updateAuth(global, {
    state: isImporting ? AuthState.importWalletConfirmPin : AuthState.confirmPin,
    pin,
  });
  setGlobal(global);
});

addActionHandler('confirmPin', async (global, actions, { isImporting }) => {
  const pin = global.auth.pin!;
  global = updateAuth(global, { pin: undefined });
  setGlobal(global);

  try {
    const enclaveSession = await enclave.setupAuth('passcode', pin);
    if (!enclaveSession) throw new Error('Failed to setup auth');

    global = getGlobal();
    global = updateAuth(global, { isLoading: false });
    global = { ...global, authTypes: ['passcode'], enclaveSession };
    setGlobal(global);

    if (getIsBiometricAuthSupported()) {
      global = getGlobal();
      global = updateAuth(global, {
        state: isImporting ? AuthState.importWalletCreateBiometrics : AuthState.createBiometrics,
      });
      setGlobal(global);
    } else {
      actions.skipBiometrics();
    }
  } catch (err: any) {
    const error = err?.message || 'Failed to setup auth';

    global = getGlobal();
    global = updateAuth(global, { isLoading: false, error });
    setGlobal(global);
  }
});

addActionHandler('cancelConfirmPin', (global, actions, { isImporting }) => {
  global = updateAuth(global, {
    state: isImporting ? AuthState.importWalletCreatePin : AuthState.createPin,
  });
  setGlobal(global);
});

/**
 * Storage outlives the global state and can hold an auth the app no longer remembers, after a setup
 * that was interrupted or a cache that was lost. `setupAuth` refuses over any auth at all, not only one
 * of the type being set up, because the master key it would mint is one per storage and would strand
 * every secret sealed under the old one. An auth that guards no secrets is a leftover of a setup that
 * never imported anything, and clearing it is the only way past that refusal that destroys nothing.
 */
async function clearAuthGuardingNothing() {
  if (await enclave.hasProvisionedAuth() && !await enclave.hasStoredSecrets()) {
    await enclave.reset();
  }
}

addActionHandler('createPassword', async (global, actions, { password, isNumeric }) => {
  global = updateAuth(global, { isLoading: true });
  setGlobal(global);

  try {
    await clearAuthGuardingNothing();

    const isProvisioned = await enclave.isAuthProvisioned('passcode');
    const enclaveSession = isProvisioned
      ? await enclave.authorize('passcode', false, password)
      : await enclave.setupAuth('passcode', password);
    if (!enclaveSession) {
      throw new Error(isProvisioned ? 'Wrong password, please try again.' : 'Failed to setup auth');
    }

    global = getGlobal();
    global = { ...global, authTypes: ['passcode'], enclaveSession };
    setGlobal(global);

    // `createAccount` owns the loading state from here on: this dispatcher runs it synchronously, so
    // clearing the flag afterwards would leave the button live for the whole account import.
    actions.createAccount({ isPasswordNumeric: isNumeric });
  } catch (err: any) {
    const error = err?.message || 'Failed to setup auth';

    global = getGlobal();
    global = updateAuth(global, { isLoading: false, error });
    setGlobal(global);
  }
});

addActionHandler('setupBiometricAuth', async (global, actions) => {
  global = updateAuth(global, { isLoading: true });
  setGlobal(global);

  try {
    await clearAuthGuardingNothing();

    // A biometric auth already in storage is authorized against rather than replaced. A passcode auth
    // that is still guarding secrets survives this and makes the setup below refuse, which is correct:
    // only the password that sealed the master key can hand it over to biometrics.
    const isProvisioned = await enclave.isAuthProvisioned('biometric');
    const enclaveSession = isProvisioned
      ? await enclave.authorize('biometric', false)
      : await enclave.setupAuth('biometric');
    if (!enclaveSession) {
      throw new Error(isProvisioned ? 'Biometric confirmation failed.' : 'Failed to setup biometric auth');
    }

    global = getGlobal();
    global = { ...global, authTypes: ['biometric'], enclaveSession };
    setGlobal(global);

    // `createAccount` owns the loading state from here on: this dispatcher runs it synchronously, so
    // clearing the flag afterwards would leave both protection buttons live for the whole import.
    actions.createAccount();
  } catch (err: any) {
    const error = err?.message || 'Biometric setup failed.';
    global = getGlobal();
    global = updateAuth(global, { isLoading: false, error });
    setGlobal(global);

    void vibrateOnError();
  }
});

addActionHandler('skipCreateBiometrics', (global, actions, { isImporting } = {}) => {
  global = updateAuth(global, {
    state: isImporting ? AuthState.importWalletCreatePassword : AuthState.createPassword,
  });
  setGlobal(global);
});

addActionHandler('skipBiometrics', (global, actions) => {
  actions.createAccount({ isPasswordNumeric: getDoesUsePinPad() });
});

addActionHandler('createAccount', async (global, actions) => {
  if (IS_EXPLORER) return;

  if (takeAbortDappConnectWalletCreationIfRequested()) {
    finalizeDappConnectWalletCreationAbort();
    return;
  }

  setGlobal(updateAuth(global, { isLoading: true }));

  const isHardware = global.auth.method === 'importHardwareWallet';
  if (isHardware) {
    actions.createHardwareAccounts();

    return;
  }

  const enclaveToken = selectEnclaveToken(global);
  if (!enclaveToken) throw new Error('Missing authorization');

  const isImporting = global.auth.method !== 'createAccount';
  const mnemonic = global.auth.mnemonic!;
  const mainNetwork = selectCurrentNetwork(getGlobal());
  const networks: ApiNetwork[] = [mainNetwork];

  // The trimmed product has no way to add an account on demand, so it pre-creates the twin to make the network
  // toggle work. A full build reaches `startChangingNetwork`, which opens the auth flow when the other network
  // is empty - pre-creating there would only leave an invisible account holding the same mnemonic.
  if (IS_FEATURE_LIMITED) {
    networks.push(mainNetwork === 'testnet' ? 'mainnet' : 'testnet');
  }

  const isPrivateKeyBased = isMnemonicPrivateKey(mnemonic);
  const accounts = isPrivateKeyBased
    // TODO: Create a separate screen for private key importing, where users will choose the chain
    ? await callApi('importPrivateKey', 'ton', networks, mnemonic[0])
    : await callApi('importMnemonic', networks, mnemonic, !isImporting);

  global = getGlobal();

  if (isErrorTransferResult(accounts)) {
    if (takeAbortDappConnectWalletCreationIfRequested()) {
      finalizeDappConnectWalletCreationAbort();
      return;
    }
    if (global.dappConnectRequest?.isCreatingAccount) {
      global = clearDappConnectRequest(global);
    }
    setGlobal(updateAuth(global, { isLoading: undefined }));
    actions.showError({ error: accounts?.error });
    return;
  }

  if (await rollbackDappConnectWalletCreationIfPersisted(accounts)) {
    return;
  }

  try {
    await enclave.importSecret(accounts[0].accountId, mnemonic.join(' '), enclaveToken);
    for (let i = 1; i < accounts.length; i++) {
      await enclave.duplicateSecret(accounts[0].accountId, accounts[i].accountId);
    }
  } catch (err: any) {
    // The wallet exists in storage but its secret does not, so surface the failure instead of leaving the
    // screen loading forever - the user can retry, and the accounts stay recoverable from the mnemonic.
    // Both loading flags have to go: the auth flow and the account selector each own one.
    logDebugError('createAccount', err);

    global = updateAuth(getGlobal(), { isLoading: undefined });
    global = updateAccounts(global, { isLoading: undefined });
    setGlobal(global);
    actions.showError({ error: ApiCommonError.Unexpected });
    return;
  }

  global = getGlobal();

  if (isImporting) {
    await refreshImportedAccountsMfa(accounts, enclaveToken);
    global = getGlobal();
  }

  const authAccounts = isPrivateKeyBased
    ? accounts.map((account) => ({ ...account, partial: { isPrivateKeyBased: true as const } }))
    : accounts;

  if (!isImporting && !global.dappConnectRequest?.isCreatingAccount) {
    global = { ...global, appState: AppState.Auth, isAccountSelectorOpen: undefined };
  }

  if (global.dappConnectRequest?.isCreatingAccount) {
    const network = selectCurrentNetwork(global);

    const pendingConnectAccountId = accounts.find(({ accountId }) => (
      parseAccountId(accountId).network === network
    ))?.accountId ?? accounts[0]?.accountId;

    if (pendingConnectAccountId) {
      global = updateDappConnectRequest(global, { pendingConnectAccountId });
    }
  }
  global = updateAuth(global, {
    isLoading: undefined,
    // TODO mnemonic: undefined, ?
    pin: undefined,
    accounts: authAccounts,
    // TODO Confirm not needed
    // ...(isPasswordNumeric && { isPasswordNumeric: true }),
  });
  global = clearIsPinAccepted(global);

  if (isImporting) {
    global = updateAuth(global, { state: AuthState.importCongratulations });
  } else if (!global.dappConnectRequest?.isCreatingAccount) {
    global = updateAuth(global, { state: AuthState.safetyRules });
  }

  setGlobal(global);

  if (!isImporting && getGlobal().dappConnectRequest?.isCreatingAccount) {
    actions.skipCheckMnemonic();
  }
});

/**
 * Copies the secret of an account onto a wallet just derived from it. A missing source secret means the
 * source account cannot sign either, so the derived wallet must not be silently presented as ready.
 */
async function duplicateSecretOrShowError(fromAccountId: string, toAccountId: string) {
  try {
    await enclave.duplicateSecret(fromAccountId, toAccountId);

    return true;
  } catch (err: any) {
    logDebugError('duplicateSecret', err);
    getActions().showError({ error: ApiCommonError.Unexpected });

    return false;
  }
}

async function refreshImportedAccountsMfa(
  accounts: { accountId: string; byChain: Account['byChain'] }[],
  enclaveToken: string,
) {
  await Promise.all(accounts.map(async (account) => {
    if (!account.byChain.ton) return;

    try {
      const result = await callApi('refreshMfaState', account.accountId, enclaveToken);
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

  if (!global.dappConnectRequest?.isCreatingAccount) {
    global = updateCurrentAccountId(global, global.auth.accounts![0].accountId);
  }

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
  const newAccountId = global.auth.accounts![0].accountId;
  global = createAccountsFromGlobal(global);

  if (!global.dappConnectRequest?.isCreatingAccount) {
    global = updateCurrentAccountId(global, newAccountId);
  }

  global = updateAccountState(global, newAccountId, { isBackupRequired: true });
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

addActionHandler('startImportingWallet', (global, actions, payload) => {
  if (IS_EXPLORER) return;

  const { enclaveToken } = payload ?? {};
  const hasPassword = selectHasPassword(global);
  const state = hasPassword && !enclaveToken && !selectIsEnclaveSessionValid(global)
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

  const hasPassword = selectHasPassword(global);
  const state = getDoesUsePinPad()
    ? AuthState.importWalletCreatePin
    : CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
      ? AuthState.importWalletCreateBiometrics
      : AuthState.importWalletCreatePassword;

  global = updateAuth(global, {
    mnemonic,
    error: undefined,
    ...(!hasPassword && { state }),
  });
  setGlobal(global);

  if (hasPassword) {
    actions.confirmDisclaimer();
  }
});

addActionHandler('confirmDisclaimer', (global, actions) => {
  const hasPassword = selectHasPassword(global);

  if (hasPassword) {
    setGlobal(global);
    actions.createAccount();

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

  actions.createAccount();
});

addActionHandler('enableBiometrics', async (global, actions, { isLoginFlow } = {}) => {
  if (isLoginFlow) {
    global = updateAuth(global, { isLoading: true });
    setGlobal(global);
  }

  try {
    // Get fresh token from current global state
    const currentToken = selectEnclaveToken(getGlobal());
    if (!currentToken) throw new Error('No enclave session token available');

    const shouldReplace = CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY;
    const newEnclaveSession = await enclave.migrateAuth(currentToken, 'biometric', undefined, shouldReplace);
    if (!newEnclaveSession) throw new Error('Failed to enable biometrics.');

    global = getGlobal();
    const currentAuthTypes = global.authTypes || [];
    const authTypes: AuthType[] = shouldReplace
      ? ['biometric']
      : (currentAuthTypes.includes('biometric') ? currentAuthTypes : [...currentAuthTypes, 'biometric']);
    global = { ...global, authTypes, enclaveSession: newEnclaveSession };
    setGlobal(global);

    if (isLoginFlow) {
      actions.createAccount();
    } else {
      global = getGlobal();
      global = updateBiometrics(global, { state: BiometricsState.TurnOnComplete });
      setGlobal(global);

      // Outside the login flow nothing reads the key through the session this minted - the caller
      // that asked for biometrics is holding a session of its own. A counted session has no expiry,
      // so keeping this one would leave a read authorized with no prompt behind it
      actions.releaseEnclaveSession({ enclaveToken: newEnclaveSession.token });
    }

    void vibrateOnSuccess();
  } catch (err: any) {
    const error = err?.message || 'Biometric setup failed.';

    global = getGlobal();

    if (isLoginFlow) {
      global = updateAuth(global, { error });
    } else {
      global = updateBiometrics(global, { error });
    }

    setGlobal(global);

    void vibrateOnError();
  } finally {
    global = getGlobal();

    if (isLoginFlow) {
      global = updateAuth(global, { isLoading: undefined });
    }

    global = clearIsPinAccepted(global);
    setGlobal(global);
  }
});

addActionHandler('disableBiometrics', async (global, actions, { newPassword, isPasswordNumeric } = {}) => {
  const currentToken = selectEnclaveToken(global);

  if (newPassword && currentToken) {
    // WebAuthn biometric-only: replace biometric with passcode
    const newSession = await enclave.migrateAuth(currentToken, 'passcode', newPassword, true);
    if (!newSession) {
      global = getGlobal();
      global = updateBiometrics(global, { error: 'Failed to create password' });
      setGlobal(global);
      return;
    }

    global = getGlobal();
    global = updateBiometrics(global, { state: BiometricsState.TurnOffComplete, error: undefined });
    global = {
      ...global,
      authTypes: ['passcode'],
      enclaveSession: newSession,
    };
    if (isPasswordNumeric) {
      global = updateSettings(global, { isPasswordNumeric: true });
    }
    setGlobal(global);

    // Swapping biometrics for a passcode reads no secret of its own, so the session this minted goes
    // back rather than sitting there as a read nobody asked for
    actions.releaseEnclaveSession({ enclaveToken: newSession.token });
  } else {
    if (!currentToken) {
      global = updateBiometrics(global, { error: 'Authentication required' });
      setGlobal(global);
      return;
    }

    // Native: just remove biometric, keep passcode
    await enclave.removeAuth('biometric');

    global = getGlobal();
    global = updateBiometrics(global, { state: BiometricsState.TurnOffComplete, error: undefined });
    global = { ...global, authTypes: ['passcode'] };
    setGlobal(global);
  }
});

addActionHandler('closeBiometricSettings', (global) => {
  global = { ...global, biometrics: cloneDeep(INITIAL_STATE.biometrics) };

  setGlobal(global);
});

addActionHandler('openBiometricsTurnOffWarning', (global) => {
  global = updateBiometrics(global, { state: BiometricsState.TurnOffWarning });

  setGlobal(global);
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

  if (!await duplicateSecretOrShowError(accountId, wallet.accountId)) return;

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

addActionHandler('createSubWallet', withEnclaveSessionRelease(async (global, actions, { enclaveToken }) => {
  const accountId = selectCurrentAccountId(global)!;

  const result = await callApi('createSubWallet', accountId, enclaveToken);

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

  if (!await duplicateSecretOrShowError(accountId, result.accountId)) return;

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
}));

addActionHandler('upgradeMultichainAccounts', async (global, actions, { enclaveToken }) => {
  // `PasswordForm` starts this upgrade after every authorization, so a second password entry
  // during a running upgrade would start the same upgrade again. Clearing the count right away
  // prevents that; putting it back on failure allows a retry on the next password entry.
  const upgradeCount = global.multichainUpgradeCount;
  if (!upgradeCount) return;

  setGlobal({ ...global, multichainUpgradeCount: undefined });

  // This rides along on the operation's session rather than asking for one, so it takes a hold: the
  // operation usually finishes first, and its release would otherwise land between two of the reads
  // below and leave the accounts half upgraded
  holdEnclaveSession(enclaveToken);

  try {
    const result = await callApi('upgradeMultichainAccounts', enclaveToken);

    if (result && 'error' in result) {
      logDebugError('upgradeMultichainAccounts', result.error);

      // Asking again rather than putting back the count taken before the run: the accounts upgraded
      // before the failure are no longer candidates, and the count becomes a secret-read budget on
      // the next password entry, where reads granted and not taken outlive the operation. An
      // unanswered question is not an empty answer - dropping the count there would lose the upgrade
      // until the app starts again, so the stale count is the better of the two wrong numbers
      const candidateIds = await callApi('getMultichainUpgradeCandidateIds');
      setGlobal({
        ...getGlobal(),
        multichainUpgradeCount: candidateIds ? (candidateIds.length || undefined) : upgradeCount,
      });
    }
  } finally {
    if (dropEnclaveSessionHold(enclaveToken)) {
      actions.releaseEnclaveSession({ enclaveToken });
    }
  }
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

  if (!await duplicateSecretOrShowError(accountId, result.accountId)) return;

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

    if (entry.isNew) {
      if (!await duplicateSecretOrShowError(accountId, entry.accountId)) return;
    }

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

addActionHandler('rollbackEnclaveMigration', async (global, actions) => {
  await callApi('rollbackEnclaveMigration');

  global = getGlobal();
  setGlobal({
    ...global,
    authTypes: undefined,
    enclaveSession: undefined,
  });

  actions.showToast({ message: 'Migration was rolled back' });
});

/**
 * The secrets live in the worker storage while the wallet list lives in the global state, and the two are
 * known to diverge, so an account the list never learned about is passed over here: a mark that has nowhere
 * to be drawn is not worth throwing away a migration that has already reached the Enclave.
 */
function markAccounts(global: GlobalState, accountIds: string[], partial: Partial<Account>) {
  for (const accountId of accountIds) {
    if (!selectAccount(global, accountId)) continue;

    global = updateAccount(global, accountId, partial);
  }

  return global;
}

/**
 * A migrated profile that left wallets behind is the state support has to recognise, and the account
 * ids are the only thing that identifies which ones. The mark is what every screen reads to warn that
 * the wallet cannot sign until its secret is recovered.
 */
function markUnreadableAccounts(global: GlobalState, context: string, accountIds: string[]) {
  if (!accountIds.length) return global;

  logDebugError(context, `Migrated without secrets for accounts: ${accountIds.join(', ')}`);

  return markAccounts(global, accountIds, { isRecoveryRequired: true });
}

/**
 * The screen that starts a migration holds a guard until one of the callbacks answers, and it has no
 * way to await the action. A throw that reached the action runner instead would leave that guard set:
 * every later submit, biometric tap and retry returns at it, and only closing and reopening the screen
 * clears it. So every exit from these handlers, a throw included, goes through a callback.
 */
function reportMigrationThrow(
  context: string,
  err: unknown,
  step: MigrationStep,
  onError: (error: MigrationErrorPresentation) => void,
  isPasswordFromStore = false,
) {
  logDebugError(context, err);
  onError(presentMigrationFailure(describeThrownError(err, step), isPasswordFromStore));
}

addActionHandler('migrateLegacyAuth', async (global, actions, payload: {
  password: string;
  isLongSession: boolean;
  usageCount?: number;
  onSuccess: (token: string) => void;
  onError: (error: MigrationErrorPresentation) => void;
}) => {
  const { password, isLongSession, usageCount, onSuccess, onError } = payload;
  let token: string;

  try {
    const legacyAccounts = await callApi('fetchLegacyAccountsWithMnemonic');
    if (!legacyAccounts?.length) {
      onError({ kind: 'inline', text: 'Unable to migrate wallet data. Please contact support.' });
      return;
    }

    const migrationOutcome = await legacyAuth.migrateFromLegacy(
      legacyAccounts, password, isLongSession, usageCount,
    );
    if (checkIsMigrationFailure(migrationOutcome)) {
      onError(presentMigrationFailure(migrationOutcome.error));
      return;
    }

    const { session, privateKeyAccountIds, migratedAccountIds, unreadableAccountIds } = migrationOutcome;

    global = getGlobal();
    global = { ...global, authTypes: ['passcode'], enclaveSession: session };
    global = markAccounts(global, privateKeyAccountIds, { isPrivateKeyBased: true });
    global = markUnreadableAccounts(global, 'migrateLegacyAuth', unreadableAccountIds);
    setGlobal(global);

    token = session.token;

    // Best-effort: the migration is committed by now, so a cleanup that throws must not turn the
    // success into a reported failure
    if (SHOULD_CLEANUP_LEGACY_AUTH) {
      try {
        await callApi('cleanupLegacyAuthAfterMigration', migratedAccountIds);
      } catch (err) {
        logDebugError('migrateLegacyAuth', err);
      }
    }
  } catch (err) {
    reportMigrationThrow('migrateLegacyAuth', err, 'read', onError);
    return;
  }

  onSuccess(token);
});

addActionHandler('migrateLegacyBiometricAuth', async (global, actions, payload: {
  legacyAuthConfig: LegacyAuthConfig;
  isLongSession: boolean;
  usageCount?: number;
  onSuccess: (token: string) => void;
  onError: (error: MigrationErrorPresentation) => void;
}) => {
  const { legacyAuthConfig, isLongSession, usageCount, onSuccess, onError } = payload;
  let step: MigrationStep = 'legacyPassword';
  let token: string;

  try {
    // Get password from old biometric storage
    const password = await legacyAuth.getPasswordFromLegacyBiometrics(legacyAuthConfig);
    if (!password) {
      onError({ kind: 'inline', text: 'Failed to retrieve password from biometrics' });
      return;
    }

    step = 'read';
    const legacyAccounts = await callApi('fetchLegacyAccountsWithMnemonic');
    if (!legacyAccounts?.length) {
      onError({ kind: 'inline', text: 'Unable to migrate wallet data. Please contact support.' });
      return;
    }

    let session;
    let privateKeyAccountIds: string[] = [];
    let migratedAccountIds: string[] = [];
    let unreadableAccountIds: string[] = [];
    let authTypes: ('passcode' | 'biometric')[];

    if (legacyAuthConfig.kind === 'native-biometrics') {
      // Native biometrics stored user's real password - migrate to both passcode and biometric
      const migrationOutcome = await legacyAuth.migrateFromLegacy(legacyAccounts, password, isLongSession);
      if (checkIsMigrationFailure(migrationOutcome)) {
        onError(presentMigrationFailure(migrationOutcome.error, true));
        return;
      }

      ({ session, privateKeyAccountIds, migratedAccountIds, unreadableAccountIds } = migrationOutcome);

      // Add biometric as second auth method (don't replace passcode). The caller is handed the session
      // this mints rather than the one the migration returned, so the budget is declared here
      step = 'secondAuth';
      const biometricSession = await enclave.migrateAuth(session.token, 'biometric', undefined, false, usageCount);
      if (biometricSession) {
        session = biometricSession;
        authTypes = ['passcode', 'biometric'];
      } else {
        // Biometric setup failed, but passcode migration succeeded - continue with passcode only
        authTypes = ['passcode'];
      }
    } else {
      // electron-safe-storage or webauthn - password was random, user doesn't know it
      const migrationOutcome = await legacyAuth.migrateFromLegacyBiometric(legacyAccounts, password, usageCount);
      if (checkIsMigrationFailure(migrationOutcome)) {
        onError(presentMigrationFailure(migrationOutcome.error, true));
        return;
      }

      ({ session, privateKeyAccountIds, migratedAccountIds, unreadableAccountIds } = migrationOutcome);
      // Legacy WebAuthn/electron-safe-storage users had a random password they don't know.
      // They remain biometric-only after migration. They can add a passcode via Settings > Change Password.
      authTypes = ['biometric'];
    }

    global = getGlobal();
    global = { ...global, authTypes, enclaveSession: session };
    global = markAccounts(global, privateKeyAccountIds, { isPrivateKeyBased: true });
    global = markUnreadableAccounts(global, 'migrateLegacyBiometricAuth', unreadableAccountIds);
    setGlobal(global);

    token = session.token;

    // Best-effort: the migration is committed by now, so a cleanup that throws must not turn the
    // success into a reported failure
    if (SHOULD_CLEANUP_LEGACY_AUTH) {
      try {
        await callApi('cleanupLegacyAuthAfterMigration', migratedAccountIds);
      } catch (err) {
        logDebugError('migrateLegacyBiometricAuth', err);
      }
    }
  } catch (err) {
    reportMigrationThrow('migrateLegacyBiometricAuth', err, step, onError, true);
    return;
  }

  onSuccess(token);
});

function reduceGlobalForDebug() {
  const reduced = cloneDeep(getGlobal());

  reduced.tokenInfo = {} as any;
  reduced.swapTokenInfo = {} as any;
  Object.entries(reduced.byAccountId).forEach(([, state]) => {
    state.activities = {} as any;
  });

  reduced.enclaveSession = undefined;
  reduced.auth.pin = undefined;
  reduced.auth.mnemonic = undefined;

  return reduced;
}
