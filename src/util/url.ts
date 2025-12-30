import type { ApiChain, ApiNft } from '../api/types';
import type { LangCode } from '../global/types';

import { EMPTY_HASH_VALUE, MTW_CARDS_BASE_URL, MYTONWALLET_BLOG, SELF_UNIVERSAL_HOST_URL } from '../config';
import { base64ToHex } from './base64toHex';
import { getChainConfig } from './chain';
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

export function getExplorerName(chain: ApiChain) {
  return getChainConfig(chain).explorer.name;
}

function getExplorerBaseUrl(chain: ApiChain, isTestnet = false) {
  return getChainConfig(chain).explorer.baseUrl[isTestnet ? 'testnet' : 'mainnet'];
}

function getTokenExplorerBaseUrl(chain: ApiChain, isTestnet = false) {
  return getChainConfig(chain).explorer.token.replace('{base}', getExplorerBaseUrl(chain, isTestnet));
}

export function getExplorerTransactionUrl(
  chain: ApiChain,
  transactionHash: string | undefined,
  isTestnet?: boolean,
) {
  if (!transactionHash || transactionHash === EMPTY_HASH_VALUE) return undefined;

  const config = getChainConfig(chain).explorer;

  return config.transaction
    .replace('{base}', getExplorerBaseUrl(chain, isTestnet))
    .replace('{hash}', config.doConvertHashFromBase64 ? base64ToHex(transactionHash) : transactionHash);
}

export function getExplorerAddressUrl(chain: ApiChain, address?: string, isTestnet?: boolean) {
  if (!address) return undefined;

  return getChainConfig(chain).explorer.address
    .replace('{base}', getExplorerBaseUrl(chain, isTestnet))
    .replace('{address}', address);
}

export function getExplorerNftCollectionUrl(nftCollectionAddress?: string, isTestnet?: boolean) {
  if (!nftCollectionAddress) return undefined;

  return `${getExplorerBaseUrl('ton', isTestnet)}nft/${nftCollectionAddress}`;
}

export function getExplorerNftUrl(nftAddress?: string, isTestnet?: boolean) {
  if (!nftAddress) return undefined;

  return `${getExplorerBaseUrl('ton', isTestnet)}nft/${nftAddress}`;
}

export function getExplorerTokenUrl(chain: ApiChain, slug?: string, address?: string, isTestnet?: boolean) {
  if (!slug && !address) return undefined;

  return address
    ? getTokenExplorerBaseUrl(chain, isTestnet).replace('{address}', address)
    : `https://coinmarketcap.com/currencies/${slug}/`;
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

export function getViewAccountUrl(addressByChain: Partial<Record<ApiChain, string>>): string {
  const params = new URLSearchParams();
  Object.entries(addressByChain).forEach(([chain, address]) => {
    params.append(chain, address);
  });

  return `${SELF_UNIVERSAL_HOST_URL}/view?${params.toString()}`;
}
