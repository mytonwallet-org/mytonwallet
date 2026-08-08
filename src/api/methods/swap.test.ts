import type {
  ApiChain,
  ApiSubmitGasfullTransferOptions,
  ApiSwapBuildTransactionRequest,
  ApiSwapHistoryItem,
} from '../types';

import {
  confirmSwapMfaRequest,
  fetchSwaps,
  initSwap,
  swapCexCreateTransaction,
  swapCexSubmit,
  swapSubmit,
} from './swap';

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    base: {
      submitGasfullTransfer: jest.fn().mockResolvedValue({ txId: '0xbase-deposit' }),
    },
    ton: {
      submitOnchainSwapTransfer: jest.fn().mockResolvedValue({
        activityId: 'swap-id::local',
        submittedHashes: ['raw-boc-hash', 'normalized-external-hash'],
      }),
    },
  },
}));

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../common/backend', () => ({
  callBackendGet: jest.fn(),
  callBackendPost: jest.fn(),
}));

jest.mock('../common/activities/reconciler/cexSwapReconciler', () => ({
  buildCexSwapRefreshPatch: jest.fn(),
  normalizeCexSwapRefreshActivity: jest.fn((swap) => ({
    ...swap,
    status: swap.isCanceled ? 'expired' : swap.status,
    shouldHide: undefined,
  })),
}));

jest.mock('../common/activities/reconciler/activeCexSwapState', () => ({
  expireActiveCexSwaps: jest.fn(),
  rememberActiveCexSwap: jest.fn(),
  rememberActiveCexSwaps: jest.fn(),
  rememberActiveCexSwapSubmittedHashes: jest.fn(),
}));

jest.mock('../common/activities/reconciler/operationIntentStore', () => ({
  buildSwapOperationId: jest.fn((swapId: string) => `swap:${swapId}`),
  getWalletOperationIntents: jest.fn(),
  rememberCexSwapOperationIntent: jest.fn(),
  rememberDexSwapOperationIntent: jest.fn(),
  rememberWalletOperationSubmittedHashes: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../common/cache', () => ({
  getBackendConfigCache: jest.fn(),
}));

jest.mock('../common/swap', () => ({
  convertSwapItemToTrusted: jest.fn(),
  getSwapItemSlug: jest.fn(),
  patchSwapItem: jest.fn(),
  swapGetHistoryItem: jest.fn(),
  swapItemToActivity: jest.fn(),
}));

jest.mock('../hooks', () => ({
  callHook: jest.fn(),
}));

jest.mock('./mfa', () => ({
  publishSignedMfaRequest: jest.fn(),
}));

