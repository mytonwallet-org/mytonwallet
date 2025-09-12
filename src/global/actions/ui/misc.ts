import { BarcodeScanner } from '@capacitor-mlkit/barcode-scanning';

import type { GlobalState } from '../../types';
import {
  AppState,
  AuthState,
  ContentTab,
  DomainLinkingState,
  SettingsState,
  SwapState,
  TransferState,
} from '../../types';

import {
  ANIMATION_LEVEL_MIN,
  APP_VERSION,
  BETA_URL,
  BOT_USERNAME,
  DEBUG,
  IS_PRODUCTION,
  PRODUCTION_URL,
} from '../../../config';
import { getDoesUsePinPad } from '../../../util/biometrics';
import { openDeeplinkOrUrl, parseDeeplinkTransferParams, processDeeplink } from '../../../util/deeplink';
import getIsAppUpdateNeeded from '../../../util/getIsAppUpdateNeeded';
import { vibrate, vibrateOnSuccess } from '../../../util/haptics';
import { omit } from '../../../util/iteratees';
import { getTranslation } from '../../../util/langProvider';
import { callActionInMain, callActionInNative } from '../../../util/multitab';
import { openUrl } from '../../../util/openUrl';
import { getTelegramApp } from '../../../util/telegram';
import {
  getIsMobileTelegramApp,
  IS_ANDROID_APP,
  IS_BIOMETRIC_AUTH_SUPPORTED,
  IS_DELEGATED_BOTTOM_SHEET,
  IS_DELEGATING_BOTTOM_SHEET,
  IS_ELECTRON,
} from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { closeAllOverlays, parsePlainAddressQr } from '../../helpers/misc';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearCurrentSwap,
  clearCurrentTransfer,
  clearIsPinAccepted,
  renameAccount,
  setCurrentTransferAddress,
  setIsPinAccepted,
  updateAccounts,
  updateAuth,
  updateCurrentAccountSettings,
  updateCurrentAccountState,
  updateCurrentDomainLinking,
  updateCurrentSwap,
  updateCurrentTransfer,
  updateSettings,
} from '../../reducers';
import {
  selectCurrentAccount,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsPasswordPresent,
} from '../../selectors';
import { switchAccount } from '../api/auth';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

import { reportAppLockActivityEvent } from '../../../components/appLocked/AppLocked';
import { closeModal } from '../../../components/ui/Modal';

const APP_VERSION_URL = IS_ANDROID_APP ? `${IS_PRODUCTION ? PRODUCTION_URL : BETA_URL}/version.txt` : 'version.txt';

addActionHandler('showActivityInfo', (global, actions, { id }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('showActivityInfo', { id });
    return undefined;
  }

  return updateCurrentAccountState(global, { currentActivityId: id });
});

addActionHandler('showAnyAccountTx', async (global, actions, { txId, accountId, network }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('showAnyAccountTx', { txId, accountId, network });
    return;
  }

  await Promise.all([
    closeAllOverlays(),
    switchAccount(global, accountId, network),
  ]);

  actions.showActivityInfo({ id: txId });
});

addActionHandler('showAnyAccountTokenActivity', async (global, actions, { slug, accountId, network }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('showAnyAccountTokenActivity', { slug, accountId, network });
    return;
  }

  await Promise.all([
    closeAllOverlays(),
    switchAccount(global, accountId, network),
  ]);

  actions.showTokenActivity({ slug });
});

addActionHandler('closeActivityInfo', (global, actions, { id }) => {
  if (selectCurrentAccountState(global)?.currentActivityId !== id) {
    return undefined;
  }

  return updateCurrentAccountState(global, { currentActivityId: undefined });
});

addActionHandler('addSavedAddress', (global, actions, { address, name, chain }) => {
  const { savedAddresses = [] } = selectCurrentAccountState(global) || {};

  return updateCurrentAccountState(global, {
    savedAddresses: [
      ...savedAddresses,
      { address, name, chain },
    ],
  });
});

