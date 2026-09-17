import type { ApiBalanceBySlug, ApiStakingState } from '../api/types';
import type { GlobalState, UserToken } from '../global/types';

import { STAKED_TOKEN_SLUGS } from '../config';
import { Big } from '../lib/big.js';
import { calcBigChangeValue } from './calcChangeValue';
import { toBig } from './decimals';
import { formatNumber } from './formatNumber';
import { buildArrayCollectionByKey } from './iteratees';
import { round } from './math';
import { getFullStakingBalance } from './staking';

type ChangePrefix = 'up' | 'down' | undefined;

export function calculateFullBalance(
  tokens?: UserToken[],
  stakingStates?: ApiStakingState[],
  baseCurrencyRate: string = '1',
) {
  const stakingStateBySlug = buildArrayCollectionByKey(stakingStates ?? [], 'tokenSlug');

  const primaryValueUsd = (tokens ?? []).reduce((acc, token) => {
    if (STAKED_TOKEN_SLUGS.has(token.slug)) {
      // Cost of staked tokens is already taken into account
      return acc;
    }

    const stakingStates = stakingStateBySlug[token.slug] ?? [];

    for (const stakingState of stakingStates) {
      const stakingAmount = toBig(getFullStakingBalance(stakingState), token.decimals);
      acc = acc.plus(stakingAmount.mul(token.priceUsd));
    }

    return acc.plus(toBig(token.amount, token.decimals).mul(token.priceUsd));
  }, Big(0));
  const primaryValue = primaryValueUsd.mul(baseCurrencyRate);

  const [primaryWholePart, primaryFractionPart] = formatNumber(primaryValue).split('.');
  const changeValue = (tokens ?? []).reduce((acc, token) => {
    return acc.plus(calcBigChangeValue(token.totalValue, token.change24h));
  }, Big(0)).round(4).toNumber();

  const changePercent = round(primaryValue ? (changeValue / (primaryValue.toNumber() - changeValue)) * 100 : 0, 2);
  const changePrefix: ChangePrefix = changeValue > 0 ? 'up' : changeValue < 0 ? 'down' : undefined;

  return {
    primaryValue: primaryValue.toString(),
    primaryValueUsd: primaryValueUsd.toString(),
    primaryWholePart,
    primaryFractionPart,
    changePrefix,
    changePercent,
    changeValue,
  };
}

// Gives the same `primaryValue` as `calculateFullBalance`, but straight from the raw balances. Multi-account
// lists need only the total of a wallet, and building a `UserToken` list for each of them is too expensive.
// The result must match `calculateFullBalance`: same token set, same staking handling, same
// `STAKED_TOKEN_SLUGS` exclusion.
export function calculateTotalBalanceValue(
  balancesBySlug: ApiBalanceBySlug | undefined,
  tokenInfo: GlobalState['tokenInfo'],
  deletedSlugs: string[] | undefined,
  stakingStates?: ApiStakingState[],
  baseCurrencyRate: string = '1',
) {
  const stakingStateBySlug = buildArrayCollectionByKey(stakingStates ?? [], 'tokenSlug');

  let primaryValueUsd = Big(0);

  for (const slug in balancesBySlug) {
    const info = tokenInfo.bySlug[slug];
    // Cost of staked tokens is already taken into account via the underlying token's staking state
    if (!info || STAKED_TOKEN_SLUGS.has(slug) || deletedSlugs?.includes(slug)) continue;

    const { decimals, priceUsd } = info;
    // Tokens without a price and empty balances add zero - skip the `Big.js` work
    if (!priceUsd) continue;

    for (const stakingState of stakingStateBySlug[slug] ?? []) {
      const stakingAmount = toBig(getFullStakingBalance(stakingState), decimals);
      primaryValueUsd = primaryValueUsd.plus(stakingAmount.mul(priceUsd));
    }

    if (balancesBySlug[slug] > 0n) {
      primaryValueUsd = primaryValueUsd.plus(toBig(balancesBySlug[slug], decimals).mul(priceUsd));
    }
  }

  const primaryValue = primaryValueUsd.mul(baseCurrencyRate);
  const [primaryWholePart, primaryFractionPart] = formatNumber(primaryValue).split('.');

  return {
    primaryValue: primaryValue.toString(),
    primaryWholePart,
    primaryFractionPart,
  };
}
