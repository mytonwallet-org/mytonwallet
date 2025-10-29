import type { ApiBalanceBySlug, ApiBaseCurrency, ApiChain, ApiCurrencyRates } from '../../api/types';
import type { Account, AccountSettings, GlobalState, UserToken } from '../types';

import {
  DEFAULT_ENABLED_TOKEN_COUNT,
  DEFAULT_ENABLED_TOKEN_SLUGS,
  MYCOIN,
  MYCOIN_TESTNET,
  PRICELESS_TOKEN_HASHES,
  PRIORITY_TOKEN_SLUGS,
  TINY_TRANSFER_MAX_COST,
  TONCOIN,
} from '../../config';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { round } from '../../util/round';
import withCache from '../../util/withCache';
import { selectAccountSettings, selectAccountState, selectCurrentAccountState } from './accounts';

function getIsNewAccount(balancesBySlug: ApiBalanceBySlug, tokenInfo: GlobalState['tokenInfo']) {
  // Check if the number of balances equals the default token count
  if (Object.keys(balancesBySlug).length !== DEFAULT_ENABLED_TOKEN_COUNT) {
    return false;
  }

  return Object.entries(balancesBySlug).every(([slug, balance]) => {
    const info = tokenInfo.bySlug[slug];

    // If token info is missing, treat it as zero-value
    if (!info) return true;

    const balanceBig = toBig(balance, info.decimals);
    return balanceBig.mul(info.priceUsd ?? 0).lt(TINY_TRANSFER_MAX_COST);
  });
}

export const selectAccountTokensMemoizedFor = withCache((accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug,
  tokenInfo: GlobalState['tokenInfo'],
  accountSettings: AccountSettings = {},
  isSortByValueEnabled: boolean = false,
  areTokensWithNoCostHidden: boolean = false,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
) => {
  const isNewAccount = getIsNewAccount(balancesBySlug, tokenInfo);

  return Object
    .entries(balancesBySlug)
    .filter(([slug]) => (slug in tokenInfo.bySlug && !accountSettings.deletedSlugs?.includes(slug)))
    .map(([slug, balance]) => {
      const {
        symbol, name, image, decimals, cmcSlug, color, chain, tokenAddress, codeHash,
        type, percentChange24h = 0, priceUsd,
      } = tokenInfo.bySlug[slug];

      const price = calculateTokenPrice(priceUsd ?? 0, baseCurrency, currencyRates);
      const balanceBig = toBig(balance, decimals);
      const totalValue = balanceBig.mul(price).round(decimals).toString();
      const hasCost = balanceBig.mul(priceUsd ?? 0).gte(TINY_TRANSFER_MAX_COST);
      const isPricelessTokenWithBalance = PRICELESS_TOKEN_HASHES.has(codeHash!) && balance > 0n;

      const isEnabled = (
        (isNewAccount && Object.values(DEFAULT_ENABLED_TOKEN_SLUGS).some((tokenSlugs) => tokenSlugs.includes(slug)))
        || !areTokensWithNoCostHidden
        || (areTokensWithNoCostHidden && hasCost)
        || isPricelessTokenWithBalance
        || accountSettings.alwaysShownSlugs?.includes(slug)
      );

      const isDisabled = !isEnabled || accountSettings.alwaysHiddenSlugs?.includes(slug);

      return {
        chain,
        symbol,
        slug,
        amount: balance,
        name,
        image,
        price,
        priceUsd,
        decimals,
        change24h: round(percentChange24h / 100, 4),
        isDisabled,
        cmcSlug,
        totalValue,
        color,
        tokenAddress,
        codeHash,
        type,
      } satisfies UserToken as UserToken;
    })
    .sort((tokenA, tokenB) => {
      if (isSortByValueEnabled || !accountSettings.orderedSlugs) {
        const priorityA = PRIORITY_TOKEN_SLUGS.indexOf(tokenA.slug);
        const priorityB = PRIORITY_TOKEN_SLUGS.indexOf(tokenB.slug);

        // If both tokens are prioritized and their balances match
        if (priorityA !== -1 && priorityB !== -1 && tokenA.totalValue === tokenB.totalValue) {
          return priorityA - priorityB;
        }

        // If one token is prioritized and the other is not
        if (priorityA !== -1 && priorityB === -1) return -1;
        if (priorityB !== -1 && priorityA === -1) return 1;

        return Number(tokenB.totalValue) - Number(tokenA.totalValue);
      }

      const indexA = accountSettings.orderedSlugs.indexOf(tokenA.slug);
      const indexB = accountSettings.orderedSlugs.indexOf(tokenB.slug);
      return indexA - indexB;
    });
}));

export function selectCurrentAccountTokens(global: GlobalState) {
  return selectAccountTokens(global, global.currentAccountId!);
}

export function selectCurrentAccountTokenBalance(global: GlobalState, slug: string) {
  return selectCurrentAccountState(global)?.balances?.bySlug[slug] ?? 0n;
}

export function selectCurrentToncoinBalance(global: GlobalState) {
  return selectCurrentAccountTokenBalance(global, TONCOIN.slug);
}

export function selectAccountTokens(global: GlobalState, accountId: string) {
  const balancesBySlug = selectAccountState(global, accountId)?.balances?.bySlug;
  if (!balancesBySlug || !global.tokenInfo) {
    return undefined;
  }

  const accountSettings = selectAccountSettings(global, accountId);
  const { areTokensWithNoCostHidden, isSortByValueEnabled, baseCurrency } = global.settings;

  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    global.tokenInfo,
    accountSettings,
    isSortByValueEnabled,
    areTokensWithNoCostHidden,
    baseCurrency,
    global.currencyRates,
  );
}

export function selectAccountTokenBySlug(global: GlobalState, slug: string) {
  const accountTokens = selectCurrentAccountTokens(global);
  return accountTokens?.find((token) => token.slug === slug);
}

export function selectToken(global: GlobalState, slug: string) {
  return global.tokenInfo.bySlug[slug];
}

export function selectMycoin(global: GlobalState) {
  const { isTestnet } = global.settings;
  return selectToken(global, isTestnet ? MYCOIN_TESTNET.slug : MYCOIN.slug);
}

export function selectTokenByMinterAddress(global: GlobalState, minter: string) {
  return Object.values(global.tokenInfo.bySlug).find((token) => token.tokenAddress === minter);
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

export function selectMultipleAccountsTokensSlow(
  networkAccounts: Record<string, Account> | undefined,
  byAccountId: GlobalState['byAccountId'],
  tokenInfo: GlobalState['tokenInfo'],
  settingsByAccountId: Record<string, AccountSettings>,
  isSortByValueEnabled: boolean | undefined,
  areTokensWithNoCostHidden: boolean | undefined,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
) {
  const result: Record<string, UserToken[] | undefined> = {};
  if (!networkAccounts || !tokenInfo) return result;

  for (const accountId in networkAccounts) {
    const balancesBySlug = byAccountId[accountId]?.balances?.bySlug;
    if (!balancesBySlug) {
      result[accountId] = undefined;
      continue;
    }

    const accountSettings = settingsByAccountId[accountId];
    result[accountId] = selectAccountTokensMemoizedFor(accountId)(
      balancesBySlug,
      tokenInfo,
      accountSettings,
      isSortByValueEnabled,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }

  return result;
}
