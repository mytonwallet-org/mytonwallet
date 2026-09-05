import type { ApiStakingState, ApiStakingType } from '../../api/types';

import {
  ETHENA_STAKING_MIN_AMOUNT,
  MIN_ACTIVE_STAKING_REWARDS,
  NEW_STAKE_DISABLED_TOKEN_SLUGS,
  NOMINATORS_STAKING_MIN_AMOUNT,
  STAKING_MIN_AMOUNT,
} from '../../config';

export function getIsNewStakeAllowed(tokenSlug?: string) {
  return !tokenSlug || !NEW_STAKE_DISABLED_TOKEN_SLUGS.has(tokenSlug);
}

export function filterStakingStatesByTonStrategy(
  states: ApiStakingState[],
  shouldUseNominators?: boolean,
) {
  const hasNominatorsStake = states.some((state) => (
    state.type === 'nominators' && getIsActiveStakingState(state)
  ));
  const hasLiquidStake = states.some((state) => (
    state.type === 'liquid' && getIsActiveStakingState(state)
  ));

  if (shouldUseNominators && !hasLiquidStake) {
    return states.filter((state) => state.type !== 'liquid');
  }
  if (!shouldUseNominators && !hasNominatorsStake) {
    return states.filter((state) => state.type !== 'nominators');
  }
  return states;
}

/**
 * Answers which position a token slug refers to. TON is the only slug two positions can share:
 * an account gets a nominators position only when the API builds one for it, so the position's own
 * presence answers whether this account stakes through nominators - a flag read separately could
 * contradict it. An active liquid stake still wins the tie, since nominators is the legacy pool.
 */
export function pickStakingStateForToken(states: ApiStakingState[], tokenSlug: string) {
  const matching = states.filter((state) => state.tokenSlug === tokenSlug);

  if (matching.length < 2) {
    return matching[0];
  }

  const liquid = matching.find((state) => state.type === 'liquid');
  if (liquid && getIsActiveStakingState(liquid)) {
    return liquid;
  }

  return matching.find((state) => state.type === 'nominators') ?? matching[0];
}

export function getStakingMinAmount(type?: ApiStakingType) {
  switch (type) {
    case 'nominators':
      return NOMINATORS_STAKING_MIN_AMOUNT;
    case 'ethena':
      return ETHENA_STAKING_MIN_AMOUNT;
    default:
      return STAKING_MIN_AMOUNT;
  }
}

export function getUnstakeTime(state?: ApiStakingState) {
  switch (state?.type) {
    case 'nominators':
    case 'liquid':
      return state.end;
    case 'ethena':
      return state.unlockTime;
    default:
      return undefined;
  }
}

export function getStakingTitle(stakingType?: ApiStakingState['type']) {
  return stakingType === 'ethena' ? 'How does it work?' : 'Why this is safe';
}

export type StakingStateStatus = 'inactive' | 'active' | 'unstakeRequested' | 'readyToClaim';

export function getStakingStateStatus(state: ApiStakingState): StakingStateStatus {
  if (state.unstakeRequestAmount) {
    if (state.type === 'ethena' && state.unlockTime && state.unlockTime <= Date.now()) {
      return 'readyToClaim';
    }

    return 'unstakeRequested';
  }
  if (getIsActiveStakingState(state)) {
    return 'active';
  }
  return 'inactive';
}

export function getIsActiveStakingState(state: ApiStakingState) {
  return Boolean(
    state.balance
    || state.unstakeRequestAmount
    || ('unclaimedRewards' in state && state.unclaimedRewards > MIN_ACTIVE_STAKING_REWARDS),
  );
}

export function getIsStakingClaimable(state: ApiStakingState) {
  if (state.type === 'jetton') {
    return state.unclaimedRewards > 0n;
  }

  return getStakingStateStatus(state) === 'readyToClaim';
}

export function getIsStakingUnstakeable(state: ApiStakingState) {
  return state.balance > 0n;
}

export function getIsLongUnstake(state: ApiStakingState, amount?: bigint): boolean | undefined {
  switch (state.type) {
    case 'nominators': {
      return true;
    }
    case 'liquid': {
      return amount === undefined ? false : amount > state.instantAvailable;
    }
    case 'jetton': {
      return false;
    }
    case 'ethena': {
      return true;
    }
  }

  return undefined;
}

export function getFullStakingBalance(state: ApiStakingState): bigint {
  switch (state.type) {
    case 'jetton': {
      return state.balance + state.unclaimedRewards;
    }
    case 'liquid': {
      // The loyalty bonus is not held in the STAKED jetton, so `balance` (jettons at the current
      // rate) can't contain it - that number is also the unstake limit, and inflating it would
      // build a burn for more jettons than the wallet holds. It is the holder's money all the same,
      // and arrives as a separate transfer on unstake, so it belongs in the full balance.
      return state.balance + (state.loyaltyBalance ?? 0n);
    }
    case 'ethena': {
      return state.balance + state.unstakeRequestAmount;
    }
  }

  return state.balance;
}
