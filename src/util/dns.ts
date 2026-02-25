import type { ApiNft } from '../api/types';

import {
  TON_DNS_RENEWAL_WARNING_DAYS,
  TON_DNS_ZONES,
} from '../config';
import { getCountDaysToDate } from './dateFormat';

// NOTE: Use "domain" when referring to the specific domain zone (e.g. `isDotTonDomainNft`) and "DNS" otherwise.

export function isTonChainDns(value: string) {
  return getDnsDomainZone(value) !== undefined;
}

export function isTonBlockchainDnsNft(nft: ApiNft | undefined): nft is ApiNft {
  return TON_DNS_ZONES.some((zone) => zone.resolver === nft?.collectionAddress);
}

export function isLinkableDnsNft(nft: ApiNft | undefined): nft is ApiNft {
  return TON_DNS_ZONES.find((zone) => zone.resolver === nft?.collectionAddress)?.isLinkable ?? false;
}

export function getDnsDomainZone(domain: string) {
  for (const zone of TON_DNS_ZONES) {
    const { suffixes, baseFormat } = zone;

    // Iterating the zones in reverse to prioritize longer zones when multiple zones match (assuming the zones go from
    // the shortest to the longest). For example, `test.ton.vip` matches both `vip` and `ton.vip`, and `ton.vip` must be
    // used.
    for (let i = suffixes.length - 1; i >= 0; i--) {
      const suffix = suffixes[i];
      if (!domain.endsWith(`.${suffix}`)) {
        continue;
      }

      const base = domain.slice(0, -suffix.length - 1);
      if (!baseFormat.test(base)) {
        continue;
      }

      return { base, zone };
    }
  }

  return undefined;
}

export function getDnsZoneByCollection(collectionAddress: string) {
  return TON_DNS_ZONES.find((zone) => zone.resolver === collectionAddress);
}

export function isDotTonDomainNft(nft: ApiNft | undefined): nft is ApiNft {
  return TON_DNS_ZONES.find((zone) => zone.resolver === nft?.collectionAddress)?.collectionName === 'TON DNS Domains';
}

export function isRenewableDnsNft(nft: ApiNft | undefined): nft is ApiNft {
  return TON_DNS_ZONES.find((zone) => zone.resolver === nft?.collectionAddress)?.isRenewable ?? false;
}

export function getDnsExpirationDate(nft: ApiNft | undefined, dnsExpiration: Record<string, number> | undefined) {
  return isRenewableDnsNft(nft) ? dnsExpiration?.[nft.address] : undefined;
}

export function filterExpiringDomains(
  nftAddresses: string[],
  nftByAddress?: Record<string, ApiNft>,
  dnsExpiration?: Record<string, number>,
) {
  const expiringDomains: ApiNft[] = [];

  if (nftByAddress && dnsExpiration) {
    for (const address of nftAddresses) {
      const nft = nftByAddress[address];
      if (isRenewableDnsNft(nft)) {
        const daysToExpire = getCountDaysToDate(getDnsExpirationDate(nft, dnsExpiration) ?? Infinity);
        if (daysToExpire <= TON_DNS_RENEWAL_WARNING_DAYS) {
          expiringDomains.push(nft);
        }
      }
    }
  }

  return expiringDomains;
}

export function getDomainsExpirationDate(
  nfts: ApiNft[],
  nftByAddress?: Record<string, ApiNft>,
  dnsExpiration?: Record<string, number>,
) {
  if (!dnsExpiration) {
    return undefined;
  }

  return nfts.reduce<number | undefined>(
    (minDate, nftOrAddress) => {
      const nft = typeof nftOrAddress === 'string' ? nftByAddress?.[nftOrAddress] : nftOrAddress;
      const expirationDate = getDnsExpirationDate(nft, dnsExpiration);
      return expirationDate
        ? Math.min(expirationDate, minDate ?? Infinity)
        : minDate;
    },
    undefined,
  );
}
