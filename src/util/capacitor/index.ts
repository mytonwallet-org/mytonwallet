import type { URLOpenListenerEvent } from '@capacitor/app';
import { App } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import { SplashScreen } from '@capacitor/splash-screen';
import { BiometryType, NativeBiometric } from '@capgo/capacitor-native-biometric';
import { AirAppLauncher } from '@mytonwallet/air-app-launcher';
import type { SafeAreaInsets } from 'capacitor-plugin-safe-area';
import { SafeArea } from 'capacitor-plugin-safe-area';
import { getGlobal } from '../../global';

import type { AuthConfig } from '../authApi/types';
import type { CapacitorPlatform } from './platform';

import { GLOBAL_STATE_CACHE_KEY } from '../../config';
import { callApi } from '../../api';
import { processDeeplink } from '../deeplink';
import { logDebug } from '../logs';
import { IS_IOS } from '../windowEnvironment';
import * as storageMethods from '../windowProvider/methods';
import { initNotificationsWithGlobal } from './notifications';
import { getCapacitorPlatform, setCapacitorPlatform } from './platform';

// Full list of options can be found at https://github.com/apache/cordova-plugin-inappbrowser#cordovainappbrowseropen
export const INAPP_BROWSER_OPTIONS = [
  `location=${IS_IOS ? 'no' : 'yes'}`,
  `lefttoright=${IS_IOS ? 'no' : 'yes'}`,
  'usewkwebview=yes',
  'clearcache=no',
  'clearsessioncache=no',
  'hidden=yes',
  'toolbarposition=top',
  'hidenavigationbuttons=yes',
  'hideurlbar=no',
  'backbuttoncaption=Back',
  'allowInlineMediaPlayback=yes',
].join(',');
const IOS_SPLASH_SCREEN_HIDE_DELAY = 500;
const IOS_SPLASH_SCREEN_HIDE_DURATION = 600;
export const VIBRATE_SUCCESS_END_PAUSE_MS = 1300;

let isNativeBiometricAuthSupported = false;
let isFaceIdAvailable = false;
let isTouchIdAvailable = false;
let statusBarHeight = 0;
let safeAreaTop = 0;

let capacitorAppLaunchDeeplinkProcessedAt = 0;
const CAPACITOR_APP_URL_OPEN_EVENT_IGNORE_DELAY_MS = 500;

function updateSafeAreaValues(safeAreaInsets: SafeAreaInsets) {
  for (const [key, value] of Object.entries(safeAreaInsets.insets)) {
    document.documentElement.style.setProperty(
      `--safe-area-${key}`,
      `${getCapacitorPlatform() === 'android' && key === 'top' ? value + 8 : value}px`,
    );
  }
}

export async function initCapacitor() {
  setCapacitorPlatform(Capacitor.getPlatform() as CapacitorPlatform);

  void SafeArea.getStatusBarHeight().then(({ statusBarHeight: height }) => {
    statusBarHeight = height;
    document.documentElement.style.setProperty('--status-bar-height', `${height}px`);
  });

  void SafeArea.getSafeAreaInsets().then(({ insets: { bottom, top } }) => {
    safeAreaTop = top;
    document.documentElement.style.setProperty('--safe-area-bottom', `${bottom}px`);
  });

  if (getCapacitorPlatform() === 'ios') {
    setTimeout(() => {
      void SplashScreen.hide({ fadeOutDuration: IOS_SPLASH_SCREEN_HIDE_DURATION });
    }, IOS_SPLASH_SCREEN_HIDE_DELAY);
  }

  void App.addListener('appUrlOpen', (event: URLOpenListenerEvent) => {
    // Prevent processing the same deeplink twice on cold start
    // 1. `app.getLaunchUrl()` returns the deeplink
    // 2. And the `appUrlOpen` event contains the same deeplink
    if (Date.now() - capacitorAppLaunchDeeplinkProcessedAt > CAPACITOR_APP_URL_OPEN_EVENT_IGNORE_DELAY_MS) {
      void processDeeplink(event.url);
    } else {
      logDebug(`[CAPACITOR] appUrlOpen event ignored`, event);
    }
  });

  void App.addListener('backButton', ({ canGoBack }) => {
    if (canGoBack) {
      window.history.back();
    } else {
      void App.exitApp();
    }
  });

  updateSafeAreaValues(await SafeArea.getSafeAreaInsets());

  await SafeArea.addListener('safeAreaChanged', (data) => {
    updateSafeAreaValues(data);
  });
}

export async function processCapacitorLaunchDeeplink() {
  const launchUrl = (await App.getLaunchUrl())?.url;
  if (launchUrl) {
    void processDeeplink(launchUrl);
  }

  capacitorAppLaunchDeeplinkProcessedAt = Date.now();
}

export async function initCapacitorWithGlobal(authConfig?: AuthConfig) {
  const isNativeBiometricAuthEnabled = !!authConfig && authConfig.kind === 'native-biometrics';

  const biometricsAvailableResult = await NativeBiometric.isAvailable({
    isWeakAuthenticatorAllowed: isNativeBiometricAuthEnabled,
    useFallback: false,
  });

  isNativeBiometricAuthSupported = biometricsAvailableResult.isAvailable;
  isFaceIdAvailable = biometricsAvailableResult.biometryType === BiometryType.FACE_ID;
  isTouchIdAvailable = biometricsAvailableResult.biometryType === BiometryType.TOUCH_ID;

  void initNotificationsWithGlobal(getGlobal());
}

export function getStatusBarHeight() {
  return statusBarHeight;
}

export function getSafeAreaTop() {
  return safeAreaTop;
}

export function getIsCapacitorBiometricAuthSupported() {
  return isNativeBiometricAuthSupported;
}

export function getIsCapacitorFaceIdAvailable() {
  return isFaceIdAvailable;
}

export function getIsCapacitorTouchIdAvailable() {
  return isTouchIdAvailable;
}

export async function fixIosAppStorage() {
  await storageMethods.init();

  const isLocalStorageDataExists = Boolean(window.localStorage.getItem(GLOBAL_STATE_CACHE_KEY));
  const isApiStorageDataExists = Boolean(await storageMethods.capacitorStorageGetItem('accounts'));

  if (isLocalStorageDataExists && !isApiStorageDataExists) {
    window.localStorage.clear();
  }

  if (!isLocalStorageDataExists && isApiStorageDataExists) {
    await storageMethods.capacitorStorageClear();
  }
}

export function switchToAir() {
  void callApi('destroy');
  void AirAppLauncher.switchToAir();
}
