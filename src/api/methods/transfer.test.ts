import { beginCell } from '@ton/core';

import type {
  ApiBalanceBySlug,
  ApiChain,
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiSubmitTransferOptions,
  ApiUpdateBalances,
  OnApiUpdate,
} from '../types';
import { ApiTransactionError } from '../types';

import { ETH_USDC_MAINNET, ETH_USDT_MAINNET } from '../../config';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAddress } from '../common/accounts';
import { applyPendingBalances, clearPendingBalances } from '../common/pendingBalances';
import { checkTransactionDraft, initTransfer, submitTransfer } from './transfer';

const mockPublishSignedMfaRequest = jest.fn();
const mockRegisterMfaConfirmationHandler = jest.fn();

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: {
      checkTransactionDraft: jest.fn(),
      submitGasfullTransfer: jest.fn(),
      normalizeAddress: jest.fn((address: string) => address),
    },
    ethereum: {
      submitGasfullTransfer: jest.fn(),
      submitGaslessTransfer: jest.fn(),
      normalizeAddress: jest.fn((address: string) => address),
    },
    solana: {
      submitGasfullTransfer: jest.fn(),
      normalizeAddress: jest.fn((address: string) => address),
    },
  },
}));
jest.mock('../common/accounts', () => ({
  fetchStoredAddress: jest.fn(),
}));
jest.mock('./optional', () => ({
  requireMfaMethods: () => ({
    publishSignedMfaRequest: mockPublishSignedMfaRequest,
    registerMfaConfirmationHandler: mockRegisterMfaConfirmationHandler,
  }),
}));

const mockedCheckTransactionDraft = jest.mocked(chains.ton.checkTransactionDraft);
const mockedSubmitGasfullTransfer = jest.mocked(chains.ton.submitGasfullTransfer);

const options: ApiCheckTransactionDraftOptions = {
  accountId: '0-mainnet',
  toAddress: 'EQ-test',
  amount: 1n,
};
const transferOptions: ApiSubmitTransferOptions = {
  accountId: '0-mainnet',
  toAddress: 'EQ-test',
  amount: 1n,
};

describe('checkTransactionDraft cancellation isolation', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedCheckTransactionDraft.mockResolvedValue({});
  });

  it('bypasses the shared draft cache and passes the signal to the chain', async () => {
    const controller = new AbortController();

    await checkTransactionDraft('ton', options, controller.signal);
    await checkTransactionDraft('ton', options, controller.signal);

    expect(mockedCheckTransactionDraft).toHaveBeenCalledTimes(2);
    expect(mockedCheckTransactionDraft).toHaveBeenNthCalledWith(1, options, controller.signal);
    expect(mockedCheckTransactionDraft).toHaveBeenNthCalledWith(2, options, controller.signal);
  });

  it('bounds the independent UI draft cache and evicts the least recently used entry', async () => {
    for (let i = 0; i < 65; i++) {
      await checkTransactionDraft('ton', { ...options, toAddress: `EQ-test-${i}` });
    }

    await checkTransactionDraft('ton', { ...options, toAddress: 'EQ-test-0' });

    expect(mockedCheckTransactionDraft).toHaveBeenCalledTimes(66);
  });

  it('keeps an evicted late completion from overwriting a replacement request', async () => {
    const stale = createDeferred<ApiCheckTransactionDraftResult>();
    const current = createDeferred<ApiCheckTransactionDraftResult>();
    let targetRequestCount = 0;
    mockedCheckTransactionDraft.mockImplementation(({ toAddress }) => {
      if (toAddress !== 'EQ-late-key') return Promise.resolve({});
      targetRequestCount += 1;
      return targetRequestCount === 1 ? stale.promise : current.promise;
    });

    const staleRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-key' });
    for (let i = 0; i < 64; i++) {
      await checkTransactionDraft('ton', { ...options, toAddress: `EQ-eviction-${i}` });
    }
    const currentRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-key' });
    stale.resolve({ resolvedAddress: 'EQ-stale' });
    await staleRequest;
    const coalescedRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-key' });
    current.resolve({ resolvedAddress: 'EQ-current' });

    await expect(currentRequest).resolves.toMatchObject({ resolvedAddress: 'EQ-current' });
    await expect(coalescedRequest).resolves.toMatchObject({ resolvedAddress: 'EQ-current' });
    expect(targetRequestCount).toBe(2);
  });

  it('keeps an evicted late rejection from deleting a replacement request', async () => {
    const stale = createDeferred<ApiCheckTransactionDraftResult>();
    const current = createDeferred<ApiCheckTransactionDraftResult>();
    let targetRequestCount = 0;
    mockedCheckTransactionDraft.mockImplementation(({ toAddress }) => {
      if (toAddress !== 'EQ-late-rejection') return Promise.resolve({});
      targetRequestCount += 1;
      return targetRequestCount === 1 ? stale.promise : current.promise;
    });

    const staleRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-rejection' });
    const staleExpectation = expect(staleRequest).rejects.toThrow('Stale failure');
    for (let i = 0; i < 64; i++) {
      await checkTransactionDraft('ton', { ...options, toAddress: `EQ-rejection-eviction-${i}` });
    }
    const currentRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-rejection' });
    stale.reject(new Error('Stale failure'));
    await staleExpectation;
    const coalescedRequest = checkTransactionDraft('ton', { ...options, toAddress: 'EQ-late-rejection' });
    current.resolve({ resolvedAddress: 'EQ-current' });

    await expect(currentRequest).resolves.toMatchObject({ resolvedAddress: 'EQ-current' });
    await expect(coalescedRequest).resolves.toMatchObject({ resolvedAddress: 'EQ-current' });
    expect(targetRequestCount).toBe(2);
  });
});

