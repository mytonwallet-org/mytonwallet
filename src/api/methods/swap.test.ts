import type { ApiChain, ApiSubmitGasfullTransferOptions, ApiSwapHistoryItem } from '../types';

import { ARBITRUM_USDC_MAINNET, BASE_USDC_MAINNET, TON_USDT_MAINNET } from '../../config';
import { buildLocalTxId } from '../../util/activities';
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
import { setEnvironment } from '../environment';
import { ApiServerError } from '../errors';
import {
  fetchSwaps, initSwap, swapBuildTransfer, swapCexCreateTransaction, swapCexSubmit,
  swapEstimate, swapGetPairs, swapSubmit,
} from './swap';

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    base: {
      buildOnchainSwapTransfer: jest.fn().mockResolvedValue({ id: 'vt-swap', chain: 'base' }),
      submitGasfullTransfer: jest.fn().mockResolvedValue({ txId: '0xbase-deposit' }),
      resolveSwapNeedsBatch: jest.fn((_accountId: string, needsApprove?: boolean) => !!needsApprove),
      estimateSwapDiesel: jest.fn(),
    },
    ton: {
      resolveSwapNeedsBatch: jest.fn((_accountId: string, needsApprove?: boolean) => !!needsApprove),
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
  registerMfaConfirmationHandler: jest.fn(),
}));

