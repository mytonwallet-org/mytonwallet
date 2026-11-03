import type { ApiPerpsDraftRequest, ApiPerpsOperation, ApiPerpsTradeIntent } from '../types';
import { ApiCommonError, ApiTransactionError } from '../types';

import { ARBITRUM_USDC_MAINNET } from '../../config';
import { Big } from '../../lib/big.js';
import { getChainConfig } from '../../util/chain';
import Deferred from '../../util/Deferred';
import { fetchWithTimeout } from '../../util/fetch';
import depositFixture from '../../../tests/fixtures/perpsDeposit.json';
import { perpsWithdrawalFixture } from '../../../tests/helpers/perpsWithdrawal';
import { chains } from '../chains';
import { fetchStoredChainAccount } from '../common/accounts';
import { getPerpsAssetsFetchedAt } from '../common/perpsAssets';
import {
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsWithdrawMargin,
  perpsBuildWithdrawal,
  perpsEstimateModifyPosition,
  perpsEstimatePosition,
  perpsGetActivities,
  perpsGetAssetChart,
  perpsGetAssets,
  perpsGetPositions,
  perpsWithdrawReleasedMargin,
} from './perps';
import {
  initPerpsTrading,
  perpsAcknowledgeOperation,
  perpsDepositMargin,
  perpsExecuteReviewedOrder,
  perpsGetActivityHistory,
  perpsGetCandles,
  perpsGetFundingRequirements,
  perpsGetLeverageEstimates,
  perpsGetMarketSnapshot,
  perpsGetSnapshot,
  perpsOpenFromBalance,
  perpsPrepareOrder,
  perpsPrepareWithdrawal,
  perpsPreviewOrder,
  perpsReconcileOperation,
  perpsRetryWithdrawal,
  perpsWithdrawMargin,
} from './perpsTrading';

jest.mock('../chains', () => ({ chains: { arbitrum: { getWalletAssets: jest.fn() } } }));
jest.mock('../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../common/perpsAssets', () => ({ getPerpsAssetsFetchedAt: jest.fn() }));
jest.mock('../../util/fetch', () => ({ fetchWithTimeout: jest.fn(), handleFetchErrors: jest.fn() }));
jest.mock('./perps', () => ({
  perpsBuildWithdrawal: jest.fn(),
  perpsEstimateModifyPosition: jest.fn(),
  perpsGetActivities: jest.fn(),
  perpsGetAssets: jest.fn(),
  perpsGetAssetChart: jest.fn(),
  perpsEstimatePosition: jest.fn(),
  perpsGetPositions: jest.fn(),
  executePerpsOpenPosition: jest.fn(),
  executePerpsModifyPosition: jest.fn(),
  executePerpsClosePosition: jest.fn(),
  executePerpsDepositMargin: jest.fn(),
  executePerpsWithdrawMargin: jest.fn(),
  executePerpsOpenFromBalance: jest.fn(),
  perpsWithdrawReleasedMargin: jest.fn(),
}));

const WALLET = depositFixture.permitData.values.from;
const signatureRejection = '[HL_EXCHANGE_ERROR] User or API Wallet '
  + '0x1111111111111111111111111111111111111111 does not exist.';

const asset = {
  id: 'hyperliquid:hl:BTC',
  index: 0,
  name: 'BTC',
  symbol: 'BTC',
  dex: '',
  wireAssetIndex: 0,
  chain: 'hyperliquid',
  provider: 'hyperliquid',
  szDecimals: 5,
  maxLeverage: 40,
  context: { markPx: '100000', prevDayPx: '99000', openInterest: '2.5', funding: '0.0000125' },
};
const position = {
  coin: 'BTC',
  leverage: { type: 'isolated', value: 10 },
  szi: '0.01',
  marginUsed: '110',
  unrealizedPnl: '10',
  entryPx: '99000',
  liquidationPx: '90500',
  positionValue: '1000',
};
const state = (positions: unknown[] = []) => ({
  positionsByChain: {
    hyperliquid: { withdrawable: '100', assetPositions: positions.map((position) => ({ position })) },
  },
});
const hyperliquidLimits = {
  minOpenDepositUsdc: '10.2',
  minIncreaseDepositUsdc: '0.2',
  minPositionMarginUsdc: '10',
};

function assetsResult(assets: unknown[], extra: Record<string, unknown> = {}) {
  return {
    assetsByChain: { hyperliquid: assets },
    sections: [],
    limitsByChain: { hyperliquid: hyperliquidLimits },
    ...extra,
  };
}

const draft = {
  assetId: asset.id,
  side: 'long' as const,
  amount: '50',
  unit: 'currency' as const,
  leverage: 10,
};
let serial = 0;
let account: string;
const onUpdate = jest.fn();

function savedOperation(state: ApiPerpsOperation['state'], id = `saved-${++serial}`): ApiPerpsOperation {
  return { id, accountId: account, assetId: asset.id, kind: 'close', state, stage: 'withdrawal', createdAt: 1 };
}

test.each(['running', 'partial', 'unknown'] as const)(
  'restoring historical receipts cannot unlock a %s operation', async (state) => {
    await perpsReconcileOperation(account, savedOperation(state));
    await perpsReconcileOperation(account, savedOperation('completed'));
    await perpsReconcileOperation(account, savedOperation('failed'));
    const quote = await perpsPrepareOrder(account, draft);
    await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');
    expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  },
);

test('reconciliation keeps a known order unresolved without an upstream request or replay', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, orderId: 123 };
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(fetchWithTimeout).not.toHaveBeenCalled();
  const quote = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
    .rejects.toThrow('PerpsOperationPending');
});

test('explicit acknowledgement preserves an unknown record and permits only a new reviewed order', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, depositTxHash: '0xdeposit' };
  const acknowledged = await perpsAcknowledgeOperation(account, saved);
  expect(acknowledged).toEqual({ ...saved, acknowledgedAt: expect.any(Number) });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(await perpsReconcileOperation(account, saved)).toEqual(acknowledged);
  expect(await perpsExecuteReviewedOrder(account, 'token', 'expired-quote', saved.id)).toEqual(acknowledged);
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xnewdeposit',
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `new-${++serial}`))
    .toMatchObject({ state: 'completed' });
  expect(executePerpsOpenPosition).toHaveBeenCalledTimes(1);
});

test('acknowledged records retain their unknown outcome without backend reconciliation', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, orderId: 123, acknowledgedAt: 100 };
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(await perpsAcknowledgeOperation(account, saved)).toEqual(saved);
});

test('acknowledgement rejects another account and cannot bypass a pending withdrawal', async () => {
  const partial = await perpsReconcileOperation(account, savedOperation('partial'));
  await expect(perpsAcknowledgeOperation(account, partial)).rejects.toThrow('PerpsInvalidOperation');
  await expect(perpsAcknowledgeOperation(account, { ...partial, state: 'unknown' }))
    .rejects.toThrow('PerpsOperationPending');
  const saved = savedOperation('unknown');
  await perpsReconcileOperation(account, saved);
  const other = `${++serial}-mainnet`;
  await expect(perpsAcknowledgeOperation(other, saved)).rejects.toThrow('PerpsInvalidOperation');
  await expect(perpsAcknowledgeOperation(other, { ...saved, accountId: other }))
    .rejects.toThrow('PerpsInvalidOperation');
  const quote = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
    .rejects.toThrow('PerpsOperationPending');
});

test('a stale unknown record cannot acknowledge a running execution', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  const id = `running-${++serial}`;
  let finish: (() => void) | undefined;
  jest.mocked(executePerpsOpenPosition).mockImplementationOnce(() => new Promise((resolve) => {
    finish = () => resolve({ address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xdeposit' });
  }));
  const execution = perpsExecuteReviewedOrder(account, 'token', quote.id, id);
  while (!finish) await Promise.resolve();
  await expect(perpsAcknowledgeOperation(account, savedOperation('unknown', id)))
    .rejects.toThrow('PerpsOperationPending');
  finish();
  const completed = await execution;
  expect(completed.state).toBe('completed');
  expect(completed.acknowledgedAt).toBeUndefined();
});

test('withdrawal authentication failures keep partial recovery available with a new review', async () => {
  const partial = await perpsReconcileOperation(account, savedOperation('partial'));
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsWithdrawReleasedMargin).mockRejectedValueOnce(new Error(ApiCommonError.InvalidPassword));
  expect(await perpsRetryWithdrawal(account, 'expired-token', partial.id)).toMatchObject({
    state: 'partial', stage: 'withdrawal', error: ApiCommonError.InvalidPassword,
  });
  await expect(perpsRetryWithdrawal(account, 'fresh-token', partial.id)).rejects.toThrow('PerpsQuoteExpired');
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsWithdrawReleasedMargin).mockResolvedValueOnce({
    phase: 'completed', withdrawResult: { status: 'ok' },
  } as any);
  expect(await perpsRetryWithdrawal(account, 'fresh-token', partial.id)).toMatchObject({
    state: 'completed', error: undefined,
  });
});

