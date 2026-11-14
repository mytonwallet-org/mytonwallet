import { beforeEach, expect, jest, test } from '@jest/globals';
import { Interface, Transaction, Wallet, zeroPadValue } from 'ethers';

import type { ApiChain } from '../../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferOptions,
} from '../../../types/swap';
import type { VtPlan } from './types';
import { EvmSmartAccountError } from '../../../types';

import { getEvmProvider } from '../util/client';
import { callBackendPost } from '../../../common/backend';
import { patchSwapItem } from '../../../common/swap';
import { rememberSwapExecutionQuote } from '../../../common/swapExecutionQuote';
import { storage } from '../../../storages';
import { getSignerFromPrivateKey } from '../auth';
import { estimateBatchUserOpFee, submitBatchUserOp } from '../smartAccount/batch';
import arc from './fixtures/arc.json';
import taxi from './fixtures/taxi.json';
import deployments from './deployments.json';
import { buildVtTransfer, submitVtTransfer } from './driver';

jest.mock('../../../storages', () => {
  const store = { getItem: jest.fn(), setItem: jest.fn() };
  return { storage: store, getCurrentStorage: () => store };
});
jest.mock('../../../common/backend', () => ({ callBackendPost: jest.fn() }));
jest.mock('../../../common/swap', () => ({
  ...jest.requireActual<typeof import('../../../common/swap')>('../../../common/swap'), patchSwapItem: jest.fn(),
}));
jest.mock('../../../common/accounts', () => ({ fetchStoredChainAccount: () => ({ type: 'bip39' }) }));
jest.mock('../util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('../smartAccount/batch', () => ({ estimateBatchUserOpFee: jest.fn(), submitBatchUserOp: jest.fn() }));
jest.mock('../auth', () => ({
  fetchPrivateKeyString: () => 'test-only',
  getSignerFromPrivateKey: jest.fn(),
}));
jest.mock('../util/account', () => ({ fetchEvmWallet: () => ({ address: mockOwner }) }));
jest.mock('../../../../util/tokens', () => ({
  findNativeToken: (chain: string) => ({ slug: `${chain}-native`, decimals: 18 }),
  getChainBySlug: (slug: string) => slug.split('-')[0],
}));
jest.mock('../../../common/tokens', () => {
  const tokens = {
    'base-usdc': {
      slug: 'base-usdc', chain: 'base', decimals: 6,
      tokenAddress: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    },
    'arbitrum-usdc': {
      slug: 'arbitrum-usdc', chain: 'arbitrum', decimals: 6,
      tokenAddress: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    },
    'arc-native': { slug: 'arc-native', chain: 'arc', decimals: 18, tokenAddress: undefined },
  };
  return {
    getTokenBySlug: (slug: keyof typeof tokens) => tokens[slug],
    getTokenByAddress: (address: string, chain?: string) => Object.values(tokens).find((token) => (
      token.tokenAddress?.toLowerCase() === address.toLowerCase() && (!chain || token.chain === chain)
    )),
  };
});

const WALLET = new Wallet('0x' + '01'.padStart(64, '0'));
const mockOwner = WALLET.address;
const WRAPPER = new Interface([
  'function execute((address target,uint256 value,bytes data)[] calls,bytes32 quoteId)',
]);
const DELEGATE = new Interface([
  'function delegateTransferFrom(address token,address from,address to,uint256 amount)',
]);
const SEND = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function send((uint32 dstEid,bytes32 to,uint256 amountLD,uint256 minAmountLD,bytes extraOptions,bytes composeMsg,bytes oftCmd) param,(uint256 nativeFee,uint256 lzTokenFee) fee,address refundAddress)',
]);
const TOKEN = new Interface([
  'function approve(address spender,uint256 amount)',
  'function allowance(address owner,address spender) view returns(uint256)',
]);