jest.mock('./other', () => ({
  getBackendAuthToken: jest.fn().mockResolvedValue('backend-auth-token'),
  getStoredBackendAuthToken: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as {
  base: {
    buildOnchainSwapTransfer: jest.Mock;
    submitGasfullTransfer: jest.Mock;
    resolveSwapNeedsBatch: jest.Mock;
    estimateSwapDiesel: jest.Mock;
  };
  ton: { submitOnchainSwapTransfer: jest.Mock; resolveSwapNeedsBatch: jest.Mock };
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
const { callBackendGet, callBackendPost } = require('../common/backend') as {
  callBackendGet: jest.Mock; callBackendPost: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getBackendConfigCache } = require('../common/cache') as { getBackendConfigCache: jest.Mock };

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { publishSignedMfaRequest, registerMfaConfirmationHandler } = require('./mfa') as {
  publishSignedMfaRequest: jest.Mock;
  registerMfaConfirmationHandler: jest.Mock;
};

describe('swap estimate hints', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredAccount.mockResolvedValue({ byChain: { ethereum: { address: '0xwallet' } } });
    getBackendConfigCache.mockResolvedValue({ swapVersion: 2 });
    getSwapItemSlug.mockReturnValue('sol');
  });

  it.each([
    'Swap routers are unavailable',
    'Exchange providers are unavailable',
  ])('returns an expected outage for clients to display: %s', async (message) => {
    callBackendPost.mockRejectedValueOnce(new ApiServerError(message, 503));

    await expect(swapEstimate('account', { from: 'eth', to: 'wct', fromAmount: '3' }))
      .resolves.toEqual({ error: 'Swap routers are unavailable' });
  });

  it('hands a request the backend validator rejected to clients as a refusal', async () => {
    callBackendPost.mockResolvedValueOnce({
      errors: [{ value: '0', msg: 'Invalid value', param: 'fromAmount', location: 'body' }],
    });

    await expect(swapEstimate('account', { from: 'sol', to: 'usdc', fromAmount: '0' }))
      .resolves.toEqual({ error: 'Invalid value' });
  });

  it.each([
    new ApiServerError('Unexpected error', 500),
    new ApiServerError('Unknown service failure', 503),
    new Error('Invalid quote payload'),
  ])('does not disguise an unknown failure as an unavailable quote: %s', async (error) => {
    callBackendPost.mockRejectedValueOnce(error);

    await expect(swapEstimate('account', { from: 'eth', to: 'wct', fromAmount: '3' })).rejects.toBe(error);
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
    }, { isAllowBadRequest: true, onHeaders: expect.any(Function) });
    expect(fetchStoredWallet).not.toHaveBeenCalled();
  });

  it.each([
    { error: 'Pair not found' },
    { route: 'dex', from: 'TON', to: 'USD₮', fromAmount: '1', toAmount: '5' },
    { route: 'cex', from: 'eth', to: 'sol', fromAmount: '1', toAmount: '5', fromMin: '0.1' },
  ])('normalizes intermediate hints in SDK responses for every client: %p', async (estimate) => {
    const response = { ...estimate, hint: { type: 'intermediate', token: 'solana:native' } };
    callBackendPost.mockResolvedValue(response);

    const result = await swapEstimate('account-mainnet', { from: 'eth', to: 'sol', fromAmount: '1' });
    expect(result).toEqual({
      ...estimate,
      hint: { type: 'intermediate', token: 'sol' },
      ...('route' in estimate && estimate.route === 'dex' ? { needsBatch: false } : undefined),
    });
    expect(getSwapItemSlug).toHaveBeenCalledWith('solana:native');
    expect(response.hint.token).toBe('solana:native');
    expect(fetchStoredWallet).not.toHaveBeenCalled();
  });

  it('preserves the TON wallet version and an ordinary estimate response', async () => {
    fetchStoredAccount.mockResolvedValue({ byChain: { ton: { version: 'W5' } } });
    const response = { route: 'dex', from: 'TON', to: 'USD₮', fromAmount: '1', toAmount: '5' };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', { from: 'TON', to: 'USD₮', fromAmount: '1' })).toEqual({
      ...response,
      needsBatch: false,
    });
    expect(callBackendPost).toHaveBeenCalledWith('/swap/estimate', expect.objectContaining({
      walletVersion: 'W5',
    }), { isAllowBadRequest: true, onHeaders: expect.any(Function) });
  });

  it('sets dex needsBatch from the chain sdk', async () => {
    const resolveSwapNeedsBatch = chains.base.resolveSwapNeedsBatch;
    resolveSwapNeedsBatch.mockResolvedValueOnce(true);
    const response = {
      route: 'dex' as const,
      chain: 'base' as const,
      from: 'eth',
      to: 'usdc',
      fromAmount: '1',
      toAmount: '5',
      needsApprove: false,
    };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', { from: 'eth', to: 'usdc', fromAmount: '1' })).toEqual({
      ...response,
      needsBatch: true,
    });
    expect(resolveSwapNeedsBatch).toHaveBeenCalledWith('account-mainnet', false);
  });

  describe('diesel', () => {
    const response = {
      route: 'dex' as const,
      chain: 'base' as const,
      from: `base:${BASE_USDC_MAINNET.tokenAddress}`,
      to: 'base:native',
      fromAmount: '1',
      toAmount: '0.0003',
      dieselStatus: 'not-available' as const,
      networkFee: '0.001',
    };

    beforeEach(() => {
      getSwapItemSlug.mockReturnValue(BASE_USDC_MAINNET.slug);
    });

    it('fills the diesel of a quote whose native fee the wallet cannot pay', async () => {
      chains.base.estimateSwapDiesel.mockResolvedValueOnce({
        status: 'available', amount: 15_582n, nativeAmount: 0n, remainingFee: 0n, realFee: 10_388n,
      });
      callBackendPost.mockResolvedValue(response);

      expect(await swapEstimate('account-mainnet', { from: response.from, to: response.to, fromAmount: '1' }))
        .toEqual({ ...response, needsBatch: false, dieselStatus: 'available', dieselFee: '0.015582' });
      expect(getSwapItemSlug).toHaveBeenCalledWith(response.from, 'base');
      expect(chains.base.estimateSwapDiesel).toHaveBeenCalledWith(
        'account-mainnet', BASE_USDC_MAINNET.tokenAddress, 10n ** 15n,
      );
    });

    it('keeps the quote gasfull when the chain has no diesel for it', async () => {
      chains.base.estimateSwapDiesel.mockResolvedValueOnce({
        status: 'not-available', nativeAmount: 0n, remainingFee: 0n, realFee: 0n,
      });
      callBackendPost.mockResolvedValue(response);

      expect(await swapEstimate('account-mainnet', { from: response.from, to: response.to, fromAmount: '1' }))
        .toEqual({ ...response, needsBatch: false });
    });

    it('keeps the quote gasfull when the diesel quote fails', async () => {
      chains.base.estimateSwapDiesel.mockRejectedValueOnce(new Error('RPC unavailable'));
      callBackendPost.mockResolvedValue(response);

      expect(await swapEstimate('account-mainnet', { from: response.from, to: response.to, fromAmount: '1' }))
        .toEqual({ ...response, needsBatch: false });
    });

    it('keeps the diesel the backend quoted', async () => {
      const quoted = { ...response, dieselStatus: 'available' as const, dieselFee: '0.02' };
      callBackendPost.mockResolvedValue(quoted);

      expect(await swapEstimate('account-mainnet', { from: response.from, to: response.to, fromAmount: '1' }))
        .toEqual({ ...quoted, needsBatch: false });
      expect(chains.base.estimateSwapDiesel).not.toHaveBeenCalled();
    });
  });

  it('returns below-minimum Changelly limits without retrying or switching to exact out', async () => {
    const response = {
      route: 'cex', cexLabel: 'changelly', from: 'usdt20', to: 'btc',
      fromAmount: '29.786803', toAmount: '0', fromMin: '30.03',
    };
    callBackendPost.mockImplementationOnce((_path, _request, { onHeaders }) => {
      onHeaders(200);
      return Promise.resolve(response);
    });
    const request = { from: 'usdt20', to: 'btc', fromAmount: '29.786803' };

    expect(await swapEstimate('account-mainnet', request)).toBe(response);
    expect(callBackendPost).toHaveBeenCalledTimes(1);
    expect(callBackendPost).toHaveBeenCalledWith('/swap/estimate', expect.objectContaining(request), {
      isAllowBadRequest: true, onHeaders: expect.any(Function),
    });
    expect(callBackendPost.mock.calls[0][1]).not.toHaveProperty('toAmount');
  });

  it.each([false, true])('uses LI.FI approval state for needsBatch (%s)', async (needsApprove) => {
    const resolveSwapNeedsBatch = chains.base.resolveSwapNeedsBatch;
    resolveSwapNeedsBatch.mockResolvedValueOnce(true);
    const response = {
      route: 'dex' as const,
      chain: 'base' as const,
      dexRouterLabel: 'lifi' as const,
      from: 'base:native',
      to: 'base:usdc',
      fromAmount: '1',
      toAmount: '5',
      needsApprove,
    };
    callBackendPost.mockResolvedValue(response);

    expect(await swapEstimate('account-mainnet', { from: 'base:native', to: 'base:usdc', fromAmount: '1' }))
      .toEqual({ ...response, needsBatch: needsApprove });
    expect(resolveSwapNeedsBatch).not.toHaveBeenCalled();
  });
});

