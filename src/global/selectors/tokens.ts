import type {
  ApiBalanceBySlug,
  ApiBaseCurrency,
  ApiChain,
  ApiCurrencyRates,
  ApiTokenWithPrice,
} from '../../api/types';
import type { AccountSettings, AccountState, GlobalState, UserToken } from '../types';

import { MYCOIN_MAINNET, MYCOIN_TESTNET, TONCOIN } from '../../config';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { round } from '../../util/round';
import { buildTokenVisibilityOptions, getIsTokenDisabled, sortTokens } from '../../util/tokens';
import withCache from '../../util/withCache';
import {
  selectAccountSettings,
  selectAccountState,
  selectCurrentAccountId,
  selectCurrentAccountState,
} from './accounts';

const EMPTY_BALANCES: ApiBalanceBySlug = {};

// The order `selectSortedTokenInfo` produced last. It depends on names and symbols alone, and every price tick
// replaces the whole `tokenInfo`, so re-sorting thousands of tokens with `localeCompare` costs far more than
// checking that none was added, removed or renamed.
let lastSortedTokenInfo: ApiTokenWithPrice[] | undefined;

export function getHasConfirmedActivities(activities: AccountState['activities']) {
  const confirmedCount = (activities?.idsMain?.length ?? 0)
    - (activities?.localActivityIds?.length ?? 0)
    - Object.values(activities?.pendingActivityIds ?? {}).reduce<number>((sum, ids) => sum + (ids?.length ?? 0), 0);
  return confirmedCount > 0;
}

// A price tick replaces the whole `tokenInfo`, even when no token of this account changed. Only the entries of the
// tokens the account holds are compared here, and when they are the same, the previous `tokenInfo` is returned.
// The account selectors then get the same argument and reuse their cached result.
export const selectAccountTokenInfoMemoizedFor = withCache((_accountId: string) => {
  let lastBalancesBySlug: ApiBalanceBySlug | undefined;
  let lastTokenInfo: GlobalState['tokenInfo'] | undefined;

  return (balancesBySlug: ApiBalanceBySlug | undefined, tokenInfo: GlobalState['tokenInfo']) => {
    if (
      lastTokenInfo
      && lastBalancesBySlug === balancesBySlug
      && getIsTokenInfoSliceSame(balancesBySlug, lastTokenInfo, tokenInfo)
    ) {
      return lastTokenInfo;
    }

    lastBalancesBySlug = balancesBySlug;
    lastTokenInfo = tokenInfo;
    return tokenInfo;
  };
});

export const selectAccountTokensMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  tokenInfo: GlobalState['tokenInfo'],
  accountSettings: AccountSettings = {},
  areTokensWithNoCostHidden: boolean = false,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
  hasActivities: boolean = false,
) => {
  const tokensBySlug = tokenInfo.bySlug;
  const visibility = buildTokenVisibilityOptions(
    accountId, balancesBySlug, tokensBySlug, accountSettings, areTokensWithNoCostHidden, hasActivities,
  );
  const pinnedSlugs = accountSettings.pinnedSlugs ?? [];

  const tokens = Object
    .entries(balancesBySlug)
    .filter(([slug]) => (slug in tokensBySlug && !accountSettings.deletedSlugs?.includes(slug)))
    .map(([slug, balance]): UserToken => {
      const token = tokensBySlug[slug];
      const {
        symbol, name, localizedName, image, decimals, cmcSlug, color, chain, tokenAddress, codeHash,
        type, label, keywords, percentChange24h = 0, priceUsd,
      } = token;

      // Most tokens carry no price, and `Big.js` on them would only yield zeros
      const price = priceUsd ? calculateTokenPrice(priceUsd, baseCurrency, currencyRates) : 0;
      const totalValue = priceUsd && balance > 0n
        ? toBig(balance, decimals).mul(price).round(decimals).toString()
        : '0';

      return {
        chain,
        symbol,
        slug,
        amount: balance,
        name,
        localizedName,
        image,
        price,
        priceUsd,
        decimals,
        change24h: round(percentChange24h / 100, 4),
        isDisabled: getIsTokenDisabled(slug, balance, token, visibility),
        cmcSlug,
        totalValue,
        color,
        tokenAddress,
        codeHash,
        type,
        label,
        keywords,
      };
    });

  return sortTokens(tokens, pinnedSlugs);
}));

export function selectCurrentAccountTokens(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountTokens(global, accountId) : undefined;
}

export function selectCurrentAccountTokenBalance(global: GlobalState, slug: string) {
  return selectCurrentAccountState(global)?.balances?.bySlug[slug] ?? 0n;
}

export function selectCurrentToncoinBalance(global: GlobalState) {
  return selectCurrentAccountTokenBalance(global, TONCOIN.slug);
}

export function selectAccountTokens(global: GlobalState, accountId: string) {
  const accountState = selectAccountState(global, accountId);
  const balancesBySlug = accountState?.balances?.bySlug;
  if (!balancesBySlug || !global.tokenInfo) {
    return undefined;
  }

  const accountSettings = selectAccountSettings(global, accountId);
  const { areTokensWithNoCostHidden, baseCurrency } = global.settings;
  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    selectAccountTokenInfoMemoizedFor(accountId)(balancesBySlug, global.tokenInfo),
    accountSettings,
    areTokensWithNoCostHidden,
    baseCurrency,
    global.currencyRates,
    getHasConfirmedActivities(accountState?.activities),
  );
}