function buildPlan(): VtPlan {
  const quote = JSON.parse(JSON.stringify(taxi)) as VtPlan['quote'];
  for (const step of quote.userSteps) {
    step.signerAddress = mockOwner;
    step.transaction!.encoded.from = mockOwner;
  }
  const transaction = quote.userSteps[1].transaction!.encoded;
  const [decoded, id] = WRAPPER.decodeFunctionData('execute', transaction.data);
  const calls = decoded.map((call: { target: string; value: bigint; data: string }) => ({
    target: call.target,
    value: call.value,
    data: call.data,
  }));
  const pull = DELEGATE.decodeFunctionData('delegateTransferFrom', calls[0].data);
  calls[0].data = DELEGATE.encodeFunctionData('delegateTransferFrom', [pull[0], mockOwner, pull[2], pull[3]]);
  const [param, fee, refund] = SEND.decodeFunctionData('send', calls[2].data);
  calls[2].data = SEND.encodeFunctionData('send', [
    [param[0], zeroPadValue(mockOwner, 32), ...Array.from(param).slice(2)],
    fee,
    refund,
  ]);
  const sweep = new Interface(['function sweep(address[] tokens,address recipient)']);
  const [tokens] = sweep.decodeFunctionData('sweep', calls[3].data);
  calls[3].data = sweep.encodeFunctionData('sweep', [tokens, mockOwner]);
  transaction.data = WRAPPER.encodeFunctionData('execute', [calls, id]);
  return {

    provider: 'layerzero',
    quote,
    expiresAt: Date.now() + 60000,
  };
}

const BUILD = {
  accountId: 'account',
  swapId: '123',
  enclaveToken: 'test',
  authToken: 'test',
  request: {
    from: taxi.userSteps[0].transaction.encoded.to,
    to: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    fromAddress: mockOwner,
    toAddress: mockOwner,
    fromAmount: '100',
    toMinAmount: '98.939906',
    ourFee: '0',
    networkFee: '0.001',
    dexRouterLabel: 'layerzero',
  },
} as ApiBuildOnchainSwapTransferOptions;
let journal: unknown;
let allowance: bigint;
let nonce: number;
let transactions: Map<string, Transaction>;
const broadcast = jest.fn<(raw: string) => Promise<void>>();
const receipt = jest.fn<(hash: string) => Promise<{ status: number }>>();
const onUpdate = jest.fn();

beforeEach(() => {
  jest.clearAllMocks();
  rememberQuote(BUILD.request);
  journal = undefined;
  allowance = 1n;
  nonce = 0;
  transactions = new Map();
  jest
    .mocked(storage.getItem)
    .mockImplementation(() => Promise.resolve(journal ? JSON.parse(JSON.stringify(journal)) : undefined));
  jest.mocked(storage.setItem).mockImplementation((_key, value) => {
    journal = value;
    return Promise.resolve();
  });
  jest.mocked(getSignerFromPrivateKey).mockReturnValue({
    connect: () => ({
      populateTransaction: (transaction: object) => Promise.resolve({ ...transaction, nonce: nonce++, type: 0 }),
      signTransaction: WALLET.signTransaction.bind(WALLET),
    }),
  } as unknown as ReturnType<typeof getSignerFromPrivateKey>);
  broadcast.mockImplementation((raw) => {
    const tx = Transaction.from(raw);
    transactions.set(tx.hash!, tx);
    return Promise.resolve();
  });
  receipt.mockImplementation((hash) => {
    const tx = transactions.get(hash)!;
    allowance = TOKEN.decodeFunctionData('approve', tx.data)[1] as bigint;
    return Promise.resolve({ status: 1 });
  });
  jest.mocked(getEvmProvider).mockReturnValue({
    getCode: (address: string) => {
      const isWrapper = Object.values(deployments.chains).some((config) => config.wrapper === address);
      return Promise.resolve(isWrapper ? '0x01' : '0x02');
    },
    estimateGas: () => Promise.resolve(30000n),
    getFeeData: () => Promise.resolve({ gasPrice: 1n }),
    call: () => Promise.resolve(TOKEN.encodeFunctionResult('allowance', [allowance])),
    getTransaction: (hash: string) => Promise.resolve(transactions.get(hash)),
    broadcastTransaction: broadcast,
    waitForTransaction: receipt,
  } as unknown as ReturnType<typeof getEvmProvider>);
  jest.mocked(callBackendPost).mockResolvedValue(buildPlan());
  // No batch support unless a test grants it: the separate-transaction path stays the default
  jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ error: 'BundlerNotConfigured' } as never);
});

