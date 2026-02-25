import type { Address } from '@solana/kit';
import { isAddress } from '@solana/kit';

import type { ApiNetwork } from '../../types';

export function normalizeAddress(network: ApiNetwork, address: string) {
  return address;
}

export function isValidAddress(address: string): address is Address {
  return isAddress(address);
}
