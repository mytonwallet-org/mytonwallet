import type { ApiStakingState } from '../../../../../api/types';
import type { UserToken } from '../../../../../global/types';

import { STAKED_TOKEN_SLUGS } from '../../../../../config';
import { Big } from '../../../../../lib/big.js';
import { calcBigChangeValue } from '../../../../../util/calcChangeValue';
import { toBig } from '../../../../../util/decimals';
import { formatNumber } from '../../../../../util/formatNumber';
import { buildArrayCollectionByKey } from '../../../../../util/iteratees';
import { round } from '../../../../../util/math';
import { getFullStakingBalance } from '../../../../../util/staking';

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