test('a withdrawal timeout after submission stays unknown and cannot be replayed', async () => {
  const partial = await perpsReconcileOperation(account, savedOperation('partial'));
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsWithdrawReleasedMargin).mockImplementationOnce((_a, _t, _amount, onSubmitting) => {
    onSubmitting?.();
    return Promise.reject(new Error('timeout'));
  });
  expect(await perpsRetryWithdrawal(account, 'token', partial.id)).toMatchObject({ state: 'unknown' });
  await expect(perpsPrepareWithdrawal(account, partial.id)).rejects.toThrow('PerpsInvalidOperation');
});

test('finishing a withdrawal preserves the block for another restored operation', async () => {
  const partial = await perpsReconcileOperation(account, savedOperation('partial'));
  await perpsReconcileOperation(account, savedOperation('unknown'));
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsWithdrawReleasedMargin).mockResolvedValueOnce({
    phase: 'completed', withdrawResult: { status: 'ok' },
  } as any);
  await perpsRetryWithdrawal(account, 'token', partial.id);
  const quote = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
    .rejects.toThrow('PerpsOperationPending');
});

test.each([
  ['cross', '110.44', '100400', 'completed'],
  ['cross', '111', '100400', 'completed'],
  ['cross', '110.44', '100600', 'completed'],
  ['isolated', '110.44', '100400', 'completed'],
  ['isolated', '110.0000', '100000', 'completed'],
])('%s collateral %s at price %s yields %s', async (type, marginUsed, markPx, expected) => {
  const current = { ...position, leverage: { ...position.leverage, type } };
  jest.mocked(perpsGetPositions).mockResolvedValue(state([current]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, amount: '120', editing: true });
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...current, marginUsed }]) as any);
  jest.mocked(perpsGetAssets).mockResolvedValue(
    assetsResult([{ ...asset, context: { ...asset.context, markPx } }]) as any,
  );
  jest.mocked(executePerpsModifyPosition).mockResolvedValueOnce({ address: WALLET, rawResponse: {}, status: 'filled' });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `cross-${++serial}`))
    .toMatchObject({ state: expected });
  expect(executePerpsModifyPosition).toHaveBeenCalledTimes(expected === 'completed' ? 1 : 0);
});

test('snapshot forwards locale and returns normalized prices in backend section order', async () => {
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset], {
    sections: [{ id: 'featured', title: 'منتخب', layout: 'largeHorizontal', limit: 1, hasMore: false,
      assets: [{ ...asset, displayName: 'Bitcoin', description: 'Catalogue description', tintColor: '#F7931A' }] }],
  }) as any);
  const snapshot = await perpsGetSnapshot(account, 'fa');
  expect(perpsGetAssets).toHaveBeenCalledWith(undefined, 'fa', undefined);
  expect(snapshot.assetsFetchedAt).toBe(1000);
  expect(snapshot.timestamp).toBeGreaterThan(snapshot.assetsFetchedAt);
  expect(snapshot.marketSections?.[0]).toMatchObject({ id: 'featured', title: 'منتخب', limit: 1 });
  expect(snapshot.marketSections?.[0].assets[0]).toEqual(snapshot.assets[0]);
  expect(snapshot.assets[0].context.percentChange24h).toBeCloseTo(1.010101);
  expect(snapshot.assets[0].displayName).toBe('Bitcoin');
  expect(snapshot.assets[0].tintColor).toBe('#F7931A');
  expect(snapshot.assets[0].description).toBe('Catalogue description');
  expect(snapshot.assets[0].context).toMatchObject({
    openInterestUsd: '250000', fundingPercent: '0.00125', fundingIntervalHours: 1,
  });
});

test('market updates normalize cached catalogue without requesting account positions', async () => {
  const market = await perpsGetMarketSnapshot('en');
  expect(market.assets[0].context.openInterestUsd).toBe('250000');
  expect(market.assetsFetchedAt).toBe(1000);
  expect(market.limits).toEqual(hyperliquidLimits);
  expect(perpsGetAssets).toHaveBeenCalledWith(undefined, 'en', undefined);
  expect(fetchStoredChainAccount).not.toHaveBeenCalled();
  expect(perpsGetPositions).not.toHaveBeenCalled();
});

test('market snapshots retain unsupported markets for browsing with SDK-owned trading availability', async () => {
  const custom = { ...asset, id: 'hyperliquid:xyz:BTC', name: 'xyz:BTC', dex: 'xyz',
    tradingAvailability: { isAvailable: true } };
  const delisted = { ...asset, id: 'hyperliquid:hl:OLD', name: 'OLD', isDelisted: true };
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset, custom, delisted], {
    sections: [{ id: 'markets', title: 'Markets', layout: 'rows', hasMore: false, assets: [asset, custom] }],
  }) as any);
  const market = await perpsGetMarketSnapshot();
  expect(market.assets).toHaveLength(3);
  expect(market.assets[0].tradingAvailability).toEqual({ isAvailable: true });
  expect(market.assets[1].tradingAvailability).toEqual({ isAvailable: true });
  expect(market.assets[2].tradingAvailability).toEqual({ isAvailable: false, reason: 'PerpsTradingUnavailable' });
  expect(market.marketSections?.[0].assets[1].tradingAvailability).toEqual({ isAvailable: true });
  expect(fetchStoredChainAccount).not.toHaveBeenCalled();
});

test.each(['view', 'ledger'] as const)('%s accounts remain browsable with trading unavailable', async (type) => {
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ type, byChain: { arbitrum: { address: WALLET } } } as any);
  const snapshot = await perpsGetSnapshot(account);
  expect(snapshot.tradingAvailability).toEqual({ isAvailable: false, reason: 'PerpsUnsupportedAccount' });
  expect(snapshot.assets[0].tradingAvailability).toEqual({ isAvailable: true });
  await expect(perpsGetFundingRequirements(account, draft)).rejects.toThrow('PerpsUnsupportedAccount');
  await expect(perpsGetLeverageEstimates(account, draft)).rejects.toThrow('PerpsUnsupportedAccount');
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsUnsupportedAccount');
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('review and submission refresh catalogue instead of authorizing a cached price', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  expect(perpsGetAssets).toHaveBeenLastCalledWith(undefined, undefined, { force: true });
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xdeposit',
  });
  await perpsExecuteReviewedOrder(account, 'token', quote.id, `fresh-prices-${++serial}`);
  expect(perpsGetAssets).toHaveBeenCalledTimes(2);
  expect(perpsGetAssets).toHaveBeenLastCalledWith(undefined, undefined, { force: true });
});

beforeEach(() => {
  jest.resetAllMocks();
  initPerpsTrading(onUpdate);
  jest.mocked(perpsBuildWithdrawal).mockResolvedValue({ address: WALLET, withdraw: perpsWithdrawalFixture(WALLET) });
  account = `${++serial}-mainnet`;
  Object.defineProperty(globalThis.crypto, 'randomUUID', {
    value: () => `quote-${++serial}`,
    configurable: true,
  });
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    type: 'mnemonic', byChain: { arbitrum: { address: WALLET } },
  } as any);
  jest.mocked(getPerpsAssetsFetchedAt).mockReturnValue(1000);
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n,
    [getChainConfig('arbitrum').nativeToken.slug]: 1_000_000_000_000_000n,
  });
  jest.mocked(perpsEstimatePosition).mockImplementation((request) => Promise.resolve({
    orderValue: '0', marginRequired: '0',
    size: request.depositAmount !== undefined
      ? Big(request.depositAmount).minus(request.reduceOnly ? 0 : '0.2').mul(request.leverage ?? 10)
        .div(100000).round(5, request.reduceOnly ? Big.roundUp : Big.roundDown).toFixed()
      : '0.01',
    liquidationPrice: '90501',
  }));
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset]) as any);
  jest.mocked(perpsGetPositions).mockResolvedValue(state() as any);
});

