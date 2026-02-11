import type { ApiFetchEstimateDieselResult } from '../types';

import { randomBytes } from '../../util/random';
import { storage } from '../storages';

export const DIESEL_NOT_AVAILABLE: ApiFetchEstimateDieselResult = {
  status: 'not-available',
  nativeAmount: 0n,
  remainingFee: 0n,
  realFee: 0n,
};

let clientId: string | undefined;
let referrer: string | undefined;

export async function initClientId() {
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
