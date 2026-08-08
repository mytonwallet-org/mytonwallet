import './staking';

import type { ApiStakingState } from '../../../api/types';
import type { GlobalState } from '../../types';
import { StakingState } from '../../types';

import { MYCOIN_MAINNET, TONCOIN } from '../../../config';
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

function makeGlobal(stakingId?: string): GlobalState {
  return {
    currentAccountId: 'acc',
    accounts: { byId: { acc: { title: 'Test', type: 'mnemonic', byChain: {} } } },
    auth: { accounts: [] },
    byAccountId: {
      acc: { staking: { stateById: { 'my-1': MY_STATE, 'ton-1': TON_STATE }, stakingId } },
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

  function run(global: GlobalState, payload?: { tokenSlug?: string }) {
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

  it('refuses to build a stake draft when the current position is blocked', async () => {
    store = makeGlobal('my-1');
    await getHandler('submitStakingInitial')(store, {}, { amount: 1n });
    expect(setGlobal).not.toHaveBeenCalled();
  });
});