test('reviewed execution publishes correlated submission before settlement and immutable final updates', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  let finish!: (result: any) => void;
  let start!: () => void;
  const started = new Promise<void>((resolve) => {
    start = resolve;
  });
  jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onDeposit?.('0xdeposit');
    start();
    return new Promise((resolve) => {
      finish = resolve;
    });
  });
  const id = `background-${++serial}`;
  let settled = false;
  const execution = perpsExecuteReviewedOrder(account, 'token', quote.id, id).then((result) => {
    settled = true;
    return result;
  });
  await started;
  expect(settled).toBe(false);
  expect(onUpdate.mock.calls.map(([update]) => update.operation)).toMatchObject([
    { id, accountId: account, assetId: asset.id, kind: 'open', state: 'running', stage: 'deposit' },
    { id, state: 'running', stage: 'trade', depositTxHash: '0xdeposit' },
  ]);
  finish({ address: WALLET, rawResponse: {}, depositTxHash: '0xdeposit', status: 'filled', oid: 123 });
  const result = await execution;
  expect(onUpdate).toHaveBeenLastCalledWith({ type: 'perpsOperationUpdated', operation: result });
  expect(onUpdate.mock.calls[0][0].operation).toMatchObject({ state: 'running', stage: 'deposit' });
  expect(result).toMatchObject({ state: 'completed', stage: 'finished' });
});

test('pre-submission rejection publishes failure without a submission update', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({ error: ApiCommonError.InvalidPassword });
  const result = await perpsExecuteReviewedOrder(account, 'token', quote.id, `rejected-${++serial}`);
  expect(result.state).toBe('failed');
  expect(onUpdate).toHaveBeenCalledTimes(1);
  expect(onUpdate).toHaveBeenCalledWith({ type: 'perpsOperationUpdated', operation: result });
});

test.each([0n])('zero ETH blocks deposits but permits reductions: %s', async (eth) => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: eth,
  });
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsInsufficientGas');
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, amount: '120' }))
    .rejects.toThrow('PerpsInsufficientGas');
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, amount: '75' }))
    .resolves.toMatchObject({ kind: 'reduce' });
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, close: true }))
    .resolves.toMatchObject({ kind: 'close' });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('funding requirements are available before amount entry and refresh after acquiring funds', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValueOnce({});
  expect(await perpsGetFundingRequirements(account, { ...draft, amount: '' })).toMatchObject({
    requiredUsdc: '10.2', requiredEth: '0.0001', needsUsdc: true, needsEth: true,
  });
  expect(await perpsGetFundingRequirements(account, { ...draft, amount: '' })).toMatchObject({
    needsUsdc: false, needsEth: false,
  });
  expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(2);
  expect(perpsGetPositions).not.toHaveBeenCalled();
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('read-only funding requirements use backend minimums and do not mistake a reduction for a deposit', async () => {
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset], {
    limitsByChain: { hyperliquid: {
      minOpenDepositUsdc: '20.2', minIncreaseDepositUsdc: '30.2', minPositionMarginUsdc: '10',
    } },
  }) as any);
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({ [ARBITRUM_USDC_MAINNET.slug]: 15_000000n });
  expect(await perpsGetFundingRequirements(account, { ...draft, amount: '' }))
    .toMatchObject({ requiredUsdc: '20.2', needsUsdc: true, needsEth: true });
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  expect(await perpsGetFundingRequirements(account, { ...draft, editing: true, amount: '110' }))
    .toMatchObject({ requiredUsdc: '30.2', needsUsdc: true });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  expect(await perpsGetFundingRequirements(account, { ...draft, editing: true, amount: '75' }))
    .toMatchObject({ requiredUsdc: '0', requiredEth: '0', needsUsdc: false, needsEth: false });
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, amount: '75' }))
    .resolves.toMatchObject({ kind: 'reduce', fundingRequirements: { needsUsdc: false, needsEth: false } });
});

test('missing deposit funds leave account eligibility and reduction or close recovery available', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const snapshot = await perpsGetSnapshot(account);
  expect(snapshot.tradingAvailability).toEqual({ isAvailable: true });
  expect(snapshot.assets[0].tradingAvailability).toEqual({ isAvailable: true });
  expect(await perpsGetFundingRequirements(account, { ...draft, editing: true, amount: '120' }))
    .toMatchObject({ needsUsdc: true, needsEth: true });
  for (const change of [{ amount: '75' }, { amount: '0', close: true }]) {
    const reducing = { ...draft, editing: true, ...change };
    expect(await perpsGetFundingRequirements(account, reducing))
      .toMatchObject({ requiredUsdc: '0', requiredEth: '0', needsUsdc: false, needsEth: false });
    await expect(perpsPrepareOrder(account, reducing))
      .resolves.toMatchObject({ kind: change.close ? 'close' : 'reduce' });
  }
});

test('deposit gas estimation failures preserve a specific actionable error', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({ error: ApiTransactionError.InsufficientBalance });
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `gas-${++serial}`))
    .resolves.toMatchObject({ state: 'failed', error: 'PerpsInsufficientGas', stage: 'preparing' });
});

test('a reviewed operation is submitted once and another account cannot reuse its ID', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onDeposit?.('0xdeposit');
    return Promise.resolve({
      address: WALLET,
      rawResponse: {},
      depositTxHash: '0xdeposit',
      status: 'filled',
      oid: 123,
      filledSize: '0.005',
      avgPrice: '100000',
    });
  });
  const result = await perpsExecuteReviewedOrder(account, 'token', quote.id, 'completed');
  expect(result).toMatchObject({ state: 'completed', depositTxHash: '0xdeposit', orderId: 123 });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, 'completed')).toEqual(result);
  expect(executePerpsOpenPosition).toHaveBeenCalledTimes(1);
  await expect(perpsExecuteReviewedOrder('99-mainnet', 'token', quote.id, 'completed')).rejects.toThrow(
    'PerpsInvalidOperation',
  );
});

test.each(['98000', '102000'])('ordinary market movement to %s keeps the reviewed deposit intent', async (markPx) => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(perpsGetAssets)
    .mockResolvedValue(assetsResult([{ ...asset, context: { ...asset.context, markPx } }]) as any);
  jest.mocked(executePerpsOpenPosition)
    .mockResolvedValue({ address: WALLET, rawResponse: {}, depositTxHash: '0xdeposit', status: 'filled' });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `market-${++serial}`))
    .toMatchObject({ state: 'completed' });
  expect(executePerpsOpenPosition).toHaveBeenCalledWith(account, 'token',
    expect.objectContaining({ depositAmount: '50.2', leverage: 10, slippage: 0.03 }),
    expect.any(Object));
});

test.each([
  { markPx: '102000', limit: '98940', orderSize: '0.00491', filledSize: '0.00491', error: undefined },
  { markPx: '98000', limit: '95060', orderSize: '0.00511', filledSize: '0.005', error: 'PerpsPartialFill' },
])('fill classification uses the submitted order after repricing to $markPx', async ({
  markPx, limit, orderSize, filledSize, error,
}) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true });
  expect(quote.orderSize).toBe('0.005');
  jest.mocked(perpsGetAssets)
    .mockResolvedValue(assetsResult([{ ...asset, context: { ...asset.context, markPx } }]) as any);
  jest.mocked(executePerpsModifyPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
    hooks?.validateBuild?.({
      marketReferencePrice: markPx,
      action: { orders: [{ a: 0, b: false, r: true, s: orderSize, p: limit, t: { limit: { tif: 'Ioc' } } }] },
    });
    hooks?.onSubmitting?.();
    return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled', filledSize, avgPrice: markPx });
  });
  const result = await perpsExecuteReviewedOrder(account, 'token', quote.id, `repriced-fill-${++serial}`);
  expect(result).toMatchObject({ state: 'completed', filledSize,
    positionSize: Big(position.szi).minus(filledSize).toFixed() });
  expect(result.error).toBe(error);
  expect(quote.orderSize).toBe('0.005');
  expect(quote.collateral).toBe('50');
});

