/*
 * This module is to be used instead of /src/util/environment.ts
 * when `window` is not available (e.g. in a web worker).
 */
import type { ApiInitArgs } from './types';

import {
  ELECTRON_TONCENTER_MAINNET_KEY,
  ELECTRON_TONCENTER_TESTNET_KEY,
  IS_CAPACITOR,
  TONCENTER_MAINNET_KEY,
  TONCENTER_TESTNET_KEY,
} from '../config';

const ELECTRON_ORIGIN = 'file://';

let environment: ApiInitArgs & {
  isDappSupported?: boolean;
  isSseSupported?: boolean;
  apiHeaders?: AnyLiteral;
  toncenterMainnetKey?: string;
  toncenterTestnetKey?: string;
};

function getAppOrigin(args: ApiInitArgs): string | undefined {
  if (args.isElectron) {
    return ELECTRON_ORIGIN;
  } else if (IS_CAPACITOR) {
    return self?.origin;
  } else {
    return undefined;
  }
}

export function setEnvironment(args: ApiInitArgs) {
  const appOrigin = getAppOrigin(args);
  environment = {
    ...args,
    isDappSupported: true,
    isSseSupported: args.isElectron || (IS_CAPACITOR && !args.isNativeBottomSheet),
    apiHeaders: appOrigin ? { 'X-App-Origin': appOrigin } : {},
    toncenterMainnetKey: args.isElectron ? ELECTRON_TONCENTER_MAINNET_KEY : TONCENTER_MAINNET_KEY,
    toncenterTestnetKey: args.isElectron ? ELECTRON_TONCENTER_TESTNET_KEY : TONCENTER_TESTNET_KEY,
  };
  return environment;
}

export function getEnvironment() {
  return environment;
}