export function selectAccountTokenBySlug(global: GlobalState, slug: string) {
  const accountTokens = selectCurrentAccountTokens(global);
  return accountTokens?.find((token) => token.slug === slug);
}

export function selectToken(global: GlobalState, slug: string) {
  return global.tokenInfo.bySlug[slug];
}

export function selectTokenDetails(global: GlobalState, slug: string) {
  return global.tokenDetails.bySlug[slug];
}

export const selectUserTokenMemoized = memoize((global: GlobalState, slug: string): UserToken | undefined => {
  const apiToken = selectToken(global, slug);
  if (!apiToken) return undefined;

  const amount = selectCurrentAccountTokenBalance(global, slug);

  return buildUserTokenFromTokenInfo(
    apiToken,
    amount,
    global.settings.baseCurrency,
    global.currencyRates,
  );
});

const selectTokenInfoUserTokensMemoized = memoize((
  tokensBySlug: GlobalState['tokenInfo']['bySlug'],
  balancesBySlug: ApiBalanceBySlug,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
): UserToken[] => {
  return selectSortedTokenInfo(tokensBySlug)
    .map((token) => buildUserTokenFromTokenInfo(
      token,
      balancesBySlug[token.slug] ?? 0n,
      baseCurrency,
      currencyRates,
    ));
});

function selectSortedTokenInfo(tokensBySlug: GlobalState['tokenInfo']['bySlug']) {
  const reused = lastSortedTokenInfo && reuseTokenInfoOrder(lastSortedTokenInfo, tokensBySlug);
  lastSortedTokenInfo = reused ?? Object.values(tokensBySlug).sort(compareTokenInfo);

  return lastSortedTokenInfo;
}

/** The previous order filled with the current token objects, or undefined once a token is added, removed or renamed */
function reuseTokenInfoOrder(sorted: ApiTokenWithPrice[], tokensBySlug: GlobalState['tokenInfo']['bySlug']) {
  if (sorted.length !== Object.keys(tokensBySlug).length) return undefined;

  const result: ApiTokenWithPrice[] = new Array(sorted.length);

  for (let i = 0; i < sorted.length; i++) {
    const previous = sorted[i];
    const current = tokensBySlug[previous.slug];
    if (!current || (current !== previous && (current.name !== previous.name || current.symbol !== previous.symbol))) {
      return undefined;
    }

    result[i] = current;
  }

  return result;
}

export function selectTokenInfoUserTokens(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || !global.tokenInfo) {
    return undefined;
  }

  return selectTokenInfoUserTokensMemoized(
    global.tokenInfo.bySlug,
    selectCurrentAccountState(global)?.balances?.bySlug ?? EMPTY_BALANCES,
    global.settings.baseCurrency,
    global.currencyRates,
  );
}

export function selectMycoin(global: GlobalState) {
  const { isTestnet } = global.settings;
  return selectToken(global, isTestnet ? MYCOIN_TESTNET.slug : MYCOIN_MAINNET.slug);
}

export function selectTokenByMinterAddress(global: GlobalState, minter: string) {
  return Object.values(global.tokenInfo.bySlug).find((token) => token.tokenAddress === minter);
}

const selectHasLocalizedTokenNamesMemoized = memoize((tokensBySlug: GlobalState['tokenInfo']['bySlug']) => {
  for (const slug in tokensBySlug) {
    if (tokensBySlug[slug].localizedName) {
      return true;
    }
  }

  return false;
});

export function selectHasLocalizedTokenNames(global: GlobalState) {
  return selectHasLocalizedTokenNamesMemoized(global.tokenInfo.bySlug);
}

export function selectChainTokenWithMaxBalanceSlow(global: GlobalState, chain: ApiChain): UserToken | undefined {
  return (selectCurrentAccountTokens(global) ?? [])
    .filter((token) => token.chain === chain)
    .reduce((maxToken, currentToken) => {
      const currentBalance = currentToken.priceUsd * Number(currentToken.amount);
      const maxBalance = maxToken ? maxToken.priceUsd * Number(maxToken.amount) : 0;

      return currentBalance > maxBalance ? currentToken : maxToken;
    });
}

function buildUserTokenFromTokenInfo(
  token: ApiTokenWithPrice,
  amount: bigint,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
): UserToken {
  const priceUsd = token.priceUsd ?? 0;
  const price = priceUsd ? calculateTokenPrice(priceUsd, baseCurrency, currencyRates) : 0;

  return {
    ...token,
    amount,
    price,
    priceUsd,
    change24h: round((token.percentChange24h ?? 0) / 100, 4),
    totalValue: amount > 0n && price ? toBig(amount, token.decimals).mul(price).toString() : '0',
  };
}

function compareTokenInfo(a: ApiTokenWithPrice, b: ApiTokenWithPrice) {
  return a.name.trim().toLowerCase().localeCompare(b.name.trim().toLowerCase())
    || a.symbol.trim().toLowerCase().localeCompare(b.symbol.trim().toLowerCase());
}

function getIsTokenInfoSliceSame(
  balancesBySlug: ApiBalanceBySlug | undefined,
  tokenInfo: GlobalState['tokenInfo'],
  otherTokenInfo: GlobalState['tokenInfo'],
) {
  if (tokenInfo === otherTokenInfo) return true;

  for (const slug in balancesBySlug) {
    if (tokenInfo.bySlug[slug] !== otherTokenInfo.bySlug[slug]) return false;
  }

  return true;
}
