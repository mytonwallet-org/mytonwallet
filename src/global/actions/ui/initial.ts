import type {
  Account, AccountSettings, AccountState, ToastType,
} from '../../types';
import { AppState } from '../../types';

import {
  DEFAULT_SWAP_FIRST_TOKEN_SLUG,
  DEFAULT_SWAP_SECOND_TOKEN_SLUG,
  DEFAULT_TRANSFER_TOKEN_SLUG,
  IS_CAPACITOR,
  IS_EXPLORER,
  IS_EXTENSION,
  IS_TELEGRAM_APP,
  TONCOIN,
} from '../../../config';
import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { parseAccountId } from '../../../util/account';
import authApi from '../../../util/authApi';
import { initCapacitorWithGlobal } from '../../../util/capacitor';
import {
  getDeeplinkFromLocation,
  processDeeplink,
  processDeeplinkAfterInit,
  processDeeplinkAfterSignIn,
} from '../../../util/deeplink';
import { omit } from '../../../util/iteratees';
import { clearPreviousLangpacks, getTranslation, setLanguage } from '../../../util/langProvider';
import { initializeSounds } from '../../../util/notificationSound';
import switchAnimationLevel from '../../../util/switchAnimationLevel';
import switchTheme, { setStatusBarStyle } from '../../../util/switchTheme';
import { initTelegramWithGlobal } from '../../../util/telegram';
import {
  getIsMobileTelegramApp,
  IS_ANDROID,
  IS_ANDROID_APP,
  IS_ELECTRON,
  IS_IOS,
  IS_LINUX,
  IS_MAC_OS,
  IS_OPERA,
  IS_SAFARI,
  IS_WINDOWS,
  setScrollbarWidthProperty,
} from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { errorCodeToMessage } from '../../helpers/errors';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateCurrentAccountId, updateCurrentAccountState } from '../../reducers';
import {
  selectCurrentAccountId,
  selectCurrentNetwork,
  selectNetworkAccounts,
  selectNetworkAccountsMemoized,
  selectNewestActivityTimestamps,
  selectSwapTokens,
} from '../../selectors';

const ANIMATION_DELAY_MS = 320;

addActionHandler('init', (_, actions) => {
  requestMutation(() => {
    const { documentElement } = document;

    if (IS_IOS) {
      documentElement.classList.add('is-ios', 'is-mobile');
    } else if (IS_ANDROID) {
      documentElement.classList.add('is-android', 'is-mobile');
      if (IS_ANDROID_APP) {
        documentElement.classList.add('is-android-app');
      }
    } else if (IS_MAC_OS) {
      documentElement.classList.add('is-macos');
    } else if (IS_WINDOWS) {
      documentElement.classList.add('is-windows');
    } else if (IS_LINUX) {
      documentElement.classList.add('is-linux');
    }
    if (IS_SAFARI) {
      documentElement.classList.add('is-safari');
    }
    if (IS_OPERA) {
      documentElement.classList.add('is-opera');
    }
    if (IS_EXTENSION) {
      documentElement.classList.add('is-extension');
    }
    if (IS_ELECTRON) {
      documentElement.classList.add('is-electron');
    }
    if (IS_TELEGRAM_APP) {
      documentElement.classList.add('is-telegram-app');
    }
    if (getIsMobileTelegramApp()) {
      documentElement.classList.add('is-mobile-telegram-app');
    }

    setScrollbarWidthProperty();

    actions.afterInit();
  });
});

addActionHandler('afterInit', (global, actions) => {
  const {
    theme, animationLevel, langCode, authConfig,
  } = global.settings;

  switchTheme(theme);
  switchAnimationLevel(animationLevel);
  setStatusBarStyle({
    forceDarkBackground: false,
  });
  void setLanguage(langCode);
  clearPreviousLangpacks();
  processDeeplinkAfterInit();

  if (IS_CAPACITOR) {
    void initCapacitorWithGlobal(authConfig);
  } else {
    if (IS_TELEGRAM_APP) {
      initTelegramWithGlobal(global);
    }

    document.addEventListener('click', initializeSounds, { once: true });
  }

  if (!IS_EXPLORER) return;

  void callApi('clearStorageForExplorerMode');

  const deeplinkUrl = getDeeplinkFromLocation();

  if (deeplinkUrl) {
    void processDeeplink(deeplinkUrl);
  } else {
    actions.showToast({ message: getTranslation('$explorer_mode_warning') });
  }
});

