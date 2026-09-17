import type { ApiBalanceBySlug, ApiChain, ApiSwapAsset, ApiToken, ApiTokenWithPrice } from '../api/types';
import type { TokenWithId } from '../components/ui/TokenDropdown';
import type { AccountSettings, UserSwapToken, UserToken } from '../global/types';
import type { LangFn } from './langProvider';

import {
  PRICELESS_TOKEN_HASHES,
  PRIORITY_TOKENS,
  STAKED_TOKEN_SLUGS,
  STAKED_TON_SLUG,
  STAKING_SLUG_PREFIX,
  TINY_TRANSFER_MAX_COST,
  TON_USDE,
} from '../config';
import { parseAccountId } from './account';
import { findChainConfig, getChainConfig, getDefaultEnabledSlugs, getSupportedChains } from './chain';
import { toBig } from './decimals';
import { pick } from './iteratees';

const ETHENA_STAKING_SLUG = `${STAKING_SLUG_PREFIX}${TON_USDE.slug}`;
const RWA_STOCK_KEYWORD = 'rwa';
const XSTOCKS_NAME_REGEX = /\s+xStock$/;
const SHIFT_NAME_REGEX = /^Shift\s+/;

const chainByNativeSlug = Object.fromEntries(
  getSupportedChains().map((chain) => [getNativeToken(chain).slug, chain]),
);

/**
 * Everything `getIsTokenDisabled` needs that is the same for every token of one account: the settings, the flags
 * and the default token set. It is built once per account and passed into each call.
 */
export interface TokenVisibilityOptions {
  accountSettings: AccountSettings;
  areTokensWithNoCostHidden: boolean;
  shouldShowOnlyDefaultTokens: boolean;
  defaultEnabledSlugs: ReadonlySet<string>;
}

export function getIsNativeToken(slug?: string) {
  return slug ? slug in chainByNativeSlug : false;
}

export function getIsNativeStakedToken(slug?: string) {
  if (!slug) return false;
  if (slug === STAKED_TON_SLUG) return true;
  if (slug.startsWith(STAKING_SLUG_PREFIX)) {
    return getIsNativeToken(slug.slice(STAKING_SLUG_PREFIX.length));
  }
  return false;
}

export function getNativeToken(chain: ApiChain): ApiToken {
  return getChainConfig(chain).nativeToken;
}

export function findNativeToken(chain: string | undefined): ApiToken | undefined {
  return findChainConfig(chain)?.nativeToken;
}

export function getIsRwaStockToken(token?: ApiToken | UserToken | UserSwapToken | ApiSwapAsset | TokenWithId) {
  return token?.keywords?.includes(RWA_STOCK_KEYWORD) ?? false;
}

