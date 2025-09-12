import type { DeviceInfo, Feature } from '@tonconnect/protocol';

import type { ApiAccountWithChain } from '../api/types';

import {
  APP_NAME, IS_EXTENSION, IS_TELEGRAM_APP, TONCONNECT_PROTOCOL_VERSION,
} from '../config';
import packageJson from '../../package.json';
import { DEFAULT_MAX_MESSAGES, W5_MAX_MESSAGES } from '../api/chains/ton/constants';
import { getMaxMessagesInTransaction } from './ton/transfer';

type DevicePlatform = DeviceInfo['platform'];

/*
 This function is called in TonConnect `connect` method (where we know the wallet version)
 and in JS Bridge (where no account is selected, so we show maximum number of messages).
*/
export function tonConnectGetDeviceInfo(account?: ApiAccountWithChain<'ton'>): DeviceInfo {
  const features: Feature[] = [
    'SendTransaction', // TODO DEPRECATED
    {
      name: 'SendTransaction',
      maxMessages: account ? getTonConnectMaxMessages(account) : W5_MAX_MESSAGES,
    },
  ];

  if (!account || account.type !== 'ledger') {
    features.push({
      name: 'SignData',
      types: ['text', 'binary', 'cell'],
    });
  }

  return {
    platform: getPlatform(),
    appName: APP_NAME,
    appVersion: packageJson.version,
    maxProtocolVersion: TONCONNECT_PROTOCOL_VERSION,
    features,
  };
}

/** How many messages can be sent in a single TON Connect transaction sending */
export function getTonConnectMaxMessages(account: ApiAccountWithChain<'ton'>) {
  const { type } = account;

  if (type === 'ledger') {
    return DEFAULT_MAX_MESSAGES; // TODO Remove after DEXs support the 1 message limit
  } else {
    return getMaxMessagesInTransaction(account);
  }
}

function getPlatform(): DevicePlatform {
  const { userAgent } = navigator;
  const platform = navigator.platform || navigator?.userAgentData?.platform || '';

  const macosPlatforms = ['macOS', 'Macintosh', 'MacIntel', 'MacPPC', 'Mac68K'];
  const windowsPlatforms = ['Win32', 'Win64', 'Windows', 'WinCE'];
  const iphonePlatforms = ['iPhone'];
  const ipadPlatforms = ['iPad', 'iPod'];

  let devicePlatform: DevicePlatform | undefined;

  if (IS_EXTENSION || IS_TELEGRAM_APP) {
    devicePlatform = 'browser';
  } else if (/Android/.test(userAgent)) {
    devicePlatform = 'android';
  } else if (iphonePlatforms.indexOf(platform) !== -1) {
    devicePlatform = 'iphone';
  } else if (ipadPlatforms.indexOf(platform) !== -1) {
    devicePlatform = 'ipad';
  } else if (macosPlatforms.indexOf(platform) !== -1) {
    devicePlatform = 'mac';
  } else if (windowsPlatforms.indexOf(platform) !== -1) {
    devicePlatform = 'windows';
  } else if (/Linux/.test(platform)) {
    devicePlatform = 'linux';
  } else {
    devicePlatform = 'browser';
  }

  return devicePlatform;
}
