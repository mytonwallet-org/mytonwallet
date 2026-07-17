import type { Platforms } from '@twa-dev/types';

import {
  IS_AIR_APP,
  IS_ANDROID_DIRECT,
  IS_EXTENSION,
  IS_FIREFOX_EXTENSION,
  IS_OPERA_EXTENSION,
  IS_PACKAGED_ELECTRON,
  IS_TELEGRAM_APP,
} from '../config';
import { getTelegramApp } from './telegram';
import { IS_ELECTRON } from './windowEnvironment';

export type BuildPlatform = Platforms
  | 'web'
  | 'extension'
  | 'firefox-extension'
  | 'opera-extension'
  | 'electron'
  | 'telegram-unknown';

export function getBuildPlatform(): BuildPlatform {
  if (IS_FIREFOX_EXTENSION) return 'firefox-extension';
  if (IS_OPERA_EXTENSION) return 'opera-extension';
  if (IS_EXTENSION) return 'extension';

  if (IS_TELEGRAM_APP) {
    return getTelegramApp()?.platform || 'telegram-unknown';
  }

  if (IS_ELECTRON) return 'electron';

  return 'web';
}

export function getFlagsValue() {
  return {
    IS_ANDROID_DIRECT,
    IS_TELEGRAM_APP,
    IS_EXTENSION,
    IS_FIREFOX_EXTENSION,
    IS_PACKAGED_ELECTRON,
    IS_AIR_APP,
    IS_ELECTRON,
    IS_OPERA_EXTENSION,
  };
}
