import type { OnBalancesUpdate } from '../../common/websocket/balanceStream';
import type { ApiBalanceBySlug, ApiEthenaStakingState, ApiStakingState } from '../../types';

import { STAKED_TON_SLUG, TON_TSUSDE, TON_USDE } from '../../../config';
import { createCallbackManager } from '../../../util/callbacks';
import Deferred from '../../../util/Deferred';
import { setIsAppFocused } from '../../../util/focusAwareDelay';
import { getStakingCommonCache } from '../../common/cache';
import { pollStaking, setupStakingPolling } from './polling';
import { getBackendStakingState, getStakingStates } from './staking';

jest.mock('../../common/cache', () => ({ getStakingCommonCache: jest.fn() }));
jest.mock('./staking', () => ({ getBackendStakingState: jest.fn(), getStakingStates: jest.fn() }));

const ACCOUNT_ID = '0-ton-mainnet';
const EMPTY_STATE: ApiEthenaStakingState = {
  id: 'ethena', type: 'ethena', tokenSlug: TON_USDE.slug, yieldType: 'APY', annualYield: 4,
  balance: 0n, tokenBalance: 0n, unstakeRequestAmount: 0n, pool: 'pool', tsUsdeWalletAddress: 'wallet',
};
const ACTIVE_STATES: ApiStakingState[] = [
  { ...EMPTY_STATE, balance: 1n },
  { ...EMPTY_STATE, tokenBalance: 1n },
  { ...EMPTY_STATE, unstakeRequestAmount: 1n },
  {
    ...EMPTY_STATE, type: 'liquid', loyaltyBalance: 1n, instantAvailable: 0n,
    start: 0, end: 0, tvl: 0n, totalStakers: 0,
  },
  {
    ...EMPTY_STATE, type: 'jetton', unclaimedRewards: 1n, tokenAmount: 0n, tokenAddress: 'token',
    stakeWalletAddress: 'wallet', period: 0, tvl: 0n, dailyReward: 0n,
  },
];

const mockGetStakingStates = jest.mocked(getStakingStates);
const mockGetBackendStakingState = jest.mocked(getBackendStakingState);
const mockGetStakingCommonCache = jest.mocked(getStakingCommonCache);