addActionHandler('removeFromSavedAddress', (global, actions, { address, chain }) => {
  const { savedAddresses = [] } = selectCurrentAccountState(global) || {};

  const newSavedAddresses = savedAddresses.filter((item) => !(item.address === address && item.chain === chain));

  return updateCurrentAccountState(global, { savedAddresses: newSavedAddresses });
});

addActionHandler('toggleTinyTransfersHidden', (global, actions, { isEnabled } = {}) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      areTinyTransfersHidden: isEnabled,
    },
  };
});

addActionHandler('setCurrentTokenPeriod', (global, actions, { period }) => {
  return updateCurrentAccountState(global, {
    currentTokenPeriod: period,
  });
});

addActionHandler('addAccount', async (global, actions, { method, password, isAuthFlow }) => {
  const isPasswordPresent = selectIsPasswordPresent(global);
  const isMnemonicImport = method === 'importMnemonic';

  if (isPasswordPresent) {
    if (!isAuthFlow) {
      global = updateAccounts(global, {
        isLoading: true,
      });
      setGlobal(global);
    }

    if (!(await callApi('verifyPassword', password))) {
      global = getGlobal();
      if (isAuthFlow) {
        global = updateAuth(global, {
          isLoading: undefined,
          error: 'Wrong password, please try again.',
        });
      } else {
        global = updateAccounts(getGlobal(), {
          isLoading: undefined,
          error: 'Wrong password, please try again.',
        });
      }
      setGlobal(global);
      return;
    }

    if (getDoesUsePinPad()) {
      global = setIsPinAccepted(getGlobal());
      setGlobal(global);
    }
    await vibrateOnSuccess(true);
  }

  global = getGlobal();
  if (isMnemonicImport || !isPasswordPresent) {
    global = { ...global, isAddAccountModalOpen: undefined };
  } else {
    global = updateAccounts(global, { isLoading: true });
  }
  setGlobal(global);

  if (!IS_DELEGATED_BOTTOM_SHEET) {
    actions.addAccount2({ method, password });
  } else {
    callActionInMain('addAccount2', { method, password });
  }
});

addActionHandler('addAccount2', (global, actions, { method, password }) => {
  const isMnemonicImport = method === 'importMnemonic';
  const isPasswordPresent = selectIsPasswordPresent(global);
  const authState = isPasswordPresent
    ? isMnemonicImport
      ? AuthState.importWallet
      : undefined
    : (
      getDoesUsePinPad()
        ? AuthState.createPin
        : (IS_BIOMETRIC_AUTH_SUPPORTED ? AuthState.createBiometrics : AuthState.createPassword)
    );

  if (isMnemonicImport || !isPasswordPresent) {
    global = { ...global, appState: AppState.Auth };
  }
  global = updateAuth(global, { password, state: authState });
  global = clearCurrentTransfer(global);
  global = clearCurrentSwap(global);

  setGlobal(global);

  if (isMnemonicImport) {
    actions.startImportingWallet();
  } else {
    actions.startCreatingWallet();
  }
});

addActionHandler('renameAccount', (global, actions, { accountId, title }) => {
  global = { ...global, shouldForceAccountEdit: false };

  setGlobal(renameAccount(global, accountId, title));

  actions.renameNotificationAccount({ accountId });
});

addActionHandler('clearAccountError', (global) => {
  return updateAccounts(global, { error: undefined });
});

addActionHandler('openAddAccountModal', (global, _, props) => {
  const { forceAddingTonOnlyAccount } = props || {};

  if (IS_DELEGATED_BOTTOM_SHEET && !global.areSettingsOpen) {
    callActionInMain('openAddAccountModal', props);
    return;
  }

  global = { ...global, isAddAccountModalOpen: true };

  if (forceAddingTonOnlyAccount) {
    global = updateAuth(global, { forceAddingTonOnlyAccount });
  }

  setGlobal(global);
});

addActionHandler('closeAddAccountModal', (global, _, props) => {
  if (getDoesUsePinPad()) {
    global = clearIsPinAccepted(global);
  }

  global = updateAuth(global, { forceAddingTonOnlyAccount: undefined });
  global = { ...global, isAddAccountModalOpen: undefined };

  return global;
});

