import type { ApiChain, ApiNft } from '../api/types';
import type { LangCode } from '../global/types';

import {
  DEFAULT_CHAIN,
  EMPTY_HASH_VALUE,
  MTW_CARDS_BASE_URL,
  MTW_NEWS_CHANNEL_NAME,
  MTW_TIPS_CHANNEL_NAME,
  MYTONWALLET_BLOG,
  SELF_UNIVERSAL_HOST_URL,
} from '../config';
import { base64ToHex } from './base64toHex';
import { getAvailableExplorers, getExplorer, getMarketplace, getSupportedChains } from './chain';
import { logDebugError } from './logs';

const VALID_PROTOCOLS = new Set(['http:', 'https:']);

function isValidIp(ip: string) {
  const parts = ip.split(/[.:]/);

  if (parts.length === 4) {
    // Check IPv4 parts
    for (const part of parts) {
      const num = parseInt(part);
      if (isNaN(num) || num < 0 || num > 255) {
        return false;
      }
    }
    return true;
  } else if (parts.length === 8) {
    // Check IPv6 parts
    for (const part of parts) {
      if (!/^[0-9a-fA-F]{1,4}$/.test(part)) {
        return false;
      }
    }
    return true;
  }
  return false;
}

export function isValidUrl(url: string, validProtocols = VALID_PROTOCOLS) {
  try {
    const urlObject = new URL(url);
    const isValidProtocol = validProtocols.has(urlObject.protocol);
    const isLocalhost = urlObject.hostname === 'localhost';
    const isIp = isValidIp(urlObject.hostname);

    const parts = urlObject.hostname.split('.');
    // http://data.iana.org/TLD/tlds-alpha-by-domain.txt
    const hasValidTld = parts.length > 1 && parts[parts.length - 1].length > 1 && parts[parts.length - 1].length <= 24;

    return isValidProtocol && (isLocalhost || isIp || hasValidTld);
  } catch (e) {
    logDebugError('isValidUrl', e);
    return false;
  }
}

export function normalizeUrl(url: string): string {
  const withoutProtocol = url.replace(/^https?:\/\//, '');
  return `https://${withoutProtocol}`;
}

export function getHostnameFromUrl(url: string) {
  try {
    const urlObject = new URL(url);

    return urlObject.hostname;
  } catch (e) {
    logDebugError('getHostnameFromUrl', e);
    return url;
  }
}

export function getMarketplaceName(chain: ApiChain = DEFAULT_CHAIN, id?: string) {
  return getMarketplace(chain, id).name;
}

export function getExplorerName(chain: ApiChain = DEFAULT_CHAIN, explorerId?: string) {
  return getExplorer(chain, explorerId).name;
}

export function getExplorerBaseUrl(chain: ApiChain = DEFAULT_CHAIN, isTestnet = false, explorerId?: string) {
  return getExplorer(chain, explorerId).baseUrl[isTestnet ? 'testnet' : 'mainnet'];
}

export function getMarketplaceBaseUrl(chain: ApiChain = DEFAULT_CHAIN, isTestnet = false, id?: string) {
  return getMarketplace(chain, id).baseUrl[isTestnet ? 'testnet' : 'mainnet'];
}

function parseBaseUrl(chain: ApiChain, config: 'explorer' | 'marketplace', isTestnet = false, explorerId?: string) {
  const baseUrl = config === 'explorer'
    ? getExplorerBaseUrl(chain, isTestnet, explorerId)
    : getMarketplaceBaseUrl(chain, isTestnet, explorerId);
  const parsedBaseUrl = typeof baseUrl === 'string' ? baseUrl : baseUrl.url;
  const parsedUrlParam = typeof baseUrl === 'string' ? '' : baseUrl.param;

  return { parsedBaseUrl, parsedUrlParam };
}

function getTokenExplorerBaseUrl(chain: ApiChain, isTestnet = false, explorerId?: string) {
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'explorer', isTestnet, explorerId);

  return getExplorer(chain, explorerId).token.replace('{base}', parsedBaseUrl) + parsedUrlParam;
}

export function getExplorerTransactionUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  transactionHash: string | undefined,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!transactionHash || transactionHash === EMPTY_HASH_VALUE) return undefined;

  const explorer = getExplorer(chain, explorerId);
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'explorer', isTestnet);

  return explorer.transaction
    .replace('{base}', parsedBaseUrl)
    .replace('{hash}', explorer.doConvertHashFromBase64 ? base64ToHex(transactionHash) : transactionHash)
    + parsedUrlParam;
}

