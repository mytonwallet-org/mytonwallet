import { getActions } from '../../../global';

import type { ApiChain, ApiSite } from '../../../api/types';

import { getSupportedChains } from '../../../util/chain';
import { isValidAddressOrDomain } from '../../../util/isValidAddress';
import { openUrl } from '../../../util/openUrl';
import { getHostnameFromUrl, isValidUrl, normalizeUrl } from '../../../util/url';

export interface WalletSuggestion {
  chain: ApiChain;
  address: string;
  title?: string;
}

export interface SearchSuggestions {
  history: string[];
  sites: ApiSite[];
  wallets: WalletSuggestion[];
  isEmpty: boolean;
}

export interface ProcessedSites {
  featuredSites: ApiSite[];
  allSites: Record<number, ApiSite[]>;
}

export type SearchFactors<L extends number> = number[] & { length: L };

const GOOGLE_SEARCH_URL = 'https://www.google.com/search?q=';

function matchLength(candidate: string, searchValue: string, method: 'startsWith' | 'includes') {
  return candidate.toLowerCase()[method](searchValue.toLowerCase()) ? searchValue.length : 0;
}

function commonPrefixLength(a: ApiSite | string, searchValue: string): SearchFactors<3> {
  if (typeof a === 'string') {
    return [matchLength(a, searchValue, 'startsWith'), 0, 0];
  }
  const maxNameLength = matchLength(a.name, searchValue, 'startsWith');
  const maxDescriptionLength = matchLength(a.description, searchValue, 'startsWith');
  const maxUrlLength = matchLength(a.url, searchValue, 'startsWith');

  return [maxNameLength, maxDescriptionLength, maxUrlLength];
}

function intersectionLength(a: ApiSite | string, searchValue: string): SearchFactors<3> {
  if (typeof a === 'string') {
    return [matchLength(a, searchValue, 'includes'), 0, 0];
  }
  const maxNameLength = matchLength(a.name, searchValue, 'includes');
  const maxDescriptionLength = matchLength(a.description, searchValue, 'includes');
  const maxUrlLength = matchLength(a.url, searchValue, 'includes');

  return [maxNameLength, maxDescriptionLength, maxUrlLength];
}

function searchFactorsOf(candidate: ApiSite | string, searchValue: string): SearchFactors<6> {
  return [
    ...commonPrefixLength(candidate, searchValue),
    ...intersectionLength(candidate, searchValue),
  ] as any;
}

function comparator(factorsA: SearchFactors<6>, factorsB: SearchFactors<6>) {
  for (let i = 0; i < 6; i++) {
    if (factorsA[i] !== factorsB[i]) {
      return factorsB[i] - factorsA[i];
    }
  }

  return 0;
}

export function filterSites(sites?: ApiSite[], shouldRestrict?: boolean) {
  if (!sites) {
    return undefined;
  }

  return shouldRestrict
    ? sites.filter((site) => !site.canBeRestricted)
    : sites;
}

export function validateAddressForChains(
  address: string,
): Array<{ chain: ApiChain; isValid: boolean }> {
  const chains = getSupportedChains();

  return chains.map((chain) => ({
    chain,
    isValid: isValidAddressOrDomain(address, chain),
  }));
}

export function generateSearchSuggestions(
  searchValue: string,
  browserHistory?: string[],
  filteredSites?: ApiSite[],
): SearchSuggestions {
  const search = searchValue.toLowerCase();
  const historyResult = browserHistory?.filter((url) => url.toLowerCase().includes(search));
  const sitesResult = search.length && filteredSites
    ? filteredSites.filter(({ url, name, description }) => {
      return url.toLowerCase().includes(search)
        || name.toLowerCase().includes(search)
        || description.toLowerCase().includes(search);
    })
    : undefined;

  const factors = {
    history: historyResult?.reduce((acc, url) => {
      acc[url] = searchFactorsOf(url, searchValue);
      return acc;
    }, {} as Record<string, SearchFactors<6>>),
    sites: sitesResult?.reduce((acc, site) => {
      acc[site.url] = searchFactorsOf(site, searchValue);
      return acc;
    }, {} as Record<string, SearchFactors<6>>),
  };

  return {
    isEmpty: (historyResult?.length || 0) + (sitesResult?.length || 0) === 0,
    sites: [
      ...(sitesResult ?? []),
    ].sort((a, b) => comparator(factors.sites![a.url], factors.sites![b.url])),
    history: [
      ...(historyResult ?? []),
    ].sort((a, b) => comparator(factors.history![a], factors.history![b])),
    wallets: [],
  };
}

export function processSites(sites?: ApiSite[]): ProcessedSites {
  return (sites || []).reduce((acc, site) => {
    if (site.isFeatured) {
      acc.featuredSites.push(site);
    }

    if (!acc.allSites[site.categoryId!]) {
      acc.allSites[site.categoryId!] = [];
    }
    acc.allSites[site.categoryId!].push(site);

    return acc;
  }, { featuredSites: [], allSites: {} } as ProcessedSites);
}

export function findSiteByUrl(sites?: ApiSite[], targetUrl?: string): ApiSite | undefined {
  return sites?.find(({ url }) => url === targetUrl);
}

export function openSite(originalUrl: string, isExternal?: boolean, title?: string) {
  let url = normalizeUrl(originalUrl);
  if (!isValidUrl(url)) {
    url = `${GOOGLE_SEARCH_URL}${encodeURIComponent(originalUrl)}`;
  } else {
    getActions().addSiteToBrowserHistory({ url });
  }

  void openUrl(url, { isExternal, title, subtitle: getHostnameFromUrl(url) });
}
