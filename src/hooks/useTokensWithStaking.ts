import { useMemo } from '../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../api/types';
import type { UserToken } from '../global/types';

import { IS_CORE_WALLET, STAKING_SLUG_PREFIX } from '../config';
import { calculateTokenPrice } from '../util/calculatePrice';
import { toBig } from '../util/decimals';
import { buildCollectionByKey } from '../util/iteratees';
import { getFullStakingBalance, getIsActiveStakingState } from '../util/staking';
import { sortTokens } from '../util/tokens';

interface UseTokensWithStakingOptions {
  tokens?: UserToken[];
  states?: ApiStakingState[];
  baseCurrency: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  pinnedSlugs?: string[];
  alwaysHiddenSlugs?: string[];
}

export default function useTokensWithStaking({
  tokens,
  states,
  baseCurrency,
  currencyRates,
  pinnedSlugs = [],
  alwaysHiddenSlugs = [],
}: UseTokensWithStakingOptions) {
  const activeStates = useMemo(() => {
    if (IS_CORE_WALLET) return [];

    return states?.filter(getIsActiveStakingState) ?? [];
  }, [states]);

  return useMemo((): UserToken[] | undefined => {
    if (!tokens || !currencyRates) return tokens;

    const tokenBySlug = buildCollectionByKey(tokens, 'slug');
    const result: UserToken[] = [...tokens];

    activeStates.forEach((state) => {
      const token = tokenBySlug[state.tokenSlug];
      if (token) {
        const stakingSlug = `${STAKING_SLUG_PREFIX}${state.tokenSlug}`;
        const stakingAmount = getFullStakingBalance(state);

        // Calculate `totalValue` for staking clone based on staking amount and token price
        const price = calculateTokenPrice(token.priceUsd ?? 0, baseCurrency, currencyRates);
        const stakingTotalValue = toBig(stakingAmount, token.decimals)
          .mul(price)
          .toString();

        // Staking tokens have their own visibility state based on their slug
        const isStakingDisabled = alwaysHiddenSlugs.includes(stakingSlug);

        result.push({
          ...token,
          slug: stakingSlug,
          amount: stakingAmount,
          totalValue: stakingTotalValue,
          isDisabled: isStakingDisabled,
          isStaking: true,
          stakingId: state.id,
        });
      }
    });

    return sortTokens(result, pinnedSlugs);
  }, [activeStates, alwaysHiddenSlugs, baseCurrency, currencyRates, pinnedSlugs, tokens]);
}