export function getExplorerAddressUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  address?: string,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!address) return undefined;

  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'explorer', isTestnet);

  return getExplorer(chain, explorerId).address
    .replace('{base}', parsedBaseUrl)
    .replace('{address}', address)
    + parsedUrlParam;
}

export function getExplorerNftCollectionUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  nftCollectionAddress?: string,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!nftCollectionAddress) return undefined;

  const explorer = getExplorer(chain, explorerId);
  if (!explorer.nftCollection) return undefined;
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'explorer', isTestnet);

  return explorer.nftCollection
    .replace('{base}', parsedBaseUrl)
    .replace('{address}', nftCollectionAddress)
    + parsedUrlParam;
}

export function getExplorerNftUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  nftAddress?: string,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!nftAddress) return undefined;

  const explorer = getExplorer(chain, explorerId);
  if (!explorer.nft) return undefined;
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'explorer', isTestnet);

  return explorer.nft
    .replace('{base}', parsedBaseUrl)
    .replace('{address}', nftAddress)
    + parsedUrlParam;
}

export function getExplorerTokenUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  slug?: string,
  address?: string,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!slug && !address) return undefined;

  return address
    ? getTokenExplorerBaseUrl(chain, isTestnet, explorerId).replace('{address}', address)
    : `https://coinmarketcap.com/currencies/${slug}/`;
}

export function getMarketplaceNftCollectionUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  nftCollectionAddress?: string,
  isTestnet?: boolean,
  marketplaceId?: string,
) {
  if (!nftCollectionAddress) return undefined;

  const marketplace = getMarketplace(chain, marketplaceId);
  if (!marketplace.nftCollection) return undefined;
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'marketplace', isTestnet);

  return marketplace.nftCollection
    .replace('{base}', parsedBaseUrl)
    .replace('{address}', nftCollectionAddress)
    + parsedUrlParam;
}

export function getMarketplaceNftUrl(
  chain: ApiChain = DEFAULT_CHAIN,
  nftAddress?: string,
  isTestnet?: boolean,
  explorerId?: string,
) {
  if (!nftAddress) return undefined;

  const marketplace = getMarketplace(chain, explorerId);
  if (!marketplace.nft) return undefined;
  const { parsedBaseUrl, parsedUrlParam } = parseBaseUrl(chain, 'marketplace', isTestnet);

  return marketplace.nft
    .replace('{base}', parsedBaseUrl)
    .replace('{address}', nftAddress)
    + parsedUrlParam;
}

export function isTelegramUrl(url: string) {
  return url.startsWith('https://t.me/');
}

export function getCardNftImageUrl(nft: ApiNft, format: 'svg' | 'webp' = 'svg'): string {
  return `${MTW_CARDS_BASE_URL}${nft.metadata.mtwCardId}.${format}`;
}

export function getBlogUrl(lang: LangCode): string {
  return MYTONWALLET_BLOG[lang] || MYTONWALLET_BLOG.en!;
}

export function getTelegramNewsChannelUrl(lang: LangCode): string {
  return `https://t.me/${MTW_NEWS_CHANNEL_NAME[lang] ?? MTW_NEWS_CHANNEL_NAME.en}`;
}

export function getTelegramTipsChannelUrl(lang: LangCode): string {
  return `https://t.me/${MTW_TIPS_CHANNEL_NAME[lang] ?? MTW_TIPS_CHANNEL_NAME.en}`;
}

export function getViewTransactionUrl(chain: ApiChain, txId: string, isTestnet?: boolean): string {
  const url = `${SELF_UNIVERSAL_HOST_URL}/tx/${chain}/${encodeURIComponent(txId)}`;

  return isTestnet ? `${url}?testnet=true` : url;
}

export function getViewAccountUrl(addressByChain: Partial<Record<ApiChain, string>>, isTestnet?: boolean): string {
  const params = new URLSearchParams();
  Object.entries(addressByChain).forEach(([chain, address]) => {
    params.append(chain, address);
  });
  if (isTestnet) {
    params.append('testnet', 'true');
  }

  return `${SELF_UNIVERSAL_HOST_URL}/view/?${params.toString()}`;
}

