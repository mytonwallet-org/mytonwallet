import type { ApiForeignUnstakeDraft } from '../../api/types';
import type { Account, ForeignUnstake, GlobalState } from '../types';
import { StakingState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { clearCurrentStaking, completeForeignUnstake } from './staking';

const ACCOUNT_ID = '0-mainnet';
const BANNER_ID = 'foreign-staking:ton:tonstakers';

const DRAFT: ApiForeignUnstakeDraft = {
  amountNative: 99_000_000n,
  transfers: [],
  fee: 50_000_000n,
  realFee: 7_000_000n,
  isInstant: false,
};

describe('completeForeignUnstake', () => {
  it('hides the unstaked banner and closes the staking modal', () => {
    const foreignUnstake = buildForeignUnstake(DRAFT);

    const result = completeForeignUnstake(buildGlobal(foreignUnstake), foreignUnstake);

    expect(result.byAccountId[ACCOUNT_ID].submittedForeignStakingIds).toEqual([BANNER_ID]);
    expect(result.currentStaking).toEqual({ state: StakingState.None });
  });

  it('returns to the stake form after an instant unstake', () => {
    const foreignUnstake = buildForeignUnstake({ ...DRAFT, isInstant: true });

    const result = completeForeignUnstake(buildGlobal(foreignUnstake), foreignUnstake);

    expect(result.currentStaking.state).toBe(StakingState.StakeInitial);
    expect(result.currentStaking.foreignUnstake).toBeUndefined();
  });

  it('hides the banner without reopening the staking modal the user has closed', () => {
    const foreignUnstake = buildForeignUnstake({ ...DRAFT, isInstant: true });

    const result = completeForeignUnstake(clearCurrentStaking(buildGlobal(foreignUnstake)), foreignUnstake);

    expect(result.byAccountId[ACCOUNT_ID].submittedForeignStakingIds).toEqual([BANNER_ID]);
    expect(result.currentStaking).toEqual({ state: StakingState.None });
  });
});

function buildGlobal(foreignUnstake: ForeignUnstake): GlobalState {
  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } as unknown as Account } },
    byAccountId: { [ACCOUNT_ID]: {} },
    currentStaking: { state: StakingState.ForeignUnstakePassword, foreignUnstake },
  };
}

function buildForeignUnstake(draft: ApiForeignUnstakeDraft): ForeignUnstake {
  return { accountId: ACCOUNT_ID, bannerId: BANNER_ID, chain: 'ton', providerName: 'tonstakers', draft };
}
