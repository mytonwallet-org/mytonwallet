import { Address } from '@ton/core';

import type { ApiNetwork } from '../api/types';

import { resolveAddressByDomain } from '../api/chains/ton/address';
import { isTonChainDns } from './dns';
import withCache from './withCache';

export { isValidAddressOrDomain } from './isValidAddress';

const resolveDomainWithCache = withCache(resolveAddressByDomain);

export async function resolveOrValidate(addressOrDomain: string, network: ApiNetwork = 'mainnet') {
  if (isTonChainDns(addressOrDomain)) {
    try {
      const resolvedAddress = await resolveDomainWithCache(network, addressOrDomain);

      if (!resolvedAddress) {
        return {
          error: `Could not resolve TON domain: ${addressOrDomain}. Please check if the domain is valid and exists.`,
        };
      }

      return { resolvedAddress };
    } catch (domainError) {
      return {
        // eslint-disable-next-line @stylistic/max-len
        error: `Failed to resolve TON domain ${addressOrDomain}: ${domainError instanceof Error ? domainError.message : 'Unknown error'}`,
      };
    }
  } else {
    try {
      Address.parse(addressOrDomain);

      return { resolvedAddress: addressOrDomain };
    } catch (addressError) {
      return {
        error: `Invalid receiver address format: ${addressOrDomain}. Please use a valid TON address or .ton domain.`,
      };
    }
  }
}