test('deposit followed by a timeout remains locked without replaying the transfer', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onDeposit?.('0xdeposit');
    return Promise.reject(new Error('timeout'));
  });
  const unknown = await perpsExecuteReviewedOrder(account, 'token', quote.id, 'unknown');
  expect(unknown).toMatchObject({ state: 'unknown', depositTxHash: '0xdeposit' });
  const next = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', next.id, 'retry')).rejects.toThrow(
    'PerpsOperationPending',
  );
  expect(await perpsReconcileOperation(account, unknown)).toEqual(unknown);
  expect(executePerpsOpenPosition).toHaveBeenCalledTimes(1);
});

test.each(['reduce', 'close'] as const)('a rejected %s permits a fresh review without recovery', async (kind) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, close: kind === 'close' });
  const status = 'error: Order must have minimum value of $10. asset=0';
  const reject = (_a: unknown, _t: unknown, _r: unknown, hooks: any) => {
    hooks.onSubmitting();
    hooks.onTrade({ status });
    return Promise.resolve({ error: status });
  };
  if (kind === 'reduce') jest.mocked(executePerpsModifyPosition).mockImplementationOnce(reject);
  else jest.mocked(executePerpsClosePosition).mockImplementationOnce(reject);
  const result = await perpsExecuteReviewedOrder(account, 'token', quote.id, `rejected-${++serial}`);
  expect(result).toMatchObject({
    state: 'failed', stage: 'finished', orderStatus: status, error: 'PerpsOrderTooSmall',
  });
  const next = await perpsPrepareOrder(account, { ...draft, editing: true, close: kind === 'close' });
  if (kind === 'reduce') {
    jest.mocked(executePerpsModifyPosition).mockResolvedValueOnce({
      address: WALLET, rawResponse: {}, status: 'filled',
    });
  } else {
    jest.mocked(executePerpsClosePosition).mockResolvedValueOnce({ phase: 'completed', close: {
      address: WALLET, rawResponse: {}, status: 'filled',
    }, withdrawResult: { address: WALLET, rawResponse: {}, status: 'success' } });
  }
  expect(await perpsExecuteReviewedOrder(account, 'token', next.id, `fresh-${++serial}`))
    .toMatchObject({ state: 'completed' });
});

test.each(['reduce', 'close'] as const)('a definite %s signature rejection finishes as failed', async (kind) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, close: kind === 'close' });
  if (kind === 'reduce') {
    jest.mocked(executePerpsModifyPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      return Promise.reject(new Error(signatureRejection));
    });
  } else {
    jest.mocked(executePerpsClosePosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      return Promise.reject(new Error(signatureRejection));
    });
  }
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `signature-rejected-${++serial}`))
    .toMatchObject({ state: 'failed', stage: 'finished', error: `PerpsOrderRejected: ${signatureRejection}` });
});

test.each(['open', 'leverage'] as const)(
  '%s rejected after a deposit keeps recovery available for the funds',
  async (kind) => {
    let execute: typeof executePerpsOpenPosition | typeof executePerpsModifyPosition = executePerpsOpenPosition;
    let quote = await perpsPrepareOrder(account, draft);
    if (kind === 'leverage') {
      jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
      jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '50.2' });
      quote = await perpsPrepareOrder(account, { ...draft, amount: '100', leverage: 5, editing: true });
      execute = executePerpsModifyPosition;
    }
    expect(quote.kind).toBe(kind);
    expect(Number(quote.paymentAmount)).toBeGreaterThan(0);
    jest.mocked(execute).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      hooks?.onDeposit?.('0xdeposit');
      return Promise.resolve({ address: WALLET, depositTxHash: '0xdeposit', rawResponse: {},
        status: 'error: Insufficient margin to place order. asset=0' });
    });
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `deposit-rejected-${++serial}`))
      .toMatchObject({ state: 'unknown', error: 'PerpsInsufficientMargin', depositTxHash: '0xdeposit' });
  },
);

test.each(['reduce', 'close', 'open'] as const)('reconciliation leaves a %s outcome unknown', async (kind) => {
  const saved = { ...savedOperation('unknown'), kind, orderId: 587150124719, stage: 'trade' as const };
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
  expect(executePerpsClosePosition).not.toHaveBeenCalled();
});

test('partial close retains its order and retries only a reviewed withdrawal', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, amount: '0', editing: true, close: true });
  jest.mocked(executePerpsClosePosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onTrade?.({ address: WALLET, rawResponse: {}, status: 'filled', oid: 77 });
    return Promise.resolve({
      phase: 'withdraw_unavailable',
      close: { address: WALLET, rawResponse: {}, status: 'filled', oid: 77 },
    });
  });
  const partial = await perpsExecuteReviewedOrder(account, 'token', quote.id, 'partial');
  expect(partial).toMatchObject({ state: 'partial', orderId: 77 });
  await expect(perpsRetryWithdrawal(account, 'token', partial.id)).rejects.toThrow('PerpsQuoteExpired');
  expect(await perpsPrepareWithdrawal(account, partial.id)).toBe('99.97');
  jest.mocked(perpsWithdrawReleasedMargin).mockResolvedValue({
    phase: 'completed', withdrawResult: { status: 'ok' },
  } as any);
  expect(await perpsRetryWithdrawal(account, 'fresh-token', partial.id)).toMatchObject({
    state: 'completed',
    orderId: 77,
    withdrawalAmount: '99.97',
  });
  expect(executePerpsClosePosition).toHaveBeenCalledTimes(1);
  expect(perpsWithdrawReleasedMargin).toHaveBeenCalledWith(account, 'fresh-token',
    expect.objectContaining({ amountUsdc: '99.97', action: expect.objectContaining({ sourceDex: 'spot' }) }),
    expect.any(Function));
});

test('one aggregate positions call includes every book without duplicate account reads', async () => {
  const custom = { ...asset, id: 'hyperliquid:xyz:BTC', name: 'xyz:BTC', dex: 'xyz' };
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset, custom]) as any);
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position, { ...position, coin: 'xyz:BTC' }]) as any);
  const snapshot = await perpsGetSnapshot(account);
  expect(snapshot).toMatchObject({ totalEquity: '220', totalPnl: '20', unavailableDexs: [] });
  expect(snapshot.positions).toHaveLength(2);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
  expect(perpsGetPositions).toHaveBeenCalledWith({ addressByChain: { hyperliquid: WALLET } });
});

test('a failed aggregate positions request cannot produce an empty portfolio', async () => {
  jest.mocked(perpsGetPositions).mockRejectedValueOnce(new Error('offline'));
  await expect(perpsGetSnapshot(account)).rejects.toThrow('offline');
});

test('charts use backend timestamps in seconds without contacting the venue', async () => {
  jest.mocked(perpsGetAssetChart).mockResolvedValueOnce([[1700000000, 100]]);
  expect(await perpsGetCandles(asset.id, '1D')).toEqual([[1700000000, 100]]);
  expect(perpsGetAssetChart).toHaveBeenCalledWith({ chain: 'hyperliquid', asset: asset.id, period: '1D' });
  expect(fetchStoredChainAccount).not.toHaveBeenCalled();
});

test('a leverage change quotes the modify estimate deposit', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValueOnce({ depositAmount: '50.2' });
  const decrease = await perpsPrepareOrder(account, { ...draft, amount: '100', leverage: 5, editing: true });
  expect(decrease).toMatchObject({
    kind: 'leverage', paymentAmount: '50.2', modify: { leverage: 5, depositAmount: '50.2' },
  });
  expect(perpsEstimateModifyPosition).toHaveBeenCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, leverage: 5,
  });

  jest.mocked(perpsEstimateModifyPosition).mockResolvedValueOnce({ depositAmount: '0' });
  const increase = await perpsPrepareOrder(account, { ...draft, amount: '100', leverage: 20, editing: true });
  expect(increase.paymentAmount).toBe('0');
  expect(increase.modify?.depositAmount).toBe('0');

  jest.mocked(perpsEstimateModifyPosition).mockResolvedValueOnce({ error: 'No open position for asset' });
  await expect(perpsPrepareOrder(account, { ...draft, amount: '100', leverage: 4, editing: true }))
    .rejects.toThrow('No open position for asset');
});

