import type { ApiChain, ApiToken, ApiTokenWithPrice } from '../api/types';
import type { UserToken } from '../global/types';

import { PRICELESS_TOKEN_HASHES, PRIORITY_TOKEN_SLUGS, STAKED_TOKEN_SLUGS } from '../config';
import { findChainConfig, getChainConfig, getSupportedChains } from './chain';
import { pick } from './iteratees';

const chainByNativeSlug = Object.fromEntries(
  getSupportedChains().map((chain) => [getNativeToken(chain).slug, chain]),
);

export function getIsNativeToken(slug?: string) {
  return slug ? slug in chainByNativeSlug : false;
}

export function getNativeToken(chain: ApiChain): ApiToken {
  return getChainConfig(chain).nativeToken;
}

export function findNativeToken(chain: string | undefined): ApiToken | undefined {
  return findChainConfig(chain)?.nativeToken;
}

export function getChainBySlug(slug: string) {
  const items = slug.split('-');
  return items.length > 1 ? items[0] as ApiChain : chainByNativeSlug[slug];
}

export function getIsServiceToken(token?: ApiToken) {
  const { type, codeHash = '', slug = '' } = token ?? {};

  return type === 'lp_token'
    || STAKED_TOKEN_SLUGS.has(slug)
    || PRICELESS_TOKEN_HASHES.has(codeHash);
}

/**
 * Sorts user tokens by pinned status, priority slugs, and total value.
 * Sort order:
 * 1. Pinned tokens (by `pinnedSlugs` order)
 * 2. Priority tokens (TON, USDT, TRX, USDT TRC20) — if unpinned
 * 3. All others sorted by `totalValue` (descending), then alphabetically by `symbol`
 */
export function sortTokens(tokens: UserToken[], pinnedSlugs: string[]) {
  const pinnedIndexes = new Map(pinnedSlugs.map((slug, index) => [slug, index]));

  return tokens.slice().sort((tokenA, tokenB) => {
    const indexA = pinnedIndexes.get(tokenA.slug) ?? -1;
    const indexB = pinnedIndexes.get(tokenB.slug) ?? -1;

    // Both pinned - sort by pinnedSlugs order
    if (indexA !== -1 && indexB !== -1) return indexA - indexB;

    // One pinned - pinned goes first
    if (indexA !== -1) return -1;
    if (indexB !== -1) return 1;

    // Both unpinned - priority tokens go first
    const priorityA = PRIORITY_TOKEN_SLUGS.indexOf(tokenA.slug);
    const priorityB = PRIORITY_TOKEN_SLUGS.indexOf(tokenB.slug);

    if (priorityA !== -1 && priorityB !== -1 && tokenA.totalValue === tokenB.totalValue) {
      return priorityA - priorityB;
    }

    if (priorityA !== -1 && priorityB === -1) return -1;
    if (priorityB !== -1 && priorityA === -1) return 1;

    const valueDiff = Number(tokenB.totalValue) - Number(tokenA.totalValue);
    if (valueDiff !== 0) return valueDiff;

    // If total value is the same, sort alphabetically
    return tokenA.symbol.localeCompare(tokenB.symbol);
  });
}

export function buildUserToken(token: ApiTokenWithPrice | ApiToken): UserToken {
  return {
    ...pick(token, [
      'symbol',
      'slug',
      'name',
      'image',
      'decimals',
      'keywords',
      'chain',
      'tokenAddress',
      'type',
    ]),
    amount: 0n,
    totalValue: '0',
    price: 0,
    priceUsd: 0,
    change24h: 0,
  };
}
