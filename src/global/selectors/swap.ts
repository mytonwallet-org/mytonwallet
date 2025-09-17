import type { ApiBalanceBySlug, ApiBaseCurrency, ApiCurrencyRates, ApiSwapAsset } from '../../api/types';
import type { AccountSettings, GlobalState, UserSwapToken } from '../types';
import { SwapType } from '../types';

import { DEFAULT_SWAP_FIRST_TOKEN_SLUG, DEFAULT_SWAP_SECOND_TOKEN_SLUG, IS_CORE_WALLET } from '../../config';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { getChainBySlug } from '../../util/tokens';
import withCache from '../../util/withCache';
import {
  selectCurrentAccount,
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
      tokenAddress, isPopular, color, priceUsd = 0,
    }]) => {
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
      } satisfies UserSwapToken;
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
    'jUSDT',
    'jWBTC',
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

const selectAccountTokensForSwapMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  tokenInfo: GlobalState['tokenInfo'],
  swapTokenInfo: GlobalState['swapTokenInfo'],
  accountSettings: AccountSettings,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
  isSortByValueEnabled = false,
  areTokensWithNoCostHidden = false,
) => {
  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    tokenInfo,
    accountSettings,
    isSortByValueEnabled,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ).filter((token) => token.slug in swapTokenInfo.bySlug && !token.isDisabled);
}));

export function selectAvailableUserForSwapTokens(global: GlobalState) {
  const balancesBySlug = selectCurrentAccountState(global)?.balances?.bySlug;
  if (!balancesBySlug || !global.tokenInfo || !global.swapTokenInfo) {
    return undefined;
  }

  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { areTokensWithNoCostHidden, isSortByValueEnabled } = global.settings;

  return selectAccountTokensForSwapMemoizedFor(global.currentAccountId!)(
    balancesBySlug,
    global.tokenInfo,
    global.swapTokenInfo,
    accountSettings,
    global.settings.baseCurrency,
    global.currencyRates,
    isSortByValueEnabled,
    areTokensWithNoCostHidden,
  );
}

export function selectPopularTokens(global: GlobalState) {
  const balancesBySlug = selectCurrentAccountState(global)?.balances?.bySlug;
  if (!balancesBySlug || !global.swapTokenInfo) {
    return undefined;
  }

  return selectPopularTokensMemoizedFor(global.currentAccountId!)(
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

  return selectSwapTokensMemoizedFor(global.currentAccountId!)(
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
  const tokenInChain = getChainBySlug(tokenInSlug);
  const tokenOutChain = getChainBySlug(tokenOutSlug);

  if (tokenInChain === 'ton' && tokenOutChain === 'ton') {
    return SwapType.OnChain;
  }

  const byChain = selectCurrentAccount(global)?.byChain ?? {};

  if (tokenInChain in byChain) {
    return SwapType.CrosschainFromWallet;
  }

  return SwapType.CrosschainToWallet;
}

export function selectIsSwapDisabled(global: GlobalState) {
  return IS_CORE_WALLET
    || global.restrictions.isSwapDisabled
    || global.settings.isTestnet
    || selectIsHardwareAccount(global);
}
