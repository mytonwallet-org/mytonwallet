import type { ApiChain, ApiSubmitGasfullTransferOptions } from '../types';

import {
  activitiesFromBackendRows,
  activitiesFromSocketMessage,
  backendRowsOf,
  fixtures,
  socketMessage,
  visible,
  wallet2,
} from '../../../tests/helpers/swapReconcilerFixtures';
import { projectSwapActivities } from '../common/activities/swapReconciler';
import { fetchSwaps, initSwap, swapCexSubmit, swapEstimate } from './swap';

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

jest.mock('../common/cache', () => ({
  getBackendConfigCache: jest.fn(),
}));

jest.mock('../common/swap', () => ({
  ...jest.requireActual('../common/swap'),
  getSwapItemSlug: jest.fn(),
  patchSwapItem: jest.fn(),
  swapGetHistoryItem: jest.fn(),
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
const { getStoredBackendAuthToken } = require('./other') as { getStoredBackendAuthToken: jest.Mock };

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getSwapItemSlug, patchSwapItem, swapGetHistoryItem } = require('../common/swap') as {
  getSwapItemSlug: jest.Mock;
  patchSwapItem: jest.Mock;
  swapGetHistoryItem: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { callBackendPost } = require('../common/backend') as { callBackendPost: jest.Mock };

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getBackendConfigCache } = require('../common/cache') as { getBackendConfigCache: jest.Mock };

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { publishSignedMfaRequest } = require('./mfa') as {
  publishSignedMfaRequest: jest.Mock;
};

describe('swap estimate hints', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredAccount.mockResolvedValue({ byChain: { ethereum: { address: '0xwallet' } } });
    getBackendConfigCache.mockResolvedValue({ swapVersion: 2 });
    getSwapItemSlug.mockReturnValue('sol');
  });

  it.each([
    { type: 'external', providerName: '1inch', url: 'https://example.com/swap?from=eth&to=usdc' },
  ])('passes through error hints without requiring a TON wallet: $type', async (hint) => {
    const response = { error: 'Pair not found', hint };
    const request = { from: 'eth', to: 'ethereum-usdc', fromAmount: '0.1' };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', request)).toBe(response);
    expect(callBackendPost).toHaveBeenCalledWith('/swap/estimate', {
      ...request, swapVersion: 2, walletVersion: undefined,
    }, { isAllowBadRequest: true });
    expect(fetchStoredWallet).not.toHaveBeenCalled();
  });

  it.each([
    { error: 'Pair not found' },
    { route: 'dex', from: 'TON', to: 'USD₮', fromAmount: '1', toAmount: '5' },
    { route: 'cex', from: 'eth', to: 'sol', fromAmount: '1', toAmount: '5', fromMin: '0.1' },
  ])('normalizes intermediate hints in SDK responses for every client: %p', async (estimate) => {
    const response = { ...estimate, hint: { type: 'intermediate', token: 'solana:native' } };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', { from: 'eth', to: 'sol', fromAmount: '1' })).toEqual({
      ...estimate, hint: { type: 'intermediate', token: 'sol' },
    });
    expect(getSwapItemSlug).toHaveBeenCalledWith('solana:native');
    expect(response.hint.token).toBe('solana:native');
    expect(fetchStoredWallet).not.toHaveBeenCalled();
  });

  it('preserves the TON wallet version and an ordinary estimate response', async () => {
    fetchStoredAccount.mockResolvedValue({ byChain: { ton: { version: 'W5' } } });
    const response = { route: 'dex', from: 'TON', to: 'USD₮', fromAmount: '1', toAmount: '5' };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', { from: 'TON', to: 'USD₮', fromAmount: '1' })).toBe(response);
    expect(callBackendPost).toHaveBeenCalledWith('/swap/estimate', expect.objectContaining({
      walletVersion: 'W5',
    }), { isAllowBadRequest: true });
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
    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'EQ-ton-history-owner',
      authToken: 'backend-auth-token',
      msgHash: '0xbase-deposit',
      msgHashNormalized: '0xbase-deposit',
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

    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      msgHash: '0xbase-cex-hash',
      msgHashNormalized: '0xbase-deposit',
    }));
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

  it('shows the swap row with the submitted hash as soon as the deposit is sent', async () => {
    const onUpdate = jest.fn();
    initSwap(onUpdate);
    const row = fixtures.nearIntentsBackend.swapRowVersions[0];
    patchSwapItem.mockResolvedValue(row);

    await swapCexSubmit('base' as ApiChain, {
      accountId: '0-mainnet', enclaveToken: 'enclave-token', toAddress: '0xdeposit', amount: 1n, fee: 1n,
    } as unknown as ApiSubmitGasfullTransferOptions, row.id);

    expect(onUpdate).toHaveBeenCalledWith({
      type: 'newActivities',
      accountId: '0-mainnet',
      activities: [expect.objectContaining({
        id: `${row.id}::backend-swap`,
        status: 'pendingTrusted',
        hashes: ['0xbase-deposit'],
      })],
    });
  });
});

describe('fetchSwaps', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredWallet.mockResolvedValue({ address: wallet2.wallet });
    fetchStoredAccount.mockResolvedValue({ type: 'bip39', byChain: { ton: { address: wallet2.wallet } } });
    getStoredBackendAuthToken.mockResolvedValue('backend-auth-token');
  });

  it('hides the sources of the refreshed row and leaves rows hidden under other swaps untouched', async () => {
    const [pending, completed] = ['pending', 'completed'].map((status) => {
      return fixtures.nearIntentsBackend.swapRowVersions.find((row) => row.status === status)!;
    });
    swapGetHistoryItem.mockResolvedValue(completed);
    const [pendingRow] = activitiesFromBackendRows([pending]);
    const [deposit] = activitiesFromSocketMessage(socketMessage(fixtures.nearIntentsWsActions, 'finalized'), wallet2);
    const [foreignRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const foreignChainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const foreignHiddenLeg = projectSwapActivities(foreignChainRows, [foreignRow], { fromTime: 0, toTime: Infinity })
      .find(({ shouldHide }) => shouldHide)!;

    const result = await fetchSwaps(
      '0-mainnet',
      [{ id: '2545651', chain: 'ton' }],
      [pendingRow, deposit, foreignHiddenLeg],
      { forceProviderRefresh: true },
    );

    expect(swapGetHistoryItem).toHaveBeenCalledWith(wallet2.wallet, '2545651', expect.objectContaining({
      forceProviderRefresh: true,
      authToken: 'backend-auth-token',
    }));
    expect(result.patch.upsert.map(({ id, status, shouldHide }) => [id, status, shouldHide]).sort()).toEqual([
      ['2545651::backend-swap', 'completed', undefined],
      [deposit.id, 'completed', true],
    ].sort());
    expect(visible(result.patch.upsert).map(({ id }) => id)).toEqual(['2545651::backend-swap']);
  });
});