test('loads unaggregated executions through backend activities for the selected wallet', async () => {
  const fill = { kind: 'fill' as const, dex: '', coin: 'BTC', time: 1000, tid: 1, oid: 42,
    px: '100', sz: '2', side: 'B', dir: 'Open Long', startPosition: '0', closedPnl: '0',
    fee: '0.3', builderFee: '0.2', feeToken: 'USDC' };
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: WALLET.toUpperCase(), activities: [fill,
      { kind: 'historicalOrder', dex: '', time: 1000, order: { oid: 42 }, status: 'filled' },
      { kind: 'fundingPayment', dex: '', time: 2000,
        delta: { type: 'funding', coin: 'BTC', szi: '2', usdc: '-0.01', fundingRate: '0.00005' } },
      { kind: 'ledgerUpdate', dex: '', time: 3000, delta: { type: 'deposit', usdc: '5' } }],
  } } });
  expect((await perpsGetActivityHistory(account)).fills).toMatchObject([{
    eventKind: 'opened', positionSide: 'long', oid: 42, notional: '200',
    fee: '0.3', builderFee: '0.2', fillIds: [1], positionOpenedAt: 1000,
  }]);
  expect(perpsGetActivities).toHaveBeenCalledWith({
    addressByChain: { hyperliquid: WALLET },
  });
  expect(perpsGetAssets).not.toHaveBeenCalled();
});

test('native activity history fetches trades and cash flows together once', async () => {
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: WALLET, activities: [{ kind: 'ledgerUpdate', dex: '', time: 1000, delta: { type: 'deposit', usdc: '5' } }],
  } } });
  expect(await perpsGetActivityHistory(account)).toMatchObject({
    fills: [], cashFlows: [{ kind: 'deposit', amount: '5' }],
  });
  expect(perpsGetActivities).toHaveBeenCalledTimes(1);
});

test('distinguishes an empty history from a missing, wrong-wallet or failed backend response', async () => {
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: WALLET, activities: [],
  } } });
  expect(await perpsGetActivityHistory(account)).toMatchObject({ fills: [], hasActivity: false });
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: {} });
  await expect(perpsGetActivityHistory(account)).rejects.toThrow('PerpsIncompleteData');
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: 'another-wallet', activities: [],
  } } });
  await expect(perpsGetActivityHistory(account)).rejects.toThrow('PerpsIncompleteData');
  jest.mocked(perpsGetActivities).mockRejectedValueOnce(new Error('Backend unavailable'));
  await expect(perpsGetActivityHistory(account)).rejects.toThrow('Backend unavailable');
});

test('HIP-3 reviews require the canonical index and validate builds against it', async () => {
  const custom = { ...asset, id: 'hyperliquid:xyz:BTC', name: 'xyz:BTC', dex: 'xyz', wireAssetIndex: undefined };
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([custom]) as any);
  await expect(perpsPrepareOrder(account, { ...draft, assetId: custom.id })).rejects.toThrow('PerpsTradingUnavailable');
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...custom, wireAssetIndex: 110005 }]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, assetId: custom.id });
  expect(quote).toMatchObject({ kind: 'open', assetId: custom.id, wireAssetIndex: 110005 });
  jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, request, hooks) => {
    expect(request.asset).toBe(custom.id);
    hooks?.validateBuild?.({
      marketReferencePrice: '100010',
      action: { orders: [{ a: 110005, b: true, r: false, s: '0.005', p: '103010',
        t: { limit: { tif: 'Ioc' } } }] },
      updateLeverage: { action: { asset: 110005, leverage: 10, isCross: false }, hash: '0xbuild', nonce: 1,
        typedData: { domain: {}, types: {}, primaryType: 'Agent', message: {} } },
      deposit: { ...depositFixture, requiresPermitSignature: true as const },
    });
    hooks?.onSubmitting?.();
    return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled',
      depositTxHash: '0xdeposit', filledSize: '0.005', avgPrice: '100010' });
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `hip3-${++serial}`))
    .toMatchObject({ state: 'completed', assetId: custom.id, filledSize: '0.005' });
});

test('a catalogue book change requires a new review', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(perpsGetAssets).mockResolvedValue(
    assetsResult([{ ...asset, dex: 'xyz', wireAssetIndex: 110000 }]) as any,
  );
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, 'changed-book'))
    .toMatchObject({ state: 'failed', error: 'PerpsReviewChanged' });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('execution rejects a canonical index changed since review before asking for a build', async () => {
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...asset, wireAssetIndex: 7 }]) as any);
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.wireAssetIndex).toBe(7);
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...asset, wireAssetIndex: 8 }]) as any);
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `changed-index-${++serial}`))
    .toMatchObject({ state: 'failed', error: 'PerpsReviewChanged', stage: 'preparing' });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('a delisted market cannot execute an earlier review', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...asset, isDelisted: true }]) as any);
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `delisted-${++serial}`))
    .toMatchObject({ state: 'failed', error: 'PerpsTradingUnavailable', stage: 'preparing' });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
  expect(executePerpsClosePosition).not.toHaveBeenCalled();
});

test.each([{ wireAssetIndex: -1 }, { isDelisted: true }])('unavailable market %j cannot preview', async (fields) => {
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...asset, ...fields }]) as any);
  await expect(perpsGetLeverageEstimates(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
  await expect(perpsGetFundingRequirements(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
});

afterEach(() => {
  expect(fetchWithTimeout).not.toHaveBeenCalled();
});

test.each<{ intent: ApiPerpsTradeIntent; target: Partial<ApiPerpsDraftRequest> }>([
  { intent: { kind: 'open', assetId: asset.id, side: 'long', depositAmount: '50.2', leverage: 10 }, target: {} },
  { intent: { kind: 'increase', assetId: asset.id, amount: '20.2' }, target: { editing: true, amount: '120' } },
  { intent: { kind: 'reduce', assetId: asset.id, amount: '20' }, target: { editing: true, amount: '80' } },
  { intent: { kind: 'leverage', assetId: asset.id, leverage: 20 },
    target: { editing: true, amount: '100', leverage: 20, leverageOnly: true } },
  { intent: { kind: 'close', assetId: asset.id }, target: { editing: true, close: true } },
])('deposit/release and target-collateral inputs share the same $intent.kind review', async ({ intent, target }) => {
  if (intent.kind !== 'open') jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '0' });
  const quote = await perpsPrepareOrder(account, intent);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
  expect(perpsEstimatePosition).toHaveBeenCalledTimes(1);
  const targetQuote = await perpsPrepareOrder(account, { ...draft, ...target });
  expect(quote).toEqual({ ...targetQuote, id: quote.id, createdAt: quote.createdAt, expiresAt: quote.expiresAt });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
  expect(executePerpsClosePosition).not.toHaveBeenCalled();
});

test.each(['100', '105'])('a profitable %s USDC reduction keeps its explicit intent', async (amount) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position,
    marginUsed: '150', unrealizedPnl: '50', szi: '0.015',
  }]) as any);
  const quote = await perpsPrepareOrder(account, { kind: 'reduce', assetId: asset.id, amount });
  expect(quote).toMatchObject({ kind: 'reduce', modify: { depositAmount: amount, reduceOnly: true } });
  expect(quote.close).toBeUndefined();
  expect(Big(quote.size).gt(0)).toBe(true);
  expect(perpsEstimatePosition).toHaveBeenCalledWith(expect.objectContaining({
    depositAmount: amount, reduceOnly: true,
  }));
});

test('a reduction still rejects insufficient remaining margin using the backend balance', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position,
    marginUsed: '80', unrealizedPnl: '-20',
  }]) as any);
  await expect(perpsPrepareOrder(account, { kind: 'reduce', assetId: asset.id, amount: '75' }))
    .rejects.toThrow('PerpsAmountTooSmall');
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
});

test.each(['100', '120'])('leverage changes with %s USDC profit cannot become a close', async (unrealizedPnl) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position, marginUsed: '100', unrealizedPnl }]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '0' });
  const quote = await perpsPrepareOrder(account, { kind: 'leverage', assetId: asset.id, leverage: 20 });
  expect(quote).toMatchObject({ kind: 'leverage', modify: { leverage: 20 }, size: position.szi });
  expect(quote.close).toBeUndefined();
  const unchanged = await perpsPrepareOrder(account, { kind: 'leverage', assetId: asset.id, leverage: 10 });
  expect(unchanged.kind).toBe('unchanged');
});

