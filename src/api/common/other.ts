import type { Storage } from '../storages/types';
import type { ApiInitArgs } from '../types';
import type { ApiFetchEstimateDieselResult } from '../types';

import { IS_AIR_APP, IS_EXPLORER, IS_EXTENSION, IS_TELEGRAM_APP } from '../../config';
import { randomBytes } from '../../util/random';
import { isWebFunnelOrigin } from '../../util/webFunnel';
import { getCurrentStorage, storage } from '../storages';
import idb from '../storages/idb';
import { mutateWebFunnelStorage } from '../storages/webFunnel';
import { initializeWebClientState } from '../storages/webFunnelState';

export const DIESEL_NOT_AVAILABLE: ApiFetchEstimateDieselResult = {
  status: 'not-available',
  nativeAmount: 0n,
  remainingFee: 0n,
  realFee: 0n,
};

let clientId: string | undefined;
let referrer: string | undefined;

export async function initClientId(args?: ApiInitArgs) {
  if (args && isWebFunnelClient(args, getCurrentStorage())) {
    const candidate = Buffer.from(randomBytes(10)).toString('hex');
    const saved = await mutateWebFunnelStorage((items) => initializeWebClientState(items, candidate, {
      ...args.webFunnel!, hasExistingState: args.webFunnel!.hasExistingState || Boolean(args.accountIds?.length),
    }));
    clientId = saved.clientId;
    referrer = saved.referrer;
    return;
  }
  if (!clientId) {
    [clientId, referrer] = await Promise.all([
      storage.getItem('clientId'),
      storage.getItem('referrer'),
    ]);
  }

  if (clientId) {
    const parts = clientId.split(':', 1);
    if (referrer && referrer !== parts[1]) {
      clientId = `${parts[0]}:${referrer}`;
      void storage.setItem('clientId', clientId);
    }
  } else {
    const hex = Buffer.from(randomBytes(10)).toString('hex');
    clientId = `${hex}:${referrer ?? ''}`;
    void storage.setItem('clientId', clientId);
  }
}

export function getClientId() {
  return clientId!;
}

export function isWebFunnelClient(args: ApiInitArgs, runtimeStorage: Storage) {
  return Boolean(args.webFunnel) && !args.isElectron && !args.isIosApp && !args.isAndroidApp
    && !IS_AIR_APP && !IS_EXPLORER && !IS_EXTENSION && !IS_TELEGRAM_APP
    && isWebFunnelOrigin(self.location.origin) && runtimeStorage === idb;
}
