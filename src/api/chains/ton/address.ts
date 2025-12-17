import { Address } from '@ton/core';

import type { ApiNetwork } from '../../types';
import { ApiCommonError } from '../../types';

import { getDnsDomainZone, isTonChainDns } from '../../../util/dns';
import { dnsResolve } from './util/dns';
import { getTonClient, toBase64Address } from './util/tonCore';
import { getKnownAddressInfo } from '../../common/addresses';
import { DnsCategory } from './constants';
import { fetchAddressBook } from './toncenter';

export async function resolveAddress(network: ApiNetwork, address: string, skipFormatSelection?: boolean): Promise<{
  address: string;
  name?: string;
  isMemoRequired?: boolean;
  isScam?: boolean;
} | { error: ApiCommonError }> {
  const isDomain = isTonChainDns(address);
  let domain: string | undefined;

  if (isDomain) {
    const resolvedAddress = await resolveAddressByDomain(network, address);
    if (!resolvedAddress) {
      return { error: ApiCommonError.DomainNotResolved };
    }

    domain = address;
    address = resolvedAddress;

    if (!skipFormatSelection) {
      const addressBook = await fetchAddressBook(network, [address]);
      address = addressBook[address].user_friendly;
    }
  }

  let normalizedAddress: string;
  try {
    normalizedAddress = normalizeAddress(network, address);
  } catch {
    return { error: ApiCommonError.InvalidAddress };
  }
  const known = getKnownAddressInfo(normalizedAddress);

  if (known) {
    return {
      address,
      ...known,
      name: domain ?? known.name,
    };
  }

  return { address, name: domain };
}

export async function resolveAddressByDomain(network: ApiNetwork, domain: string) {
  try {
    const zoneMatch = getDnsDomainZone(domain);
    if (!zoneMatch) {
      return undefined;
    }

    const result = await dnsResolve(
      getTonClient(network),
      zoneMatch.zone.resolver,
      zoneMatch.base,
      DnsCategory.Wallet,
    );

    if (!(result instanceof Address)) {
      return undefined;
    }

    return toBase64Address(result, undefined, network);
  } catch (err: any) {
    if (!err.message?.includes('exit_code')) {
      throw err;
    }
    return undefined;
  }
}

export function normalizeAddress(network: ApiNetwork, address: string) {
  return toBase64Address(address, true, network);
}
