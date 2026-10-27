import type { ApiForeignStakingPromotion } from '../../api/types';
import type { Account, GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { updateAccountBanners } from './banners';

const ACCOUNT_ID = '0-mainnet';
const BANNER_ID = 'foreign-staking:ton:tonstakers';

describe('updateAccountBanners', () => {
  it('stops hiding the unstaked banners that the SDK no longer sends', () => {
    const global: GlobalState = {
      ...INITIAL_STATE,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } as unknown as Account } },
      byAccountId: { [ACCOUNT_ID]: { submittedForeignStakingIds: [BANNER_ID, 'foreign-staking:ton:other'] } },
    };
    const banner = { id: BANNER_ID } as ApiForeignStakingPromotion;

    const result = updateAccountBanners(global, ACCOUNT_ID, [], [banner]);

    expect(result.byAccountId[ACCOUNT_ID].banners).toEqual({ home: [], staking: [banner] });
    expect(result.byAccountId[ACCOUNT_ID].submittedForeignStakingIds).toEqual([BANNER_ID]);
  });
});
