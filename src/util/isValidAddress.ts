import type { ApiChain } from '../api/types';

import { getChainConfig } from './chain';
import { isTonChainDns } from './dns';

export function isValidAddress(address: string, chain: ApiChain, allowPrefix?: boolean) {
  if (!address) {
    return false;
  }
  const config = getChainConfig(chain);
  return config[allowPrefix ? 'addressPrefixRegex' : 'addressRegex'].test(address);
}

export function isValidAddressOrDomain(address: string, chain: ApiChain, allowPrefix?: boolean) {
  return isValidAddress(address, chain, allowPrefix)
    || (getChainConfig(chain).isDnsSupported && isTonChainDns(address));
}

export function getChainFromAddress(
  address: string,
  availableChains: Partial<Record<ApiChain, unknown>>,
  allowDomain?: boolean,
): ApiChain | undefined {
  const availableChainsArray = Object.keys(availableChains) as (keyof typeof availableChains)[];
  return availableChainsArray.find((chain) => (
    allowDomain
      ? isValidAddressOrDomain(address, chain)
      : isValidAddress(address, chain)
  ));
}

export function isTonsiteAddress(address: string) {
  address = address.trim().toLowerCase();

  return address.startsWith('tonsite://') || address.startsWith('ton://');
}