describe('swapCexSubmit', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    initSwap(jest.fn());
    patchSwapItem.mockReset();
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

  it.each(['returned error', 'thrown error', 'unpublished MFA request'])(
    'replaces the created activity immediately on %s even when the backend patch fails',
    async (failure) => {
      const onUpdate = jest.fn();
      initSwap(onUpdate);
      const row = fixtures.nearIntentsBackend.swapRowVersions[0];
      callBackendPost.mockResolvedValue({ route: 'cex', swap: row });
      const created = await swapCexCreateTransaction('0-mainnet', 'enclave-token', {
        from: row.from, to: row.to, fromAmount: row.fromAmount, fromAddress: row.fromAddress,
      });
      expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
        activities: [expect.objectContaining({ id: created.activity.id, status: 'pendingTrusted' })],
      }));
      onUpdate.mockClear();
      patchSwapItem.mockRejectedValue(new Error('backend unavailable'));
      if (failure === 'returned error') {
        chains.base.submitGasfullTransfer.mockResolvedValue({ error: 'InsufficientBalance' });
      } else if (failure === 'thrown error') {
        chains.base.submitGasfullTransfer.mockRejectedValue(new Error('submit failed'));
      } else {
        chains.base.submitGasfullTransfer.mockResolvedValue({ mfaRequest: { payload: 'payload' } });
        publishSignedMfaRequest.mockRejectedValue(new Error('submit failed'));
      }
      const submission = swapCexSubmit('base', {
        accountId: '0-mainnet', enclaveToken: 'enclave-token', toAddress: '0xdeposit', amount: 1n, fee: 1n,
      }, row.id);
      if (failure === 'returned error') {
        await expect(submission).resolves.toEqual({ error: 'InsufficientBalance' });
      } else {
        await expect(submission).rejects.toThrow('submit failed');
      }
      expect(onUpdate).toHaveBeenCalledTimes(1);
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'newActivities',
        accountId: '0-mainnet',
        activities: [expect.objectContaining({
          id: created.activity.id,
          status: 'failed',
          cex: expect.objectContaining({ status: 'failed' }),
        })],
      });
      expect(onUpdate.mock.invocationCallOrder[0]).toBeLessThan(patchSwapItem.mock.invocationCallOrder[0]);
    },
  );

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

