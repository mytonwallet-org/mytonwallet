const mockTonCheckStakeDraft = jest.fn();
const mockSolanaCheckStakeDraft = jest.fn();
const mockTonSubmitStake = jest.fn();
const mockTonSubmitUnstake = jest.fn();
const mockTonSubmitTokenStakingClaim = jest.fn();
const mockTonSubmitUnstakeEthenaLocked = jest.fn();
const mockTonPoll = jest.fn();
const mockFetchStoredWallet = jest.fn();
const mockCreateLocalTransactions = jest.fn();
const mockPublishMfa = jest.fn();
const mockRegisterMfa = jest.fn();

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: {
      staking: {
        checkStakeDraft: (...args: unknown[]) => mockTonCheckStakeDraft(...args),
        submitStake: (...args: unknown[]) => mockTonSubmitStake(...args),
        submitUnstake: (...args: unknown[]) => mockTonSubmitUnstake(...args),
        submitTokenStakingClaim: (...args: unknown[]) => mockTonSubmitTokenStakingClaim(...args),
        submitUnstakeEthenaLocked: (...args: unknown[]) => mockTonSubmitUnstakeEthenaLocked(...args),
        poll: (...args: unknown[]) => mockTonPoll(...args),
      },
    },
    solana: { staking: { checkStakeDraft: (...args: unknown[]) => mockSolanaCheckStakeDraft(...args) } },
    tron: {},
  },
}));

jest.mock('../common/accounts', () => ({
  fetchStoredWallet: (...args: unknown[]) => mockFetchStoredWallet(...args),
}));

jest.mock('./transfer', () => ({
  createLocalTransactions: (...args: unknown[]) => mockCreateLocalTransactions(...args),
}));

jest.mock('./mfa', () => ({
  publishSignedMfaRequest: (...args: unknown[]) => mockPublishMfa(...args),
  registerMfaConfirmationHandler: (...args: unknown[]) => mockRegisterMfa(...args),
}));

import type { ApiEthenaStakingState, ApiJettonStakingState, ApiStakingState } from '../types';
import { ApiCommonError } from '../types';

import { checkStakeDraft, submitStake, submitStakingClaimOrUnlock, submitUnstake } from './staking';

const ACCOUNT_ID = '0-ton-mainnet';

function buildState(tokenSlug: string) {
  return { type: 'liquid', tokenSlug } as unknown as ApiStakingState;
}

describe('staking chain routing', () => {
  afterEach(() => {
    mockTonCheckStakeDraft.mockReset();
    mockSolanaCheckStakeDraft.mockReset();
  });

  it('routes to the chain named by the staking state, not to the first staking chain in the registry', async () => {
    mockSolanaCheckStakeDraft.mockResolvedValue({ realFee: 1n });

    await checkStakeDraft(ACCOUNT_ID, 1n, buildState('solana-abc'));

    expect(mockSolanaCheckStakeDraft).toHaveBeenCalledTimes(1);
    expect(mockTonCheckStakeDraft).not.toHaveBeenCalled();
  });

  it('routes a native token slug to its chain', async () => {
    mockTonCheckStakeDraft.mockResolvedValue({ realFee: 1n });

    await checkStakeDraft(ACCOUNT_ID, 1n, buildState('toncoin'));

    expect(mockTonCheckStakeDraft).toHaveBeenCalledTimes(1);
    expect(mockSolanaCheckStakeDraft).not.toHaveBeenCalled();
  });

  it('rejects when the state names a chain without staking', async () => {
    await expect(checkStakeDraft(ACCOUNT_ID, 1n, buildState('tron-xyz')))
      .rejects.toThrow('Staking is not supported for tron');
  });
});

describe.each([
  {
    action: 'stake',
    submit: () => submitStake(ACCOUNT_ID, undefined, 1n, buildState('toncoin')),
    mockSubmit: mockTonSubmitStake,
  },
  {
    action: 'unstake',
    submit: () => submitUnstake(ACCOUNT_ID, undefined, 1n, buildState('toncoin')),
    mockSubmit: mockTonSubmitUnstake,
  },
  {
    action: 'claim',
    submit: () => submitStakingClaimOrUnlock(
      ACCOUNT_ID, undefined, { type: 'jetton', tokenSlug: 'toncoin' } as ApiJettonStakingState,
    ),
    mockSubmit: mockTonSubmitTokenStakingClaim,
  },
  {
    action: 'unlock',
    submit: () => submitStakingClaimOrUnlock(
      ACCOUNT_ID, undefined, { type: 'ethena', tokenSlug: 'toncoin' } as ApiEthenaStakingState,
    ),
    mockSubmit: mockTonSubmitUnstakeEthenaLocked,
  },
])('staking polling after $action', ({ submit, mockSubmit }) => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSubmit.mockReset();
    mockFetchStoredWallet.mockResolvedValue({ address: 'wallet-address' });
    mockCreateLocalTransactions.mockReturnValue([{ id: 'local-activity-id' }]);
    mockPublishMfa.mockResolvedValue({ mfaRequestHash: 'mfa-request-hash' });
  });

  it('polls once after creating the successful local transaction', async () => {
    mockSubmit.mockResolvedValue({ txId: 'transaction-id' });

    await expect(submit()).resolves.toEqual({ activityId: 'local-activity-id' });

    expect(mockCreateLocalTransactions).toHaveBeenCalledTimes(1);
    expect(mockTonPoll).toHaveBeenCalledTimes(1);
    expect(mockTonPoll).toHaveBeenCalledWith(ACCOUNT_ID);
    expect(mockCreateLocalTransactions.mock.invocationCallOrder[0]).toBeLessThan(
      mockTonPoll.mock.invocationCallOrder[0],
    );
    expect(mockRegisterMfa).not.toHaveBeenCalled();
  });

  it('does not poll after a failed submission', async () => {
    mockSubmit.mockResolvedValue({ error: 'Submission failed' });

    await expect(submit()).resolves.toEqual({ error: 'Submission failed' });

    expect(mockTonPoll).not.toHaveBeenCalled();
    expect(mockCreateLocalTransactions).not.toHaveBeenCalled();
    expect(mockRegisterMfa).not.toHaveBeenCalled();
  });

  it('does not poll when the submission has no transaction', async () => {
    mockSubmit.mockResolvedValue({});

    await expect(submit()).resolves.toEqual({ error: ApiCommonError.Unexpected });

    expect(mockTonPoll).not.toHaveBeenCalled();
    expect(mockCreateLocalTransactions).not.toHaveBeenCalled();
    expect(mockRegisterMfa).not.toHaveBeenCalled();
  });

  it('polls only after the MFA request is confirmed', async () => {
    const mfaRequest = { boc: 'signed-request' };
    mockSubmit.mockResolvedValue({ mfaRequest });

    await expect(submit()).resolves.toEqual({ mfaRequestHash: 'mfa-request-hash' });

    expect(mockPublishMfa).toHaveBeenCalledWith(ACCOUNT_ID, 'ton', mfaRequest);
    expect(mockRegisterMfa).toHaveBeenCalledTimes(1);
    expect(mockRegisterMfa).toHaveBeenCalledWith('mfa-request-hash', expect.any(Function));
    expect(mockTonPoll).not.toHaveBeenCalled();
    expect(mockCreateLocalTransactions).not.toHaveBeenCalled();

    const handleConfirmation = mockRegisterMfa.mock.calls[0][1] as (txHash: string) => void;
    handleConfirmation('confirmed-transaction-id');

    expect(mockTonPoll).toHaveBeenCalledTimes(1);
    expect(mockTonPoll).toHaveBeenCalledWith(ACCOUNT_ID);
  });
});
