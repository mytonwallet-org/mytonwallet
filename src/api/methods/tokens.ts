import type { ApiChain, ApiTokenDetails, ApiTokenLink, ApiTokenPriceDetails, OnApiUpdate } from '../types';
import { ApiCommonError } from '../types';

import { TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import { SECOND } from '../../util/dateFormat';
import { logDebugError } from '../../util/logs';
import chains from '../chains';
import {
  fetchBackendTokenDetails,
  getHasFullTokenSlug,
  getTokenBySlug,
  resetLastTokens,
  sendUpdateTokens,
  tokensPreload,
  updateTokensFromBackend,
} from '../common/tokens';
import { storage } from '../storages';
import { resetLastCurrencyRates, updateCurrencyRates } from './polling';

export { buildTokenSlug } from '../common/tokens';

type BackendTokenInfo = NonNullable<ApiTokenPriceDetails['tokenInfo']>;

// The backend lists the website first, while the design opens with the social links
const LINK_ORDER: ApiTokenLink['kind'][] = ['x', 'telegram', 'website'];

export function fetchToken(accountId: string, chain: ApiChain, tokenAddress: string) {
  const { network } = parseAccountId(accountId);
  return chains[chain].fetchToken(network, tokenAddress);
}

export async function fetchTokenDetails(assets: string[]): Promise<ApiTokenPriceDetails[]> {
  const langCode = await storage.getItem('langCode');

  return fetchBackendTokenDetails(assets, langCode);
}

/**
 * A requested slug absent from `detailsBySlug` has no info. A token with a full slug never gets any, as its details
 * come back under the slug of another token.
 */
export async function fetchTokenInfo(
  slugs: string[],
): Promise<{ detailsBySlug: Record<string, ApiTokenDetails> } | { error: ApiCommonError }> {
  await tokensPreload.promise;
  const assetIds: string[] = [];
  for (const slug of slugs) {
    const token = getTokenBySlug(slug);
    if (!token || getHasFullTokenSlug(token)) continue;

    // The backend keys the assets by the token address, and the native ones by the slug, `TON` aside
    assetIds.push(token.tokenAddress ?? (slug === TONCOIN.slug ? 'TON' : slug));
  }
  if (!assetIds.length) return { detailsBySlug: {} };

  try {
    const requestedSlugs = new Set(slugs);
    const detailsBySlug: Record<string, ApiTokenDetails> = {};
    for (const { slug, tokenInfo } of await fetchTokenDetails(assetIds)) {
      if (tokenInfo && requestedSlugs.has(slug)) detailsBySlug[slug] = buildTokenDetails(tokenInfo);
    }

    return { detailsBySlug };
  } catch (err) {
    logDebugError('fetchTokenInfo', err);

    return { error: ApiCommonError.Unexpected };
  }
}

let onUpdate: OnApiUpdate | undefined;

export function initTokens(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
  resetLastTokens();
}

/** Refreshes a UI whose local token cache was cleared, without clearing SDK storage. */
export async function refreshTokens() {
  if (!onUpdate) return;
  resetLastTokens();
  resetLastCurrencyRates();
  const langCode = await storage.getItem('langCode');
  try {
    await updateTokensFromBackend(onUpdate, { langCode, shouldNarrowToHeldTokens: true }, updateCurrencyRates);
  } finally {
    // Concurrent polling may have sent a diff while the request was in flight.
    resetLastTokens();
    sendUpdateTokens(onUpdate);
  }
}

export async function importToken(accountId: string, chain: ApiChain, tokenAddress: string) {
  const { network } = parseAccountId(accountId);
  await chains[chain].importToken(network, tokenAddress, () => onUpdate && sendUpdateTokens(onUpdate));
}

function buildTokenDetails(tokenInfo: BackendTokenInfo): ApiTokenDetails {
  const {
    description, localizedDescription, marketCap, supply, createdAt, volume24h,
    links, aggregatorLinks, docsUrl, sourceCodeUrl,
  } = tokenInfo;

  return {
    description: localizedDescription ?? description,
    links: links
      ?.map(buildTokenLink)
      .sort((a, b) => LINK_ORDER.indexOf(a.kind) - LINK_ORDER.indexOf(b.kind)),
    aggregatorLinks,
    docsUrl,
    sourceCodeUrl,
    marketCap,
    circulatingSupply: supply?.circulating,
    totalSupply: supply?.total,
    createdAt: parseCreatedAt(createdAt),
    volume24h: volume24h && {
      // The backend has no total of its own, and the change is only known for some data sources
      total: volume24h.buy + volume24h.sell,
      buy: volume24h.buy,
      sell: volume24h.sell,
      change: volume24h.percentChange === undefined ? undefined : volume24h.percentChange / 100,
    },
  };
}

function parseCreatedAt(createdAt?: string) {
  if (!createdAt) return undefined;

  const timestamp = Date.parse(createdAt);

  return Number.isNaN(timestamp) ? undefined : Math.round(timestamp / SECOND);
}

function buildTokenLink({ url, type }: NonNullable<BackendTokenInfo['links']>[number]): ApiTokenLink {
  return { kind: type ?? 'website', url };
}
