import './staking';

import type { ApiStakingState } from '../../../api/types';
import type { GlobalState } from '../../types';
import { StakingState } from '../../types';

import { MYCOIN_MAINNET, TON_USDE, TONCOIN } from '../../../config';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => unknown;

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

const MY_STATE = {
  id: 'my-1', type: 'jetton', tokenSlug: MYCOIN_MAINNET.slug, balance: 1n,
} as unknown as ApiStakingState;
const TON_STATE = {
  id: 'ton-1', type: 'liquid', tokenSlug: TONCOIN.slug, balance: 0n,
} as unknown as ApiStakingState;
const TON_ALT_STATE = {
  id: 'ton-2', type: 'nominators', tokenSlug: TONCOIN.slug, balance: 0n,
} as unknown as ApiStakingState;

function makeGlobal(stakingId?: string): GlobalState {
  return {
    currentAccountId: 'acc',
    accounts: { byId: { acc: { title: 'Test', type: 'mnemonic', byChain: {} } } },
    auth: { accounts: [] },
    byAccountId: {
      acc: {
        staking: {
          stateById: { 'my-1': MY_STATE, 'ton-1': TON_STATE, 'ton-2': TON_ALT_STATE },
          stakingId,
        },
      },
    },
    stakingDefault: TON_STATE,
    currentStaking: {},
  } as unknown as GlobalState;
}

describe('startStaking action', () => {
  let store: GlobalState;

  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
    (getGlobal as jest.Mock).mockImplementation(() => store);
    (setGlobal as jest.Mock).mockImplementation((next: GlobalState) => {
      store = next;
    });
  });

  function run(global: GlobalState, payload?: {
    stakingId?: string;
    tokenSlug?: string;
    initialAmount?: bigint | 'all';
  }) {
    store = global;
    getHandler('startStaking')(store, {}, payload);
    return store;
  }

  it('rejects a new stake for an explicitly blocked token', () => {
    const result = run(makeGlobal('ton-1'), { tokenSlug: MYCOIN_MAINNET.slug });
    expect(result.currentStaking.state).not.toBe(StakingState.StakeInitial);
  });

  it('rejects a new stake when a missing tokenSlug resolves to a blocked current position', () => {
    const result = run(makeGlobal('my-1'));
    expect(result.currentStaking.state).not.toBe(StakingState.StakeInitial);
  });

  it('opens the stake form for an allowed token', () => {
    const result = run(makeGlobal('ton-1'), { tokenSlug: TONCOIN.slug });
    expect(result.currentStaking.state).toBe(StakingState.StakeInitial);
  });

  it('opens an available Ethena product with no owned tokens or existing stake', () => {
    const global = makeGlobal('ton-1');
    const ethena = {
      ...TON_STATE, id: 'ethena', type: 'ethena', tokenSlug: TON_USDE.slug,
      balance: 0n, tokenBalance: 0n, unstakeRequestAmount: 0n,
    } as ApiStakingState;
    global.byAccountId.acc.staking!.stateById!.ethena = ethena;
    const result = run(global, { stakingId: 'ethena', tokenSlug: TON_USDE.slug });
    expect(result.byAccountId.acc.staking?.stakingId).toBe('ethena');
    expect(result.currentStaking.state).toBe(StakingState.StakeInitial);
  });

  it('selects the exact product and preserves an exact amount prefill', () => {
    const result = run(makeGlobal('ton-1'), {
      stakingId: 'ton-2',
      tokenSlug: TONCOIN.slug,
      initialAmount: 10_000_000_000n,
    });

    expect(result.byAccountId.acc.staking?.stakingId).toBe('ton-2');
    expect(result.currentStaking).toMatchObject({
      state: StakingState.StakeInitial,
      initialAmount: 10_000_000_000n,
    });
  });

  it('preserves an all-balance prefill for the exact product', () => {
    const result = run(makeGlobal('ton-1'), {
      stakingId: 'ton-1',
      tokenSlug: TONCOIN.slug,
      initialAmount: 'all',
    });

    expect(result.currentStaking.initialAmount).toBe('all');
  });

  it('rejects a mismatched product and asset pair', () => {
    const result = run(makeGlobal('ton-1'), {
      stakingId: 'ton-1',
      tokenSlug: MYCOIN_MAINNET.slug,
      initialAmount: 1n,
    });

    expect(result.currentStaking.state).not.toBe(StakingState.StakeInitial);
    expect(setGlobal).not.toHaveBeenCalled();
  });

  it('refuses to build a stake draft when the current position is blocked', async () => {
    store = makeGlobal('my-1');
    await getHandler('submitStakingInitial')(store, {}, { amount: 1n });
    expect(setGlobal).not.toHaveBeenCalled();
  });
});