describe('swapSubmit', () => {
  const historyItem = {
    id: 'swap-id',
    timestamp: 1,
    status: 'pendingTrusted',
    from: 'TON',
    fromAmount: '1',
    to: 'USDT',
    toAmount: '3',
  } as ApiSwapHistoryItem;

  beforeEach(() => {
    jest.clearAllMocks();
    patchSwapItem.mockReset();
    fetchStoredWallet.mockResolvedValue({ address: 'UQ-ton-wallet' });
    publishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request-hash' });
    chains.ton.submitOnchainSwapTransfer.mockResolvedValueOnce({ mfaRequest: { payload: 'payload' } });
  });

  it('shows an MFA swap in the history once the request is confirmed in Telegram', async () => {
    const onUpdate = jest.fn();
    initSwap(onUpdate);

    const result = await swapSubmit('ton', '0-mainnet', 'enclave-token', [], historyItem);

    const localActivityId = buildLocalTxId('swap-id');
    expect(result).toEqual({ activityId: localActivityId, swapId: 'swap-id', mfaRequestHash: 'mfa-request-hash' });
    expect(onUpdate).not.toHaveBeenCalled();

    const [[mfaRequestHash, handleConfirmation]] = registerMfaConfirmationHandler.mock.calls;
    expect(mfaRequestHash).toBe('mfa-request-hash');

    handleConfirmation('confirmed-tx-hash');

    expect(onUpdate).toHaveBeenCalledWith({
      type: 'newLocalActivities',
      accountId: '0-mainnet',
      activities: [expect.objectContaining({
        id: localActivityId,
        kind: 'swap',
        externalMsgHashNorm: 'confirmed-tx-hash',
      })],
    });
  });

  it('closes the backend swap row when the MFA request cannot be published', async () => {
    publishSignedMfaRequest.mockRejectedValue(new Error('publish failed'));

    await expect(swapSubmit('ton', '0-mainnet', 'enclave-token', [], historyItem)).rejects.toThrow('publish failed');

    expect(patchSwapItem).toHaveBeenCalledWith({
      address: 'UQ-ton-wallet',
      swapId: 'swap-id',
      authToken: 'backend-auth-token',
      error: expect.stringContaining('publish failed'),
    });
    expect(registerMfaConfirmationHandler).not.toHaveBeenCalled();
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

describe('SDK-owned execution quote boundary', () => {
  const owner = '0x1111111111111111111111111111111111111111';
  const recipient = '0x2222222222222222222222222222222222222222';
  const request = {
    from: BASE_USDC_MAINNET.tokenAddress, to: ARBITRUM_USDC_MAINNET.tokenAddress,
    fromAddress: owner, toAddress: recipient, fromAmount: '100', slippage: 1,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    getSwapItemSlug.mockImplementation(jest.requireActual('../common/swap').getSwapItemSlug);
    fetchStoredAccount.mockResolvedValue({
      byChain: { base: { address: owner }, arbitrum: { address: recipient } },
    });
    fetchStoredWallet.mockResolvedValue({ version: 'W5' });
    getBackendConfigCache.mockResolvedValue({ swapVersion: 3 });
    callBackendPost.mockImplementation((path: string) => Promise.resolve(path === '/swap/estimate' ? {
      route: 'dex', chain: 'base', dexRouterLabel: 'layerzero',
      from: `base:${BASE_USDC_MAINNET.tokenAddress}`, to: `arbitrum:${ARBITRUM_USDC_MAINNET.tokenAddress}`,
      fromAmount: '100', toAmount: '99', toMinAmount: '98', slippage: 1,
      ourFee: '0', ourFeeMode: 'included', networkFee: '0.001', realNetworkFee: '0.001',
      vtNativeFeeBudget: '0.004', swapFee: '0', swapFeePercent: 0, impact: 0,
    } : { route: 'dex', chain: 'base', id: 'vt-swap', transaction: '{}' }));
  });

  it('uses the existing app contract without selected-slug fields or an estimate handle', async () => {
    const estimate = await swapEstimate('account', { ...request, nativeBalance: '9.007199254740993123' });
    if (!('route' in estimate) || estimate.route !== 'dex') throw new Error('Expected DEX quote');
    expect(estimate).not.toHaveProperty('vtNativeFeeBudget');
    expect(estimate).not.toHaveProperty('estimateId');
    expect(estimate).not.toHaveProperty('ourFeeMode');
    expect(estimate).toMatchObject({
      ourFee: '0',
    });
    await swapBuildTransfer('account', 'enclave', {
      ...request, dexRouterLabel: estimate.dexRouterLabel,
      networkFee: estimate.realNetworkFee, ourFee: estimate.ourFee, toMinAmount: estimate.toMinAmount,
    });
    expect(callBackendPost).toHaveBeenCalledWith('/swap/estimate', {
      from: `base:${BASE_USDC_MAINNET.tokenAddress}`, to: `arbitrum:${ARBITRUM_USDC_MAINNET.tokenAddress}`,
      fromAddress: owner, toAddress: recipient, fromAmount: '100', slippage: 1, swapVersion: 3,
      walletVersion: undefined, historyAddress: undefined, nativeBalance: '9.007199254740993123',
    }, expect.any(Object));
    expect(callBackendPost).toHaveBeenCalledWith('/swap/buildTransaction', {
      from: `base:${BASE_USDC_MAINNET.tokenAddress}`, to: `arbitrum:${ARBITRUM_USDC_MAINNET.tokenAddress}`,
      fromAddress: owner, toAddress: recipient, fromAmount: '100', slippage: 1,
      dexRouterLabel: 'layerzero', networkFee: '0.001', ourFee: '0', toMinAmount: '98',
      vtNativeFeeBudget: '0.004', walletVersion: 'W5', swapVersion: 3, isMsgHashMode: true,
    }, { authToken: 'backend-auth-token' });
    expect(chains.base.buildOnchainSwapTransfer).toHaveBeenCalledWith(expect.objectContaining({
      accountId: 'account', request: expect.objectContaining({
        from: request.from, to: request.to, ourFee: '0',
      }),
    }));
  });

  it('preserves precise client balances, zero and omitted fields in the HTTP body', async () => {
    setEnvironment({});
    const originalFetch = globalThis.fetch;
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true, status: 200, json: () => Promise.resolve({ error: 'Pair not found' }),
    });
    globalThis.fetch = fetchMock;
    try {
      const backend = jest.requireActual<typeof import('../common/backend')>('../common/backend');
      const ton = { from: TON_USDT_MAINNET.tokenAddress, to: 'TON', fromAddress: 'ton-wallet', toAmount: '1.25' };
      const base = { ...request, from: `base:${BASE_USDC_MAINNET.tokenAddress}`, to: 'arbitrum:native' };
      const cases = [
        [{ ...ton, nativeBalance: '0.262988684', toncoinBalance: '0.262988684', shouldTryDiesel: true }],
        [{ ...base, nativeBalance: '9.007199254740993123' }],
        [{ ...base, nativeBalance: '0' }],
        [base],
        // eslint-disable-next-line no-null/no-null
        [{ ...base, nativeBalance: null }, base],
        [{ ...base, fromAddress: undefined, cexLabel: 'changelly' }],
        [{ ...ton, toncoinBalance: '0.262988684', shouldTryDiesel: true }],
      ] as const;

      for (const [input, expected = input] of cases) {
        callBackendPost.mockImplementationOnce(backend.callBackendPost);
        await swapEstimate('account', input as Parameters<typeof swapEstimate>[1]);

        const [url, init] = fetchMock.mock.lastCall!;
        expect(new URL(url).pathname).toBe('/swap/estimate');
        expect(init.method).toBe('POST');
        expect(JSON.parse(init.body)).toEqual({ ...JSON.parse(JSON.stringify(expected)), swapVersion: 3 });
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('qualifies discovery by the selected asset without an executor capability argument', async () => {
    await swapGetPairs(BASE_USDC_MAINNET.tokenAddress);
    expect(callBackendGet).toHaveBeenCalledWith('/swap/pairs', { asset: `base:${BASE_USDC_MAINNET.tokenAddress}` });
  });
});
