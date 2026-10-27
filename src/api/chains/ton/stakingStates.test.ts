import type { ApiBackendStakingState, ApiBalanceBySlug, ApiStakingCommonData } from '../../types';

import { TON_TSUSDE, TON_USDE, TONCOIN } from '../../../config';
import { setStakingCommonCache, updateAccountCache } from '../../common/cache';
import { setupStakingPolling } from './polling';
import * as staking from './staking';

const { getStakingStates } = staking;

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
    jest.useFakeTimers();
    updateAccountCache(ACCOUNT_ID, WALLET_ADDRESS, { ethenaDepletedAt: undefined, ethenaTokenBalance: undefined });
    mockGetTimeLockData.mockReset().mockResolvedValue({ lockedUsdeBalance: 0n });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it.each<ApiBalanceBySlug>([
    { [TONCOIN.slug]: 1_000_000_000n },
    { [TONCOIN.slug]: 0n, [TON_USDE.slug]: 0n },
    { [TON_TSUSDE.slug]: 0n },
  ])('provides a supported empty product without requiring token ownership', async (balances) => {
    const previousStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), balances);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(1);
    mockGetTimeLockData.mockClear();

    const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), balances, previousStates);
    expect(states.map(({ id }) => id)).toEqual(['liquid', 'ethena']);
    expect(states[1]).toMatchObject({
      id: 'ethena', tokenSlug: TON_USDE.slug, balance: 0n, tokenBalance: 0n,
      unstakeRequestAmount: 0n, annualYield: 6,
    });
    expect(mockGetTimeLockData).not.toHaveBeenCalled();
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
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(1);
  });

  it.each([
    { lockedUsdeBalance: 250_000n, unlockTime: 100_000, shouldRead: true },
    { lockedUsdeBalance: 0n, unlockTime: Date.now() + 60_000, shouldRead: true },
    { lockedUsdeBalance: 0n, unlockTime: 100_000, shouldRead: false },
  ])('checks known pending withdrawals without tsUSDe: %s', async ({
    lockedUsdeBalance, unlockTime, shouldRead,
  }) => {
    const previousStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
    const previousState = previousStates.find((state) => state.type === 'ethena')!;
    previousState.unstakeRequestAmount = lockedUsdeBalance;
    previousState.unlockTime = unlockTime;
    mockGetTimeLockData.mockClear();
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 500_000n, unlockTime: 200 });

    const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, previousStates);

    expect(mockGetTimeLockData).toHaveBeenCalledTimes(shouldRead ? 1 : 0);
    expect(states.find((state) => state.type === 'ethena')).toMatchObject({
      tokenBalance: 0n,
      unstakeRequestAmount: shouldRead ? 500_000n : 0n,
      unlockTime: shouldRead ? 200_000 : undefined,
    });
  });

  it('discovers and follows a locked-only withdrawal after all tsUSDe is unstaked', async () => {
    const stakedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {
      [TON_TSUSDE.slug]: 2_000_000n,
    });
    expect(stakedStates[1]).toMatchObject({ tokenBalance: 2_000_000n, unstakeRequestAmount: 0n });
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n, unlockTime: 100 });

    const lockedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, stakedStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(2);
    expect(lockedStates[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 250_000n, unlockTime: 100_000 });

    const pendingStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, lockedStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
    expect(pendingStates[1]).toEqual(lockedStates[1]);

    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 0n });
    const clearedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, pendingStates);
    jest.setSystemTime(Date.now() + 600_000);
    await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, clearedStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(4);
    expect(clearedStates[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 0n, unlockTime: undefined });
  });

  it('accepts empty snapshots and discovers a delayed lock within the depletion window', async () => {
    jest.setSystemTime(0);
    let states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), { [TON_TSUSDE.slug]: 1n });

    for (let attempt = 0; attempt < 5; attempt++) {
      jest.setSystemTime(attempt * 60_000);
      states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
      expect(states[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 0n, unlockTime: undefined });
    }

    jest.setSystemTime(300_000);
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n, unlockTime: 100 });
    const lockedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(7);
    expect(lockedStates[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 250_000n, unlockTime: 100_000 });
  });

  it('updates other products after a full transfer and stops lock reads after ten minutes', async () => {
    jest.setSystemTime(0);
    let states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), { [TON_TSUSDE.slug]: 1n });
    const backend = backendState();
    backend.liquid = { unstakeRequestAmount: '1' };

    states = await getStakingStates(ACCOUNT_ID, commonData(), backend, {}, states);
    expect(states[0]).toMatchObject({ unstakeRequestAmount: 1_000_000_000n });
    expect(states[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 0n, unlockTime: undefined });

    jest.setSystemTime(599_999);
    states = await getStakingStates(ACCOUNT_ID, commonData(), backend, {}, states);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);

    jest.setSystemTime(600_000);
    backend.liquid = { unstakeRequestAmount: '0' };
    states = await getStakingStates(ACCOUNT_ID, commonData(), backend, {}, states);
    jest.setSystemTime(1_200_000);
    states = await getStakingStates(ACCOUNT_ID, commonData(), backend, {}, states);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
    expect(states[1]).toMatchObject({ balance: 0n, tokenBalance: 0n, unstakeRequestAmount: 0n });
    expect(states.every(({ balance }) => balance === 0n)).toBe(true);
  });

  it('does not extend the depletion window when reads fail and retain a positive snapshot', async () => {
    jest.setSystemTime(0);
    let states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), { [TON_TSUSDE.slug]: 1n });
    mockGetTimeLockData.mockRejectedValue(new Error('chain unavailable'));

    states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
    expect(states[1]).toMatchObject({ tokenBalance: 1n });
    jest.setSystemTime(599_999);
    states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
    expect(states[1]).toMatchObject({ tokenBalance: 1n });
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);

    jest.setSystemTime(600_000);
    states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
    expect(states[1]).toMatchObject({ balance: 0n, tokenBalance: 0n, unstakeRequestAmount: 0n });
  });

  it('discovers a locked-only balance when the SDK restarts without previous states', async () => {
    const emptyStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n, unlockTime: 100 });
    await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, emptyStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(1);

    const restartedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(2);
    expect(restartedStates[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 250_000n, unlockTime: 100_000 });

    await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, restartedStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
  });

  it('keeps reading a returned future unlock time with zero locked balance until it expires', async () => {
    const now = Date.now();
    const unlockTime = Math.floor(now / 1000) + 60;
    const mockNow = jest.spyOn(Date, 'now').mockReturnValue(now);
    try {
      mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 0n, unlockTime });
      const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
      expect(states[1]).toMatchObject({ unstakeRequestAmount: 0n, unlockTime: unlockTime * 1000 });
      const pendingStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
      expect(mockGetTimeLockData).toHaveBeenCalledTimes(2);

      mockNow.mockReturnValue(unlockTime * 1000 + 1);
      const expiredStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, pendingStates);
      expect(mockGetTimeLockData).toHaveBeenCalledTimes(2);
      expect(expiredStates[1]).toMatchObject({ unstakeRequestAmount: 0n, unlockTime: undefined });
    } finally {
      mockNow.mockRestore();
    }
  });

  it('skips an update after initial Ethena failure, retries, and falls back only to known Ethena state', async () => {
    setStakingCommonCache('ton', commonData());
    const backend = backendState();
    const backendSpy = jest.spyOn(staking, 'getBackendStakingState').mockResolvedValue(backend);
    const onUpdate = jest.fn();
    mockGetTimeLockData.mockRejectedValueOnce(new Error('chain unavailable'));
    const stop = setupStakingPolling(ACCOUNT_ID, {
      getBalances: () => Promise.resolve({}),
      onUpdate: () => () => {},
    }, onUpdate);
    try {
      await jest.advanceTimersByTimeAsync(0);
      expect(mockGetTimeLockData).toHaveBeenCalledTimes(1);
      expect(onUpdate).not.toHaveBeenCalled();

      mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n });
      await jest.advanceTimersByTimeAsync(30_000);
      expect(mockGetTimeLockData).toHaveBeenCalledTimes(2);
      expect(onUpdate).toHaveBeenCalledTimes(1);
      expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
        type: 'updateStaking',
        states: [expect.objectContaining({ type: 'liquid' }), expect.objectContaining({
          type: 'ethena', tokenBalance: 0n, unstakeRequestAmount: 250_000n,
        })],
      }));

      const previousEthena = onUpdate.mock.calls[0][0].states[1];
      backend.liquid = { unstakeRequestAmount: '1' };
      mockGetTimeLockData.mockRejectedValueOnce(new Error('chain unavailable'));
      await jest.advanceTimersByTimeAsync(30_000);
      expect(onUpdate).toHaveBeenCalledTimes(2);
      expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
        type: 'updateStaking',
        states: [expect.objectContaining({ unstakeRequestAmount: 1_000_000_000n }), previousEthena],
      }));
    } finally {
      stop();
      backendSpy.mockRestore();
      jest.clearAllTimers();
    }
  });

  it('tracks depletion when the first positive balance was observed during a read error', async () => {
    jest.setSystemTime(0);
    mockGetTimeLockData.mockRejectedValueOnce(new Error('chain unavailable'));
    await expect(getStakingStates(ACCOUNT_ID, commonData(), backendState(), { [TON_TSUSDE.slug]: 1n }))
      .rejects.toThrow('chain unavailable');

    let states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
    expect(states[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 0n });
    jest.setSystemTime(60_000);
    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n });
    states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, states);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
    expect(states[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 250_000n });
  });

  it('retries a failed depletion read using the unchanged staked state', async () => {
    const previousStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), { [TON_TSUSDE.slug]: 1n });
    mockGetTimeLockData.mockRejectedValueOnce(new Error('chain unavailable'));
    const failedStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, previousStates);
    expect(failedStates[1]).toEqual(previousStates[1]);

    mockGetTimeLockData.mockResolvedValue({ lockedUsdeBalance: 250_000n });
    const states = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {}, failedStates);
    expect(mockGetTimeLockData).toHaveBeenCalledTimes(3);
    expect(states[1]).toMatchObject({ tokenBalance: 0n, unstakeRequestAmount: 250_000n });
  });

  it('respects protocol availability for an empty account', async () => {
    const common = commonData();
    common.ethena.isDisabled = true;
    const states = await getStakingStates(ACCOUNT_ID, common, backendState(), {});
    expect(states.map(({ id }) => id)).toEqual(['liquid']);
    expect(mockGetTimeLockData).not.toHaveBeenCalled();
  });

  it('preserves a known lock while other products update after a chain read error', async () => {
    const previousStates = await getStakingStates(ACCOUNT_ID, commonData(), backendState(), {});
    const previousState = previousStates.find((state) => state.type === 'ethena')!;
    previousState.unstakeRequestAmount = 250_000n;
    previousState.unlockTime = 100_000;
    mockGetTimeLockData.mockRejectedValue(new Error('chain unavailable'));
    const backend = backendState();
    backend.liquid = { unstakeRequestAmount: '1' };
    const states = await getStakingStates(ACCOUNT_ID, commonData(), backend, {}, previousStates);
    expect(states[0]).toMatchObject({ unstakeRequestAmount: 1_000_000_000n });
    expect(states[1]).toEqual(previousState);
  });
});
