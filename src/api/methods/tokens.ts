import type { ApiChain, ApiTokenDetails, ApiTokenLink, ApiTokenPriceDetails, OnApiUpdate } from '../types';
import { ApiCommonError } from '../types';

import { TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import { SECOND } from '../../util/dateFormat';
import { logDebugError } from '../../util/logs';
import chains from '../chains';
import { fetchBackendTokenDetails, getTokenBySlug, sendUpdateTokens, tokensPreload } from '../common/tokens';
import { storage } from '../storages';

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

export async function fetchTokenInfo(slug: string): Promise<{ details?: ApiTokenDetails } | { error: ApiCommonError }> {
  await tokensPreload.promise;
  const token = getTokenBySlug(slug);
  if (!token) return {};

  // The backend keys the assets by the token address, and the native ones by the slug, `TON` aside
  const assetId = token.tokenAddress ?? (slug === TONCOIN.slug ? 'TON' : slug);

  try {
    const details = await fetchTokenDetails([assetId]);
    const tokenInfo = details.find((item) => item.slug === slug)?.tokenInfo;

    return { details: tokenInfo && buildTokenDetails(tokenInfo) };
  } catch (err) {
    logDebugError('fetchTokenInfo', err);

    return { error: ApiCommonError.Unexpected };
  }
}

let onUpdate: OnApiUpdate | undefined;

export function initTokens(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
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