// A local deployment manifest is trusted release input; changing it here isolates journal behavior
jest.mock('./deployments.json', () => {
  const { keccak256 } = jest.requireActual<typeof import('ethers')>('ethers');
  const config = jest.requireActual<typeof deployments>('./deployments.json');
  return {
    ...config,
    chains: Object.fromEntries(Object.entries(config.chains).map(([chain, entry]) => [chain, {
      ...entry, wrapperCodeHash: keccak256('0x01'), delegateCodeHash: keccak256('0x02'),
    }])),
  };
});

function buildSubmit(): ApiSubmitOnchainSwapTransferOptions {
  return {
    accountId: 'account',
    swapId: '123',
    enclaveToken: 'test',
    authToken: 'test',
    transaction: JSON.stringify(buildPlan()),
    localSwap: { id: 'local', hashes: [], status: 'pendingTrusted' },
  } as unknown as ApiSubmitOnchainSwapTransferOptions;
}

test('resets an existing allowance, approves only the exact amount and refreshes after receipts', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect('error' in result).toBe(false);
  expect(broadcast).toHaveBeenCalledTimes(3);
  expect(receipt).toHaveBeenCalledTimes(2);
  const approved = [...transactions.values()].filter(
    (tx) => tx.to?.toLowerCase() === BUILD.request.from.toLowerCase(),
  );
  expect(approved.map((tx) => String(TOKEN.decodeFunctionData('approve', tx.data)[1]))).toEqual([
    '0',
    '100000000',
  ]);
  expect(callBackendPost).toHaveBeenCalledTimes(1);
  expect(patchSwapItem).toHaveBeenCalledWith(
    expect.objectContaining({ msgHash: [...transactions.keys()][2] }),
  );
});

test('a lost bridge broadcast response reports the signed bridge pending instead of an error to retry', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  broadcast.mockImplementation((raw) => {
    const tx = Transaction.from(raw);
    transactions.set(tx.hash!, tx);
    if (tx.to?.toLowerCase() === deployments.chains.base.wrapper.toLowerCase()) {
      return Promise.reject(new Error('Response lost'));
    }
    return Promise.resolve();
  });
  const first = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  const bridgeHash = [...transactions.keys()][2];
  expect(first).toEqual({ activityId: 'local', submittedHashes: [bridgeHash] });
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect(result).toEqual({ activityId: 'local', submittedHashes: [bridgeHash] });
  expect(transactions.size).toBe(3);
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

test('parallel builds preserve both execution journals', async () => {
  await Promise.all(
    ['123', '124'].map((swapId) =>
      buildVtTransfer('base', 'mainnet', {
        ...BUILD,
        swapId,
        transaction: JSON.stringify(buildPlan()),
      }),
    ),
  );
  expect(Object.keys(journal as Record<string, unknown>).sort()).toEqual(['account:123', 'account:124']);
});

test('binds native Arc USDC to six-decimal CCTP without treating it as native VT input', async () => {
  const quote = JSON.parse(JSON.stringify(arc)) as VtPlan['quote'];
  const original = '0x0000000000000000000000000000000000000001';
  for (const step of quote.userSteps) {
    step.signerAddress = mockOwner;
    step.transaction!.encoded.from = mockOwner;
    step.transaction!.encoded.data = step.transaction!.encoded.data.replaceAll(
      zeroPadValue(original, 32).slice(2), zeroPadValue(mockOwner, 32).slice(2),
    );
  }
  const plan: VtPlan = {
    provider: 'layerzero', quote, expiresAt: Date.now() + 60000,
  };
  const request = {
    ...BUILD.request, from: 'arc:native', to: 'base:0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    fromAmount: '99.12', ourFee: '0', toMinAmount: '98',
  };
  rememberQuote(request, '0.004', 'arc');
  const result = await buildVtTransfer('arc', 'mainnet', {
    ...BUILD, transaction: JSON.stringify(plan), request,
  });
  expect(result.id).toBe('123');
  expect(journal).toEqual(expect.objectContaining({
    'account:123': expect.objectContaining({ intent: expect.objectContaining({
      sourceToken: '0x3600000000000000000000000000000000000000', sourceDecimals: 6,
      amount: '99120000', feeAmount: '0',
    }) }),
  }));
});

test('a changed refresh minimum never sends the bridge after approval', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  const changed = buildPlan();
  changed.quote.dstAmountMin = '1';
  jest.mocked(callBackendPost).mockResolvedValue(changed);
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect(result).toEqual({ error: 'VT minimum output changed' });
  expect(broadcast).toHaveBeenCalledTimes(2);
  expect(patchSwapItem).not.toHaveBeenCalled();
});