test.each(['reduce', 'close'] as const)('%s can exit after the catalogue lowers maximum leverage', async (kind) => {
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([{ ...asset, maxLeverage: 5 }]) as any);
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, kind === 'reduce'
    ? { kind, assetId: asset.id, amount: '20' } : { kind, assetId: asset.id });
  expect(quote).toMatchObject({ kind, leverage: 10 });
});

test('review preparation keeps one estimate when the next market tick changes the rounded size', async () => {
  jest.mocked(perpsEstimatePosition)
    .mockResolvedValueOnce({ size: '0.005', orderValue: '500', marginRequired: '50', liquidationPrice: '90501' })
    .mockResolvedValueOnce({
      size: '0.00499', orderValue: '499.5', marginRequired: '49.95', liquidationPrice: '90502',
    });
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote).toMatchObject({ orderSize: '0.005', estimatedLiquidationPrice: '90501' });
  expect(perpsEstimatePosition).toHaveBeenCalledTimes(1);
});

test('quotes use backend liquidation estimates without inventing net collateral or fees', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.estimatedCollateral).toBeUndefined();
  expect(quote.estimatedLiquidationPrice).toBe('90501');
  expect(quote.estimatedFees).toBeUndefined();
  expect(await perpsGetLeverageEstimates(account, draft)).toEqual([{ leverage: 10, liquidationPrice: '90501' }]);
});

test('estimate lot mismatches fail before a review can be executed', async () => {
  jest.mocked(perpsEstimatePosition)
    .mockResolvedValueOnce({ size: '1', orderValue: '100000', marginRequired: '10000' });
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsReviewChanged');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('backend estimate validation errors reach review and leverage previews without signing', async () => {
  jest.mocked(perpsEstimatePosition).mockResolvedValue({ error: 'PerpsOrderTooSmall' });
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsOrderTooSmall');
  await expect(perpsGetLeverageEstimates(account, draft)).rejects.toThrow('PerpsOrderTooSmall');
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await expect(perpsGetLeverageEstimates(account, { ...draft, editing: true, amount: '120' }))
    .rejects.toThrow('PerpsOrderTooSmall');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
});

test('USDC leverage previews check the cached catalogue without requesting positions or balances', async () => {
  expect(await perpsGetLeverageEstimates(account, { ...draft, leverage: 2 }))
    .toEqual([{ leverage: 2, liquidationPrice: '90501' }]);
  expect(perpsEstimatePosition).toHaveBeenCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long',
    depositAmount: '50.2', leverage: 2, isCross: false,
  });
  expect(perpsGetAssets).toHaveBeenCalledWith();
  expect(perpsGetPositions).not.toHaveBeenCalled();
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
});

test('a leverage preview below the opening minimum is not an executable review', async () => {
  expect(await perpsGetLeverageEstimates(account, { ...draft, amount: '1' }))
    .toEqual([{ leverage: 10, liquidationPrice: '90501' }]);
  await expect(perpsPrepareOrder(account, { ...draft, amount: '1' })).rejects.toThrow('PerpsAmountTooSmall');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test.each(['0', '-1', undefined])('a nonpositive or unavailable liquidation price stays absent: %s', async (price) => {
  jest.mocked(perpsEstimatePosition).mockResolvedValueOnce({
    size: '0.0001', orderValue: '10', marginRequired: '5', liquidationPrice: price,
  });
  expect(await perpsGetLeverageEstimates(account, draft))
    .toEqual([{ leverage: 10, liquidationPrice: undefined }]);
});

test('unchanged leverage keeps the current liquidation price without requesting a resize estimate', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  expect(await perpsGetLeverageEstimates(account, { ...draft, editing: true, reset: true }))
    .toEqual([{ leverage: 10, liquidationPrice: '90500' }]);
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
});

test('history cursor and limit reach the backend without changing the selected wallet', async () => {
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: WALLET, activities: [], nextCursor: 'next',
  } } });
  expect(await perpsGetActivityHistory(account, { cursor: 'previous', limit: 20 }))
    .toMatchObject({ nextCursor: 'next' });
  expect(perpsGetActivities).toHaveBeenCalledWith({
    addressByChain: { hyperliquid: WALLET }, cursor: 'previous', limit: 20,
  });
});

test('withdrawal recovery preserves the original reduction amount and signs the backend route', async () => {
  const partial = await perpsReconcileOperation(account, {
    ...savedOperation('partial'), kind: 'reduce', withdrawalRequestedAmount: '5.123456',
  });
  const withdraw = perpsWithdrawalFixture(WALLET, '5.123456');
  jest.mocked(perpsBuildWithdrawal).mockResolvedValue({ address: WALLET, withdraw });
  expect(await perpsPrepareWithdrawal(account, partial.id)).toBe('5.123456');
  expect(perpsBuildWithdrawal).toHaveBeenCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, amountUsdc: '5.123456',
  });
  jest.mocked(perpsWithdrawReleasedMargin).mockResolvedValueOnce({
    phase: 'completed', withdrawResult: { status: 'ok' },
  } as any);
  await perpsRetryWithdrawal(account, 'token', partial.id);
  expect(perpsWithdrawReleasedMargin).toHaveBeenCalledWith(account, 'token', withdraw, expect.any(Function));
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
  expect(executePerpsClosePosition).not.toHaveBeenCalled();
});

test('a reduction without its recorded release amount never sweeps free collateral', async () => {
  const partial = await perpsReconcileOperation(account, { ...savedOperation('partial'), kind: 'reduce' });
  await expect(perpsPrepareWithdrawal(account, partial.id)).rejects.toThrow('PerpsWithdrawalPending');
  expect(perpsBuildWithdrawal).not.toHaveBeenCalled();
  expect(perpsWithdrawReleasedMargin).not.toHaveBeenCalled();
});

test.each(['amount', 'wireAmount', 'recipient', 'source'] as const)(
  'withdrawal review rejects a mismatched backend %s', async (field) => {
    const partial = await perpsReconcileOperation(account, {
      ...savedOperation('partial'), kind: 'reduce', withdrawalRequestedAmount: '5',
    });
    const withdraw = perpsWithdrawalFixture(
      WALLET, field === 'amount' ? '6' : '5', field === 'source' ? 'xyz' : 'spot',
    );
    if (field === 'wireAmount') withdraw.amountUsdc = '6';
    if (field === 'recipient') withdraw.destination = '0x2222222222222222222222222222222222222222';
    jest.mocked(perpsBuildWithdrawal).mockResolvedValueOnce({ address: WALLET, withdraw });
    await expect(perpsPrepareWithdrawal(account, partial.id)).rejects.toThrow();
    expect(perpsWithdrawReleasedMargin).not.toHaveBeenCalled();
  },
);

test.each(['close', 'reduce'] as const)('a filled pending withdrawal allows %s on another position', async (kind) => {
  await perpsReconcileOperation(account, { ...savedOperation('partial'),
    assetId: 'hyperliquid:hl:ETH', orderStatus: 'filled', orderId: 2 });
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true,
    close: kind === 'close', amount: kind === 'close' ? '0' : '80' });
  jest.mocked(executePerpsClosePosition).mockResolvedValueOnce({ phase: 'completed' } as any);
  jest.mocked(executePerpsModifyPosition).mockResolvedValueOnce({ status: 'filled' } as any);
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `safe-${++serial}`))
    .toMatchObject({ state: 'completed' });
});

test.each([
  ['partial', 'filled', 'hyperliquid:hl:BTC', 'close'],
  ['unknown', 'filled', 'hyperliquid:hl:ETH', 'close'],
  ['partial', undefined, 'hyperliquid:hl:ETH', 'close'],
  ['partial', 'filled', 'hyperliquid:hl:ETH', 'increase'],
] as const)('pending %s/%s on %s continues to block %s', async (stateName, orderStatus, assetId, kind) => {
  await perpsReconcileOperation(account, { ...savedOperation(stateName), assetId, orderStatus, orderId: 2 });
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true,
    close: kind === 'close', amount: kind === 'close' ? '0' : '130' });
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
    .rejects.toThrow('PerpsOperationPending');
});

