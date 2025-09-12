import type { ApiChain, ApiNft } from '../api/types';

import { EMPTY_HASH_VALUE, MTW_CARDS_BASE_URL } from '../config';
import { base64ToHex } from './base64toHex';
import { logDebugError } from './logs';

// Regexp from https://stackoverflow.com/a/3809435
const URL_REGEX = /[-a-z0-9@:%._+~#=]{1,256}\.[a-z0-9()]{1,6}\b([-a-z0-9()@:%_+.~#?&/=]*)/gi;
const VALID_PROTOCOLS = new Set(['http:', 'https:']);

// The configuration does not contain data for NFT addresses, they must be configured separately
const EXPLORER_CONFIGURATIONS = {
  ton: {
    name: 'Tonscan',
    base: {
      mainnet: 'https://tonscan.org/',
      testnet: 'https://testnet.tonscan.org/',
    },
    address: '{base}address/{address}',
    explorer: '{base}jetton/{address}',
    transaction: '{base}tx/{hash}',
    doConvertHashFromBase64: true,
  },
  tron: {
    name: 'Tronscan',
    base: {
      mainnet: 'https://tronscan.org/#/',
      testnet: 'https://shasta.tronscan.org/#/',
    },
    address: '{base}address/{address}',
    explorer: '{base}token20/{address}',
    transaction: '{base}transaction/{hash}',
    doConvertHashFromBase64: false,
  },
};

export function isValidUrl(url: string, validProtocols = VALID_PROTOCOLS) {
  try {
    const match = url.match(URL_REGEX);
    if (!match) return false;

    const urlObject = new URL(url);

    return validProtocols.has(urlObject.protocol);
  } catch (e) {
    logDebugError('isValidUrl', e);
    return false;
  }
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
  return EXPLORER_CONFIGURATIONS[chain].name;
}

function getExplorerBaseUrl(chain: ApiChain, isTestnet = false) {
  return EXPLORER_CONFIGURATIONS[chain].base[isTestnet ? 'testnet' : 'mainnet'];
}

function getTokenExplorerBaseUrl(chain: ApiChain, isTestnet = false) {
  return EXPLORER_CONFIGURATIONS[chain].explorer.replace('{base}', getExplorerBaseUrl(chain, isTestnet));
}

export function getExplorerTransactionUrl(
  chain: ApiChain,
  transactionHash: string | undefined,
  isTestnet?: boolean,
) {
  if (!transactionHash || transactionHash === EMPTY_HASH_VALUE) return undefined;

  const config = EXPLORER_CONFIGURATIONS[chain];

  return config.transaction
    .replace('{base}', getExplorerBaseUrl(chain, isTestnet))
    .replace('{hash}', config.doConvertHashFromBase64 ? base64ToHex(transactionHash) : transactionHash);
}

export function getExplorerAddressUrl(chain: ApiChain, address?: string, isTestnet?: boolean) {
  if (!address) return undefined;

  return EXPLORER_CONFIGURATIONS[chain].address
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

export function getCardNftImageUrl(nft: ApiNft): string | undefined {
  return `${MTW_CARDS_BASE_URL}${nft.metadata.mtwCardId}.webp`;
}
