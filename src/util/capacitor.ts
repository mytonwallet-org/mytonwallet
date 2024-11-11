import type { URLOpenListenerEvent } from '@capacitor/app';
import { App } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { BiometryType, NativeBiometric } from '@capgo/capacitor-native-biometric';
import { NavigationBar } from '@mauricewegner/capacitor-navigation-bar';
import { SplashScreen } from '@sina_kh/mtw-capacitor-splash-screen';
import { StatusBar, Style } from '@sina_kh/mtw-capacitor-status-bar';
import type { SafeAreaInsets } from 'capacitor-plugin-safe-area';
import { SafeArea } from 'capacitor-plugin-safe-area';

import type { Theme } from '../global/types';
import type { AuthConfig } from './authApi/types';

import { GLOBAL_STATE_CACHE_KEY, IS_CAPACITOR } from '../config';
import * as storageMethods from './capacitorStorageProxy/methods';
import { processDeeplink } from './deeplink';
import { pause } from './schedulers';
import {
  IS_ANDROID_APP, IS_BIOMETRIC_AUTH_SUPPORTED, IS_DELEGATED_BOTTOM_SHEET, IS_IOS,
} from './windowEnvironment';

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

let launchUrl: string | undefined;
let platform: 'ios' | 'android' | undefined;
let isNativeBiometricAuthSupported = false;
let isFaceIdAvailable = false;
let isTouchIdAvailable = false;
let statusBarHeight = 0;

function updateSafeAreaValues(safeAreaInsets: SafeAreaInsets) {
  for (const [key, value] of Object.entries(safeAreaInsets.insets)) {
    document.documentElement.style.setProperty(
      `--safe-area-${key}`,
      `${platform === 'android' && key === 'top' ? value + 8 : value}px`,
    );
  }
}

export async function initCapacitor() {
  platform = Capacitor.getPlatform() as 'ios' | 'android';

  SafeArea.getStatusBarHeight().then(({ statusBarHeight: height }) => {
    statusBarHeight = height;
    document.documentElement.style.setProperty('--status-bar-height', `${height}px`);
  });

  SafeArea.getSafeAreaInsets().then(({ insets: { bottom } }) => {
    document.documentElement.style.setProperty('--safe-area-bottom', `${bottom}px`);
  });

  if (IS_DELEGATED_BOTTOM_SHEET) {
    void SplashScreen.hide({ fadeOutDuration: 0 });
    return;
  }

  if (platform === 'ios') {
    setTimeout(() => {
      void SplashScreen.hide({ fadeOutDuration: IOS_SPLASH_SCREEN_HIDE_DURATION });
    }, IOS_SPLASH_SCREEN_HIDE_DELAY);
  }

  App.addListener('appUrlOpen', (event: URLOpenListenerEvent) => {
    processDeeplink(event.url);
  });

  App.addListener('backButton', ({ canGoBack }) => {
    if (canGoBack) {
      window.history.back();
    } else {
      App.exitApp();
    }
  });

  updateSafeAreaValues(await SafeArea.getSafeAreaInsets());

  await SafeArea.addListener('safeAreaChanged', (data) => {
    updateSafeAreaValues(data);
  });

  launchUrl = (await App.getLaunchUrl())?.url;

  if (launchUrl) {
    void processDeeplink(launchUrl);
  }
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
}

export function switchStatusBar(
  currentAppTheme: Theme, isSystemDark: boolean, forceDarkBackground?: boolean, isModalOpen?: boolean,
) {
  const style = forceDarkBackground || currentAppTheme === 'dark'
    ? Style.Dark
    : (isSystemDark && currentAppTheme === 'system' ? Style.Dark : Style.Light);

  void StatusBar.setStyle({ style, isModalOpen });
  if (IS_ANDROID_APP) {
    void NavigationBar.setColor({
      color: '#00000000',
      darkButtons: currentAppTheme === 'light' || (!isSystemDark && currentAppTheme === 'system'),
    });
  }
}

export function getLaunchUrl() {
  return launchUrl;
}

export function clearLaunchUrl() {
  launchUrl = undefined;
}

export function getStatusBarHeight() {
  return statusBarHeight;
}

export async function vibrate() {
  if (!IS_CAPACITOR) return;

  await Haptics.impact({ style: ImpactStyle.Light });
}

export async function vibrateOnError() {
  if (!IS_CAPACITOR) return;

  await Haptics.impact({ style: ImpactStyle.Medium });
  await pause(100);
  await Haptics.impact({ style: ImpactStyle.Medium });
  await pause(75);
  await Haptics.impact({ style: ImpactStyle.Light });
}

export async function vibrateOnSuccess(withPauseOnEnd = false) {
  if (!IS_CAPACITOR) return;

  await Haptics.impact({ style: ImpactStyle.Light });

  if (withPauseOnEnd) {
    await pause(VIBRATE_SUCCESS_END_PAUSE_MS);
  }
}

export function getIsNativeBiometricAuthSupported() {
  return isNativeBiometricAuthSupported;
}

export function getIsBiometricAuthSupported() {
  return IS_BIOMETRIC_AUTH_SUPPORTED || getIsNativeBiometricAuthSupported();
}

export function getIsFaceIdAvailable() {
  return isFaceIdAvailable;
}

export function getIsTouchIdAvailable() {
  return isTouchIdAvailable;
}

export async function fixIosAppStorage() {
  await storageMethods.init();

  const isLocalStorageDataExists = Boolean(window.localStorage.getItem(GLOBAL_STATE_CACHE_KEY));
  const isApiStorageDataExists = Boolean(await storageMethods.getItem('accounts'));

  if (isLocalStorageDataExists && !isApiStorageDataExists) {
    window.localStorage.clear();
  }

  if (!isLocalStorageDataExists && isApiStorageDataExists) {
    await storageMethods.clear();
  }
}