test.each(['larger', 'smaller', 'source', 'fee'] as const)(
  'withdrawal recovery requires a new review when the refreshed permit is %s', async (change) => {
    const partial = await perpsReconcileOperation(account, savedOperation('partial'));
    await perpsPrepareWithdrawal(account, partial.id);
    const fresh = perpsWithdrawalFixture(WALLET,
      change === 'larger' ? '100.97' : change === 'smaller' ? '98.97' : '99.97', change === 'source' ? '' : 'spot');
    if (change === 'fee') fresh.forwardFeeUsdc = '0.3';
    jest.mocked(perpsBuildWithdrawal).mockResolvedValueOnce({ address: WALLET, withdraw: fresh });
    expect(await perpsRetryWithdrawal(account, 'token', partial.id))
      .toMatchObject({ state: 'partial', error: 'PerpsReviewChanged' });
    expect(perpsWithdrawReleasedMargin).not.toHaveBeenCalled();
  },
);

test('withdrawal retry waits while an admitted reduction on another asset is executing', async () => {
  const partial = await perpsReconcileOperation(account, { ...savedOperation('partial'),
    assetId: 'hyperliquid:hl:ETH', orderStatus: 'filled', orderId: 2 });
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, close: true, amount: '0' });
  let finish: (() => void) | undefined;
  jest.mocked(executePerpsClosePosition).mockImplementationOnce(() => new Promise((resolve) => {
    finish = () => resolve({ phase: 'completed' } as any);
  }));
  const execution = perpsExecuteReviewedOrder(account, 'token', quote.id, `active-close-${++serial}`);
  while (!finish) await Promise.resolve();
  await expect(perpsRetryWithdrawal(account, 'token', partial.id)).rejects.toThrow('PerpsOperationPending');
  expect(perpsWithdrawReleasedMargin).not.toHaveBeenCalled();
  finish();
  await execution;
});

test('display previews reuse known funding without reloading balances or creating executable reviews', async () => {
  await perpsGetFundingRequirements(account, draft);
  jest.clearAllMocks();
  jest.mocked(chains.arbitrum.getWalletAssets).mockRejectedValue(new Error('balance endpoint offline'));
  const quote = await perpsPreviewOrder(account, draft);
  expect(quote).toMatchObject({ id: '', kind: 'open', orderSize: '0.005' });
  expect(quote.fundingRequirements).toMatchObject({ usdcBalance: '200', needsUsdc: false, needsEth: false });
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
  expect(perpsGetPositions).not.toHaveBeenCalled();
  expect(perpsGetAssets).toHaveBeenCalledWith();
  expect(perpsEstimatePosition).toHaveBeenCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long',
    depositAmount: '50.2', leverage: 10, isCross: false,
  });
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `preview-${++serial}`))
    .rejects.toThrow('PerpsQuoteExpired');
});

test('small backend-sized edits use the same amount-only estimate and build intent as the lab', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await perpsGetFundingRequirements(account, { ...draft, editing: true });
  jest.clearAllMocks();
  const quote = await perpsPreviewOrder(account, { ...draft, editing: true, amount: '100.5' });
  expect(quote).toMatchObject({ kind: 'increase', paymentAmount: '0.7', orderSize: '0.00005', size: '0.01005' });
  expect(quote.modify).not.toHaveProperty('size');
  expect(quote.modify).not.toHaveProperty('price');
  expect(perpsEstimatePosition).toHaveBeenCalledWith(expect.objectContaining({
    depositAmount: '0.7', reduceOnly: false,
  }));
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
});

test('typing an oversized increase recalculates funding hints using the known wallet balance', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await perpsGetFundingRequirements(account, { ...draft, editing: true });
  jest.clearAllMocks();
  const quote = await perpsPreviewOrder(account, { ...draft, editing: true, amount: '10000' });
  expect(quote.fundingRequirements).toMatchObject({
    requiredUsdc: '9900.2', usdcBalance: '200', needsUsdc: true, needsEth: false,
  });
  expect(quote.id).toBe('');
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
});

test('funding previews refresh expired balances and Review always reads funds again', async () => {
  const now = Date.now();
  const clock = jest.spyOn(Date, 'now').mockReturnValue(now);
  try {
    await perpsGetFundingRequirements(account, draft);
    jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
    clock.mockReturnValue(now + 30_001);
    expect((await perpsPreviewOrder(account, draft)).fundingRequirements)
      .toMatchObject({ needsUsdc: true, needsEth: true });
    expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(2);
    await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsInsufficientUsdc');
    expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(3);
  } finally {
    clock.mockRestore();
  }
});

test.each(['account', 'address'] as const)('funding preview cache is isolated by %s', async (identity) => {
  await perpsGetFundingRequirements(account, draft);
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  let targetAccount = account;
  if (identity === 'account') {
    targetAccount = `${++serial}-mainnet`;
  } else {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'mnemonic', byChain: { arbitrum: { address: '0x2222222222222222222222222222222222222222' } },
    } as any);
  }
  expect((await perpsPreviewOrder(targetAccount, draft)).fundingRequirements)
    .toMatchObject({ usdcBalance: '0', needsUsdc: true, needsEth: true });
  expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(2);
});

test('concurrent funding previews share the same balance read', async () => {
  const previews = await Promise.all([
    perpsGetFundingRequirements(account, draft), perpsPreviewOrder(account, draft), perpsPreviewOrder(account, draft),
  ]);
  expect(previews).toHaveLength(3);
  expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(1);
});

test('modify previews share only in-flight positions and retain separate estimates', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '0' });
  const previews = await Promise.all([
    perpsPreviewOrder(account, { kind: 'increase', assetId: asset.id, amount: '20' }),
    perpsPreviewOrder(account, { kind: 'reduce', assetId: asset.id, amount: '20' }),
    perpsPreviewOrder(account, { kind: 'leverage', assetId: asset.id, leverage: 20 }),
  ]);
  expect(previews.map(({ kind }) => kind)).toEqual(['increase', 'reduce', 'leverage']);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);
  expect(perpsEstimatePosition).toHaveBeenCalledTimes(3);
  expect(perpsEstimateModifyPosition).toHaveBeenCalledTimes(1);

  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position, szi: '0.02' }]) as any);
  expect(await perpsPreviewOrder(account, { kind: 'increase', assetId: asset.id, amount: '20' }))
    .toMatchObject({ previousSize: '0.02' });
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
});

test('concurrent previews for different wallet addresses read separate positions', async () => {
  const otherAddress = '0x2222222222222222222222222222222222222222';
  jest.mocked(fetchStoredChainAccount).mockImplementation((accountId) => Promise.resolve({
    type: 'mnemonic', byChain: { arbitrum: { address: accountId === account ? WALLET : otherAddress } },
  } as any));
  jest.mocked(perpsGetPositions).mockImplementation(({ addressByChain }) =>
    Promise.resolve(state([{ ...position, szi: addressByChain.hyperliquid === WALLET ? '0.01' : '0.02' }]) as any),
  );
  const intent = { kind: 'increase', assetId: asset.id, amount: '20' } as const;
  const previews = await Promise.all([
    perpsPreviewOrder(account, intent), perpsPreviewOrder(`${++serial}-mainnet`, intent),
  ]);
  expect(previews.map(({ previousSize }) => previousSize)).toEqual(['0.01', '0.02']);
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
});

test('a failed shared position read does not prevent subsequent previews from retrying', async () => {
  jest.mocked(perpsGetPositions).mockRejectedValueOnce(new Error('offline'));
  const intent = { kind: 'increase', assetId: asset.id, amount: '20' } as const;
  const results = await Promise.allSettled([
    perpsPreviewOrder(account, intent), perpsPreviewOrder(account, intent),
  ]);
  expect(results.map(({ status }) => status)).toEqual(['rejected', 'rejected']);
  expect(perpsGetPositions).toHaveBeenCalledTimes(1);

  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await expect(perpsPreviewOrder(account, intent)).resolves.toMatchObject({ kind: 'increase' });
  expect(perpsGetPositions).toHaveBeenCalledTimes(2);
});