addActionHandler('afterSignIn', (global, actions) => {
  setGlobal({ ...global, appState: AppState.Main });

  setTimeout(() => {
    actions.resetAuth();

    processDeeplinkAfterSignIn();
  }, ANIMATION_DELAY_MS);
});

addActionHandler('afterSignOut', (global, actions, payload) => {
  if (payload?.shouldReset) {
    if (global.settings.authConfig?.kind === 'native-biometrics') {
      void authApi.removeNativeBiometrics();
    }
    actions.setInMemoryPassword({ password: undefined, force: true });

    actions.resetApiSettings({ areAllDisabled: true });
  }
});

addActionHandler('showDialog', (global, actions, payload) => {
  const newDialogs = [...global.dialogs];
  const existingMessageIndex = newDialogs.findIndex((dialog) => dialog.message === payload.message);
  if (existingMessageIndex !== -1) {
    newDialogs.splice(existingMessageIndex, 1);
  }

  newDialogs.push(payload);

  return {
    ...global,
    dialogs: newDialogs,
  };
});

addActionHandler('dismissDialog', (global) => {
  const newDialogs = [...global.dialogs];

  newDialogs.pop();

  return {
    ...global,
    dialogs: newDialogs,
  };
});

addActionHandler('selectToken', (global, actions, { slug } = {}) => {
  if (slug) {
    const isToncoin = slug === TONCOIN.slug;
    const tokens = selectSwapTokens(global);

    if (isToncoin || tokens?.some((token) => token.slug === slug)) {
      if (isToncoin) {
        actions.setDefaultSwapParams({ tokenInSlug: DEFAULT_SWAP_SECOND_TOKEN_SLUG, tokenOutSlug: slug });
      } else {
        actions.setDefaultSwapParams({ tokenOutSlug: slug });
      }
      actions.changeTransferToken({ tokenSlug: slug });
    }
  } else {
    const currentAccountId = selectCurrentAccountId(global);
    if (!currentAccountId) return;

    const currentActivityToken = global.byAccountId[currentAccountId].currentTokenSlug;

    const isDefaultFirstTokenOutSwap = global.currentSwap.tokenOutSlug === DEFAULT_SWAP_FIRST_TOKEN_SLUG
      && global.currentSwap.tokenInSlug === DEFAULT_SWAP_SECOND_TOKEN_SLUG;

    const shouldResetSwap = global.currentSwap.tokenOutSlug === currentActivityToken
      && (
        (
          global.currentSwap.tokenInSlug === DEFAULT_SWAP_FIRST_TOKEN_SLUG
          && global.currentSwap.tokenOutSlug !== DEFAULT_SWAP_SECOND_TOKEN_SLUG
        )
        || isDefaultFirstTokenOutSwap
      );

    if (shouldResetSwap) {
      actions.setDefaultSwapParams({ tokenInSlug: undefined, tokenOutSlug: undefined, withResetAmount: true });
    }

    const shouldResetTransfer = (global.currentTransfer.tokenSlug === currentActivityToken
      && global.currentTransfer.tokenSlug !== DEFAULT_TRANSFER_TOKEN_SLUG)
    && !global.currentTransfer.nfts?.length;

    if (shouldResetTransfer) {
      actions.changeTransferToken({ tokenSlug: DEFAULT_TRANSFER_TOKEN_SLUG, withResetAmount: true });
    }
  }

  return updateCurrentAccountState(global, { currentTokenSlug: slug });
});

addActionHandler('showError', (global, actions, { error } = {}) => {
  actions.showDialog({
    message: error === undefined || typeof error === 'string'
      ? errorCodeToMessage(error)
      : error,
  });
});

addActionHandler('showToast', (global, actions, payload) => {
  const { message, icon } = payload;

  const newToasts: ToastType[] = [...global.toasts];
  const existingToastIndex = newToasts.findIndex((n) => n.message === message);
  if (existingToastIndex !== -1) {
    newToasts.splice(existingToastIndex, 1);
  }

  newToasts.push({ message, icon });

  return {
    ...global,
    toasts: newToasts,
  };
});

addActionHandler('dismissToast', (global) => {
  const newToasts = [...global.toasts];

  newToasts.pop();

  return {
    ...global,
    toasts: newToasts,
  };
});

addActionHandler('toggleTonProxy', (global, actions, { isEnabled }) => {
  void callApi('doProxy', isEnabled);

  return {
    ...global,
    settings: {
      ...global.settings,
      isTonProxyEnabled: isEnabled,
    },
  };
});

