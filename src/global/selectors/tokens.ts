import type { ApiBalanceBySlug, ApiBaseCurrency, ApiChain, ApiCurrencyRates, ApiNetwork } from '../../api/types';
import type { Account, AccountSettings, GlobalState, UserToken } from '../types';

import {
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
  PRICELESS_TOKEN_HASHES,
  TINY_TRANSFER_MAX_COST,
  TONCOIN,
} from '../../config';
import { parseAccountId } from '../../util/account';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { getDefaultEnabledSlugs } from '../../util/chain';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { round } from '../../util/round';
import { sortTokens } from '../../util/tokens';
import withCache from '../../util/withCache';
import {
  selectAccountSettings,
  selectAccountState,
  selectCurrentAccountId,
  selectCurrentAccountState,
} from './accounts';

function getIsNewAccount(balancesBySlug: ApiBalanceBySlug, tokenInfo: GlobalState['tokenInfo'], network: ApiNetwork) {
  // Check if the number of balances equals the default token count
  if (Object.keys(balancesBySlug).length !== getDefaultEnabledSlugs(network).size) {
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
  areTokensWithNoCostHidden: boolean = false,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
) => {
  const { network } = parseAccountId(accountId);
  const isNewAccount = getIsNewAccount(balancesBySlug, tokenInfo, network);
  const pinnedSlugs = accountSettings.pinnedSlugs ?? [];

  const tokens = Object
    .entries(balancesBySlug)
    .filter(([slug]) => (slug in tokenInfo.bySlug && !accountSettings.deletedSlugs?.includes(slug)))
    .map(([slug, balance]): UserToken => {
      const {
        symbol, name, image, decimals, cmcSlug, color, chain, tokenAddress, codeHash,
        type, label, percentChange24h = 0, priceUsd,
      } = tokenInfo.bySlug[slug];

      const price = calculateTokenPrice(priceUsd ?? 0, baseCurrency, currencyRates);
      const balanceBig = toBig(balance, decimals);
      const totalValue = balanceBig.mul(price).round(decimals).toString();
      const hasCost = balanceBig.mul(priceUsd ?? 0).gte(TINY_TRANSFER_MAX_COST);
      const isPricelessTokenWithBalance = PRICELESS_TOKEN_HASHES.has(codeHash!) && balance > 0n;

      const isEnabled = (
        (isNewAccount && getDefaultEnabledSlugs(network).has(slug))
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
        label,
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
  const balancesBySlug = selectAccountState(global, accountId)?.balances?.bySlug;
  if (!balancesBySlug || !global.tokenInfo) {
    return undefined;
  }

  const accountSettings = selectAccountSettings(global, accountId);
  const { areTokensWithNoCostHidden, baseCurrency } = global.settings;

  return selectAccountTokensMemoizedFor(accountId)(
    balancesBySlug,
    global.tokenInfo,
    accountSettings,
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

export const selectUserTokenMemoized = memoize((global: GlobalState, slug: string): UserToken | undefined => {
  const apiToken = selectToken(global, slug);
  if (!apiToken) return undefined;

  const amount = selectCurrentAccountTokenBalance(global, slug);
  const price = calculateTokenPrice(apiToken.priceUsd ?? 0, global.settings.baseCurrency, global.currencyRates);

  return {
    ...apiToken,
    amount,
    price,
    change24h: round(apiToken.percentChange24h / 100, 4),
    totalValue: toBig(amount, apiToken.decimals).mul(price).toString(),
  };
});

export function selectMycoin(global: GlobalState) {
  const { isTestnet } = global.settings;
  return selectToken(global, isTestnet ? MYCOIN_TESTNET.slug : MYCOIN_MAINNET.slug);
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
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }

  return result;
}