test.each(['review', 'submission'] as const)('%s refreshes positions during an in-flight preview', async (stage) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const intent = { kind: 'increase', assetId: asset.id, amount: '20' } as const;
  const quote = await perpsPrepareOrder(account, intent);
  const pending = new Deferred<Awaited<ReturnType<typeof perpsGetPositions>>>();
  const started = new Deferred();
  jest.mocked(perpsGetPositions).mockImplementationOnce(() => {
    started.resolve();
    return pending.promise;
  });
  const preview = perpsPreviewOrder(account, intent);
  await started.promise;
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position, szi: '0.02' }]) as any);
  try {
    if (stage === 'review') {
      expect(await perpsPrepareOrder(account, intent)).toMatchObject({ previousSize: '0.02' });
    } else {
      const operation = await perpsExecuteReviewedOrder(account, 'token', quote.id, `fresh-positions-${++serial}`);
      expect(operation).toMatchObject({ state: 'failed', error: 'PerpsQuoteExpired' });
      expect(executePerpsModifyPosition).not.toHaveBeenCalled();
    }
    expect(perpsGetPositions).toHaveBeenCalledTimes(3);
  } finally {
    pending.resolve(state([position]) as any);
    await preview;
  }
});

test.each([false, true])('risk-reducing previews need no wallet balance read (close=%s)', async (close) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(chains.arbitrum.getWalletAssets).mockRejectedValue(new Error('balance endpoint offline'));
  const quote = await perpsPreviewOrder(account, { ...draft, editing: true, close, amount: '80' });
  expect(quote.fundingRequirements).toMatchObject({ needsUsdc: false, needsEth: false });
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
});

test('positive ETH below the advisory reserve reaches actual execution fee validation', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: 1n,
  });
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.fundingRequirements).toMatchObject({ requiredEth: '0.0001', needsEth: false });
});

test('leverage funding hints and preparation use the backend deposit requirement', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '50.2' });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  const leverageDraft = { ...draft, editing: true, leverageOnly: true, amount: '200', leverage: 5 };
  expect(await perpsGetFundingRequirements(account, leverageDraft))
    .toMatchObject({ requiredUsdc: '50.2', needsUsdc: true, needsEth: true });
  expect(await perpsPreviewOrder(account, leverageDraft))
    .toMatchObject({ kind: 'leverage', previousLeverage: 10, paymentAmount: '50.2', size: '0.01' });
  await expect(perpsPrepareOrder(account, leverageDraft)).rejects.toThrow('PerpsInsufficientUsdc');
});

test.each([
  { szi: '0.011' }, { szi: '-0.01' }, { leverage: { type: 'isolated', value: 5 } },
])('a changed live position cannot redefine reviewed edit intent: %j', async (change) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, amount: '120' });
  jest.mocked(perpsGetPositions).mockResolvedValue(state([{ ...position, ...change }]) as any);
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `changed-${++serial}`))
    .toMatchObject({ state: 'failed', error: 'PerpsQuoteExpired' });
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
});

test('account snapshots preserve backend abstraction mode and spot balances', async () => {
  const response = state([position]);
  jest.mocked(perpsGetPositions).mockResolvedValue({ positionsByChain: { hyperliquid: {
    ...response.positionsByChain.hyperliquid, abstractionMode: 'unifiedAccount',
    spotUsdcTotal: '120', spotUsdcAvailable: '20',
  } } } as any);
  expect(await perpsGetSnapshot(account)).toMatchObject({ abstractionMode: 'unifiedAccount',
    spotUsdcTotal: '120', spotUsdcAvailable: '20', withdrawable: '100' });
});

const estimatedFees = { exchange: '0.009', service: '0.0176', trading: '0.0266', bridge: '0.2', total: '0.2266' };

test.each(['open', 'increase', 'reduce', 'close'] as const)('%s uses complete backend fee estimates', async (kind) => {
  if (kind !== 'open') jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const estimate = jest.mocked(perpsEstimatePosition).getMockImplementation()!;
  jest.mocked(perpsEstimatePosition).mockImplementation(async (...args) => ({
    ...await estimate(...args), estimatedFees,
  }));
  const quote = await perpsPrepareOrder(account, {
    ...draft, editing: kind !== 'open', close: kind === 'close', amount: kind === 'increase' ? '110' : '50',
  });
  expect(quote.estimatedFees).toEqual(estimatedFees);
  if (kind === 'close') {
    expect(perpsEstimatePosition).toHaveBeenCalledWith({
      chain: 'hyperliquid', address: WALLET, asset: asset.id, close: true,
    });
  }
});

test('leverage funding fees come from modify estimate and are not overwritten by the zero-order ticket', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const fees = { exchange: '0', service: '0', trading: '0', bridge: '0.2', total: '0.2' };
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '100.2', estimatedFees: fees });
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, leverageOnly: true, leverage: 5 });
  expect(quote.estimatedFees).toEqual(fees);
});

test('a close-estimate error cannot block an exit or fabricate fee totals', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimatePosition).mockResolvedValue({ error: 'No open position for asset' });
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, close: true });
  expect(quote.kind).toBe('close');
  expect(quote.estimatedFees).toBeUndefined();
});

test('missing fee data remains unknown instead of displaying only the bridge fee as total', async () => {
  expect((await perpsPrepareOrder(account, draft)).estimatedFees).toBeUndefined();
});

test('a close fee lookup transport failure cannot block exiting', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimatePosition).mockRejectedValue(new Error('Network unavailable'));
  const quote = await perpsPrepareOrder(account, { ...draft, editing: true, close: true });
  expect(quote.kind).toBe('close');
  expect(quote.estimatedFees).toBeUndefined();
});

test('balance deposit, withdrawal and open use the wallet and block reviewed trading', async () => {
  const completion = new Deferred<void>();
  const started = new Deferred();
  jest.mocked(executePerpsDepositMargin).mockImplementation(() => {
    started.resolve();
    return Promise.resolve({ submitted: true, completion: completion.promise });
  });
  const first = perpsDepositMargin(account, 'token', '10.2');
  await started.promise;
  expect(await first).toEqual({ submitted: true });
  await expect(perpsWithdrawMargin(account, 'token', '10.2')).rejects.toThrow('PerpsOperationPending');
  await expect(perpsOpenFromBalance(account, 'token', {
    assetId: asset.id, side: 'long', amount: '50', leverage: 10, isCross: false,
  })).rejects.toThrow('PerpsOperationPending');
  const quote = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `during-deposit-${serial}`))
    .rejects.toThrow('PerpsOperationPending');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
  expect(executePerpsOpenFromBalance).not.toHaveBeenCalled();
  completion.resolve();
  await completion.promise;
  await Promise.resolve();
  expect(executePerpsDepositMargin).toHaveBeenCalledWith(account, 'token', {
    chain: 'hyperliquid', address: WALLET, amount: '10.2',
  });

  jest.mocked(executePerpsWithdrawMargin).mockResolvedValueOnce({
    address: WALLET, status: 'ok', rawResponse: {},
  });
  expect(await perpsWithdrawMargin(account, 'token', '4')).toMatchObject({ status: 'ok' });
  expect(executePerpsWithdrawMargin).toHaveBeenCalledWith(account, 'token', {
    chain: 'hyperliquid', address: WALLET, amount: '4',
  });
  jest.mocked(executePerpsOpenFromBalance).mockResolvedValueOnce({
    address: WALLET, status: 'filled', rawResponse: {},
  });
  expect(await perpsOpenFromBalance(account, 'token', {
    assetId: asset.id, side: 'short', amount: '25', leverage: 3, isCross: true,
  })).toMatchObject({ status: 'filled' });
  expect(executePerpsOpenFromBalance).toHaveBeenCalledWith(account, 'token', {
    chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'short', amount: '25',
    leverage: 3, isCross: true,
  });
});

test('view accounts cannot deposit, withdraw, or open from the perps balance', async () => {
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    type: 'view', byChain: { arbitrum: { address: WALLET } },
  } as any);
  await expect(perpsDepositMargin(account, 'token', '10.2')).rejects.toThrow('PerpsUnsupportedAccount');
  await expect(perpsWithdrawMargin(account, 'token', '10.2')).rejects.toThrow('PerpsUnsupportedAccount');
  await expect(perpsOpenFromBalance(account, 'token', {
    assetId: asset.id, side: 'long', amount: '50', leverage: 10, isCross: false,
  })).rejects.toThrow('PerpsUnsupportedAccount');
  expect(executePerpsDepositMargin).not.toHaveBeenCalled();
  expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
  expect(executePerpsOpenFromBalance).not.toHaveBeenCalled();
});
