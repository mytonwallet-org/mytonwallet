import './staking';

import type { ApiForeignStakingPromotion, ApiForeignUnstakeDraft, ApiStakingState } from '../../../api/types';
import type { GlobalState } from '../../types';
import { ApiCommonError, ApiTransactionDraftError } from '../../../api/types';
import { StakingState } from '../../types';

import { MYCOIN_MAINNET, TON_USDE, TONCOIN } from '../../../config';
import { callApi, callApiWithThrow } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getActions: jest.fn(() => ({ showError: jest.fn() })),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
  callApiWithThrow: jest.fn(),
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

const FOREIGN_BANNER = {
  id: 'foreign-staking:ton:tonstakers',
  kind: 'foreignStaking',
  infoBanner: {
    actionButton: { title: 'Unstake', onClickAction: 'unstakeForeign', chain: 'ton', providerName: 'tonstakers' },
  },
} as ApiForeignStakingPromotion;

const UNSTAKE_DRAFT: ApiForeignUnstakeDraft = {
  amountNative: 99_000_000n,
  transfers: [],
  fee: 50_000_000n,
  realFee: 7_000_000n,
  isInstant: false,
};

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

describe('foreign unstake actions', () => {
  let store: GlobalState;
  const actions = { showError: jest.fn(), releaseEnclaveSession: jest.fn() };

  beforeEach(() => {
    (callApi as jest.Mock).mockReset();
    (callApiWithThrow as jest.Mock).mockReset();
    actions.showError.mockClear();
    (getGlobal as jest.Mock).mockImplementation(() => store);
    (setGlobal as jest.Mock).mockImplementation((next: GlobalState) => {
      store = next;
    });
  });

  function makeForeignGlobal(currentStaking: AnyLiteral): GlobalState {
    const global = makeGlobal('ton-1');
    global.byAccountId.acc.banners = { home: [], staking: [FOREIGN_BANNER] };
    global.currentStaking = { state: StakingState.StakeInitial, ...currentStaking };
    return global;
  }

  function makeSigningGlobal() {
    return makeForeignGlobal({
      state: StakingState.ForeignUnstakePassword,
      foreignUnstake: {
        accountId: 'acc',
        bannerId: FOREIGN_BANNER.id,
        chain: 'ton',
        providerName: 'tonstakers',
        draft: UNSTAKE_DRAFT,
      },
    });
  }

  it('loads the draft once and opens the password screen', async () => {
    (callApiWithThrow as jest.Mock).mockResolvedValue(UNSTAKE_DRAFT);
    store = makeForeignGlobal({});

    const loading = getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    await getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    await loading;

    expect(callApiWithThrow).toHaveBeenCalledTimes(1);
    expect(callApiWithThrow).toHaveBeenCalledWith('checkForeignUnstakeDraft', 'acc', 'ton', 'tonstakers');
    expect(store.currentStaking.state).toBe(StakingState.ForeignUnstakePassword);
    expect(store.currentStaking.foreignUnstake?.draft).toBe(UNSTAKE_DRAFT);
  });

  it('opens the Ledger connection for a hardware account', async () => {
    (callApiWithThrow as jest.Mock).mockResolvedValue(UNSTAKE_DRAFT);
    store = makeForeignGlobal({});
    store.accounts!.byId.acc.type = 'hardware';

    await getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });

    expect(store.currentStaking.state).toBe(StakingState.ForeignUnstakeConnectHardware);
  });

  it('loads the draft for the banner the user tapped', async () => {
    const otherBanner = {
      id: 'foreign-staking:ton:other',
      kind: 'foreignStaking',
      infoBanner: {
        actionButton: { title: 'Unstake', onClickAction: 'unstakeForeign', chain: 'ton', providerName: 'other' },
      },
    } as ApiForeignStakingPromotion;
    (callApiWithThrow as jest.Mock).mockResolvedValue(UNSTAKE_DRAFT);
    store = makeForeignGlobal({});
    store.byAccountId.acc.banners = { home: [], staking: [FOREIGN_BANNER, otherBanner] };

    await getHandler('startForeignUnstake')(store, actions, { id: otherBanner.id });

    expect(callApiWithThrow).toHaveBeenCalledWith('checkForeignUnstakeDraft', 'acc', 'ton', 'other');
    expect(store.currentStaking.foreignUnstake?.bannerId).toBe(otherBanner.id);
  });

  it('does not open the confirmation after the staking modal is closed', async () => {
    let resolveDraft: (draft: ApiForeignUnstakeDraft) => void;
    (callApiWithThrow as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveDraft = resolve;
    }));
    store = makeForeignGlobal({});

    const loading = getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    store = { ...store, currentStaking: { ...store.currentStaking, state: StakingState.None } };
    resolveDraft!(UNSTAKE_DRAFT);
    await loading;

    expect(store.currentStaking.state).toBe(StakingState.None);
    expect(store.currentStaking.foreignUnstake).toBeUndefined();
  });

  it.each([ApiTransactionDraftError.InsufficientBalance, ApiCommonError.ServerError])(
    'shows the %s error and lets the user try again',
    async (error) => {
      (callApiWithThrow as jest.Mock).mockRejectedValue(new Error(error));
      store = makeForeignGlobal({});

      await getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });

      expect(actions.showError).toHaveBeenCalledWith({ error });
      expect(store.currentStaking.foreignUnstake).toBeUndefined();
    },
  );

  it('shows the generic error instead of a technical text', async () => {
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('Failed to fetch'));
    store = makeForeignGlobal({});

    await getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });

    expect(actions.showError).toHaveBeenCalledWith({ error: undefined });
  });

  it('signs the unchanged draft and hides the banner after sending', async () => {
    (callApi as jest.Mock).mockResolvedValue({ activityIds: ['tx'] });
    store = makeSigningGlobal();

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(callApi).toHaveBeenCalledWith('submitForeignUnstake', 'acc', 'ton', 'tonstakers', UNSTAKE_DRAFT, 'token');
    expect(store.byAccountId.acc.submittedForeignStakingIds).toEqual([FOREIGN_BANNER.id]);
    expect(store.currentStaking.state).toBe(StakingState.None);
  });

  it('waits for the MFA confirmation before hiding the banner', async () => {
    (callApi as jest.Mock).mockResolvedValue({ mfaRequestHash: 'hash' });
    store = makeSigningGlobal();

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(store.currentStaking).toMatchObject({
      state: StakingState.ForeignUnstakeConfirmMfa,
      mfaRequestHash: 'hash',
    });
    expect(store.byAccountId.acc.submittedForeignStakingIds).toBeUndefined();
  });

  it('ignores the confirmation of an MFA request the user replaced', async () => {
    let resolveStatus: (result: AnyLiteral) => void;
    (callApi as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveStatus = resolve;
    }));
    const global = makeSigningGlobal();
    store = {
      ...global,
      currentStaking: {
        ...global.currentStaking,
        state: StakingState.ForeignUnstakeConfirmMfa,
        mfaRequestHash: 'first',
      },
    };

    const loading = getHandler('updateStakingMfaRequestStatus')(store, actions);
    store = { ...store, currentStaking: { ...store.currentStaking, mfaRequestHash: 'second' } };
    resolveStatus!({ isConfirmed: true });
    await loading;

    expect(store.currentStaking.state).toBe(StakingState.ForeignUnstakeConfirmMfa);
    expect(store.byAccountId.acc.submittedForeignStakingIds).toBeUndefined();
  });

  it('ignores a submit that arrives after the staking modal is closed', async () => {
    store = makeForeignGlobal({ state: StakingState.None });

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(callApi).not.toHaveBeenCalled();
  });

  it('does not send a draft after the user has gone back to the staking form', async () => {
    const global = makeSigningGlobal();
    store = { ...global, currentStaking: { ...global.currentStaking, state: StakingState.StakeInitial } };

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(callApi).not.toHaveBeenCalled();
  });

  it('lets the user retry the Ledger signing after an error, but not while it is in progress', async () => {
    (callApi as jest.Mock).mockResolvedValue({ activityIds: ['tx'] });
    const global = makeSigningGlobal();
    const confirmHardware = { ...global.currentStaking, state: StakingState.ForeignUnstakeConfirmHardware };

    store = { ...global, currentStaking: { ...confirmHardware, isLoading: true } };
    await getHandler('submitForeignUnstake')(store, actions);
    expect(callApi).not.toHaveBeenCalled();

    store = { ...global, currentStaking: confirmHardware };
    await getHandler('submitForeignUnstake')(store, actions);
    expect(callApi).toHaveBeenCalledWith('submitForeignUnstake', 'acc', 'ton', 'tonstakers', UNSTAKE_DRAFT, undefined);
  });

  it('keeps the banner when sending fails', async () => {
    (callApi as jest.Mock).mockResolvedValue(undefined);
    store = makeSigningGlobal();

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(store.currentStaking.state).toBe(StakingState.ForeignUnstakePassword);
    expect(store.byAccountId.acc.submittedForeignStakingIds).toBeUndefined();
  });

  it('hides the banner when the staking modal is closed while sending', async () => {
    let resolveResult: (result: AnyLiteral) => void;
    (callApi as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveResult = resolve;
    }));
    store = makeSigningGlobal();

    const sending = getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });
    store = { ...store, currentStaking: { state: StakingState.None } };
    resolveResult!({ activityIds: ['tx'] });
    await sending;

    expect(store.byAccountId.acc.submittedForeignStakingIds).toEqual([FOREIGN_BANNER.id]);
    expect(store.currentStaking.state).toBe(StakingState.None);
  });

  it('ignores a draft of the request the user left before reopening the staking modal', async () => {
    const resolvers: ((draft: ApiForeignUnstakeDraft) => void)[] = [];
    (callApiWithThrow as jest.Mock).mockImplementation(() => new Promise((resolve) => {
      resolvers.push(resolve);
    }));
    store = makeForeignGlobal({});

    const firstLoading = getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    store = { ...store, currentStaking: { state: StakingState.StakeInitial } };
    const secondLoading = getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    const secondDraft = { ...UNSTAKE_DRAFT, amountNative: 1n };

    resolvers[0](UNSTAKE_DRAFT);
    await firstLoading;
    expect(store.currentStaking.state).toBe(StakingState.StakeInitial);

    resolvers[1](secondDraft);
    await secondLoading;
    expect(store.currentStaking.state).toBe(StakingState.ForeignUnstakePassword);
    expect(store.currentStaking.foreignUnstake?.draft).toBe(secondDraft);
  });

  it('shows no error for a draft request the user left', async () => {
    let rejectDraft: (error: Error) => void;
    (callApiWithThrow as jest.Mock).mockReturnValue(new Promise((_, reject) => {
      rejectDraft = reject;
    }));
    store = makeForeignGlobal({});

    const loading = getHandler('startForeignUnstake')(store, actions, { id: FOREIGN_BANNER.id });
    store = { ...store, currentStaking: { state: StakingState.None } };
    rejectDraft!(new Error(ApiTransactionDraftError.InsufficientBalance));
    await loading;

    expect(actions.showError).not.toHaveBeenCalled();
  });

  it('resets the flow when the current account is not the one that loaded the draft', async () => {
    store = makeSigningGlobal();
    store = { ...store, currentAccountId: 'other' };

    await getHandler('submitForeignUnstake')(store, actions, { enclaveToken: 'token' });

    expect(callApi).not.toHaveBeenCalled();
    expect(store.currentStaking).toEqual({ state: StakingState.None });
  });
});
