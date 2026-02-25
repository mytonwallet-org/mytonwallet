/*
 * This module is to be used instead of /src/util/environment.ts
 * when `window` is not available (e.g. in a web worker).
 */
import type { ApiInitArgs, ApiNetwork } from './types';

import {
  ELECTRON_TONCENTER_MAINNET_KEY,
  ELECTRON_TONCENTER_TESTNET_KEY,
  IS_CAPACITOR,
  IS_EXTENSION,
  TONCENTER_MAINNET_KEY,
  TONCENTER_TESTNET_KEY,
} from '../config';

const ELECTRON_ORIGIN = 'file://';

export type AppEnvironment = ApiInitArgs & {
  isDappSupported?: boolean;
  isSseSupported?: boolean;
  apiHeaders?: AnyLiteral;
  byNetwork: Record<ApiNetwork, { toncenterKey?: string }>;
};

let environment: AppEnvironment;

function getAppOrigin(args: ApiInitArgs): string | undefined {
  if (args.isElectron) {
    return ELECTRON_ORIGIN;
  } else if (IS_CAPACITOR || IS_EXTENSION) {
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
    isSseSupported: args.isElectron || IS_CAPACITOR,
    apiHeaders: appOrigin ? { 'X-App-Origin': appOrigin } : {},
    byNetwork: {
      mainnet: {
        toncenterKey: args.isElectron ? ELECTRON_TONCENTER_MAINNET_KEY : TONCENTER_MAINNET_KEY,
      },
      testnet: {
        toncenterKey: args.isElectron ? ELECTRON_TONCENTER_TESTNET_KEY : TONCENTER_TESTNET_KEY,
      },
    },
  };
  return environment;
}

export function getEnvironment() {
  return environment;
}
