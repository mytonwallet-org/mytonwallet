import type { ApiStakingState } from '../../api/types';
import type { AccountState, ForeignUnstake, GlobalState } from '../types';
import { StakingState } from '../types';

import isPartialDeepEqual from '../../util/isPartialDeepEqual';
import { selectAccountState } from '../selectors';
import { updateAccountState } from './misc';

export function updateCurrentStaking(global: GlobalState, update: Partial<GlobalState['currentStaking']>): GlobalState {
  return {
    ...global,
    currentStaking: {
      ...global.currentStaking,
      ...update,
    },
  };
}

export function clearCurrentStaking(global: GlobalState) {
  return {
    ...global,
    currentStaking: {
      state: StakingState.None,
    },
  };
}

export function completeForeignUnstake(global: GlobalState, foreignUnstake: ForeignUnstake): GlobalState {
  const { accountId, bannerId, draft } = foreignUnstake;
  const { submittedForeignStakingIds = [] } = selectAccountState(global, accountId) ?? {};

  global = updateAccountState(global, accountId, {
    submittedForeignStakingIds: [...submittedForeignStakingIds, bannerId],
  });

  // The user may have closed the staking modal while the transaction was being sent
  if (global.currentStaking.foreignUnstake !== foreignUnstake) return global;

  // An instant unstake is paid out right away, so the user stays on the stake form to restake the amount
  return draft!.isInstant
    ? updateCurrentStaking(global, {
      state: StakingState.StakeInitial,
      foreignUnstake: undefined,
      mfaRequestHash: undefined,
    })
    : clearCurrentStaking(global);
}

export function updateAccountStaking(
  global: GlobalState,
  accountId: string,
  partial: Partial<NonNullable<AccountState['staking']>>,
  withDeepCompare = false,
): GlobalState {
  const currentStaking = selectAccountState(global, accountId)?.staking;

  if (withDeepCompare && currentStaking && isPartialDeepEqual(currentStaking, partial)) {
    return global;
  }

  return updateAccountState(global, accountId, {
    staking: {
      ...currentStaking,
      ...partial,
    },
  });
}

export function updateAccountStakingStatePartial(
  global: GlobalState,
  accountId: string,
  partial: Partial<AccountState['staking']>,
): GlobalState {
  const currentState = selectAccountState(global, accountId)?.staking;

  if (!currentState) {
    return global;
  }

  return updateAccountState(global, accountId, {
    staking: {
      ...currentState,
      ...partial,
    },
  });
}

export function updateStakingDefault(global: GlobalState, state: ApiStakingState) {
  return {
    ...global,
    stakingDefault: state,
  };
}
