import { getActions } from '../../../global';

import type { ApiSite } from '../../../api/types';

import { openUrl } from '../../../util/openUrl';
import { getHostnameFromUrl, isValidUrl } from '../../../util/url';

export interface SearchSuggestions {
  history?: string[];
  sites?: ApiSite[];
  isEmpty: boolean;
}

export interface ProcessedSites {
  featuredSites: ApiSite[];
  allSites: Record<number, ApiSite[]>;
}
const GOOGLE_SEARCH_URL = 'https://www.google.com/search?q=';

export function filterSites(sites?: ApiSite[], shouldRestrict?: boolean) {
  if (!sites) {
    return undefined;
  }

  return shouldRestrict
    ? sites.filter((site) => !site.canBeRestricted)
    : sites;
}

export function generateSearchSuggestions(
  searchValue: string,
  browserHistory?: string[],
  filteredSites?: ApiSite[],
) {
  const search = searchValue.toLowerCase();
  const historyResult = browserHistory?.filter((url) => url.toLowerCase().includes(search));
  const sitesResult = search.length && filteredSites
    ? filteredSites.filter(({ url, name, description }) => {
      return url.toLowerCase().includes(search)
        || name.toLowerCase().includes(search)
        || description.toLowerCase().includes(search);
    })
    : undefined;

  return {
    history: historyResult,
    sites: sitesResult,
    isEmpty: (historyResult?.length || 0) + (sitesResult?.length || 0) === 0,
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
  let url = originalUrl;
  if (!url.startsWith('http:') && !url.startsWith('https:')) {
    url = `https://${url}`;
  }
  if (!isValidUrl(url)) {
    url = `${GOOGLE_SEARCH_URL}${encodeURIComponent(originalUrl)}`;
  } else {
    getActions().addSiteToBrowserHistory({ url });
  }

  void openUrl(url, { isExternal, title, subtitle: getHostnameFromUrl(url) });
}