addActionHandler('changeNetwork', (global, actions, { network }) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      isTestnet: network === 'testnet',
    },
  };
});

addActionHandler('openSettings', (global) => {
  global = updateSettings(global, { state: SettingsState.Initial });

  return { ...global, areSettingsOpen: true };
});

addActionHandler('openSettingsWithState', (global, actions, { state }) => {
  if (IS_DELEGATED_BOTTOM_SHEET && !global.areSettingsOpen) {
    callActionInMain('openSettingsWithState', { state });
    return;
  }

  global = updateSettings(global, { state });
  setGlobal({ ...global, areSettingsOpen: true });
});

addActionHandler('setSettingsState', (global, actions, { state }) => {
  global = updateSettings(global, { state });
  setGlobal(global);
});

addActionHandler('closeSettings', (global) => {
  if (!global.currentAccountId) {
    return global;
  }

  return { ...global, areSettingsOpen: false };
});

addActionHandler('openBackupWalletModal', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openBackupWalletModal');
    return undefined;
  }

  return { ...global, isBackupWalletModalOpen: true };
});

addActionHandler('closeBackupWalletModal', (global) => {
  return { ...global, isBackupWalletModalOpen: undefined };
});

addActionHandler('toggleInvestorView', (global, actions, { isEnabled } = {}) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      isInvestorViewEnabled: isEnabled,
    },
  };
});

addActionHandler('changeLanguage', (global, actions, { langCode }) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      langCode,
    },
  };
});

addActionHandler('toggleCanPlaySounds', (global, actions, { isEnabled } = {}) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      canPlaySounds: isEnabled,
    },
  };
});

addActionHandler('setLandscapeActionsActiveTabIndex', (global, actions, { index }) => {
  return updateCurrentAccountState(global, {
    landscapeActionsActiveTabIndex: index,
  });
});

addActionHandler('closeSecurityWarning', (global) => {
  return {
    ...global,
    settings: {
      ...global.settings,
      isSecurityWarningHidden: true,
    },
  };
});

addActionHandler('toggleTokensWithNoCost', (global, actions, { isEnabled }) => {
  return updateSettings(global, { areTokensWithNoCostHidden: isEnabled });
});

addActionHandler('toggleSortByValue', (global, actions, { isEnabled }) => {
  return updateSettings(global, { isSortByValueEnabled: isEnabled });
});

addActionHandler('updateOrderedSlugs', (global, actions, { orderedSlugs }) => {
  const accountSettings = selectCurrentAccountSettings(global);
  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    orderedSlugs,
  });
});

addActionHandler('toggleTokenVisibility', (global, actions, { slug, shouldShow }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { alwaysShownSlugs = [], alwaysHiddenSlugs = [] } = accountSettings;
  const alwaysShownSlugsSet = new Set(alwaysShownSlugs);
  const alwaysHiddenSlugsSet = new Set(alwaysHiddenSlugs);

  if (shouldShow) {
    alwaysHiddenSlugsSet.delete(slug);
    alwaysShownSlugsSet.add(slug);
  } else {
    alwaysShownSlugsSet.delete(slug);
    alwaysHiddenSlugsSet.add(slug);
  }

  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    alwaysHiddenSlugs: Array.from(alwaysHiddenSlugsSet),
    alwaysShownSlugs: Array.from(alwaysShownSlugsSet),
  });
});

addActionHandler('deleteToken', (global, actions, { slug }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    orderedSlugs: accountSettings.orderedSlugs?.filter((s) => s !== slug),
    alwaysHiddenSlugs: accountSettings.alwaysHiddenSlugs?.filter((s) => s !== slug),
    alwaysShownSlugs: accountSettings.alwaysShownSlugs?.filter((s) => s !== slug),
    deletedSlugs: [...accountSettings.deletedSlugs ?? [], slug],
    importedSlugs: accountSettings.importedSlugs?.filter((s) => s !== slug),
  });
});

