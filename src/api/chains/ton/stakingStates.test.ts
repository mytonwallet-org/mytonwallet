import type { ApiBackendStakingState, ApiBalanceBySlug, ApiStakingCommonData } from '../../types';

import { TON_TSUSDE, TON_USDE, TONCOIN } from '../../../config';
import { getStakingStates } from './staking';

const ACCOUNT_ID = '0-ton-mainnet';
const WALLET_ADDRESS = 'EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c';
const mockGetTimeLockData = jest.fn();

jest.mock('../../../config', () => ({
  ...jest.requireActual('../../../config'), DEBUG: false,
}));
jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(() => Promise.resolve({ address: WALLET_ADDRESS })),
}));
jest.mock('../../../util/devSettings', () => ({ getDevSettings: () => ({}) }));
jest.mock('./transfer', () => ({}));
jest.mock('./util/tonCore', () => ({
  getTonClient: () => ({ open: () => ({ getTimeLockData: mockGetTimeLockData }) }),
  resolveTokenWalletAddress: () => Promise.resolve(WALLET_ADDRESS),
}));

function commonData(): ApiStakingCommonData {
  return {
    liquid: {
      currentRate: 1, nextRoundRate: 1, apy: 5, available: 0n, tvl: 100n, totalStakers: 2,
      loyaltyApy: { black: 5, platinum: 5, gold: 5, silver: 5, standard: 5 },
    },
    round: { start: 0, end: 1, unlock: 2 },
    prevRound: { start: 0, end: 1, unlock: 2 },
    jettonPools: [],
    ethena: { apy: 4, apyVerified: 6, rate: 1.1 },
  };
}

function backendState(): ApiBackendStakingState {
  return {
    balance: 0n, totalProfit: 0n, ethena: { isBoostAvailable: true },
    nominatorsPool: { address: WALLET_ADDRESS, apy: 5, start: 0, end: 1 },
  };
}

describe('Ethena staking entry state', () => {
  beforeEach(() => {
    mockGetTimeLockData.mockReset().mockResolvedValue({ lockedUsdeBalance: 0n });
  });

  it.each<ApiBalanceBySlug>([
    { [TONCOIN.slug]: 1_000_000_000n },
    { [TONCOIN.slug]: 0n, [TON_USDE.slug]: 0n },
  ])('provides a supported empty product without requiring token ownership', async (balances) => {
    const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), balances);
    expect(states.map(({ id }) => id)).toEqual(['liquid', 'ethena']);
    expect(states[1]).toMatchObject({
      id: 'ethena', tokenSlug: TON_USDE.slug, balance: 0n, tokenBalance: 0n,
      unstakeRequestAmount: 0n, annualYield: 6,
    });
  });

  it('preserves actual staked balances and pending withdrawals', async () => {
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n, unlockTime: 100 });
    const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {
      [TON_TSUSDE.slug]: 2_000_000n,
    });
    expect(states[1]).toMatchObject({
      tokenBalance: 2_000_000n, balance: 2_200_000n,
      unstakeRequestAmount: 250_000n, unlockTime: 100_000, annualYield: 4,
    });
  });

  it('respects protocol availability for an empty account', async () => {
    const common = commonData();
    common.ethena.isDisabled = true;
    const states = await getStakingStates(ACCOUNT_ID, common, backendState(), {});
    expect(states.map(({ id }) => id)).toEqual(['liquid']);
    expect(mockGetTimeLockData).not.toHaveBeenCalled();
  });

  it('does not invent an empty position when the chain read fails', async () => {
    mockGetTimeLockData.mockRejectedValue(new Error('chain unavailable'));
    await expect(getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}))
      .rejects.toThrow('chain unavailable');
  });
});
