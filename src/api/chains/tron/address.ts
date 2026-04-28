import type { ApiNetwork } from '../../types';

import { getTronClient } from './util/tronweb';

export function normalizeAddress(address: string, network?: ApiNetwork) {
  return address;
}

export function isValidAddress(network: ApiNetwork, address: string): boolean {
  const tronWeb = getTronClient(network);
  return tronWeb.isAddress(address);
}
