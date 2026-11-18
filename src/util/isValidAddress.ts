import type { ApiChain } from '../api/types';

import { getChainConfig, getSupportedChains } from './chain';
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
  preferredChain?: ApiChain,
): ApiChain | undefined {
  const availableChainsArray = getSupportedChains().filter((chain) => chain in availableChains);

  const matchingChain = availableChainsArray.find((chain) => (
    allowDomain
      ? isValidAddressOrDomain(address, chain)
      : isValidAddress(address, chain)
  ));

  if (!matchingChain || !preferredChain || !(preferredChain in availableChains)) {
    return matchingChain;
  }

  return getPreferredChainForAddress(address, matchingChain, preferredChain);
}

export function getPreferredChainForAddress(
  address: string,
  matchingChain: ApiChain,
  preferredChain: ApiChain,
): ApiChain {
  return getAddressFormat(matchingChain) === getAddressFormat(preferredChain) && isValidAddress(address, preferredChain)
    ? preferredChain
    : matchingChain;
}

function getAddressFormat(chain: ApiChain) {
  const { addressFormat, chainStandard } = getChainConfig(chain);

  return addressFormat ?? chainStandard ?? chain;
}

export function isTonsiteAddress(address: string) {
  address = address.trim().toLowerCase();

  return address.startsWith('tonsite://') || address.startsWith('ton://');
}
