import { getActions } from '../../../global';

export function openStaking(stakingId?: string) {
  const { changeCurrentStaking, openStakingInfoOrStart } = getActions();

  if (stakingId) changeCurrentStaking({ stakingId });

  openStakingInfoOrStart();
}