addActionHandler('checkAppVersion', (global) => {
  fetch(`${APP_VERSION_URL}?${Date.now()}`)
    .then((response) => response.text())
    .then((version) => {
      version = version.trim();

      if (getIsAppUpdateNeeded(version, APP_VERSION)) {
        global = getGlobal();
        global = {
          ...global,
          isAppUpdateAvailable: true,
          latestAppVersion: version.trim(),
        };
        setGlobal(global);
      }
    })
    .catch((err) => {
      if (DEBUG) {
        // eslint-disable-next-line no-console
        console.error('[checkAppVersion failed] ', err);
      }
    });
});

addActionHandler('requestConfetti', (global) => {
  if (global.settings.animationLevel === ANIMATION_LEVEL_MIN) return global;

  return {
    ...global,
    confettiRequestedAt: Date.now(),
  };
});

addActionHandler('requestOpenQrScanner', async (global, actions) => {
  if (getIsMobileTelegramApp()) {
    const webApp = getTelegramApp();
    webApp?.showScanQrPopup({}, (data) => {
      void vibrateOnSuccess();
      webApp.closeScanQrPopup();
      actions.handleQrCode({ data });
    });
    return;
  }

  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('requestOpenQrScanner');
    return;
  }

  let currentQrScan: GlobalState['currentQrScan'];
  if (global.currentTransfer.state === TransferState.Initial) {
    currentQrScan = { currentTransfer: global.currentTransfer };
  } else if (global.currentSwap.state === SwapState.Blockchain) {
    currentQrScan = { currentSwap: global.currentSwap };
  } else if (global.currentDomainLinking.state === DomainLinkingState.Initial) {
    currentQrScan = { currentDomainLinking: global.currentDomainLinking };
  }

  const { camera } = await BarcodeScanner.requestPermissions();
  const isGranted = camera === 'granted' || camera === 'limited';
  if (!isGranted) {
    actions.showNotification({
      message: getTranslation('Permission denied. Please grant camera permission to use the QR code scanner.'),
    });
    return;
  }

  global = getGlobal();
  global = {
    ...global,
    isQrScannerOpen: true,
    currentQrScan,
  };

  setGlobal(global);
});

addActionHandler('closeQrScanner', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('closeQrScanner');
  }

  return {
    ...global,
    isQrScannerOpen: undefined,
    currentQrScan: undefined,
  };
});

addActionHandler('handleQrCode', async (global, actions, { data }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('handleQrCode', { data });
    return;
  }

  const { currentTransfer, currentSwap, currentDomainLinking } = global.currentQrScan || {};

  if (currentTransfer) {
    const transferParams = parseDeeplinkTransferParams(data, global);
    if (transferParams) {
      if ('error' in transferParams) {
        actions.showError({ error: transferParams.error });
        // Not returning on error is intentional
      }
      setGlobal(updateCurrentTransfer(global, {
        ...currentTransfer,
        ...omit(transferParams, ['error']),
      }));
    } else {
      // Assuming that the QR code content is a plain wallet address
      setGlobal(setCurrentTransferAddress(updateCurrentTransfer(global, currentTransfer), data));
    }
    return;
  }

  if (currentSwap || currentDomainLinking) {
    const linkParams = parseDeeplinkTransferParams(data, global);
    const toAddress = linkParams?.toAddress ?? data;
    if (currentSwap) {
      setGlobal(updateCurrentSwap(global, { ...currentSwap, toAddress }));
    } else {
      setGlobal(updateCurrentDomainLinking(global, { ...currentDomainLinking, walletAddress: toAddress }));
    }
    return;
  }

  if (await processDeeplink(data)) {
    return;
  }

  global = getGlobal();

  const plainAddressData = parsePlainAddressQr(global, data);
  if (plainAddressData) {
    actions.startTransfer({
      ...plainAddressData,
      isPortrait: getIsPortrait(),
    });
    return;
  }

  actions.showDialog({ title: 'This QR Code is not supported', message: '' });
});

