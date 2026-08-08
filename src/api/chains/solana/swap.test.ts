import type { ApiSwapActivity, ApiSwapHistoryItem } from '../../types';
import { ApiSwapError } from '../../types';

import { buildOnchainSwapTransfer, submitOnchainSwapTransfer, validateSwapTransaction } from './swap';

jest.mock('@solana/kit', () => ({
  ...jest.requireActual('@solana/kit'),
  getBase64Decoder: () => ({ decode: jest.fn(() => 'signed-transaction') }),
  getBase64Encoder: () => ({ encode: jest.fn(() => new Uint8Array()) }),
  getCompiledTransactionMessageDecoder: () => ({ decode: jest.fn(() => ({ staticAccounts: [] })) }),
  getTransactionDecoder: () => ({ decode: jest.fn(() => ({ messageBytes: new Uint8Array() })) }),
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/activities/reconciler/operationIntentStore', () => ({
  buildSwapOperationId: jest.fn((swapId: string) => `swap:${swapId}`),
  rememberDexSwapOperationIntent: jest.fn(),
  rememberWalletOperationSubmittedHashes: jest.fn(),
}));

jest.mock('../../common/swap', () => ({
  patchSwapItem: jest.fn(),
}));

jest.mock('../../hooks', () => ({
  callHook: jest.fn(),
}));

jest.mock('./auth', () => ({
  fetchPrivateKeyString: jest.fn(() => Promise.resolve('private-key')),
}));

jest.mock('./emulation', () => ({
  emulateTransaction: jest.fn(() => Promise.resolve({ err: undefined })),
}));

jest.mock('./sign', () => ({
  partiallySignTransaction: jest.fn(() => ({ signedBytes: new Uint8Array() })),
}));

jest.mock('./transfer', () => ({
  estimateTransactionFee: jest.fn(),
}));

jest.mock('./util/programParsers', () => ({
  parseTokenOperation: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredWallet } = require('../../common/accounts') as { fetchStoredWallet: jest.Mock };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { patchSwapItem } = require('../../common/swap') as { patchSwapItem: jest.Mock };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { estimateTransactionFee } = require('./transfer') as { estimateTransactionFee: jest.Mock };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { parseTokenOperation } = require('./util/programParsers') as { parseTokenOperation: jest.Mock };

const HISTORY_OWNER_ADDRESS = 'UQ-ton-history-owner';
const SOLANA_WALLET_ADDRESS = 'solana-source-wallet';

const HISTORY_ITEM = {
  id: 'swap-id',
  timestamp: 1,
  fromAddress: HISTORY_OWNER_ADDRESS,
  from: 'sol',
  to: 'solana-usdc',
  fromAmount: '1',
  toAmount: '2',
  networkFee: '0.01',
  swapFee: '0',
  status: 'pending',
  hashes: [],
  transactionIds: {},
} as ApiSwapHistoryItem;

const LOCAL_SWAP = {
  ...HISTORY_ITEM,
  kind: 'swap',
  id: 'local:swap-id',
  extra: {
    reconciliation: {
      operationId: 'swap:swap-id',
      sourceActionIds: ['local:swap-id'],
      hiddenSourceActionIds: [],
      reason: 'local-intent',
    },
  },
} as ApiSwapActivity;

describe('Solana on-chain swap history owner handling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredWallet.mockImplementation((_accountId: string, chain: string) => ({
      address: chain === 'ton' ? HISTORY_OWNER_ADDRESS : SOLANA_WALLET_ADDRESS,
    }));
    parseTokenOperation.mockResolvedValue({
      isSwap: true,
      swap: {
        fromAddress: SOLANA_WALLET_ADDRESS,
        from: 'sol',
        to: 'solana-usdc',
        fromAmount: '1',
        toAmount: '2',
      },
    });
  });

  it('allows TON history owner in swap history while validating Solana transaction initiator', async () => {
    await expect(validateSwapTransaction('transaction', SOLANA_WALLET_ADDRESS, 'mainnet', HISTORY_ITEM))
      .resolves.toBeUndefined();
  });

  it('patches build errors by TON history owner address', async () => {
    estimateTransactionFee.mockResolvedValue({ error: ApiSwapError.SlippageError });

    await buildOnchainSwapTransfer({
      accountId: '0-mainnet',
      request: {} as any,
      transaction: 'transaction',
      swapId: 'swap-id',
      authToken: 'auth-token',
    });

    expect(fetchStoredWallet).toHaveBeenCalledWith('0-mainnet', 'ton');
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: HISTORY_OWNER_ADDRESS,
      swapId: 'swap-id',
      authToken: 'auth-token',
      error: ApiSwapError.SlippageError,
    });
  });

  it('uses Solana address for validation but TON owner address for successful history patch', async () => {
    const executeSwap = jest.fn().mockResolvedValue({ success: true, signature: 'solana-signature' });
    const onUpdate = jest.fn();

    const result = await submitOnchainSwapTransfer({
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      transaction: 'transaction',
      historyItem: HISTORY_ITEM,
      authToken: 'auth-token',
      localSwap: LOCAL_SWAP,
      swapId: 'swap-id',
      executeSwap,
    }, onUpdate);

    expect(parseTokenOperation).toHaveBeenCalledWith('mainnet', expect.anything(), SOLANA_WALLET_ADDRESS, []);
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: HISTORY_OWNER_ADDRESS,
      swapId: 'swap-id',
      authToken: 'auth-token',
      msgHash: 'solana-signature',
    });
    expect(result).toEqual({
      activityId: LOCAL_SWAP.id,
      submittedHashes: ['solana-signature'],
    });
  });
});