jest.mock('./other', () => ({
  getBackendAuthToken: jest.fn().mockResolvedValue('backend-auth-token'),
  getStoredBackendAuthToken: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as {
  base: { submitGasfullTransfer: jest.Mock };
  ton: { submitOnchainSwapTransfer: jest.Mock };
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredAccount, fetchStoredWallet } = require('../common/accounts') as {
  fetchStoredAccount: jest.Mock;
  fetchStoredWallet: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { patchSwapItem, swapGetHistoryItem, swapItemToActivity } = require('../common/swap') as {
  patchSwapItem: jest.Mock;
  swapGetHistoryItem: jest.Mock;
  swapItemToActivity: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { publishSignedMfaRequest } = require('./mfa') as {
  publishSignedMfaRequest: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { buildCexSwapRefreshPatch } = require('../common/activities/reconciler/cexSwapReconciler') as {
  buildCexSwapRefreshPatch: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const operationIntentStore = require('../common/activities/reconciler/operationIntentStore') as {
  getWalletOperationIntents: jest.Mock;
  rememberWalletOperationSubmittedHashes: jest.Mock;
};
const { getWalletOperationIntents, rememberWalletOperationSubmittedHashes } = operationIntentStore;

const {
  expireActiveCexSwaps,
  rememberActiveCexSwap,
  rememberActiveCexSwapSubmittedHashes,
  rememberActiveCexSwaps,
// eslint-disable-next-line @typescript-eslint/no-require-imports
} = require('../common/activities/reconciler/activeCexSwapState') as {
  expireActiveCexSwaps: jest.Mock;
  rememberActiveCexSwap: jest.Mock;
  rememberActiveCexSwapSubmittedHashes: jest.Mock;
  rememberActiveCexSwaps: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getStoredBackendAuthToken } = require('./other') as {
  getStoredBackendAuthToken: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { callBackendPost } = require('../common/backend') as {
  callBackendPost: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { convertSwapItemToTrusted } = require('../common/swap') as {
  convertSwapItemToTrusted: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getBackendConfigCache } = require('../common/cache') as {
  getBackendConfigCache: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { ApiServerError } = require('../errors') as {
  ApiServerError: typeof import('../errors').ApiServerError;
};

describe('DEX swap submitted identities', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    initSwap(jest.fn());
    chains.ton.submitOnchainSwapTransfer.mockResolvedValue({
      activityId: 'swap-id::local',
      submittedHashes: ['raw-boc-hash', 'normalized-external-hash'],
    });
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-ton-history-owner' });
    getStoredBackendAuthToken.mockResolvedValue('stored-auth-token');
  });

  it('persists exact chain submit hashes in the SDK operation intent', async () => {
    const historyItem = {
      id: 'swap-id',
      timestamp: 1,
      from: 'TON',
      to: 'token-address',
      fromAddress: 'EQ-ton-history-owner',
      fromAmount: '1',
      toAmount: '2',
      networkFee: '0.1',
      swapFee: '0',
      status: 'pending',
      hashes: [],
      transactionIds: {},
    } satisfies ApiSwapHistoryItem;

    const result = await swapSubmit(
      'ton',
      '0-mainnet',
      'password',
      [],
      historyItem,
    );

    expect(rememberWalletOperationSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet',
      'swap:swap-id',
      ['raw-boc-hash', 'normalized-external-hash'],
    );
    expect(result).toEqual({ activityId: 'swap-id::local', swapId: 'swap-id' });
  });

  it('persists the confirmed MFA transaction hash before patching swap history', async () => {
    await confirmSwapMfaRequest('0-mainnet', 'swap-id', 'confirmed-mfa-hash');

    expect(rememberWalletOperationSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet',
      'swap:swap-id',
      ['confirmed-mfa-hash'],
    );
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      swapId: 'swap-id',
      authToken: 'stored-auth-token',
      msgHash: 'confirmed-mfa-hash',
    });
  });
});

describe('swapCexCreateTransaction', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    initSwap(jest.fn());
    getBackendConfigCache.mockResolvedValue({ swapVersion: 1 });
    callBackendPost.mockResolvedValue({
      route: 'cex',
      swap: {
        id: 'swap-id',
        timestamp: 1,
        from: 'trx',
        to: 'ton',
        fromAmount: '10',
        toAmount: '5',
        networkFee: '0.1',
        swapFee: '0',
        status: 'pending',
        cex: {
          payinAddress: 'payin-address',
          payoutAddress: 'payout-address',
          status: 'waiting',
          transactionId: 'cex-transaction-id',
        },
      },
    });
    convertSwapItemToTrusted.mockImplementation((swap) => ({ ...swap, status: 'pendingTrusted' }));
    swapItemToActivity.mockImplementation((swap) => ({
      ...swap,
      kind: 'swap',
      id: `${swap.id}::backend-swap`,
    }));
  });

  it('stores active CEX reconciliation state when creating a CEX transaction', async () => {
    const result = await swapCexCreateTransaction('0-mainnet', 'password', {
      from: 'trx',
      to: 'ton',
      fromAmount: '10',
    } as unknown as ApiSwapBuildTransactionRequest);

    expect(rememberActiveCexSwap).toHaveBeenCalledWith(
      '0-mainnet',
      expect.objectContaining({ id: 'swap-id::backend-swap', status: 'pendingTrusted' }),
    );
    expect(result.activity).toEqual(expect.objectContaining({ id: 'swap-id::backend-swap' }));
  });
});

describe('swapCexSubmit', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    chains.base.submitGasfullTransfer.mockResolvedValue({ txId: '0xbase-deposit' });
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-ton-history-owner' });
    publishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request-hash' });
  });

  it('patches CEX history by TON owner address after a non-TON deposit transfer', async () => {
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(chains.base.submitGasfullTransfer).toHaveBeenCalledWith(transferOptions);
    expect(fetchStoredWallet).toHaveBeenCalledWith('0-mainnet', 'ton');
    expect(rememberActiveCexSwapSubmittedHashes).toHaveBeenCalledWith('0-mainnet', 'swap-id', ['0xbase-deposit']);
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      authToken: 'backend-auth-token',
      msgHash: '0xbase-deposit',
      swapId: 'swap-id',
    });
  });

  it('prefers msgHashForCexSwap over txId when patching CEX history', async () => {
    chains.base.submitGasfullTransfer.mockResolvedValue({
      txId: '0xbase-deposit',
      msgHashForCexSwap: '0xbase-cex-hash',
    });
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(rememberWalletOperationSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet',
      'swap:swap-id',
      ['0xbase-cex-hash', '0xbase-deposit'],
    );
    expect(rememberActiveCexSwapSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet',
      'swap-id',
      ['0xbase-cex-hash', '0xbase-deposit'],
    );
    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      msgHash: '0xbase-cex-hash',
    }));
  });

  it('deduplicates identical backend and activity submitted hashes', async () => {
    chains.base.submitGasfullTransfer.mockResolvedValue({
      txId: 'same-submitted-hash',
      msgHashForCexSwap: 'same-submitted-hash',
    });
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(rememberWalletOperationSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet', 'swap:swap-id', ['same-submitted-hash'],
    );
    expect(rememberActiveCexSwapSubmittedHashes).toHaveBeenCalledWith(
      '0-mainnet', 'swap-id', ['same-submitted-hash'],
    );
  });

  it('patches CEX history with frontend error when the deposit transfer returns an error', async () => {
    chains.base.submitGasfullTransfer.mockResolvedValue({ error: 'InsufficientBalance' });
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    const result = await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(result).toEqual({ error: 'InsufficientBalance' });
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      authToken: 'backend-auth-token',
      error: 'InsufficientBalance',
      swapId: 'swap-id',
    });
  });

  it('patches CEX history with frontend error when the deposit transfer throws', async () => {
    const submitError = new Error('submit failed');
    chains.base.submitGasfullTransfer.mockRejectedValue(submitError);
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    await expect(swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id')).rejects.toThrow('submit failed');

    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      authToken: 'backend-auth-token',
      error: expect.stringContaining('submit failed'),
      swapId: 'swap-id',
    });
  });

  it('publishes MFA requests instead of patching CEX history immediately', async () => {
    const mfaRequest = {
      payload: 'payload',
      signature: 'signature',
      transaction: 'transaction',
    };
    chains.base.submitGasfullTransfer.mockResolvedValue({ mfaRequest });
    const transferOptions = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      toAddress: '0xdeposit',
      amount: 1n,
      fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions;

    const result = await swapCexSubmit('base' as ApiChain, transferOptions, 'swap-id');

    expect(publishSignedMfaRequest).toHaveBeenCalledWith('0-mainnet', 'base', mfaRequest);
    expect(patchSwapItem).not.toHaveBeenCalled();
    expect(result).toEqual({ swapId: 'swap-id', mfaRequestHash: 'mfa-request-hash' });
  });
});