addActionHandler('changeBaseCurrency', async (global, actions, { currency }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('changeBaseCurrency', { currency });
  }

  await callApi('setBaseCurrency', currency);
  await callApi('tryUpdateTokens');
  // Swap tokens will be merged with the new prices loaded in `tryUpdateTokens`
  await callApi('tryUpdateSwapTokens');
});

addActionHandler('setIsPinAccepted', (global) => {
  return setIsPinAccepted(global);
});

addActionHandler('clearIsPinAccepted', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    // Sometimes this action is called after the delegated bottom sheet is closed, e.g. on a component unmount.
    // The problem is, delegated bottom sheet doesn't synchronize the global state when it's closed, so the pin pad
    // can get stuck in the accepted state. To fix that, this action is called in the main WebView using a more reliable
    // mechanism.
    callActionInMain('clearIsPinAccepted');
  }

  return clearIsPinAccepted(global);
});

addActionHandler('openOnRampWidgetModal', (global, actions, { chain }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openOnRampWidgetModal', { chain });
    return;
  }

  setGlobal({ ...global, chainForOnRampWidgetModal: chain });
});

addActionHandler('closeOnRampWidgetModal', (global) => {
  setGlobal({ ...global, chainForOnRampWidgetModal: undefined });
});

addActionHandler('openMediaViewer', (global, actions, {
  mediaId, mediaType, txId, hiddenNfts, noGhostAnimation,
}) => {
  const accountState = selectCurrentAccountState(global);
  const { byAddress } = accountState?.nfts || {};
  const nft = byAddress?.[mediaId];

  if (!nft) return undefined;

  return {
    ...global,
    mediaViewer: {
      mediaId,
      mediaType,
      txId,
      hiddenNfts,
      noGhostAnimation,
    },
  };
});

addActionHandler('closeMediaViewer', (global) => {
  return {
    ...global,
    mediaViewer: {
      mediaId: undefined,
      mediaType: undefined,
    },
  };
});

addActionHandler('setReceiveActiveTab', (global, actions, { chain }): GlobalState => {
  return updateCurrentAccountState(global, { receiveModalChain: chain });
});

addActionHandler('openReceiveModal', (global, actions, params) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openReceiveModal', params);
    return;
  }

  global = updateCurrentAccountState(global, { receiveModalChain: params?.chain });
  global = { ...global, isReceiveModalOpen: true };
  setGlobal(global);
});

addActionHandler('closeReceiveModal', (global): GlobalState => {
  global = updateCurrentAccountState(global, { receiveModalChain: undefined });
  return { ...global, isReceiveModalOpen: undefined };
});

addActionHandler('openInvoiceModal', (global, actions, params) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('openInvoiceModal', params);
    return;
  }

  global = updateCurrentAccountState(global, { invoiceTokenSlug: params?.tokenSlug });
  setGlobal({ ...global, isInvoiceModalOpen: true });
});

addActionHandler('changeInvoiceToken', (global, actions, params) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('changeInvoiceToken', params);
  }

  global = updateCurrentAccountState(global, { invoiceTokenSlug: params.tokenSlug });
  setGlobal(global);
});

addActionHandler('closeInvoiceModal', (global): GlobalState => {
  global = updateCurrentAccountState(global, { invoiceTokenSlug: undefined });
  return { ...global, isInvoiceModalOpen: undefined };
});

addActionHandler('showIncorrectTimeError', (global, actions) => {
  actions.showDialog({
    message: getTranslation('Time synchronization issue. Please ensure your device\'s time settings are correct.'),
  });

  return { ...global, isIncorrectTimeNotificationReceived: true };
});

addActionHandler('openLoadingOverlay', (global) => {
  setGlobal({ ...global, isLoadingOverlayOpen: true });
});

addActionHandler('closeLoadingOverlay', (global) => {
  setGlobal({ ...global, isLoadingOverlayOpen: undefined });
});

addActionHandler('clearAccountLoading', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('clearAccountLoading');
  }

  setGlobal(updateAccounts(global, { isLoading: undefined }));
});

