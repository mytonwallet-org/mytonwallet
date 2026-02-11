import type { ApiBalanceBySlug, ApiBaseCurrency, ApiCurrencyRates, ApiSwapAsset } from '../../api/types';
import type { AccountSettings, GlobalState, UserSwapToken } from '../types';

import { DEFAULT_SWAP_FIRST_TOKEN_SLUG, DEFAULT_SWAP_SECOND_TOKEN_SLUG, IS_CORE_WALLET, TONCOIN } from '../../config';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { getSwapType } from '../../util/swap/getSwapType';
import withCache from '../../util/withCache';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsHardwareAccount,
} from './accounts';
import { selectAccountTokensMemoizedFor } from './tokens';

function createTokenList(
  swapTokenInfo: GlobalState['swapTokenInfo'],
  balancesBySlug: ApiBalanceBySlug,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
  sortFn: (tokenA: ApiSwapAsset, tokenB: ApiSwapAsset) => number,
  filterFn?: (token: ApiSwapAsset) => boolean,
): UserSwapToken[] {
  return Object.entries(swapTokenInfo.bySlug)
    .filter(([, token]) => !filterFn || filterFn(token))
    .map(([slug, {
      symbol, name, image,
      decimals, keywords, chain,
      tokenAddress, isPopular, color, priceUsd = 0, label,
    }]): UserSwapToken => {
      const amount = balancesBySlug[slug] ?? 0n;
      const price = calculateTokenPrice(priceUsd, baseCurrency, currencyRates);
      const totalValue = toBig(amount, decimals).mul(price).toString();

      return {
        symbol,
        slug,
        amount,
        price,
        priceUsd,
        name,
        image,
        decimals,
        isDisabled: false,
        canSwap: true,
        isPopular,
        keywords,
        totalValue,
        color,
        chain,
        tokenAddress,
        label,
      };
    })
    .sort(sortFn);
}

const selectPopularTokensMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  swapTokenInfo: GlobalState['swapTokenInfo'],
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
) => {
  const popularTokenOrder = [
    'TON',
    'USD₮',
    'USDT',
    'BTC',
    'ETH',
    'SOL',
    'TRX',
    'XLM',
    'XMR',
    'USDC',
    'LTC',
  ];
  const orderMap = new Map(popularTokenOrder.map((item, index) => [item, index]));

  const filterFn = (token: ApiSwapAsset) => token.isPopular;
  const sortFn = (tokenA: ApiSwapAsset, tokenB: ApiSwapAsset) => {
    const orderIndexA = orderMap.has(tokenA.symbol) ? orderMap.get(tokenA.symbol)! : popularTokenOrder.length;
    const orderIndexB = orderMap.has(tokenB.symbol) ? orderMap.get(tokenB.symbol)! : popularTokenOrder.length;

    return orderIndexA - orderIndexB;
  };
  return createTokenList(swapTokenInfo, balancesBySlug, baseCurrency, currencyRates, sortFn, filterFn);
}));

const selectSwapTokensMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  swapTokenInfo: GlobalState['swapTokenInfo'],
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
) => {
  const sortFn = (tokenA: ApiSwapAsset, tokenB: ApiSwapAsset) => (
    tokenA.name.trim().toLowerCase().localeCompare(tokenB.name.trim().toLowerCase())
  );
  return createTokenList(swapTokenInfo, balancesBySlug, baseCurrency, currencyRates, sortFn);
}));

const selectAccountTokensForSwapInMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  tokenInfo: GlobalState['tokenInfo'],
  swapTokenInfo: GlobalState['swapTokenInfo'],
  accountSettings: AccountSettings,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
  areTokensWithNoCostHidden = false,
) => {
  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    tokenInfo,
    accountSettings,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ).filter((token) => token.slug in swapTokenInfo.bySlug && !token.isDisabled);
}));

const selectAccountTokensForSwapOutMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  tokenInfo: GlobalState['tokenInfo'],
  swapTokenInfo: GlobalState['swapTokenInfo'],
  accountSettings: AccountSettings,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
  areTokensWithNoCostHidden = false,
) => {
  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    tokenInfo,
    accountSettings,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ).filter((token) => (
    token.slug in swapTokenInfo.bySlug
    && (!token.isDisabled || token.slug === TONCOIN.slug)
  ));
}));

export function selectAvailableUserForSwapTokens(global: GlobalState, isSwapOut = false) {
  const balancesBySlug = selectCurrentAccountState(global)?.balances?.bySlug;
  if (!balancesBySlug || !global.tokenInfo || !global.swapTokenInfo) {
    return undefined;
  }

  const accountId = selectCurrentAccountId(global)!;
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { areTokensWithNoCostHidden } = global.settings;

  const selectAccountTokens = isSwapOut
    ? selectAccountTokensForSwapOutMemoizedFor
    : selectAccountTokensForSwapInMemoizedFor;

  return selectAccountTokens(accountId)(
    balancesBySlug,
    global.tokenInfo,
    global.swapTokenInfo,
    accountSettings,
    global.settings.baseCurrency,
    global.currencyRates,
    areTokensWithNoCostHidden,
  );
}

export function selectPopularTokens(global: GlobalState) {
  const balancesBySlug = selectCurrentAccountState(global)?.balances?.bySlug;
  if (!balancesBySlug || !global.swapTokenInfo) {
    return undefined;
  }

  const accountId = selectCurrentAccountId(global)!;

  return selectPopularTokensMemoizedFor(accountId)(
    balancesBySlug,
    global.swapTokenInfo,
    global.settings.baseCurrency,
    global.currencyRates,
  );
}

export function selectSwapTokens(global: GlobalState) {
  const balancesBySlug = selectCurrentAccountState(global)?.balances?.bySlug;
  if (!balancesBySlug || !global.swapTokenInfo) {
    return undefined;
  }

  const accountId = selectCurrentAccountId(global)!;

  return selectSwapTokensMemoizedFor(accountId)(
    balancesBySlug,
    global.swapTokenInfo,
    global.settings.baseCurrency,
    global.currencyRates,
  );
}

export function selectCurrentSwapTokenIn(global: GlobalState) {
  const { tokenInSlug } = global.currentSwap;
  return tokenInSlug === undefined ? undefined : global.swapTokenInfo.bySlug[tokenInSlug];
}

export function selectCurrentSwapTokenOut(global: GlobalState) {
  const { tokenOutSlug } = global.currentSwap;
  return tokenOutSlug === undefined ? undefined : global.swapTokenInfo.bySlug[tokenOutSlug];
}

export function selectSwapType(global: GlobalState) {
  const {
    tokenInSlug = DEFAULT_SWAP_FIRST_TOKEN_SLUG,
    tokenOutSlug = DEFAULT_SWAP_SECOND_TOKEN_SLUG,
  } = global.currentSwap;
  const { byChain = {} } = selectCurrentAccount(global) ?? {};

  return getSwapType(tokenInSlug, tokenOutSlug, byChain);
}

export function selectIsSwapDisabled(global: GlobalState) {
  return IS_CORE_WALLET
    || global.restrictions.isSwapDisabled
    || global.settings.isTestnet
    || selectIsHardwareAccount(global);
}
