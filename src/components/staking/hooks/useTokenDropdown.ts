import { useMemo } from '../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState, ApiTokenWithPrice } from '../../../api/types';
import type { AmountInputToken } from '../../ui/AmountInput';

import { calculateTokenPrice } from '../../../util/calculatePrice';
import { getIsActiveStakingState, getIsNewStakeAllowed } from '../../../util/staking';

interface Options {
  tokenBySlug?: Record<string, ApiTokenWithPrice>;
  states?: ApiStakingState[];
  shouldUseNominators?: boolean;
  selectedStakingId?: string;
  isViewMode?: boolean;
  // Keeps active positions of tokens closed for new stakes selectable (e.g. to navigate to them), even when not
  // selected. Only for the info view; the new-stake form must omit it so closed tokens can't start a new stake.
  shouldKeepActiveBlockedStates?: boolean;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
}

export function useTokenDropdown({
  tokenBySlug, states, shouldUseNominators, selectedStakingId, isViewMode, shouldKeepActiveBlockedStates,
  baseCurrency, currencyRates,
}: Options) {
  const selectableTokens = useMemo<AmountInputToken[]>(() => {
    if (!tokenBySlug || !states) {
      return [];
    }

    let stakingTokens = getStakingTokens(
      tokenBySlug, states, shouldUseNominators, selectedStakingId, shouldKeepActiveBlockedStates,
    );

    if (isViewMode) {
      stakingTokens = stakingTokens.filter(({ id }) => id === selectedStakingId);
    }

    const result = stakingTokens.map((token) => ({
      ...token,
      price: calculateTokenPrice(token.priceUsd, baseCurrency, currencyRates),
    }));

    return result;
  }, [
    tokenBySlug, states, shouldUseNominators, isViewMode, selectedStakingId, shouldKeepActiveBlockedStates,
    baseCurrency, currencyRates,
  ]);

  const selectedToken = useMemo(
    () => selectableTokens.find((token) => token.id === selectedStakingId),
    [selectableTokens, selectedStakingId],
  );

  return [selectedToken, selectableTokens] as const;
}

export function getStakingTokens(
  tokenBySlug: Record<string, ApiTokenWithPrice>,
  states: ApiStakingState[],
  shouldUseNominators?: boolean,
  selectedStakingId?: string,
  shouldKeepActiveBlockedStates?: boolean,
) {
  const hasNominatorsStake = states.some((state) => state.type === 'nominators' && getIsActiveStakingState(state));
  const hasLiquidStake = states.some((state) => state.type === 'liquid' && getIsActiveStakingState(state));

  if (shouldUseNominators && !hasLiquidStake) {
    states = states.filter((state) => state.type !== 'liquid');
  }

  if (!shouldUseNominators && !hasNominatorsStake) {
    states = states.filter((state) => state.type !== 'nominators');
  }

  return states
    .filter((state) => tokenBySlug[state.tokenSlug]
      && (getIsNewStakeAllowed(state.tokenSlug)
        || state.id === selectedStakingId
        || (shouldKeepActiveBlockedStates && getIsActiveStakingState(state))))
    .map<ApiTokenWithPrice & { id: string }>((state) => ({
      ...tokenBySlug[state.tokenSlug],
      id: state.id,
    }));
}