addActionHandler('setIsAccountLoading', (global, actions, { isLoading }) => {
  setGlobal(updateAccounts(global, { isLoading }));
});

addActionHandler('authorizeDiesel', (global) => {
  const address = selectCurrentAccount(global)!.byChain.ton?.address;
  if (!address) throw new Error('TON address missing');
  setGlobal(updateCurrentAccountState(global, { isDieselAuthorizationStarted: true }));
  void openUrl(`https://t.me/${BOT_USERNAME}?start=auth-${address}`);
});

addActionHandler('submitAppLockActivityEvent', () => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('submitAppLockActivityEvent');
    return;
  }
  reportAppLockActivityEvent();
});

addActionHandler('closeAnyModal', () => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('closeAnyModal');
    return;
  }

  closeModal();
});

addActionHandler('openExplore', (global) => {
  return { ...global, isExploreOpen: true };
});

addActionHandler('closeExplore', (global) => {
  return { ...global, isExploreOpen: undefined };
});

addActionHandler('openFullscreen', (global) => {
  setGlobal({ ...global, isFullscreen: true });

  void vibrate();
});

addActionHandler('closeFullscreen', (global) => {
  setGlobal({ ...global, isFullscreen: undefined });

  void vibrate();
});

addActionHandler('setIsSensitiveDataHidden', (global, actions, { isHidden }) => {
  setGlobal(updateSettings(global, { isSensitiveDataHidden: isHidden ? true : undefined }));

  void vibrate();
});

addActionHandler('setIsAppLockActive', (global, actions, { isActive }) => {
  if (IS_DELEGATING_BOTTOM_SHEET) {
    callActionInNative('setIsAppLockActive', { isActive });
  }

  setGlobal({ ...global, isAppLockActive: isActive || undefined });
});

addActionHandler('switchAccountAndOpenUrl', async (global, actions, payload) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('switchAccountAndOpenUrl', payload);
    return;
  }

  await Promise.all([
    // The browser is closed before opening the new URL, because otherwise the browser won't apply the new
    // parameters from `payload`. It's important to wait for `closeAllOverlays` to finish, because until the in-app
    // browser is closed, it won't open again.
    closeAllOverlays(),
    payload.accountId && switchAccount(global, payload.accountId, payload.network),
  ]);

  await openDeeplinkOrUrl(payload.url, payload);
});

addActionHandler('switchToWallet', (global: GlobalState, actions) => {
  const { areSettingsOpen, isExploreOpen } = global;
  const accountState = selectCurrentAccountState(global);
  const areAssetsActive = accountState?.activeContentTab === ContentTab.Assets;
  const isWalletTabActive = !isExploreOpen && !areSettingsOpen;

  actions.closeExplore(undefined, { forceOnHeavyAnimation: true });
  actions.closeSettings(undefined, { forceOnHeavyAnimation: true });

  if (!areAssetsActive && isWalletTabActive) {
    actions.selectToken({ slug: undefined }, { forceOnHeavyAnimation: true });
    actions.setActiveContentTab({ tab: ContentTab.Assets }, { forceOnHeavyAnimation: true });
  }
});

addActionHandler('switchToExplore', (global: GlobalState, actions) => {
  const { isExploreOpen } = global;

  if (isExploreOpen) {
    actions.closeSiteCategory(undefined, { forceOnHeavyAnimation: true });
  }

  actions.closeSettings(undefined, { forceOnHeavyAnimation: true });
  actions.openExplore(undefined, { forceOnHeavyAnimation: true });
});

addActionHandler('switchToSettings', (global: GlobalState, actions) => {
  actions.closeExplore(undefined, { forceOnHeavyAnimation: true });
  actions.openSettings(undefined, { forceOnHeavyAnimation: true });
});

addActionHandler('setAppLayout', (global, actions, { layout }) => {
  if (IS_ELECTRON) {
    void window.electron?.changeAppLayout(layout);
  } else {
    void callApi('setAppLayout', layout);
  }
});
