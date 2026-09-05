import type { ApiStakingState } from '../../api/types';
import type { Account, GlobalState } from '../types';

import { DEFAULT_NOMINATORS_STAKING_STATE, TONCOIN } from '../../config';
import { buildCollectionByKey } from '../../util/iteratees';
import memoize from '../../util/memoize';
import { pickStakingStateForToken } from '../../util/staking';
import withCache from '../../util/withCache';
import { selectAccountState } from './accounts';

const selectAccountStakingStatesMemoizedFor = withCache((accountId: string) => memoize((
  stateDefault: ApiStakingState,
  stateById?: Record<string, ApiStakingState>,
) => {
  const states = stateById ? Object.values(stateById) : undefined;
  return states?.length ? states : [stateDefault];
}));

export function selectAccountStakingStates(global: GlobalState, accountId: string) {
  const { stateById } = selectAccountState(global, accountId)?.staking ?? {};
  return selectAccountStakingStatesMemoizedFor(accountId)(global.stakingDefault, stateById);
}

const selectAccountStakingStatesByPoolMemoizedFor = withCache((accountId: string) => memoize(
  (stakingStates: ApiStakingState[]) => buildCollectionByKey(stakingStates, 'pool'),
));

/** Keyed by pool because a pool holds one position, while TON's slug is shared by liquid and nominators. */
export function selectAccountStakingStatesByPool(global: GlobalState, accountId: string) {
  return selectAccountStakingStatesByPoolMemoizedFor(accountId)(selectAccountStakingStates(global, accountId));
}

export function selectAccountStakingStateForToken(global: GlobalState, accountId: string, tokenSlug: string) {
  return pickStakingStateForToken(selectAccountStakingStates(global, accountId), tokenSlug);
}

export function selectAccountStakingState(global: GlobalState, accountId: string): ApiStakingState {
  const { stateById, stakingId, shouldUseNominators } = selectAccountState(global, accountId)?.staking ?? {};

  if (!stateById || !stakingId || !(stakingId in stateById)) {
    return shouldUseNominators ? DEFAULT_NOMINATORS_STAKING_STATE : global.stakingDefault;
  }

  return stateById[stakingId];
}

export function selectAccountStakingHistory(global: GlobalState, accountId: string) {
  const accountState = selectAccountState(global, accountId);
  const stakingState = selectAccountStakingState(global, accountId);
  return stakingState.tokenSlug === TONCOIN.slug ? accountState?.stakingHistory : undefined;
}

export function selectAccountStakingTotalProfit(global: GlobalState, accountId: string) {
  const accountState = selectAccountState(global, accountId);
  const stakingState = selectAccountStakingState(global, accountId);
  return (stakingState.tokenSlug === TONCOIN.slug ? accountState?.staking?.totalProfit : undefined) ?? 0n;
}

export function selectIsStakingDisabled(global: GlobalState) {
  return Boolean(global.settings.isTestnet);
}

export function selectMultipleAccountsStakingStatesSlow(
  networkAccounts: Record<string, Account> | undefined,
  byAccountId: GlobalState['byAccountId'],
  stakingDefault: ApiStakingState,
) {
  const result: Record<string, ApiStakingState[] | undefined> = {};
  if (networkAccounts === undefined) return result;

  for (const accountId in networkAccounts) {
    const { stateById } = byAccountId[accountId]?.staking ?? {};
    result[accountId] = selectAccountStakingStatesMemoizedFor(accountId)(stakingDefault, stateById);
  }

  return result;
}