describe('submitTransfer Telegram Wallet signer mismatch', () => {
  const onUpdate = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    initTransfer(onUpdate);
    jest.mocked(fetchStoredAddress).mockResolvedValue('EQ-from');
  });

  it('emits an account view-mode update when Telegram Wallet signing key changed on-chain', async () => {
    mockedSubmitGasfullTransfer.mockResolvedValue({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });

    await expect(submitTransfer('ton', transferOptions)).resolves.toEqual({
      error: ApiTransactionError.TelegramWalletPublicKeyMismatch,
    });

    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateAccount',
      accountId: '0-mainnet',
      accountType: 'view',
    });
  });

  it('does not emit a view-mode update for unrelated transfer errors', async () => {
    mockedSubmitGasfullTransfer.mockResolvedValue({
      error: ApiTransactionError.InsufficientBalance,
    });

    await expect(submitTransfer('ton', transferOptions)).resolves.toEqual({
      error: ApiTransactionError.InsufficientBalance,
    });

    expect(onUpdate).not.toHaveBeenCalled();
  });
});

describe('submitTransfer pending balances', () => {
  const accountId = 'pending-transfer-mainnet';
  const onUpdate = jest.fn<void, Parameters<OnApiUpdate>>();
  const mockedSubmitEvmTransfer = jest.mocked(chains.ethereum.submitGasfullTransfer);
  const evmOptions: ApiSubmitTransferOptions = {
    accountId,
    toAddress: '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3',
    amount: 100n,
    realFee: 25n,
  };

  function observe(chain: ApiChain, balances: ApiBalanceBySlug) {
    const update: ApiUpdateBalances = { type: 'updateBalances', accountId, chain, balances };
    onUpdate(applyPendingBalances(update));
  }

  function balanceUpdates() {
    return onUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updateBalances');
  }

  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    clearPendingBalances(accountId);
    initTransfer(onUpdate);
    jest.mocked(fetchStoredAddress).mockResolvedValue('0x-from');
    mockedSubmitEvmTransfer.mockResolvedValue({ txId: '0x-tx' });
    jest.mocked(chains.ethereum.normalizeAddress).mockImplementation((address) => address);
  });

  afterEach(() => {
    clearPendingBalances(accountId);
    jest.useRealTimers();
  });

  it('deducts ETH and its local activity fee only after the send succeeds', async () => {
    const tokenSlug = ETH_USDT_MAINNET.slug;
    observe('ethereum', { eth: 1_000n, [tokenSlug]: 500n });
    onUpdate.mockClear();
    const sent = createDeferred<Awaited<ReturnType<typeof chains.ethereum.submitGasfullTransfer>>>();
    mockedSubmitEvmTransfer.mockReturnValue(sent.promise);

    const pendingSubmit = submitTransfer('ethereum', evmOptions);
    await Promise.resolve();
    expect(mockedSubmitEvmTransfer).toHaveBeenCalledTimes(1);
    expect(balanceUpdates()).toEqual([]);
    sent.resolve({ txId: '0x-tx' });
    await pendingSubmit;

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 875n, [tokenSlug]: 500n },
    }]);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newLocalActivities', activities: [expect.objectContaining({ amount: -100n, fee: 25n })],
    }));

    const reconnectedOnUpdate = jest.fn<void, Parameters<OnApiUpdate>>();
    initTransfer(reconnectedOnUpdate);
    onUpdate.mockClear();
    await jest.advanceTimersByTimeAsync(15 * 60_000);
    expect(reconnectedOnUpdate).toHaveBeenCalledWith({
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 1_000n, [tokenSlug]: 500n },
    });
    expect(balanceUpdates()).toEqual([]);
  });

  it('deducts ERC-20 and native fees independently while stale observations keep the pending balance', async () => {
    const { slug, tokenAddress } = ETH_USDT_MAINNET;
    const otherSlug = ETH_USDC_MAINNET.slug;
    observe('ethereum', { eth: 1_000n, [slug]: 500n, [otherSlug]: 700n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', { ...evmOptions, tokenAddress });

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum',
      balances: { eth: 975n, [slug]: 400n, [otherSlug]: 700n },
    }]);
    observe('ethereum', { eth: 1_000n, [slug]: 500n, [otherSlug]: 700n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 975n, [slug]: 400n, [otherSlug]: 700n });

    observe('ethereum', { eth: 1_000n, [slug]: 390n, [otherSlug]: 700n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 975n, [slug]: 390n, [otherSlug]: 700n });
    observe('ethereum', { eth: 1_000n, [slug]: 500n, [otherSlug]: 700n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 975n, [slug]: 500n, [otherSlug]: 700n });
  });

  it('keeps an ETH balance observed before submission returns without deducting it again', async () => {
    observe('ethereum', { eth: 1_000n });
    const sent = createDeferred<Awaited<ReturnType<typeof chains.ethereum.submitGasfullTransfer>>>();
    mockedSubmitEvmTransfer.mockReturnValue(sent.promise);

    const pendingSubmit = submitTransfer('ethereum', evmOptions);
    await Promise.resolve();
    expect(mockedSubmitEvmTransfer).toHaveBeenCalledTimes(1);
    observe('ethereum', { eth: 875n });
    onUpdate.mockClear();
    sent.resolve({ txId: '0x-tx' });
    await pendingSubmit;

    expect(balanceUpdates()).toEqual([]);
    observe('ethereum', { eth: 875n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 875n });
  });

  it.each([false, true])('deducts only the fee when an ERC-20 balance arrives during a send (gasless: %s)', async (
    isGasless,
  ) => {
    const { slug, tokenAddress } = ETH_USDT_MAINNET;
    observe('ethereum', { eth: 1_000n, [slug]: 500n });
    const sent = createDeferred<Awaited<ReturnType<typeof chains.ethereum.submitGasfullTransfer>>>();
    const submit = isGasless ? jest.mocked(chains.ethereum.submitGaslessTransfer) : mockedSubmitEvmTransfer;
    submit.mockReturnValue(sent.promise);

    const pendingSubmit = submitTransfer('ethereum', { ...evmOptions, tokenAddress, isGasless });
    await Promise.resolve();
    expect(submit).toHaveBeenCalledTimes(1);
    observe('ethereum', { eth: 1_000n, [slug]: 400n });
    onUpdate.mockClear();
    sent.resolve({ txId: '0x-tx' });
    await pendingSubmit;

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 975n, [slug]: 400n },
    }]);
    observe('ethereum', { eth: 1_000n, [slug]: 400n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 975n, [slug]: 400n });
  });

  it('keeps a new ETH balance observed before MFA confirmation without deducting it again', async () => {
    const cell = beginCell().endCell();
    mockedSubmitEvmTransfer.mockResolvedValue({
      mfaRequest: { transaction: cell, payload: cell, signature: Buffer.alloc(64) },
    });
    mockPublishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request' });
    observe('ethereum', { eth: 1_000n });

    await submitTransfer('ethereum', evmOptions);
    expect(mockedSubmitEvmTransfer).toHaveBeenCalledTimes(1);
    observe('ethereum', { eth: 875n });
    onUpdate.mockClear();

    const confirm = mockRegisterMfaConfirmationHandler.mock.calls[0][1] as (txHash: string) => void;
    confirm('0x-confirmed');

    expect(balanceUpdates()).toEqual([]);
    observe('ethereum', { eth: 875n });
    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 875n });
  });

  it('uses a zero fee when the local activity has no real fee', async () => {
    observe('ethereum', { eth: 1_000n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', { ...evmOptions, realFee: undefined });

    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 900n });
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newLocalActivities', activities: [expect.objectContaining({ fee: 0n })],
    }));
  });

  it.each([
    { asset: 'ETH', tokenAddress: undefined },
    { asset: 'ERC-20', tokenAddress: ETH_USDT_MAINNET.tokenAddress },
  ])('deducts only the fee for a case-normalized $asset self-transfer', async ({ tokenAddress }) => {
    const { normalizeAddress } = jest.requireActual<typeof import('../chains/evm/address')>('../chains/evm/address');
    jest.mocked(chains.ethereum.normalizeAddress).mockImplementation(normalizeAddress);
    const fromAddress = evmOptions.toAddress.toLowerCase();
    const toAddress = normalizeAddress(fromAddress);
    expect(toAddress).not.toBe(fromAddress);
    jest.mocked(fetchStoredAddress).mockResolvedValue(fromAddress);
    const tokenSlug = ETH_USDT_MAINNET.slug;
    observe('ethereum', { eth: 1_000n, [tokenSlug]: 500n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', { ...evmOptions, toAddress, tokenAddress });

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 975n, [tokenSlug]: 500n },
    }]);
    expect(chains.ethereum.normalizeAddress).toHaveBeenCalledWith(fromAddress, 'mainnet');
    expect(chains.ethereum.normalizeAddress).toHaveBeenCalledWith(toAddress, 'mainnet');
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newLocalActivities', activities: [expect.objectContaining({ amount: -100n, fee: 25n })],
    }));
  });

  it('does not register a debit for a self-transfer with no real fee', async () => {
    jest.mocked(fetchStoredAddress).mockResolvedValue(evmOptions.toAddress);
    observe('ethereum', { eth: 1_000n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', { ...evmOptions, realFee: undefined });
    await jest.advanceTimersByTimeAsync(15 * 60_000);

    expect(balanceUpdates()).toEqual([]);
  });

  it('deducts only the native fee after an ERC-20 self-transfer receives MFA confirmation', async () => {
    const cell = beginCell().endCell();
    mockedSubmitEvmTransfer.mockResolvedValue({
      mfaRequest: { transaction: cell, payload: cell, signature: Buffer.alloc(64) },
    });
    mockPublishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request' });
    jest.mocked(fetchStoredAddress).mockResolvedValue(evmOptions.toAddress);
    const { slug, tokenAddress } = ETH_USDT_MAINNET;
    observe('ethereum', { eth: 1_000n, [slug]: 500n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', { ...evmOptions, tokenAddress });
    expect(balanceUpdates()).toEqual([]);

    const confirm = mockRegisterMfaConfirmationHandler.mock.calls[0][1] as (txHash: string) => void;
    confirm('0x-confirmed');

    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 975n, [slug]: 500n });
  });

  it('registers MFA deductions after confirmation and never when the request is merely published', async () => {
    const cell = beginCell().endCell();
    mockedSubmitEvmTransfer.mockResolvedValue({
      mfaRequest: { transaction: cell, payload: cell, signature: Buffer.alloc(64) },
    });
    mockPublishSignedMfaRequest.mockResolvedValue({ mfaRequestHash: 'mfa-request' });
    observe('ethereum', { eth: 1_000n });
    onUpdate.mockClear();

    await expect(submitTransfer('ethereum', evmOptions)).resolves.toEqual({ mfaRequestHash: 'mfa-request' });
    observe('ethereum', { eth: 1_000n });
    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 1_000n },
    }]);
    expect(mockRegisterMfaConfirmationHandler).toHaveBeenCalledWith('mfa-request', expect.any(Function));

    const confirm = mockRegisterMfaConfirmationHandler.mock.calls[0][1] as (txHash: string) => void;
    confirm('0x-confirmed');

    expect(balanceUpdates().at(-1)?.balances).toEqual({ eth: 875n });
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newLocalActivities', activities: [expect.objectContaining({ fee: 25n })],
    }));
  });

  it('does not register deductions without a transaction ID', async () => {
    mockedSubmitEvmTransfer.mockResolvedValue({});
    observe('ethereum', { eth: 1_000n });
    onUpdate.mockClear();

    await submitTransfer('ethereum', evmOptions);
    observe('ethereum', { eth: 1_000n });
    await jest.advanceTimersByTimeAsync(15 * 60_000);

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 1_000n },
    }]);
  });

  it('does not register deductions after a send error', async () => {
    mockedSubmitEvmTransfer.mockResolvedValue({ error: ApiTransactionError.InsufficientBalance });
    observe('ethereum', { eth: 1_000n });
    onUpdate.mockClear();

    await expect(submitTransfer('ethereum', evmOptions)).resolves.toEqual({
      error: ApiTransactionError.InsufficientBalance,
    });
    observe('ethereum', { eth: 1_000n });
    await jest.advanceTimersByTimeAsync(15 * 60_000);

    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain: 'ethereum', balances: { eth: 1_000n },
    }]);
  });

  it.each(['ton', 'solana'] as const)('keeps %s balances unchanged after transfer and polling', async (chain) => {
    const slug = getNativeToken(chain).slug;
    jest.mocked(chains[chain].submitGasfullTransfer).mockResolvedValue({ txId: 'non-evm-tx' });
    const poll = jest.fn().mockResolvedValue({ [slug]: 1_000n });
    observe(chain, await poll());
    onUpdate.mockClear();

    await submitTransfer(chain, evmOptions);
    observe(chain, await poll());
    await jest.advanceTimersByTimeAsync(15 * 60_000);

    expect(poll).toHaveBeenCalledTimes(2);
    expect(balanceUpdates()).toEqual([{
      type: 'updateBalances', accountId, chain, balances: { [slug]: 1_000n },
    }]);
  });
});

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}
