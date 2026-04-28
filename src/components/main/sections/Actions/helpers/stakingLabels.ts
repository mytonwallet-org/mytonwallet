import type { StakingStateStatus } from '../../../../../util/staking';

export const STAKING_TAB_TEXT_VARIANTS: Record<StakingStateStatus, string> = {
  inactive: 'Earn',
  active: 'Earning',
  unstakeRequested: '$unstaking_short',
  readyToClaim: '$unstaking_short',
};
