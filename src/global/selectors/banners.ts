import type { ApiForeignStakingPromotion, ApiInfoBannerPromotion } from '../../api/types';
import type { AccountState, GlobalState } from '../types';

import memoize from '../../util/memoize';
import { selectCurrentAccountSettings, selectCurrentAccountState, selectIsCurrentAccountViewMode } from './accounts';
import { selectIsStakingDisabled } from './staking';

const selectUnstakeableStakingBannersMemoized = memoize((
  stakingBanners: ApiForeignStakingPromotion[],
  submittedIds?: string[],
) => stakingBanners.filter(({ id }) => !submittedIds?.includes(id)));

const selectVisibleHomeBannersMemoized = memoize((
  homeBanners: ApiInfoBannerPromotion[],
  stakingBanners: ApiForeignStakingPromotion[],
  unstakeableStakingBanners: ApiForeignStakingPromotion[],
  dismissedIds?: string[],
) => {
  const banners = homeBanners.filter(({ id }) => (
    !dismissedIds?.includes(id) && !getHasNothingToUnstake(id, stakingBanners, unstakeableStakingBanners)
  ));

  return banners.length ? banners : undefined;
});

export function selectCurrentAccountHomeBanners(global: GlobalState) {
  const accountState = selectCurrentAccountState(global);
  if (!accountState?.banners || selectIsCurrentAccountViewMode(global) || selectIsStakingDisabled(global)) {
    return undefined;
  }

  return selectVisibleHomeBannersMemoized(
    accountState.banners.home,
    accountState.banners.staking,
    getUnstakeableStakingBanners(accountState),
    selectCurrentAccountSettings(global)?.dismissedHomeBannerIds,
  );
}

export function selectCurrentAccountStakingBanners(global: GlobalState) {
  const accountState = selectCurrentAccountState(global);
  if (!accountState?.banners) return undefined;

  return getUnstakeableStakingBanners(accountState);
}

function getUnstakeableStakingBanners(accountState: AccountState) {
  return selectUnstakeableStakingBannersMemoized(
    accountState.banners!.staking,
    accountState.submittedForeignStakingIds,
  );
}

// A Home banner that leads to staking banners hides once all of them are unstaked, as nothing is left to unstake
function getHasNothingToUnstake(
  id: string,
  stakingBanners: ApiForeignStakingPromotion[],
  unstakeableStakingBanners: ApiForeignStakingPromotion[],
) {
  return stakingBanners.some(({ linkedBannerId }) => linkedBannerId === id)
    && !unstakeableStakingBanners.some(({ linkedBannerId }) => linkedBannerId === id);
}
