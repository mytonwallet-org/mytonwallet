import type { ApiSubmitOnchainSwapTransferOptions } from '../../types/swap';

import { submitOnchainSwapTransfer } from './swap';

jest.mock('@ton/core', () => ({
  Cell: { fromBase64: jest.fn(() => ({})) },
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({ patchSwapItem: jest.fn() }));
jest.mock('../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredChainAccount, fetchStoredWallet } = require('../../common/accounts') as {
  fetchStoredChainAccount: jest.Mock;
  fetchStoredWallet: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { submitMultiTransferWithMfa } = require('./transfer') as {
  submitMultiTransferWithMfa: jest.Mock;
};

describe('submitOnchainSwapTransfer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-wallet' });
    fetchStoredChainAccount.mockResolvedValue({ byChain: { ton: {} } });
    submitMultiTransferWithMfa.mockResolvedValue({
      msgHash: 'raw-boc-hash',
      msgHashNormalized: 'normalized-external-hash',
      messages: [{}],
      withW5Gasless: true,
    });
  });

  it('keeps local reconciliation metadata after a successful TON submit', async () => {
    const onUpdate = jest.fn();
    const localSwap = {
      id: 'swap-id::local',
      kind: 'swap',
      timestamp: 1,
      from: 'TON',
      fromAmount: '1',
      to: 'ton-token',
      toAmount: '2',
      networkFee: '0',
      swapFee: '0',
      ourFee: '0',
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    } as const;
    const options = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      transfers: [{ amount: '1', payload: '', toAddress: 'EQ-destination' }],
      historyItem: { from: 'TON' },
      isGasless: false,
      authToken: 'auth-token',
      localSwap,
      swapId: 'swap-id',
    } as unknown as ApiSubmitOnchainSwapTransferOptions;

    const result = await submitOnchainSwapTransfer(options, onUpdate);

    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'newLocalActivities',
      activities: [expect.objectContaining({
        externalMsgHashNorm: 'normalized-external-hash',
        extra: expect.objectContaining({
          withW5Gasless: true,
          reconciliation: expect.objectContaining({
            operationId: 'swap:swap-id',
            reason: 'local-intent',
          }),
        }),
      })],
    }));
    expect(result).toEqual({
      activityId: 'swap-id::local',
      submittedHashes: ['raw-boc-hash', 'normalized-external-hash'],
    });
  });
});