test('holds a separate bounded execution ceiling instead of using the displayed estimate as a cap', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  expect(journal).toEqual(expect.objectContaining({ 'account:123': expect.objectContaining({
    intent: expect.objectContaining({ nativeFeeBudget: '4000000000000000' }),
  }) }));
  const request = { ...BUILD.request, networkFee: '0.002' };
  rememberQuote(request, '1');
  await expect(buildVtTransfer('base', 'mainnet', {
    ...BUILD, swapId: 'bad-budget', transaction: JSON.stringify(buildPlan()),
    request,
  })).rejects.toThrow('Invalid VT execution fee budget');
});

function rememberQuote(
  request: ApiBuildOnchainSwapTransferOptions['request'], budget = '0.004', chain: ApiChain = 'base',
) {
  return rememberSwapExecutionQuote('account', { ...request, swapVersion: undefined }, {
    route: 'dex', chain,
    from: request.from, to: request.to,
    fromAmount: request.fromAmount, toAmount: '99', toMinAmount: request.toMinAmount!,
    dexRouterLabel: 'layerzero', networkFee: request.networkFee!, realNetworkFee: request.networkFee!,
    vtNativeFeeBudget: budget, ourFee: request.ourFee!, ourFeePercent: 0,
    swapFee: '0', swapFeePercent: 0, impact: 0, slippage: 1, dieselStatus: 'not-available',
  });
}

test('batches the allowance reset, exact approval and bridge into one account transaction', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ maxCost: 1000n });
  jest.mocked(submitBatchUserOp).mockResolvedValue({ txHash: '0xbatch', userOpHash: '0xop', success: true });
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect(result).toEqual({ activityId: 'local', submittedHashes: ['0xbatch'] });
  expect(broadcast).not.toHaveBeenCalled();
  const calls = jest.mocked(submitBatchUserOp).mock.calls[0][4];
  expect(calls.slice(0, 2).map((call) => String(TOKEN.decodeFunctionData('approve', call.data!)[1])))
    .toEqual(['0', '100000000']);
  expect(calls[2].to).toBe(deployments.chains.base.wrapper);
  expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({ msgHash: '0xbatch' }));
  // The batched swap is final: submitting it again never signs a second bridge
  expect(await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate))
    .toEqual({ activityId: 'local', submittedHashes: ['0xbatch'] });
  expect(submitBatchUserOp).toHaveBeenCalledTimes(1);
});

test('uses separate transactions when the batch exceeds the confirmed fee budget', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ maxCost: 10n ** 30n });
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect('error' in result).toBe(false);
  expect(submitBatchUserOp).not.toHaveBeenCalled();
  expect(broadcast).toHaveBeenCalledTimes(3);
});

test('signs the batch only within the fee budget left after the estimate', async () => {
  await buildVtTransfer('base', 'mainnet', { ...BUILD, transaction: JSON.stringify(buildPlan()) });
  jest.mocked(estimateBatchUserOpFee).mockResolvedValue({ maxCost: 1000n });
  jest.mocked(submitBatchUserOp).mockResolvedValue({ error: EvmSmartAccountError.UserOperationMismatch });
  const result = await submitVtTransfer('base', 'mainnet', buildSubmit(), 'history', onUpdate);
  expect(result).toEqual({ error: 'VT fee increased; a fresh confirmation is required' });
  const { maxCostLimit } = jest.mocked(submitBatchUserOp).mock.calls[0][5]!;
  expect(maxCostLimit).toBeGreaterThanOrEqual(1000n);
  expect(broadcast).not.toHaveBeenCalled();
});