describe('TON staking polling', () => {
  let stop: NoneToVoidFunction;
  let balances: ApiBalanceBySlug;
  let balanceUpdates: ReturnType<typeof createCallbackManager<OnBalancesUpdate>>;
  let onUpdate: jest.Mock;

  beforeEach(() => {
    jest.useFakeTimers();
    jest.resetAllMocks();
    setIsAppFocused(true);
    balances = {};
    balanceUpdates = createCallbackManager<OnBalancesUpdate>();
    onUpdate = jest.fn();
    mockGetStakingCommonCache.mockResolvedValue({} as Awaited<ReturnType<typeof getStakingCommonCache>>);
    mockGetBackendStakingState.mockResolvedValue({} as Awaited<ReturnType<typeof getBackendStakingState>>);
    mockGetStakingStates.mockResolvedValue([EMPTY_STATE]);
  });

  afterEach(() => {
    stop?.();
    jest.clearAllTimers();
    jest.useRealTimers();
    setIsAppFocused(true);
  });

  async function start(accountId = ACCOUNT_ID) {
    stop = setupStakingPolling(accountId, {
      getBalances: () => Promise.resolve(balances),
      onUpdate: balanceUpdates.addCallback,
    }, onUpdate);
    await jest.advanceTimersByTimeAsync(0);
  }

  it('polls an empty account every two minutes in focus', async () => {
    await start();
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(119_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);

    await jest.advanceTimersByTimeAsync(480_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(6);
  });

  it.each(ACTIVE_STATES)('keeps a nonzero position at 30 seconds: %s', async (state) => {
    mockGetStakingStates.mockResolvedValue([state]);
    await start();

    await jest.advanceTimersByTimeAsync(29_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);
  });

  it.each([EMPTY_STATE, ACTIVE_STATES[0]])('polls in the background no sooner than two minutes: %s', async (state) => {
    setIsAppFocused(false);
    mockGetStakingStates.mockResolvedValue([state]);
    await start();

    await jest.advanceTimersByTimeAsync(119_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);
    // Jest defers the zero-delay background stage to the next millisecond
    await jest.advanceTimersByTimeAsync(2);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);
  });

  it('polls immediately after an action and keeps 30 seconds while the position is unchanged', async () => {
    await start();
    await jest.advanceTimersByTimeAsync(1_000);

    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);

    await jest.advanceTimersByTimeAsync(29_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
  });

  it.each(['unchanged', 'failed'])('returns to two minutes after ten minutes of %s action polls', async (result) => {
    await start();
    await jest.advanceTimersByTimeAsync(1_000);
    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    if (result === 'failed') {
      mockGetBackendStakingState.mockRejectedValue(new Error('Backend unavailable'));
    }

    await jest.advanceTimersByTimeAsync(600_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(22);
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({ states: [EMPTY_STATE] }));

    await jest.advanceTimersByTimeAsync(119_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(22);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(23);
  });

  it('keeps a known stake at 30 seconds after the action deadline', async () => {
    mockGetStakingStates.mockResolvedValue([ACTIVE_STATES[0]]);
    await start();
    await jest.advanceTimersByTimeAsync(1_000);
    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(600_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(22);

    await jest.advanceTimersByTimeAsync(29_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(22);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(23);
  });

  it('extends the action deadline when another action is submitted', async () => {
    await start();
    await jest.advanceTimersByTimeAsync(1_000);
    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(541_000);

    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    mockGetBackendStakingState.mockClear();

    await jest.advanceTimersByTimeAsync(599_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(19);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(20);

    await jest.advanceTimersByTimeAsync(119_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(20);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(21);
  });

  it.each([STAKED_TON_SLUG, TON_TSUSDE.slug])('polls immediately when %s arrives', async (slug) => {
    await start();
    await jest.advanceTimersByTimeAsync(1_000);
    mockGetStakingStates.mockResolvedValue([ACTIVE_STATES[0]]);
    balances = { [slug]: 1n };
    balanceUpdates.runCallbacks(balances, 'socket');
    await jest.advanceTimersByTimeAsync(0);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);

    balanceUpdates.runCallbacks(balances, 'poll');
    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
  });

  it('slows down after the last position is cleared', async () => {
    mockGetStakingStates.mockResolvedValueOnce([ACTIVE_STATES[0]]).mockResolvedValue([EMPTY_STATE]);
    await start();

    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(119_999);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
  });

  it.each(['backend', 'contract'])('preserves the known state and interval after a %s error', async (source) => {
    const states = [{ ...EMPTY_STATE, unstakeRequestAmount: 1n }];
    mockGetStakingStates.mockResolvedValue(states);
    await start();
    if (source === 'backend') {
      mockGetBackendStakingState.mockRejectedValueOnce(new Error('Backend unavailable'));
    } else {
      mockGetStakingStates.mockRejectedValueOnce(new Error('Contract unavailable'));
    }

    await jest.advanceTimersByTimeAsync(30_000);
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({ states }));

    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
    expect(mockGetStakingStates).toHaveBeenLastCalledWith(ACCOUNT_ID, {}, {}, {}, states);
    expect(onUpdate).toHaveBeenCalledTimes(1);
  });

  it('queues an action refresh behind an in-flight poll', async () => {
    await start();
    const pendingStates = new Deferred<ApiStakingState[]>();
    mockGetStakingStates.mockReturnValueOnce(pendingStates.promise);
    await jest.advanceTimersByTimeAsync(120_000);

    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(2);

    const states = [{ ...EMPTY_STATE, annualYield: 5 }];
    mockGetStakingStates.mockResolvedValue(states);
    pendingStates.resolve(states);
    await jest.advanceTimersByTimeAsync(0);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(4);
  });

  it('keeps a pending action at 30 seconds when only yield metadata changes', async () => {
    await start();
    mockGetStakingStates.mockResolvedValue([{ ...EMPTY_STATE, annualYield: 5 }]);

    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
  });

  it('keeps a pending action at 30 seconds when an empty product appears', async () => {
    await start();
    mockGetStakingStates.mockResolvedValue([
      EMPTY_STATE,
      { ...EMPTY_STATE, id: 'nominators', type: 'nominators', start: 0, end: 0 },
    ]);

    pollStaking(ACCOUNT_ID);
    await jest.advanceTimersByTimeAsync(0);
    await jest.advanceTimersByTimeAsync(30_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(3);
  });

  it('ignores actions for another account and stops all refresh triggers on cleanup', async () => {
    await start();
    pollStaking('1-ton-mainnet');
    await jest.advanceTimersByTimeAsync(0);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);

    stop();
    expect(balanceUpdates.hasCallbacks()).toBe(false);
    pollStaking(ACCOUNT_ID);
    balanceUpdates.runCallbacks({ [TON_TSUSDE.slug]: 1n }, 'socket');
    await jest.advanceTimersByTimeAsync(120_000);
    expect(mockGetBackendStakingState).toHaveBeenCalledTimes(1);
  });

  it('does not poll staking on testnet', async () => {
    await start('0-ton-testnet');
    pollStaking('0-ton-testnet');
    await jest.advanceTimersByTimeAsync(120_000);
    expect(mockGetBackendStakingState).not.toHaveBeenCalled();
    expect(balanceUpdates.hasCallbacks()).toBe(false);
  });
});
