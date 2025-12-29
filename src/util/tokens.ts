import type { ApiChain, ApiToken, ApiTokenWithPrice } from '../api/types';
import type { UserToken } from '../global/types';

import { PRICELESS_TOKEN_HASHES, STAKED_TOKEN_SLUGS } from '../config';
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
