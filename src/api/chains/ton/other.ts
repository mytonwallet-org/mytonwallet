import { Builder, Cell } from '@ton/core';

import type { ApiNetwork } from '../../types';

import { getTonClient } from './util/tonCore';

export function packPayloadToBoc(payload: Cell | string | Uint8Array) {
  return packPayloadToBuffer(payload).toString('base64');
}

export function packPayloadToBuffer(payload: Cell | string | Uint8Array) {
  let cell = new Cell();
  if (payload) {
    if (payload instanceof Cell) {
      cell = payload;
    } else if (typeof payload === 'string') {
      if (payload.length > 0) {
        cell = new Builder()
          .storeUint(0, 32)
          .storeStringTail(payload)
          .asCell();
      }
    } else {
      cell = new Builder()
        .storeBuffer(Buffer.from(payload))
        .asCell();
    }
  }
  return cell.toBoc();
}

export async function checkApiAvailability(network: ApiNetwork) {
  try {
    await getTonClient(network).getMasterchainInfo();
    return true;
  } catch (err: any) {
    return false;
  }
}