describe('fetchSwaps', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredAccount.mockResolvedValue({
      byChain: {
        ton: { address: 'EQ-ton-history-owner' },
        solana: { address: 'solana-source-wallet' },
      },
    });
    swapGetHistoryItem.mockResolvedValue({
      id: 'swap-id',
      timestamp: 1,
      from: 'sol',
      to: 'solana-usdc',
      fromAmount: '1',
      toAmount: '2',
      networkFee: '0.01',
      swapFee: '0',
      status: 'completed',
      hashes: ['solana-signature'],
      cex: {
        payinAddress: 'payin-address',
        payoutAddress: 'payout-address',
        status: 'waiting',
        transactionId: 'cex-transaction-id',
      },
    });
    swapItemToActivity.mockImplementation((swap, chain) => ({
      ...swap,
      kind: 'swap',
      id: `${chain}:${swap.id}`,
    }));
    getWalletOperationIntents.mockResolvedValue([]);
    getStoredBackendAuthToken.mockResolvedValue('stored-auth-token');
    buildCexSwapRefreshPatch.mockImplementation((_accountId, swaps, nonExistentIds) => ({
      upsert: swaps,
      removeIds: nonExistentIds,
      replacedIds: {},
    }));
  });

  it('uses TON owner address for Solana chain-hinted backend swap history lookup', async () => {
    const result = await fetchSwaps('0-mainnet', [{ id: 'swap-id', chain: 'solana' }]);

    expect(swapGetHistoryItem).toHaveBeenCalledWith('EQ-ton-history-owner', 'swap-id', {});
    expect(swapGetHistoryItem).not.toHaveBeenCalledWith('solana-source-wallet', 'swap-id', {});
    expect(rememberActiveCexSwaps).toHaveBeenCalledWith(
      '0-mainnet', [expect.objectContaining({ id: 'solana:swap-id' })],
    );
    expect(result.swaps).toEqual([expect.objectContaining({ id: 'solana:swap-id' })]);
  });

  it('passes force provider refresh option to backend history item lookup', async () => {
    await fetchSwaps('0-mainnet', [{ id: 'swap-id', chain: 'ton' }], [], { forceProviderRefresh: true });

    expect(swapGetHistoryItem).toHaveBeenCalledWith(
      'EQ-ton-history-owner',
      'swap-id',
      { forceProviderRefresh: true, authToken: 'stored-auth-token' },
    );
  });

  it('expires active CEX state for backend ids that history lookup reports as non-existent', async () => {
    swapGetHistoryItem.mockRejectedValue(new ApiServerError('Not found', 404));

    const result = await fetchSwaps('0-mainnet', [{ id: 'swap-id', chain: 'ton' }]);

    expect(result.nonExistentIds).toEqual(['swap-id']);
    expect(expireActiveCexSwaps).toHaveBeenCalledWith('0-mainnet', ['swap-id']);
  });

  it('terminalizes a canceled provider response before storing active CEX state and building its patch', async () => {
    swapGetHistoryItem.mockResolvedValue({
      id: 'swap-id',
      timestamp: 1,
      from: 'TON',
      to: 'USDT',
      fromAmount: '1',
      toAmount: '2',
      networkFee: '0.01',
      swapFee: '0',
      status: 'pendingTrusted',
      hashes: ['payin-hash'],
      isCanceled: true,
      cex: {
        payinAddress: 'payin-address',
        payoutAddress: 'payout-address',
        status: 'failed',
        transactionId: 'cex-transaction-id',
      },
    });

    await fetchSwaps('0-mainnet', [{ id: 'swap-id', chain: 'ton' }]);

    expect(rememberActiveCexSwaps).toHaveBeenCalledWith('0-mainnet', [
      expect.objectContaining({
        id: 'ton:swap-id',
        status: 'expired',
        shouldHide: undefined,
      }),
    ]);
    expect(buildCexSwapRefreshPatch).toHaveBeenCalledWith(
      '0-mainnet',
      [expect.objectContaining({ id: 'ton:swap-id', status: 'expired' })],
      [],
      [],
      [],
    );
  });
});