export function getTokenName(
  lang: LangFn, token: UserSwapToken | ApiSwapAsset | ApiToken, areTokenNamesLocalized?: boolean,
): string;
export function getTokenName(
  lang: LangFn, token?: UserSwapToken | ApiSwapAsset | ApiToken, areTokenNamesLocalized?: boolean,
): string | undefined;
export function getTokenName(
  lang: LangFn, token?: UserSwapToken | ApiSwapAsset | ApiToken, areTokenNamesLocalized?: boolean,
) {
  if (!token) return undefined;

  let tokenName = token?.name;
  if (areTokenNamesLocalized && 'localizedName' in token && Boolean(token.localizedName)) {
    tokenName = token.localizedName;
  }

  if (!('isStaking' in token) || !token.isStaking) {
    if (getIsRwaStockToken(token)) {
      return tokenName.replace(XSTOCKS_NAME_REGEX, '').replace(SHIFT_NAME_REGEX, '');
    }

    return tokenName;
  }

  switch (token.slug) {
    case ETHENA_STAKING_SLUG:
      return lang('%token% Staking', { token: 'Ethena' })[0] as string;
    default:
      return lang('%token% Staking', { token: tokenName })[0] as string;
  }
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

export function buildTokenVisibilityOptions(
  accountId: string,
  balancesBySlug: ApiBalanceBySlug,
  tokensBySlug: Record<string, ApiTokenWithPrice>,
  accountSettings: AccountSettings = {},
  areTokensWithNoCostHidden = false,
  hasActivities = false,
): TokenVisibilityOptions {
  return {
    accountSettings,
    areTokensWithNoCostHidden,
    // A wallet with no confirmed activity whose balances are all worth almost nothing shows the chain
    // default tokens instead
    shouldShowOnlyDefaultTokens: !hasActivities && getAreAllBalancesNearZero(balancesBySlug, tokensBySlug),
    defaultEnabledSlugs: getDefaultEnabledSlugs(parseAccountId(accountId).network),
  };
}

/**
 * Whether the token is hidden from the account token list.
 *
 * A token the user hid always stays hidden, and a token the user pinned as always shown is always shown.
 * Otherwise a token is shown when it carries a meaningful cost, is a priceless token with a balance
 * (see `PRICELESS_TOKEN_HASHES`), or holds any balance while zero-cost tokens are not hidden by the settings.
 * An empty wallet without activity shows the chain default tokens instead.
 */
export function getIsTokenDisabled(
  slug: string,
  balance: bigint,
  token: ApiTokenWithPrice,
  options: TokenVisibilityOptions,
) {
  const { accountSettings, areTokensWithNoCostHidden, shouldShowOnlyDefaultTokens, defaultEnabledSlugs } = options;

  if (accountSettings.alwaysHiddenSlugs?.includes(slug)) return true;
  if (accountSettings.alwaysShownSlugs?.includes(slug)) return false;
  if (shouldShowOnlyDefaultTokens) return !defaultEnabledSlugs.has(slug);

  // Ordered cheapest first: with the default settings any funded token is shown, which skips the `Big.js`
  // math in `getHasCost`
  return !(
    (!areTokensWithNoCostHidden && balance > 0n)
    || getIsPricelessWithBalance(balance, token)
    || getHasCost(balance, token)
  );
}

function getIsPricelessWithBalance(balance: bigint, { codeHash }: ApiTokenWithPrice) {
  return balance > 0n && PRICELESS_TOKEN_HASHES.has(codeHash!);
}

function getHasCost(balance: bigint, { decimals, priceUsd }: ApiTokenWithPrice) {
  return Boolean(priceUsd) && balance > 0n && toBig(balance, decimals).mul(priceUsd).gte(TINY_TRANSFER_MAX_COST);
}

function getAreAllBalancesNearZero(balancesBySlug: ApiBalanceBySlug, tokensBySlug: Record<string, ApiTokenWithPrice>) {
  return Object.entries(balancesBySlug).every(([slug, balance]) => {
    const token = tokensBySlug[slug];

    // A token without info or price is zero-value
    if (!token?.priceUsd) return true;

    return toBig(balance, token.decimals).mul(token.priceUsd).lt(TINY_TRANSFER_MAX_COST);
  });
}

/**
 * Sorts user tokens by pinned status, priority slugs, and total value.
 * Sort order:
 * 1. Pinned tokens (by `pinnedSlugs` order)
 * 2. For an empty wallet (no balances) - priority tokens (in `PRIORITY_TOKENS` order)
 * 3. All others sorted by `totalValue` (descending), then alphabetically by `symbol`
 */
export function sortTokens(tokens: UserToken[], pinnedSlugs: string[]) {
  const pinnedIndexes = new Map(pinnedSlugs.map((slug, index) => [slug, index]));
  const isEmptyWallet = tokens.every((token) => token.amount === 0n);
  const priorityTokenSlugs = isEmptyWallet ? PRIORITY_TOKENS.map((token) => token.slug) : undefined;

  return tokens.slice().sort((tokenA, tokenB) => {
    const indexA = pinnedIndexes.get(tokenA.slug) ?? -1;
    const indexB = pinnedIndexes.get(tokenB.slug) ?? -1;

    // Both pinned - sort by pinnedSlugs order
    if (indexA !== -1 && indexB !== -1) return indexA - indexB;

    // One pinned - pinned goes first
    if (indexA !== -1) return -1;
    if (indexB !== -1) return 1;

    if (priorityTokenSlugs) {
      const priorityA = priorityTokenSlugs.indexOf(tokenA.slug);
      const priorityB = priorityTokenSlugs.indexOf(tokenB.slug);

      if (priorityA !== -1 && priorityB !== -1) return priorityA - priorityB;
      if (priorityA !== -1) return -1;
      if (priorityB !== -1) return 1;
    }

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
      'localizedName',
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
