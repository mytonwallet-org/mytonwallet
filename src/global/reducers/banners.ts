import type { ApiForeignStakingPromotion, ApiInfoBannerPromotion } from '../../api/types';
import type { GlobalState } from '../types';

import { selectAccountState } from '../selectors';
import { updateAccountState } from './misc';

export function updateAccountBanners(
  global: GlobalState,
  accountId: string,
  home: ApiInfoBannerPromotion[],
  staking: ApiForeignStakingPromotion[],
) {
  const { submittedForeignStakingIds } = selectAccountState(global, accountId) ?? {};

  return updateAccountState(global, accountId, {
    banners: { home, staking },
    submittedForeignStakingIds: submittedForeignStakingIds?.filter((id) => staking.some((banner) => banner.id === id)),
  });
}