addActionHandler('toggleDeeplinkHook', (global, actions, { isEnabled }) => {
  if (IS_ELECTRON) {
    void window.electron?.toggleDeeplinkHandler(isEnabled);
  } else {
    void callApi('doDeeplinkHook', isEnabled);
  }

  return {
    ...global,
    settings: {
      ...global.settings,
      isDeeplinkHookEnabled: isEnabled,
    },
  };
});

addActionHandler('signOut', async (global, actions, payload) => {
  const { level, accountId } = payload;

  const network = selectCurrentNetwork(global);
  const accounts = selectNetworkAccounts(global)!;
  const accountIds = Object.keys(accounts);
  const isFromAllAccounts = level !== 'account';

  const otherNetwork = network === 'mainnet' ? 'testnet' : 'mainnet';
  let otherNetworkAccountIds = Object.keys(selectNetworkAccountsMemoized(otherNetwork, global.accounts?.byId)!);

  if (level === 'all' && otherNetworkAccountIds.length > 0) {
    await callApi('removeNetworkAccounts', otherNetwork);
    otherNetworkAccountIds = [];
  }

  if (isFromAllAccounts || accountIds.length === 1) {
    actions.deleteAllNotificationAccounts({ accountIds });
    if (otherNetworkAccountIds.length) {
      await callApi('removeNetworkAccounts', network);

      global = getGlobal();

      const nextAccountId = otherNetworkAccountIds[0];
      const accountsById = Object.entries(global.accounts!.byId).reduce((byId, [accountId, account]) => {
        if (parseAccountId(accountId).network !== network) {
          byId[accountId] = account;
        }
        return byId;
      }, {} as Record<string, Account>);
      const byAccountId = Object.entries(global.byAccountId).reduce((byId, [accountId, state]) => {
        if (parseAccountId(accountId).network !== network) {
          byId[accountId] = state;
        }
        return byId;
      }, {} as Record<string, AccountState>);

      const settingsById = Object.entries(global.settings.byAccountId).reduce((byId, [accountId, settings]) => {
        if (parseAccountId(accountId).network !== network) {
          byId[accountId] = settings;
        }
        return byId;
      }, {} as Record<string, AccountSettings>);

      global = updateCurrentAccountId(global, nextAccountId);

      global = {
        ...global,
        accounts: {
          ...global.accounts!,
          byId: accountsById,
        },
        byAccountId,
        settings: {
          ...global.settings,
          byAccountId: settingsById,
        },
      };

      setGlobal(global);

      actions.switchAccount({ accountId: nextAccountId, newNetwork: otherNetwork });
      actions.closeSettings();
      actions.afterSignOut();
    } else {
      await callApi('resetAccounts');

      actions.afterSignOut({ shouldReset: true });
      actions.init();
    }
  } else {
    const currentAccountId = selectCurrentAccountId(global)!;
    const removingAccountId = accountId ?? currentAccountId;
    const shouldSwitchAccount = removingAccountId === currentAccountId;
    const isRemovingTemporaryAccount = removingAccountId === global.currentTemporaryViewAccountId;
    // If removing temporary account, we should switch to previous account (aka `global.currentAccountId`), not to the first of the `accountIds`.
    const nextAccountId = shouldSwitchAccount
      ? (isRemovingTemporaryAccount && global.currentAccountId
        ? global.currentAccountId
        : accountIds.find((id) => id !== removingAccountId)!)
      : undefined;
    const nextNewestActivityTimestamps = nextAccountId
      ? selectNewestActivityTimestamps(global, nextAccountId)
      : undefined;

    await callApi('removeAccount', removingAccountId, nextAccountId, nextNewestActivityTimestamps);
    actions.deleteNotificationAccount({ accountId: removingAccountId });

    global = getGlobal();

    const accountsById = omit(global.accounts!.byId, [removingAccountId]);
    const byAccountId = omit(global.byAccountId, [removingAccountId]);
    const settingsByAccountId = omit(global.settings.byAccountId, [removingAccountId]);

    if (nextAccountId !== undefined) {
      global = updateCurrentAccountId(global, nextAccountId);
    }

    global = {
      ...global,
      currentTemporaryViewAccountId: undefined,
      accounts: {
        ...global.accounts!,
        byId: accountsById,
      },
      byAccountId,
      settings: {
        ...global.settings,
        byAccountId: settingsByAccountId,
      },
    };

    setGlobal(global);

    actions.afterSignOut();
  }
});
