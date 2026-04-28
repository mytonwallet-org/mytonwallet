import { getAddress, isAddress } from 'ethers';

import type { ApiNetwork } from '../../types';

export function normalizeAddress(address: string, network?: ApiNetwork) {
  if (!isAddress(address)) {
    return address;
  }
  return getAddress(address);
}

export function isValidAddress(address: string): boolean {
  return isAddress(address);
}