export function getViewNftUrl(nftAddress: string, isTestnet?: boolean): string {
  const url = `${SELF_UNIVERSAL_HOST_URL}/nft/${nftAddress}`;

  return isTestnet ? `${url}?testnet=true` : url;
}

export function getExplorerByUrl(url: string): { chain: ApiChain; explorerId: string } | undefined {
  const hostname = getHostnameFromUrl(url);

  for (const chain of getSupportedChains()) {
    const explorers = getAvailableExplorers(chain);

    for (const explorer of explorers) {
      const mainnetHost = getHostnameFromUrl(parseBaseUrl(chain, 'explorer', false, explorer.id).parsedBaseUrl);
      const testnetHost = getHostnameFromUrl(parseBaseUrl(chain, 'explorer', true, explorer.id).parsedBaseUrl);

      if (hostname === mainnetHost || hostname === testnetHost) {
        return { chain, explorerId: explorer.id };
      }
    }
  }

  return undefined;
}

/**
 * Converts an explorer URL from one explorer to another (e.g., Tonscan → Tonviewer),
 * preserving the page type (address/transaction/nft) and identifier.
 * Returns the converted URL, or `undefined` if the source URL is not a known explorer.
 */
export function convertExplorerUrl(url: string, toExplorerId: string): string | undefined {
  const explorerInfo = getExplorerByUrl(url);
  if (!explorerInfo) return undefined;

  const { chain, explorerId: fromExplorerId } = explorerInfo;

  if (fromExplorerId === toExplorerId) return url;

  const explorers = getAvailableExplorers(chain);
  const fromExplorer = explorers.find((e) => e.id === fromExplorerId);
  const toExplorer = explorers.find((e) => e.id === toExplorerId);

  if (!fromExplorer || !toExplorer) return undefined;

  // Determine network by checking which base URL the input starts with
  const isTestnet = url.startsWith(parseBaseUrl(chain, 'explorer', true, fromExplorerId).parsedBaseUrl);
  const fromBaseUrl = parseBaseUrl(chain, 'explorer', isTestnet, fromExplorerId).parsedBaseUrl;
  const toBaseUrl = parseBaseUrl(chain, 'explorer', isTestnet, toExplorer.id).parsedBaseUrl;

  // Extract path after base URL (e.g., "address/EQAbc..." or "EQAbc...?address")
  const pathAfterBase = url.slice(fromBaseUrl.length);

  // Try each pattern type, ordered from most specific to least
  const patterns: Array<{ from: string | undefined; to: string | undefined }> = [
    { from: fromExplorer.nftCollection, to: toExplorer.nftCollection },
    { from: fromExplorer.nft, to: toExplorer.nft },
    { from: fromExplorer.transaction, to: toExplorer.transaction },
    { from: fromExplorer.token, to: toExplorer.token },
    { from: fromExplorer.address, to: toExplorer.address },
  ];

  for (const { from, to } of patterns) {
    if (!from || !to) continue;

    const identifier = extractIdentifier(pathAfterBase, from);
    if (identifier) {
      return buildExplorerUrl(to, toBaseUrl, identifier);
    }
  }

  // Simple base URL replacement as fallback solution
  return toBaseUrl + pathAfterBase;
}

// Extracts the identifier ({address} or {hash}) from a path using an explorer pattern.
// Pattern example: "{base}address/{address}" or "{base}{address}?address"
function extractIdentifier(path: string, pattern: string): string | undefined {
  // Remove {base} placeholder and build regex from the remaining pattern
  const patternPath = pattern.replace('{base}', '');

  // Build regex: escape special chars, then replace placeholders with capture groups.
  // Use non-greedy match that stops at query string, hash, or end of path segment.
  const regexStr = patternPath
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&') // Escape regex special chars (including {} and ?)
    .replace(/\\\{address\\\}/g, '([^?#/]+)') // Capture address (stop at ? # or /)
    .replace(/\\\{hash\\\}/g, '([^?#/]+)'); // Capture hash

  const regex = new RegExp(`^${regexStr}`);
  const match = path.match(regex);

  return match?.[1];
}

// Builds an explorer URL from base URL, pattern, and identifier
function buildExplorerUrl(pattern: string, baseUrl: string, identifier: string): string {
  return pattern
    .replace('{base}', baseUrl)
    .replace('{address}', identifier)
    .replace('{hash}', identifier);
}
