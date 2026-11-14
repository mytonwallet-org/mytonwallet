import type {
  ApiPerpsBuildBalanceWithdrawResult, ApiPerpsDraftRequest, ApiPerpsExchangeTypedData, ApiPerpsOperation,
  ApiPerpsTradeActivity, ApiPerpsTradeIntent,
} from '../types';
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
import { balanceRefreshRequests } from '../common/polling/balanceRefresh';
import { getTokenBySlug } from '../common/tokens';
import { ApiServerError } from '../errors';
import {
  estimatePerpsDepositFundingGasUsdc,
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsOpenPositionFromBalance,
  executePerpsWithdrawMargin,
  perpsBuildBalanceWithdraw,
  perpsBuildWithdrawal,
  perpsEstimateModifyPosition,
  perpsEstimatePosition,
  perpsGetActivities,
  perpsGetAssetChart,
  perpsGetAssets,
  perpsGetPositions,
  perpsWithdrawReleasedMargin,
} from './perps';
import { requestPerpsPositionsRefresh } from './perpsPositions';
import {
  initPerpsTrading,
  perpsAcknowledgeOperation,
  perpsDepositMargin,
  perpsExecuteBalanceWithdrawal,
  perpsExecuteReviewedOrder,
  perpsGetActivityHistory,
  perpsGetCandles,
  perpsGetFundingRequirements,
  perpsGetLeverageEstimate,
  perpsGetMarketSnapshot,
  perpsGetSnapshot,
  perpsOpenFromBalance,
  perpsPrepareBalanceWithdrawal,
  perpsPrepareOrder,
  perpsPrepareWithdrawal,
  perpsPreviewOrder,
  perpsReconcileOperation,
  perpsRetryWithdrawal,
  perpsWithdrawMargin,
} from './perpsTrading';

jest.mock('../chains', () => ({
  chains: { arbitrum: { getWalletAssets: jest.fn(), estimatePerpsDepositNetworkFee: jest.fn() } },
}));
jest.mock('../common/tokens', () => ({ ...jest.requireActual('../common/tokens'), getTokenBySlug: jest.fn() }));
jest.mock('../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../common/perpsAssets', () => ({ getPerpsAssetsFetchedAt: jest.fn() }));
jest.mock('../../util/fetch', () => ({ fetchWithTimeout: jest.fn(), handleFetchErrors: jest.fn() }));
jest.mock('./perpsPositions', () => ({
  ...jest.requireActual('./perpsPositions'),
  requestPerpsPositionsRefresh: jest.fn(),
}));
jest.mock('./perps', () => ({
  perpsBuildBalanceWithdraw: jest.fn(),
  perpsBuildWithdrawal: jest.fn(),
  perpsEstimateModifyPosition: jest.fn(),
  perpsGetActivities: jest.fn(),
  perpsGetAssets: jest.fn(),
  perpsGetAssetChart: jest.fn(),
  perpsEstimatePosition: jest.fn(),
  perpsGetPositions: jest.fn(),
  estimatePerpsDepositFundingGasUsdc: jest.fn().mockResolvedValue('0'),
  executePerpsOpenPosition: jest.fn(),
  executePerpsModifyPosition: jest.fn(),
  executePerpsClosePosition: jest.fn(),
  executePerpsDepositMargin: jest.fn(),
  executePerpsWithdrawMargin: jest.fn(),
  executePerpsOpenFromBalance: jest.fn(),
  executePerpsOpenPositionFromBalance: jest.fn(),
  getPerpsWallet: jest.requireActual('./perps').getPerpsWallet,
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
  leverage: 10,
};
let serial = 0;
let account: string;
const onUpdate = jest.fn();

function savedOperation(state: ApiPerpsOperation['state'], id = `saved-${++serial}`): ApiPerpsOperation {
  return { id, accountId: account, assetId: asset.id, kind: 'close', state, stage: 'withdrawal', createdAt: 1 };
}

function activities(...trades: Partial<ApiPerpsTradeActivity>[]) {
  return { activitiesByChain: { hyperliquid: { address: WALLET, activities: trades.map((trade, index) => ({
    id: `trade-${index}`, assetId: asset.id, dex: '', kind: 'open' as const, side: 'long' as const, timestamp: 1,
    ...trade,
  })) } } };
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

test('reconciliation keeps a known order unresolved while its trade is missing, without a replay', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, orderId: 123 };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities({ orderId: 124, kind: 'open', timestamp: 2 }));
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(perpsGetActivities).toHaveBeenCalledWith({
    addressByChain: { hyperliquid: WALLET }, startTime: 0, endTime: 1 + 7 * 60_000, limit: 100,
  });
  const quote = await perpsPrepareOrder(account, draft);
  await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `blocked-${++serial}`))
    .rejects.toThrow('PerpsOperationPending');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('reconciliation completes an unknown increase from its own trade and unlocks trading', async () => {
  const claimed = { ...savedOperation('completed'), kind: 'increase' as const, orderId: 40 };
  await perpsReconcileOperation(account, claimed);
  const saved = {
    ...savedOperation('unknown'), kind: 'increase' as const, stage: 'trade' as const, createdAt: 1000,
    depositTxHash: '0xdeposit', error: 'HTTP Error 504',
  };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities(
    { orderId: 39, kind: 'increase', timestamp: 999, size: '1' },
    { orderId: 40, kind: 'increase', timestamp: 1001, size: '1' },
    { orderId: 41, kind: 'increase', timestamp: 1002, size: '1', assetId: 'hyperliquid:hl:ETH' },
    { orderId: 42, kind: 'reduce', timestamp: 1003, size: '1' },
    { orderId: 44, kind: 'increase', timestamp: 1005, size: '0.004', positionSizeAfter: '0.014' },
    { orderId: 43, kind: 'increase', timestamp: 1004, size: '0.005', positionSizeAfter: '0.015' },
  ));
  expect(await perpsReconcileOperation(account, saved)).toEqual({
    ...saved, state: 'completed', stage: 'finished', error: undefined, orderId: 43, orderStatus: 'filled',
    filledSize: '0.005', positionSize: '0.015',
  });
  expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xnext',
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `next-${++serial}`))
    .toMatchObject({ state: 'completed' });
});

test('an acknowledged operation never takes a trade made after the user unlocked trading', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1000, acknowledgedAt: 2000 };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities({ orderId: 9201, timestamp: 2001, size: '1' }));
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  jest.mocked(perpsGetActivities).mockResolvedValue(activities(
    { orderId: 9202, timestamp: 2000, size: '1' }, { orderId: 9203, timestamp: 2500, size: '1' },
  ));
  expect(await perpsReconcileOperation(account, saved)).toMatchObject({ state: 'completed', orderId: 9202 });
});

test('an acknowledgement made during the trade read keeps a later trade from completing the operation', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1000 };
  const read = new Deferred<ReturnType<typeof activities>>();
  jest.mocked(perpsGetActivities).mockReturnValue(read.promise as any);
  const reconciliation = perpsReconcileOperation(account, saved);
  await Promise.resolve();
  const acknowledged = await perpsAcknowledgeOperation(account, saved);
  read.resolve(activities({ orderId: 9211, timestamp: acknowledged.acknowledgedAt! + 1, size: '1' }));
  expect(await reconciliation).toMatchObject({ state: 'unknown', acknowledgedAt: acknowledged.acknowledgedAt });
});

test('two operations reconciled at once cannot both take the same trade', async () => {
  const first = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1000 };
  const second = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1500 };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities({ orderId: 9221, timestamp: 2000, size: '1' }));
  const results = await Promise.all([
    perpsReconcileOperation(account, first), perpsReconcileOperation(account, second),
  ]);
  expect(results.map(({ state }) => state).sort()).toEqual(['completed', 'unknown']);
  expect(results.filter(({ orderId }) => orderId === 9221)).toHaveLength(1);
});

test('reconciliation reads the window around the order and takes no trade made after it', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1_000_000 };
  jest.mocked(perpsGetActivities)
    .mockResolvedValue(activities({ orderId: 9231, timestamp: 1_000_000 + 5 * 60_000 + 1 }));
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(perpsGetActivities).toHaveBeenLastCalledWith({
    addressByChain: { hyperliquid: WALLET }, startTime: 1_000_000 - 2 * 60_000,
    endTime: 1_000_000 + 7 * 60_000, limit: 100,
  });
});

test('an order whose window closed without any trade of its kind fails as not placed and unlocks trading', async () => {
  const saved = {
    ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1_000_000, depositTxHash: '0xdeposit',
    acknowledgedAt: 1_060_000,
  };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities(
    { orderId: 9261, kind: 'increase', timestamp: 1_100_000 },
    { orderId: 9262, assetId: 'hyperliquid:hl:ETH', timestamp: 1_100_000 },
  ));
  expect(await perpsReconcileOperation(account, saved)).toEqual({
    ...saved, state: 'failed', stage: 'finished', error: 'PerpsOrderNotPlaced',
  });
  expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xnext',
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `after-${++serial}`))
    .toMatchObject({ state: 'completed' });
});

test.each([
  ['its window is still open', { createdAt: Date.now() }, []],
  ['it has an order ID', { orderId: 9271 }, []],
  ['a trade of its kind falls within the clock margin', {}, [{ orderId: 9272, timestamp: 1_000_000 - 60_000 }]],
  ['a trade of its kind follows an acknowledgement', { acknowledgedAt: 1_010_000 },
    [{ orderId: 9273, timestamp: 1_020_000 }]],
] as const)('an order stays unknown rather than not placed when %s', async (_, fields, trades) => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1_000_000, ...fields };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities(...trades));
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
});

test('a window too busy for one page leaves an operation unknown', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, createdAt: 1000 };
  const busy = activities({ orderId: 9241, timestamp: 2000, size: '1' });
  jest.mocked(perpsGetActivities).mockResolvedValue({ activitiesByChain: { hyperliquid: {
    ...busy.activitiesByChain.hyperliquid, nextCursor: 'older',
  } } });
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
});

test('a trade smaller than the submitted order completes a restored operation as a partial fill', async () => {
  const saved = {
    ...savedOperation('unknown'), kind: 'increase' as const, createdAt: 1000, submittedOrderSize: '0.01',
  };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities(
    { orderId: 9251, kind: 'increase', timestamp: 2000, size: '0.004', positionSizeAfter: '0.014' },
  ));
  expect(await perpsReconcileOperation(account, saved)).toMatchObject({
    state: 'completed', orderId: 9251, filledSize: '0.004', error: 'PerpsPartialFill',
  });
});

test.each(['reduce', 'close'] as const)('reconciliation never reads trades for an unknown %s', async (kind) => {
  const saved = { ...savedOperation('unknown'), kind };
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(perpsGetActivities).not.toHaveBeenCalled();
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

test('acknowledged records retain their unknown outcome until their trade appears', async () => {
  const saved = { ...savedOperation('unknown'), kind: 'open' as const, orderId: 9123, acknowledgedAt: 100 };
  jest.mocked(perpsGetActivities).mockResolvedValue(activities());
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(await perpsAcknowledgeOperation(account, saved)).toEqual(saved);
  expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
  jest.mocked(perpsGetActivities).mockResolvedValue(activities({ orderId: 9123, timestamp: 5, size: '2' }));
  expect(await perpsReconcileOperation(account, saved)).toMatchObject({
    state: 'completed', acknowledgedAt: 100, orderId: 9123, filledSize: '2', positionSize: '2',
  });
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

test('a venue rejection of a withdrawal retry moved no funds, so recovery stays available', async () => {
  const partial = await perpsReconcileOperation(account, savedOperation('partial'));
  await perpsPrepareWithdrawal(account, partial.id);
  jest.mocked(perpsWithdrawReleasedMargin).mockImplementationOnce((_a, _t, _amount, onSubmitting) => {
    onSubmitting?.();
    return Promise.reject(new ApiServerError('[HL_EXCHANGE_ERROR] Insufficient USDC or HYPE balance', 500));
  });
  expect(await perpsRetryWithdrawal(account, 'token', partial.id)).toMatchObject({ state: 'partial' });
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
  expect(perpsGetAssets).toHaveBeenCalledWith('fa', undefined);
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
  expect(perpsGetAssets).toHaveBeenCalledWith('en', undefined);
  expect(fetchStoredChainAccount).not.toHaveBeenCalled();
  expect(perpsGetPositions).not.toHaveBeenCalled();
});

test('market snapshots carry the onboarding stories of the catalogue', async () => {
  const onboarding = { stories: [{
    id: 'intro',
    url: 'https://s3.mywallet.io/public/perps/stories/h/01-intro.mp4',
    preview: 'https://s3.mywallet.io/public/perps/stories/h/01-intro.webp',
    duration: 7,
    bytes: 625842,
  }] };
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset], { onboarding }) as any);
  expect((await perpsGetMarketSnapshot()).onboarding).toEqual(onboarding);

  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset]) as any);
  expect((await perpsGetMarketSnapshot()).onboarding).toBeUndefined();
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
  await expect(perpsGetLeverageEstimate(account, draft)).rejects.toThrow('PerpsUnsupportedAccount');
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsUnsupportedAccount');
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('review and submission refresh catalogue instead of authorizing a cached price', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  expect(perpsGetAssets).toHaveBeenLastCalledWith(undefined, { force: true });
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xdeposit',
  });
  await perpsExecuteReviewedOrder(account, 'token', quote.id, `fresh-prices-${++serial}`);
  expect(perpsGetAssets).toHaveBeenCalledTimes(2);
  expect(perpsGetAssets).toHaveBeenLastCalledWith(undefined, { force: true });
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
  jest.mocked(chains.arbitrum.estimatePerpsDepositNetworkFee).mockResolvedValue(12_000_000_000_000n);
  jest.mocked(getTokenBySlug).mockReturnValue({ priceUsd: 2000 } as any);
  jest.mocked(estimatePerpsDepositFundingGasUsdc).mockResolvedValue('0.024');
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n,
    [getChainConfig('arbitrum').nativeToken.slug]: 1_000_000_000_000_000n,
  });
  jest.mocked(perpsEstimatePosition).mockImplementation((request) => Promise.resolve({
    orderValue: '0', marginRequired: '0',
    size: request.depositAmount !== undefined
      ? Big(request.depositAmount).minus(request.reduceOnly || request.fundingSource === 'balance' ? 0 : '0.2')
        .mul(request.leverage ?? 10)
        .div(100000).round(5, request.reduceOnly ? Big.roundUp : Big.roundDown).toFixed()
      : '0.01',
    liquidationPrice: '90501',
  }));
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset]) as any);
  jest.mocked(perpsGetPositions).mockResolvedValue(state() as any);
});

test('a submitted reviewed order refreshes the account positions once it finishes', async () => {
  const rejected = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({ error: 'InsufficientBalance' } as any);
  await perpsExecuteReviewedOrder(account, 'token', rejected.id, `rejected-${++serial}`);
  expect(requestPerpsPositionsRefresh).not.toHaveBeenCalled();

  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    return Promise.resolve({ address: WALLET, rawResponse: {}, depositTxHash: '0xdeposit', status: 'filled', oid: 7 });
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `filled-${++serial}`))
    .toMatchObject({ state: 'completed' });
  expect(requestPerpsPositionsRefresh).toHaveBeenCalledTimes(1);
  expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
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

test.each([0n])('gasless deposits ignore low ETH but still require USDC: %s', async (eth) => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: eth,
  });
  await expect(perpsPrepareOrder(account, draft)).resolves.toMatchObject({ kind: 'open' });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsInsufficientUsdc');
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: eth,
  });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, amount: '120' }))
    .rejects.toThrow('PerpsInsufficientUsdc');
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: eth,
  });
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, amount: '75' }))
    .resolves.toMatchObject({ kind: 'reduce' });
  await expect(perpsPrepareOrder(account, { ...draft, editing: true, close: true }))
    .resolves.toMatchObject({ kind: 'close' });
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test('funding requirements are available before amount entry and refresh after acquiring funds', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValueOnce({});
  expect(await perpsGetFundingRequirements(account, { ...draft, amount: '' })).toMatchObject({
    requiredUsdc: '10.2', requiredGasUsdc: '0.024', requiredEth: '0', needsUsdc: true, needsEth: false,
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
    .toMatchObject({ requiredUsdc: '20.2', needsUsdc: true, needsEth: false });
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
    .toMatchObject({ needsUsdc: true, needsEth: false });
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
    .resolves.toMatchObject({ state: 'failed', error: 'PerpsInsufficientUsdc', stage: 'preparing' });
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
  const other = `${++serial}-mainnet`;
  await expect(perpsExecuteReviewedOrder(other, 'token', quote.id, 'completed')).rejects.toThrow(
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

describe('an order whose execute request a proxy ended', () => {
  beforeEach(() => {
    jest.useFakeTimers({ now: 1_000_000 });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  async function executeAfterGatewayTimeout(trade?: () => Partial<ApiPerpsTradeActivity>) {
    const quote = await perpsPrepareOrder(account, draft);
    jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      hooks?.onDeposit?.('0xdeposit');
      return Promise.reject(new ApiServerError('HTTP Error 504', 504));
    });
    let reads = 0;
    jest.mocked(perpsGetActivities).mockImplementation(() => Promise.resolve(
      ++reads < 3 || !trade ? activities() : activities({ kind: 'open', timestamp: Date.now(), ...trade() }),
    ));
    const result = perpsExecuteReviewedOrder(account, 'token', quote.id, `proxied-${++serial}`);
    await jest.runAllTimersAsync();
    return { result: await result, reads: () => reads };
  }

  test('stays running until its trade appears, then completes with it', async () => {
    const { result } = await executeAfterGatewayTimeout(() => ({ orderId: 77, size: '0.00498' }));
    expect(result).toMatchObject({
      state: 'completed', stage: 'finished', orderId: 77, orderStatus: 'filled', filledSize: '0.00498',
      positionSize: '0.00498', depositTxHash: '0xdeposit',
    });
    expect(result.error).toBeUndefined();
    const published = onUpdate.mock.calls.map(([update]) => update.operation).filter(Boolean);
    expect(published.slice(0, -1).every(({ state }) => state === 'running')).toBe(true);
    expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
    expect(executePerpsOpenPosition).toHaveBeenCalledTimes(1);
  });

  test('fails as not placed when no trade appears by the end of its window', async () => {
    const { result, reads } = await executeAfterGatewayTimeout();
    expect(result).toMatchObject({
      state: 'failed', stage: 'finished', error: 'PerpsOrderNotPlaced', depositTxHash: '0xdeposit',
    });
    expect(reads()).toBeGreaterThan(55);
    expect(Date.now() - result.createdAt).toBeGreaterThan(5 * 60_000);
    expect(Date.now() - result.createdAt).toBeLessThan(5 * 60_000 + 10_000);
    expect(executePerpsOpenPosition).toHaveBeenCalledTimes(1);
  });

  test('stays unknown and locked when its window ends with an unclear read', async () => {
    const quote = await perpsPrepareOrder(account, draft);
    jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      return Promise.reject(new ApiServerError('HTTP Error 504', 504));
    });
    jest.mocked(perpsGetActivities).mockRejectedValue(new ApiServerError('HTTP Error 502', 502));
    const execution = perpsExecuteReviewedOrder(account, 'token', quote.id, `unclear-${++serial}`);
    await jest.runAllTimersAsync();
    expect(await execution).toMatchObject({ state: 'unknown', error: 'HTTP Error 504' });
    jest.useRealTimers();
    const next = await perpsPrepareOrder(account, draft);
    await expect(perpsExecuteReviewedOrder(account, 'token', next.id, 'retry')).rejects.toThrow(
      'PerpsOperationPending',
    );
  });
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
    jest.mocked(executePerpsClosePosition).mockResolvedValueOnce(undefined);
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
  jest.mocked(perpsGetActivities).mockRejectedValue(new ApiServerError('HTTP Error 502', 502));
  expect(await perpsReconcileOperation(account, saved)).toEqual(saved);
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
  expect(executePerpsClosePosition).not.toHaveBeenCalled();
});

test('a filled close whose withdrawal the venue rejected completes and says so, without locking', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, amount: '0', editing: true, close: true });
  const reason = '[HL_EXCHANGE_ERROR] Insufficient USDC or HYPE balance for token transfer gas.';
  jest.mocked(executePerpsClosePosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onTrade?.({ address: WALLET, rawResponse: {}, status: 'filled', oid: 77 });
    hooks?.onWithdrawal?.('10.747442');
    hooks?.onWithdrawalRejected?.(reason);
    return Promise.resolve(undefined);
  });
  const closed = await perpsExecuteReviewedOrder(account, 'token', quote.id, `close-${++serial}`);
  expect(closed).toMatchObject({
    state: 'completed', stage: 'finished', orderId: 77, error: `PerpsWithdrawalRejected: ${reason}`,
  });
  jest.mocked(perpsGetPositions).mockResolvedValue(state() as any);
  await expect(perpsPrepareOrder(account, draft)).resolves.toBeDefined();
});

test('a filled full close without a withdrawal completes and keeps its proceeds on Hyperliquid', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { ...draft, amount: '0', editing: true, close: true });
  jest.mocked(executePerpsClosePosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onTrade?.({ address: WALLET, rawResponse: {}, status: 'filled', oid: 77 });
    return Promise.resolve(undefined);
  });
  const closed = await perpsExecuteReviewedOrder(account, 'token', quote.id, `close-${++serial}`);
  expect(closed).toMatchObject({ state: 'completed', stage: 'finished', orderId: 77 });
  expect(closed.withdrawalAmount).toBeUndefined();
  await expect(perpsPrepareWithdrawal(account, closed.id)).rejects.toThrow('PerpsInvalidOperation');
  expect(perpsBuildWithdrawal).not.toHaveBeenCalled();
  jest.mocked(perpsGetPositions).mockResolvedValue(state() as any);
  const next = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockResolvedValueOnce({
    address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xdeposit',
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', next.id, `after-close-${++serial}`))
    .toMatchObject({ state: 'completed' });
});

test('a filled reduction that withdraws nothing is complete and locks nothing', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const quote = await perpsPrepareOrder(account, { kind: 'reduce', assetId: asset.id, amount: '20' });
  jest.mocked(executePerpsModifyPosition).mockImplementation((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled', oid: 78 });
  });
  const completed = await perpsExecuteReviewedOrder(account, 'token', quote.id, `reduce-${++serial}`);
  expect(completed).toMatchObject({ state: 'completed', stage: 'finished', orderId: 78 });
  const increase = await perpsPrepareOrder(account, { kind: 'increase', assetId: asset.id, amount: '20.2' });
  await expect(perpsExecuteReviewedOrder(account, 'token', increase.id, `increase-${++serial}`))
    .resolves.toMatchObject({ state: 'completed' });
});

test('a saved partial reduction withdraws what is free, up to its released margin', async () => {
  const partial = await perpsReconcileOperation(account, {
    ...savedOperation('partial'), kind: 'reduce', withdrawalRequestedAmount: '20',
  });
  jest.mocked(perpsBuildWithdrawal)
    .mockResolvedValueOnce({ address: WALLET, withdraw: perpsWithdrawalFixture(WALLET, '12.5') });
  expect(await perpsPrepareWithdrawal(account, partial.id)).toBe('12.5');
  expect(perpsBuildWithdrawal).toHaveBeenCalledWith(expect.objectContaining({ amountUsdc: '20' }));
});

test('a saved partial reduction with nothing to withdraw completes instead of staying locked', async () => {
  const partial = await perpsReconcileOperation(account, {
    ...savedOperation('partial'), kind: 'reduce', withdrawalRequestedAmount: '20',
  });
  jest.mocked(perpsBuildWithdrawal).mockResolvedValueOnce({ address: WALLET });
  await expect(perpsPrepareWithdrawal(account, partial.id)).rejects.toThrow('PerpsWithdrawalPending');
  expect((await perpsReconcileOperation(account, partial)).state).toBe('completed');
});

test('close recovery never sweeps more than the withdrawal the close prepared', async () => {
  const prepared = await perpsReconcileOperation(account, { ...savedOperation('partial'), withdrawalAmount: '42.5' });
  jest.mocked(perpsBuildWithdrawal)
    .mockResolvedValue({ address: WALLET, withdraw: perpsWithdrawalFixture(WALLET, '42.5') });
  expect(await perpsPrepareWithdrawal(account, prepared.id)).toBe('42.5');
  expect(perpsBuildWithdrawal).toHaveBeenLastCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, amountUsdc: '42.5',
  });
  jest.mocked(perpsBuildWithdrawal).mockResolvedValue({ address: WALLET, withdraw: perpsWithdrawalFixture(WALLET) });
  await expect(perpsPrepareWithdrawal(account, prepared.id)).rejects.toThrow('PerpsReviewChanged');

  const unprepared = await perpsReconcileOperation(account, savedOperation('partial'));
  expect(await perpsPrepareWithdrawal(account, unprepared.id)).toBe('99.97');
  expect(perpsBuildWithdrawal).toHaveBeenLastCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, amountUsdc: undefined,
  });
  jest.mocked(perpsWithdrawReleasedMargin).mockRejectedValueOnce(new Error(ApiCommonError.InvalidPassword));
  expect(await perpsRetryWithdrawal(account, 'expired-token', unprepared.id))
    .toMatchObject({ state: 'partial', withdrawalAmount: '99.97' });
  await perpsPrepareWithdrawal(account, unprepared.id);
  expect(perpsBuildWithdrawal).toHaveBeenLastCalledWith(expect.objectContaining({ amountUsdc: '99.97' }));
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
    kind: 'leverage', paymentAmount: '55.2', modify: { leverage: 5, depositAmount: '55.2' },
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

test('loads grouped trades through backend activities for the selected wallet', async () => {
  jest.mocked(perpsGetActivities).mockResolvedValueOnce({ activitiesByChain: { hyperliquid: {
    address: WALLET.toUpperCase(), activities: [{ id: 'BTC/42/open', orderId: 42, fillIds: [1], assetId: asset.id,
      dex: '', kind: 'open', side: 'long', timestamp: 1000, size: '2', entryPrice: '100', notional: '200',
      fees: { trading: '0.3', builder: '0.2' }, positionOpenedAt: 1000 }],
  } } });
  expect(await perpsGetActivityHistory(account)).toMatchObject({ hasActivity: true, fills: [{
    activityId: 'BTC/42/open', eventKind: 'opened', positionSide: 'long', oid: 42, notional: '200',
    fee: '0.3', positionOpenedAt: 1000,
  }] });
  expect(perpsGetActivities).toHaveBeenCalledTimes(1);
  expect(perpsGetActivities).toHaveBeenCalledWith({
    addressByChain: { hyperliquid: WALLET },
  });
  expect(perpsGetAssets).not.toHaveBeenCalled();
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
  await expect(perpsGetLeverageEstimate(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
  await expect(perpsGetFundingRequirements(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
  await expect(perpsPreviewOrder(account, draft)).rejects.toThrow('PerpsTradingUnavailable');
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

test('an open shows the margin the order posts and the deposit left free on Hyperliquid', async () => {
  const largeLot = {
    ...asset, id: 'hyperliquid:hl:ZEC', name: 'ZEC', symbol: 'ZEC', wireAssetIndex: 7, szDecimals: 2,
    maxLeverage: 10, context: { ...asset.context, markPx: '1241' },
  };
  jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([largeLot]) as any);
  jest.mocked(perpsEstimatePosition).mockResolvedValue({
    size: '0.01', orderValue: '12.41', marginRequired: '6.21', liquidationPrice: '700',
    estimatedFees: { exchange: '0.005585', service: '0.010921', trading: '0.016506', bridge: '0.2', total: '0.216506' },
  });
  const quote = await perpsPrepareOrder(account, { ...draft, assetId: largeLot.id, amount: '10', leverage: 2 });
  expect(quote).toMatchObject({
    collateral: '10', paymentAmount: '10.2', notional: '12.41',
    estimatedCollateral: '6.21', estimatedRemainingCollateral: '3.773494',
  });
});

test.each([
  ['fees exceed the unallocated credit', { trading: '0.66', bridge: '0.2', total: '0.86' }],
  ['fees are unknown', undefined],
])('the remainder stays unset when %s', async (_, estimatedFees) => {
  jest.mocked(perpsEstimatePosition).mockResolvedValue({
    size: '0.00499', orderValue: '499', marginRequired: '49.9', liquidationPrice: '90501', estimatedFees,
  });
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.estimatedCollateral).toBe('49.9');
  expect(quote.estimatedRemainingCollateral).toBeUndefined();
});

test('an increase prices the resulting position at the estimate and adds its margin to the current one', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimatePosition).mockResolvedValue({
    size: '0.001', orderValue: '100.5', marginRequired: '10.05', liquidationPrice: '90000',
  });
  expect(await perpsPrepareOrder(account, { kind: 'increase', assetId: asset.id, amount: '10.2' })).toMatchObject({
    kind: 'increase', size: '0.011', notional: '1105.5', previousCollateral: '100', estimatedCollateral: '110.05',
  });
});

test('a reduce prices the remaining position at the estimate and carries its withdrawal bridge fee', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const estimatedFees = { exchange: '0.09', service: '0.18', trading: '0.27', bridge: '0.2', total: '0.47' };
  jest.mocked(perpsEstimatePosition).mockResolvedValue({
    size: '0.002', orderValue: '201', marginRequired: '0', liquidationPrice: '89000', estimatedFees,
  });
  const intent = { kind: 'reduce' as const, assetId: asset.id, amount: '20' };
  const expected = { kind: 'reduce', size: '0.008', notional: '804', bridgeFee: '0.2', estimatedFees };
  expect(await perpsPreviewOrder(account, intent)).toMatchObject(expected);
  const quote = await perpsPrepareOrder(account, intent);
  expect(quote).toMatchObject(expected);
  expect(quote.estimatedCollateral).toBeUndefined();
  expect(quote.estimatedRemainingCollateral).toBeUndefined();
});

test('deposit-funded quotes carry the deposit network fee in ETH when the wallet covers it', async () => {
  expect(await perpsPrepareOrder(account, draft)).toMatchObject({
    estimatedNetworkFeeEth: '0.000012', estimatedNetworkFeeUsd: '0.024',
    fundingRequirements: { requiredEth: '0.000012', requiredEthUsd: '0.024', requiredGasUsdc: '0', needsEth: false },
  });
  expect(chains.arbitrum.estimatePerpsDepositNetworkFee).toHaveBeenCalledWith('mainnet', WALLET);
  expect(estimatePerpsDepositFundingGasUsdc).not.toHaveBeenCalled();
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  expect(await perpsPreviewOrder(account, { kind: 'increase', assetId: asset.id, amount: '10.2' }))
    .toMatchObject({ kind: 'increase', estimatedNetworkFeeEth: '0.000012', estimatedNetworkFeeUsd: '0.024' });
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '50.2' });
  expect(await perpsPreviewOrder(account, { kind: 'leverage', assetId: asset.id, leverage: 5 }))
    .toMatchObject({ kind: 'leverage', paymentAmount: '55.2', bridgeFee: '0.2', estimatedNetworkFeeEth: '0.000012' });
});

test('a deposit without enough ETH pays its gas in USDC', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: 1n,
  });
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote).toMatchObject({
    estimatedNetworkFeeUsdc: '0.024',
    fundingRequirements: { requiredGasUsdc: '0.024', requiredEth: '0', needsEth: false, needsUsdc: false },
  });
  expect(quote.estimatedNetworkFeeEth).toBeUndefined();
  expect(estimatePerpsDepositFundingGasUsdc).toHaveBeenCalledWith(account, WALLET, '50.2');
});

test.each([
  ['reduce', { kind: 'reduce', amount: '20' }, '0.2'],
  ['close', { kind: 'close' }, '0.2'],
  ['leverage change without a deposit', { kind: 'leverage', leverage: 20 }, '0'],
] as const)('a %s quote has no network fee', async (_, intent, bridgeFee) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '0' });
  const quote = await perpsPrepareOrder(account, { ...intent, assetId: asset.id });
  expect(quote).toMatchObject({ bridgeFee, fundingRequirements: { requiredEth: '0', requiredEthUsd: '0' } });
  expect(quote.estimatedNetworkFeeEth).toBeUndefined();
  expect(quote.estimatedNetworkFeeUsdc).toBeUndefined();
  expect(chains.arbitrum.estimatePerpsDepositNetworkFee).not.toHaveBeenCalled();
  expect(estimatePerpsDepositFundingGasUsdc).not.toHaveBeenCalled();
});

test('an open reads its network fee alongside the backend estimate', async () => {
  const estimate = jest.mocked(perpsEstimatePosition).getMockImplementation()!;
  let feeReadStarted = false;
  jest.mocked(perpsEstimatePosition).mockImplementationOnce((request) => {
    feeReadStarted = jest.mocked(chains.arbitrum.estimatePerpsDepositNetworkFee).mock.calls.length === 1;
    return estimate(request);
  });
  await perpsPrepareOrder(account, draft);
  expect(feeReadStarted).toBe(true);
  expect(estimatePerpsDepositFundingGasUsdc).not.toHaveBeenCalled();
});

test('a gasless quote is requested only after the native fee shows ETH does not cover it', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: 0n,
  });
  const estimate = jest.mocked(perpsEstimatePosition).getMockImplementation()!;
  let gaslessDuringEstimate = false;
  jest.mocked(perpsEstimatePosition).mockImplementationOnce((request) => {
    gaslessDuringEstimate = jest.mocked(estimatePerpsDepositFundingGasUsdc).mock.calls.length > 0;
    return estimate(request);
  });
  await perpsPrepareOrder(account, draft);
  expect(gaslessDuringEstimate).toBe(false);
  expect(estimatePerpsDepositFundingGasUsdc).toHaveBeenCalledWith(account, WALLET, '50.2');
});

test('when the paymaster quote is unavailable a gasless deposit still reserves USDC', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: 0n,
  });
  jest.mocked(estimatePerpsDepositFundingGasUsdc).mockResolvedValueOnce('0.5');
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.fundingRequirements).toMatchObject({ requiredGasUsdc: '0.5', requiredEth: '0', needsEth: false });
  expect(quote.estimatedNetworkFeeUsdc).toBe('0.5');

  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({ [ARBITRUM_USDC_MAINNET.slug]: 200_000000n });
  await expect(perpsPrepareOrder(account, draft)).resolves.toMatchObject({ kind: 'open' });

  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsInsufficientUsdc');
});

test('a deposit records the most ETH its userOp can cost on the operation', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
    hooks?.onSubmitting?.();
    hooks?.onDeposit?.('0xdeposit');
    return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xdeposit' });
  });
  expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `fee-${++serial}`)).toMatchObject({
    state: 'completed', depositTxHash: '0xdeposit',
  });
});

test('quotes use backend liquidation estimates without inventing net collateral or fees', async () => {
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.estimatedCollateral).toBeUndefined();
  expect(quote.estimatedLiquidationPrice).toBe('90501');
  expect(quote.estimatedFees).toBeUndefined();
  expect(await perpsGetLeverageEstimate(account, draft)).toEqual({ leverage: 10, liquidationPrice: '90501' });
});

describe('a first order that switches the account to Unified', () => {
  const eth = { ...asset, id: 'hyperliquid:hl:ETH', index: 1, name: 'ETH', symbol: 'ETH', wireAssetIndex: 1 };
  const build = {
    marketReferencePrice: '100000',
    updateLeverage: { action: { asset: 0, leverage: 10, isCross: false } } as any,
    action: { orders: [{ a: 0, b: true, r: false, s: '0.005', p: '100500', t: { limit: { tif: 'Ioc' } } }] },
    deposit: { ...depositFixture, requiresPermitSignature: true as const },
    setAbstraction: { action: { type: 'userSetAbstraction', abstraction: 'unifiedAccount' } } as any,
  };

  function readAccount(abstractionMode: string, positions: unknown[] = []) {
    jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset, eth]) as any);
    jest.mocked(perpsGetPositions).mockResolvedValue({
      positionsByChain: { hyperliquid: { ...state(positions).positionsByChain.hyperliquid, abstractionMode } },
    } as any);
  }

  function estimateSwitch() {
    jest.mocked(perpsEstimatePosition).mockResolvedValueOnce({
      size: '0.005', orderValue: '500', marginRequired: '50', switchesToUnified: true,
    });
  }

  function execute(quoteId: string) {
    jest.mocked(executePerpsOpenPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks.validateBuild?.(build);
      return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled', depositTxHash: '0xhash' });
    });
    return perpsExecuteReviewedOrder(account, 'token', quoteId, `switch-${++serial}`);
  }

  test('a build the review did not disclose is refused before anything is signed', async () => {
    readAccount('default');
    const quote = await perpsPrepareOrder(account, draft);
    expect(quote.switchesToUnified).toBeUndefined();
    expect(await execute(quote.id)).toMatchObject({ state: 'failed', error: 'PerpsReviewChanged' });
  });

  test('the quote carries what the estimate reports, and a build matching it goes through', async () => {
    readAccount('default');
    estimateSwitch();
    const quote = await perpsPrepareOrder(account, draft);
    expect(quote.switchesToUnified).toBe(true);
    expect(await execute(quote.id)).toMatchObject({ state: 'completed' });
  });

  test.each([
    ['already chose a mode', 'unifiedAccount', []],
    ['holds a position in another market', 'default', [{ ...position, coin: 'ETH' }]],
    ['holds a position in a book the catalogue omits', 'default', [{ ...position, coin: 'new:ANY' }]],
  ])('a fresh read of an account that %s refuses the switch', async (_, mode, positions) => {
    readAccount(mode, positions);
    estimateSwitch();
    const quote = await perpsPrepareOrder(account, draft);
    expect(await execute(quote.id)).toMatchObject({ state: 'failed', error: 'PerpsReviewChanged' });
  });
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
  await expect(perpsGetLeverageEstimate(account, draft)).rejects.toThrow('PerpsOrderTooSmall');
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  await expect(perpsGetLeverageEstimate(account, { ...draft, editing: true, amount: '120' }))
    .rejects.toThrow('PerpsOrderTooSmall');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  expect(executePerpsModifyPosition).not.toHaveBeenCalled();
});

test('USDC leverage previews check the cached catalogue without requesting positions or balances', async () => {
  expect(await perpsGetLeverageEstimate(account, { ...draft, leverage: 2 }))
    .toEqual({ leverage: 2, liquidationPrice: '90501' });
  expect(perpsEstimatePosition).toHaveBeenCalledWith({
    chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long',
    depositAmount: '50.2', leverage: 2, isCross: false,
  });
  expect(perpsGetAssets).toHaveBeenCalledWith();
  expect(perpsGetPositions).not.toHaveBeenCalled();
  expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
});

test('a leverage preview without an amount prices nothing', async () => {
  expect(await perpsGetLeverageEstimate(account, { ...draft, amount: '' })).toEqual({ leverage: 10 });
  expect(perpsEstimatePosition).not.toHaveBeenCalled();
});

test('a leverage preview below the opening minimum is not an executable review', async () => {
  expect(await perpsGetLeverageEstimate(account, { ...draft, amount: '1' }))
    .toEqual({ leverage: 10, liquidationPrice: '90501' });
  await expect(perpsPrepareOrder(account, { ...draft, amount: '1' })).rejects.toThrow('PerpsAmountTooSmall');
  expect(executePerpsOpenPosition).not.toHaveBeenCalled();
});

test.each(['0', '-1', undefined])('a nonpositive or unavailable liquidation price stays absent: %s', async (price) => {
  jest.mocked(perpsEstimatePosition).mockResolvedValueOnce({
    size: '0.0001', orderValue: '10', marginRequired: '5', liquidationPrice: price,
  });
  expect(await perpsGetLeverageEstimate(account, draft))
    .toEqual({ leverage: 10, liquidationPrice: undefined });
});

test('unchanged leverage keeps the current liquidation price without requesting a resize estimate', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  expect(await perpsGetLeverageEstimate(account, { ...draft, editing: true, reset: true }))
    .toEqual({ leverage: 10, liquidationPrice: '90500' });
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
  expect((await perpsReconcileOperation(account, partial)).state).toBe('completed');
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
  jest.mocked(executePerpsClosePosition).mockResolvedValueOnce(undefined);
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
    finish = () => resolve(undefined);
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

test.each([[-25, 'reduce'], [-5, 'reduce'], [5, 'increase'], [25, 'increase']] as const)(
  'a preview of a %i%% wallet-funded edit sizes it from the position', async (fraction, kind) => {
    jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
    await expect(perpsPreviewOrder(account, { ...draft, editing: true, fraction })).resolves.toMatchObject({ kind });
  },
);

test('a reduce and a close quote what should reach the wallet once the fees are known', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  const estimatedFees = { trading: '0.3', bridge: '0.2', total: '0.5' };
  jest.mocked(perpsEstimatePosition).mockImplementation((request) => Promise.resolve({
    orderValue: '500', marginRequired: '0', size: request.close ? '0.01' : '0.005', estimatedFees,
  }));
  // The position's value is 110. A close delivers all of it, and half the size delivers half, less the fees.
  await expect(perpsPreviewOrder(account, { ...draft, editing: true, close: true }))
    .resolves.toMatchObject({ kind: 'close', estimatedReceiveAmount: '109.5' });
  await expect(perpsPreviewOrder(account, { ...draft, editing: true, amount: '50' }))
    .resolves.toMatchObject({ kind: 'reduce', estimatedReceiveAmount: '54.5' });
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
      .toMatchObject({ needsUsdc: true, needsEth: false });
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
    .toMatchObject({ usdcBalance: '0', needsUsdc: true, needsEth: false });
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

test('gasless deposits ignore a low ETH balance during preparation', async () => {
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({
    [ARBITRUM_USDC_MAINNET.slug]: 200_000000n, [getChainConfig('arbitrum').nativeToken.slug]: 1n,
  });
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.fundingRequirements).toMatchObject({
    requiredGasUsdc: '0.024', requiredEth: '0', needsEth: false, needsUsdc: false,
  });
  expect(quote.estimatedNetworkFeeUsdc).toBe('0.024');
  expect(quote.estimatedNetworkFeeEth).toBeUndefined();
});

test('an unavailable native fee quote pays the deposit gas in USDC', async () => {
  jest.mocked(chains.arbitrum.estimatePerpsDepositNetworkFee).mockRejectedValue(new Error('rpc down'));
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.estimatedNetworkFeeEth).toBeUndefined();
  expect(quote.estimatedNetworkFeeUsdc).toBe('0.024');
  expect(quote.fundingRequirements).toMatchObject({ requiredGasUsdc: '0.024', requiredEth: '0', needsEth: false });
});

test('a covered native fee without an ETH price stays in ETH and uses the display reserve', async () => {
  jest.mocked(getTokenBySlug).mockReturnValue(undefined);
  const quote = await perpsPrepareOrder(account, draft);
  expect(quote.estimatedNetworkFeeEth).toBe('0.000012');
  expect(quote.estimatedNetworkFeeUsd).toBeUndefined();
  expect(quote.estimatedNetworkFeeUsdc).toBeUndefined();
  expect(quote.fundingRequirements).toMatchObject({
    requiredEth: '0.0001', requiredEthUsd: '0.25', requiredGasUsdc: '0', needsEth: false,
  });
  expect(estimatePerpsDepositFundingGasUsdc).not.toHaveBeenCalled();
});

test('leverage funding hints and preparation use the backend deposit requirement', async () => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '50.2' });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({});
  const leverageDraft = { ...draft, editing: true, leverageOnly: true, amount: '200', leverage: 5 };
  expect(await perpsGetFundingRequirements(account, leverageDraft))
    .toMatchObject({ requiredUsdc: '50.2', needsUsdc: true, needsEth: false });
  expect(await perpsPreviewOrder(account, leverageDraft))
    .toMatchObject({ kind: 'leverage', previousLeverage: 10, paymentAmount: '55.2', size: '0.01' });
  await expect(perpsPrepareOrder(account, leverageDraft)).rejects.toThrow('PerpsInsufficientUsdc');
});

test.each([
  ['covers the need but not all the headroom', 52_000000n, '52', false],
  ['covers the headroom', 60_000000n, '55.2', false],
  ['does not cover the need', 40_000000n, '55.2', true],
])('a leverage preview for a wallet that %s reports only a real shortfall', async (_, balance, payment, needsUsdc) => {
  jest.mocked(perpsGetPositions).mockResolvedValue(state([position]) as any);
  jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '50.2' });
  jest.mocked(chains.arbitrum.getWalletAssets).mockResolvedValue({ [ARBITRUM_USDC_MAINNET.slug]: balance });
  const leverageDraft = { ...draft, editing: true, leverageOnly: true, amount: '200', leverage: 5 };
  expect(await perpsPreviewOrder(account, leverageDraft)).toMatchObject({
    paymentAmount: payment, fundingRequirements: { requiredUsdc: '50.2', needsUsdc },
  });
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

test('account snapshots preserve backend abstraction mode and spendable balances', async () => {
  const response = state([position]);
  jest.mocked(perpsGetPositions).mockResolvedValue({ positionsByChain: { hyperliquid: {
    ...response.positionsByChain.hyperliquid, abstractionMode: 'unifiedAccount',
    spotUsdcTotal: '120', spotUsdcAvailable: '20', spendableUsdcByDex: { '': '20', xyz: '20' },
  } } } as any);
  expect(await perpsGetSnapshot(account)).toMatchObject({ abstractionMode: 'unifiedAccount',
    spendableUsdcByDex: { '': '20', xyz: '20' } });
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

describe('balance funding', () => {
  const balanceDraft = { ...draft, funding: 'balance' as const };
  const nativeFees = { exchange: '0.225', service: '0.44', trading: '0.665', bridge: '0', total: '0.665' };

  function balanceState(positions: unknown[] = [], spendableUsdcByDex: Record<string, string> = { '': '100' }) {
    const { hyperliquid } = state(positions).positionsByChain;
    return { positionsByChain: { hyperliquid: { ...hyperliquid, spendableUsdcByDex } } };
  }

  beforeEach(() => {
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState() as any);
  });

  test('an open posts the whole amount from the balance without bridge, network fee or wallet read', async () => {
    jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset], {
      limitsByChain: { hyperliquid: { ...hyperliquidLimits, minOpenDepositUsdc: '60.2' } },
    }) as any);
    const expected = {
      kind: 'open', funding: 'balance', paymentAmount: '50', bridgeFee: '0', collateral: '50', orderSize: '0.005',
      openFromBalance: { chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long', amount: '50',
        leverage: 10, isCross: false, slippage: 0.03 },
      fundingRequirements: { requiredUsdc: '0', requiredEth: '0', requiredEthUsd: '0', usdcBalance: '100',
        availableCollateral: '98.619329', ethBalance: '0', needsUsdc: false, needsEth: false },
    };
    expect(await perpsPreviewOrder(account, balanceDraft)).toMatchObject(expected);
    const quote = await perpsPrepareOrder(account, balanceDraft);
    expect(quote).toMatchObject(expected);
    expect(quote.open).toBeUndefined();
    expect(quote.estimatedNetworkFeeEth).toBeUndefined();
    expect(perpsEstimatePosition).toHaveBeenLastCalledWith({
      chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long', depositAmount: '50', leverage: 10,
      isCross: false, fundingSource: 'balance',
    });
    expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
    expect(chains.arbitrum.estimatePerpsDepositNetworkFee).not.toHaveBeenCalled();
    await expect(perpsPrepareOrder(account, draft)).rejects.toThrow('PerpsAmountTooSmall');
  });

  test('a balance quote shows the margin its order posts but no deposit left free', async () => {
    jest.mocked(perpsEstimatePosition).mockResolvedValue({
      size: '0.0049', orderValue: '490', marginRequired: '49', liquidationPrice: '90501', estimatedFees: nativeFees,
    });
    const quote = await perpsPrepareOrder(account, balanceDraft);
    expect(quote).toMatchObject({ estimatedCollateral: '49', estimatedFees: nativeFees });
    expect(quote.estimatedRemainingCollateral).toBeUndefined();
  });

  test('funding requirements and leverage previews of a balance draft read no wallet balance', async () => {
    expect(await perpsGetFundingRequirements(account, { ...balanceDraft, amount: '' })).toMatchObject({
      usdcBalance: '100', availableCollateral: '98.619329', needsUsdc: false, needsEth: false,
    });
    expect(await perpsGetLeverageEstimate(account, balanceDraft))
      .toEqual({ leverage: 10, liquidationPrice: '90501' });
    expect(perpsEstimatePosition).toHaveBeenCalledWith(expect.objectContaining({
      depositAmount: '50', fundingSource: 'balance',
    }));
    expect(chains.arbitrum.getWalletAssets).not.toHaveBeenCalled();
    expect(chains.arbitrum.estimatePerpsDepositNetworkFee).not.toHaveBeenCalled();
  });

  test('wallet funding keeps its bridge deposit and sends no funding source', async () => {
    const quote = await perpsPrepareOrder(account, draft);
    expect(quote).toMatchObject({ paymentAmount: '50.2', bridgeFee: '0.2', open: { depositAmount: '50.2' } });
    expect(quote.funding).toBeUndefined();
    expect(quote.openFromBalance).toBeUndefined();
    expect(perpsEstimatePosition)
      .toHaveBeenCalledWith(expect.not.objectContaining({ fundingSource: expect.anything() }));
    expect(chains.arbitrum.getWalletAssets).toHaveBeenCalledTimes(1);
  });

  test('100% fills the most the balance funds after trading fees and passes review', async () => {
    const quote = await perpsPrepareOrder(account, { ...balanceDraft, fraction: 100 });
    expect(quote).toMatchObject({ inputAmount: '98.619329', paymentAmount: '98.619329' });
    const estimate = jest.mocked(perpsEstimatePosition).getMockImplementation()!;
    jest.mocked(perpsEstimatePosition).mockImplementation(async (request) => ({
      ...await estimate(request), estimatedFees: { trading: '1.3116', total: '1.3116' },
    }));
    await expect(perpsPrepareOrder(account, { ...balanceDraft, fraction: 100 })).resolves.toMatchObject({
      paymentAmount: '98.619329',
    });
  });

  test.each([
    ['the estimated trading fee', nativeFees, '50.664999', '50.665'],
    ['the fee headroom without a fee estimate', undefined, '50.699999', '50.7'],
  ])('review refuses a margin the balance cannot cover with %s', async (_, estimatedFees, short, enough) => {
    const estimate = jest.mocked(perpsEstimatePosition).getMockImplementation()!;
    jest.mocked(perpsEstimatePosition).mockImplementation(async (request) => ({
      ...await estimate(request), estimatedFees,
    }));
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([], { '': short }) as any);
    await expect(perpsPreviewOrder(account, balanceDraft)).rejects.toThrow('PerpsInsufficientBalance');
    await expect(perpsPrepareOrder(account, balanceDraft)).rejects.toThrow('PerpsInsufficientBalance');
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([], { '': enough }) as any);
    await expect(perpsPrepareOrder(account, balanceDraft)).resolves.toMatchObject({ funding: 'balance' });
  });

  test('a book without a spendable figure funds nothing', async () => {
    jest.mocked(perpsGetPositions).mockResolvedValue(state() as any);
    await expect(perpsPrepareOrder(account, balanceDraft)).rejects.toThrow('PerpsInsufficientBalance');
    expect(await perpsGetFundingRequirements(account, balanceDraft))
      .toMatchObject({ usdcBalance: '0', availableCollateral: '0', needsUsdc: false });
  });

  test('an increase takes its margin from the balance below the bridge deposit minimum', async () => {
    jest.mocked(perpsGetAssets).mockResolvedValue(assetsResult([asset], {
      limitsByChain: { hyperliquid: { ...hyperliquidLimits, minIncreaseDepositUsdc: '30.2' } },
    }) as any);
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([position]) as any);
    const quote = await perpsPrepareOrder(account, { ...balanceDraft, editing: true, amount: '120' });
    expect(quote).toMatchObject({
      kind: 'increase', funding: 'balance', paymentAmount: '20', bridgeFee: '0', orderSize: '0.002',
      modify: { depositAmount: '20', reduceOnly: false, fundingSource: 'balance' },
    });
    expect(quote.estimatedNetworkFeeEth).toBeUndefined();
    expect(perpsEstimatePosition).toHaveBeenLastCalledWith(expect.objectContaining({
      depositAmount: '20', reduceOnly: false, fundingSource: 'balance',
    }));
  });

  test('a leverage change pays the estimated margin from the balance', async () => {
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([position]) as any);
    const fees = { exchange: '0', service: '0', trading: '0', bridge: '0', total: '0' };
    jest.mocked(perpsEstimateModifyPosition)
      .mockResolvedValue({ depositAmount: '0', marginAmount: '100', estimatedFees: fees });
    const leverageDraft = { ...balanceDraft, editing: true, leverageOnly: true, amount: '100', leverage: 5 };
    const quote = await perpsPrepareOrder(account, leverageDraft);
    expect(quote).toMatchObject({
      kind: 'leverage', funding: 'balance', paymentAmount: '100', bridgeFee: '0', collateral: '200',
      estimatedFees: fees, modify: { leverage: 5, fundingSource: 'balance' },
    });
    expect(quote.modify?.depositAmount).toBeUndefined();
    expect(quote.estimatedNetworkFeeEth).toBeUndefined();
    expect(perpsEstimateModifyPosition).toHaveBeenCalledWith({
      chain: 'hyperliquid', address: WALLET, asset: asset.id, leverage: 5, fundingSource: 'balance',
    });
    expect(perpsEstimatePosition).toHaveBeenLastCalledWith(expect.objectContaining({ fundingSource: 'balance' }));
    expect(perpsEstimatePosition).toHaveBeenLastCalledWith(expect.not.objectContaining({
      depositAmount: expect.anything(),
    }));
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([position], { '': '99.999999' }) as any);
    await expect(perpsPrepareOrder(account, leverageDraft)).rejects.toThrow('PerpsInsufficientBalance');
  });

  test.each([{ amount: '75' }, { amount: '0', close: true }])(
    'a reduction ignores balance funding: %j', async (change) => {
      jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([position]) as any);
      const quote = await perpsPrepareOrder(account, { ...balanceDraft, editing: true, ...change });
      expect(quote).toMatchObject({ kind: change.close ? 'close' : 'reduce', bridgeFee: '0.2', paymentAmount: '0' });
      expect(quote.funding).toBeUndefined();
      expect(quote.modify?.fundingSource).toBeUndefined();
      expect(perpsEstimatePosition)
        .toHaveBeenCalledWith(expect.not.objectContaining({ fundingSource: expect.anything() }));
    },
  );

  test('an open executes from the balance without a deposit stage', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    jest.mocked(executePerpsOpenPositionFromBalance).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks.validateBuild?.({
        marketReferencePrice: '100000', updateLeverage: { action: { asset: 0, leverage: 10, isCross: false } } as any,
        action: { orders: [{ a: 0, b: true, r: false, s: '0.005', p: '103000', t: { limit: { tif: 'Ioc' } } }] },
      });
      hooks.onSubmitting?.();
      return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled', oid: 9, filledSize: '0.005' });
    });
    const id = `balance-open-${++serial}`;
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, id))
      .toMatchObject({ state: 'completed', stage: 'finished', orderId: 9 });
    expect(executePerpsOpenPositionFromBalance).toHaveBeenCalledWith(account, 'token', {
      chain: 'hyperliquid', address: WALLET, asset: asset.id, side: 'long', amount: '50', leverage: 10,
      isCross: false, slippage: 0.03,
    }, expect.any(Object));
    expect(executePerpsOpenPosition).not.toHaveBeenCalled();
    expect(onUpdate.mock.calls[0][0].operation).toMatchObject({ id, state: 'running', stage: 'trade' });
    expect(onUpdate.mock.calls.map(([update]) => update.operation.stage)).not.toContain('deposit');
  });

  test('a build carrying a deposit is refused before a balance open is signed', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    jest.mocked(executePerpsOpenPositionFromBalance).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks.validateBuild?.({
        marketReferencePrice: '100000', updateLeverage: { action: { asset: 0, leverage: 10, isCross: false } } as any,
        action: { orders: [{ a: 0, b: true, r: false, s: '0.005', p: '103000', t: { limit: { tif: 'Ioc' } } }] },
        deposit: { ...depositFixture, requiresPermitSignature: true as const },
      });
      return Promise.resolve({ address: WALLET, rawResponse: {}, status: 'filled' });
    });
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `balance-deposit-${++serial}`))
      .toMatchObject({ state: 'failed', error: 'PerpsReviewChanged' });
  });

  test.each(['increase', 'leverage'] as const)('a balance %s executes its reviewed modify request', async (kind) => {
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([position]) as any);
    jest.mocked(perpsEstimateModifyPosition).mockResolvedValue({ depositAmount: '0', marginAmount: '100' });
    const quote = await perpsPrepareOrder(account, kind === 'increase'
      ? { ...balanceDraft, editing: true, amount: '120' }
      : { ...balanceDraft, editing: true, leverageOnly: true, amount: '100', leverage: 5 });
    jest.mocked(executePerpsModifyPosition).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks.onSubmitting?.();
      return Promise.resolve({ address: WALLET, rawResponse: {}, status: kind === 'increase' ? 'filled' : 'ok' });
    });
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `balance-${kind}-${++serial}`))
      .toMatchObject({ state: 'completed', stage: 'finished' });
    expect(executePerpsModifyPosition).toHaveBeenCalledWith(account, 'token', quote.modify, expect.any(Object),
      kind === 'leverage' ? '100' : undefined);
    expect(quote.modify).toMatchObject({ fundingSource: 'balance' });
  });

  test('a rejected balance order moved no funds and fails without recovery', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    jest.mocked(executePerpsOpenPositionFromBalance).mockImplementationOnce((_a, _t, _r, hooks) => {
      hooks.onSubmitting?.();
      return Promise.resolve({ address: WALLET, rawResponse: {},
        status: 'error: Insufficient margin to place order. asset=0' });
    });
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `balance-rejected-${++serial}`))
      .toMatchObject({ state: 'failed', stage: 'finished', error: 'PerpsInsufficientMargin' });

    const next = await perpsPrepareOrder(account, balanceDraft);
    jest.mocked(executePerpsOpenPositionFromBalance).mockResolvedValueOnce({ error: 'InsufficientBalance' });
    expect(await perpsExecuteReviewedOrder(account, 'token', next.id, `balance-error-${++serial}`))
      .toMatchObject({ state: 'failed', error: 'InsufficientBalance' });
  });

  test('execution refuses a review the balance no longer covers', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    jest.mocked(perpsGetPositions).mockResolvedValue(balanceState([], { '': '40' }) as any);
    expect(await perpsExecuteReviewedOrder(account, 'token', quote.id, `balance-spent-${++serial}`))
      .toMatchObject({ state: 'failed', stage: 'preparing', error: 'PerpsInsufficientBalance' });
    expect(executePerpsOpenPositionFromBalance).not.toHaveBeenCalled();
  });

  test('a running balance order holds the balance lock against other balance actions', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    const settled = new Deferred<void>();
    const submitted = new Deferred();
    jest.mocked(executePerpsOpenPositionFromBalance).mockImplementationOnce(async (_a, _t, _r, hooks) => {
      hooks.onSubmitting?.();
      submitted.resolve();
      await settled.promise;
      return { address: WALLET, rawResponse: {}, status: 'filled' };
    });
    const execution = perpsExecuteReviewedOrder(account, 'token', quote.id, `balance-lock-${++serial}`);
    await submitted.promise;
    await expect(perpsWithdrawMargin(account, 'token', '10.2')).rejects.toThrow('PerpsOperationPending');
    await expect(perpsDepositMargin(account, 'token', '10.2')).rejects.toThrow('PerpsOperationPending');
    await expect(perpsOpenFromBalance(account, 'token', {
      assetId: asset.id, side: 'long', amount: '50', leverage: 10, isCross: false,
    })).rejects.toThrow('PerpsOperationPending');
    const another = await perpsPrepareOrder(account, balanceDraft);
    await expect(perpsExecuteReviewedOrder(account, 'token', another.id, `balance-second-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');
    settled.resolve();
    expect(await execution).toMatchObject({ state: 'completed' });
    expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
    expect(executePerpsDepositMargin).not.toHaveBeenCalled();
    expect(executePerpsOpenFromBalance).not.toHaveBeenCalled();
    expect(executePerpsOpenPositionFromBalance).toHaveBeenCalledTimes(1);
  });

  test('a balance order waits while a balance action holds the lock', async () => {
    const quote = await perpsPrepareOrder(account, balanceDraft);
    const withdrawn = new Deferred<any>();
    jest.mocked(executePerpsWithdrawMargin).mockImplementationOnce(() => withdrawn.promise);
    const withdrawal = perpsWithdrawMargin(account, 'token', '10.2');
    while (!jest.mocked(executePerpsWithdrawMargin).mock.calls.length) await Promise.resolve();
    await expect(perpsExecuteReviewedOrder(account, 'token', quote.id, `during-withdrawal-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');
    withdrawn.resolve({ address: WALLET, status: 'ok', rawResponse: {} });
    await withdrawal;
    expect(executePerpsOpenPositionFromBalance).not.toHaveBeenCalled();
  });
});

describe('balance withdrawal', () => {
  const success = { address: WALLET, status: 'success', rawResponse: {} };

  function withdrawBuild(destination = WALLET, sourceDex = ''): ApiPerpsBuildBalanceWithdrawResult {
    const { action, nonce, permitData } = perpsWithdrawalFixture(destination, '99.97', sourceDex);
    return {
      address: WALLET,
      hash: '0xwithdraw',
      action,
      nonce,
      typedData: {
        domain: permitData.domain,
        types: permitData.types as ApiPerpsExchangeTypedData['types'],
        message: permitData.values,
        primaryType: 'HyperliquidTransaction:SendToEvmWithData',
      },
    };
  }

  /** Submits after the build the SDK requires, then answers with `outcome`. */
  function submitWith(
    outcome: () => Promise<{ address: string; status: string; rawResponse: Record<string, unknown> }>,
  ) {
    jest.mocked(executePerpsWithdrawMargin).mockImplementation((_a, _t, _r, hooks) => {
      hooks?.validateBuild?.(withdrawBuild());
      hooks?.onSubmitting?.();
      return outcome();
    });
  }

  function publishedStages() {
    return onUpdate.mock.calls.map(([update]) => update)
      .filter((update) => update.type === 'perpsOperationUpdated')
      .map(({ operation }) => [operation.state, operation.stage]);
  }

  beforeEach(() => {
    jest.mocked(perpsBuildBalanceWithdraw).mockResolvedValue(withdrawBuild());
    onUpdate.mockClear();
  });

  test('a review takes the larger source less the reserve, for the account wallet', async () => {
    jest.mocked(perpsGetPositions).mockResolvedValue({
      positionsByChain: { hyperliquid: { withdrawable: '100', spotUsdcAvailable: '40', assetPositions: [] } },
    } as any);
    const quote = await perpsPrepareBalanceWithdrawal(account);
    expect(quote).toEqual({
      id: expect.any(String),
      accountId: account,
      destination: WALLET,
      expiresAt: expect.any(Number),
      balance: '100',
      amount: '99.97',
      bridgeFee: '0.2',
      receiveAmount: '99.77',
    });
    expect(perpsBuildBalanceWithdraw).toHaveBeenCalledWith(
      { chain: 'hyperliquid', address: WALLET, amount: '99.97' }, WALLET,
    );
    expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
  });

  test('nothing is reviewed at or below the minimum balance', async () => {
    jest.mocked(perpsGetPositions).mockResolvedValue({
      positionsByChain: { hyperliquid: { withdrawable: '0.25', spotUsdcAvailable: '0.1', assetPositions: [] } },
    } as any);
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsNothingToWithdraw');
    expect(perpsBuildBalanceWithdraw).not.toHaveBeenCalled();
  });

  test('a build that sends the USDC elsewhere cannot be reviewed', async () => {
    jest.mocked(perpsBuildBalanceWithdraw).mockResolvedValue(
      withdrawBuild('0x2222222222222222222222222222222222222222'),
    );
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects
      .toThrow('Withdraw destinationRecipient must match the wallet address');
  });

  test('a view-only account cannot review a withdrawal', async () => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'view', byChain: { arbitrum: { address: WALLET } },
    } as any);
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsUnsupportedAccount');
    expect(perpsGetPositions).not.toHaveBeenCalled();
  });

  test('a confirmed withdrawal is tracked, sent once and refreshes the account', async () => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    const id = `withdraw-${++serial}`;
    submitWith(() => Promise.resolve(success));
    const refreshBalance = jest.fn();
    const removeRefresh = balanceRefreshRequests.addCallback(refreshBalance);
    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, id)).toEqual({
      id,
      accountId: account,
      assetId: 'USDC',
      kind: 'withdraw',
      state: 'completed',
      stage: 'finished',
      createdAt: expect.any(Number),
      orderStatus: 'success',
      withdrawalAmount: '99.97',
      balanceWithdrawal: quote,
    });
    removeRefresh();
    expect(publishedStages()).toEqual([['running', 'withdrawal'], ['completed', 'finished']]);
    expect(executePerpsWithdrawMargin).toHaveBeenCalledWith(
      account, 'token', { chain: 'hyperliquid', address: WALLET, amount: '99.97' }, expect.anything(),
    );
    expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
    expect(refreshBalance).toHaveBeenCalledWith(account, 'arbitrum');

    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, id)).toMatchObject({ state: 'completed' });
    await expect(perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `again-${++serial}`))
      .rejects.toThrow('PerpsQuoteExpired');
    await expect(perpsExecuteBalanceWithdrawal(`${++serial}-mainnet`, 'token', quote.id, id))
      .rejects.toThrow('PerpsInvalidOperation');
    expect(executePerpsWithdrawMargin).toHaveBeenCalledTimes(1);
    await expect(perpsPrepareBalanceWithdrawal(account)).resolves.toMatchObject({ amount: '99.97' });
  });

  test('an expired, replaced or foreign quote is not executed', async () => {
    const first = await perpsPrepareBalanceWithdrawal(account);
    const second = await perpsPrepareBalanceWithdrawal(account);
    await expect(perpsExecuteBalanceWithdrawal(account, 'token', first.id, `replaced-${++serial}`))
      .rejects.toThrow('PerpsQuoteExpired');
    await expect(perpsExecuteBalanceWithdrawal(`${++serial}-mainnet`, 'token', second.id, `foreign-${++serial}`))
      .rejects.toThrow('PerpsQuoteExpired');
    const clock = jest.spyOn(Date, 'now').mockReturnValue(second.expiresAt + 1);
    await expect(perpsExecuteBalanceWithdrawal(account, 'token', second.id, `expired-${++serial}`))
      .rejects.toThrow('PerpsQuoteExpired');
    clock.mockRestore();
    expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
  });

  test('a build from another source fails the review before anything is submitted', async () => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    jest.mocked(executePerpsWithdrawMargin).mockImplementation((_a, _t, _r, hooks) => {
      hooks?.validateBuild?.(withdrawBuild(WALLET, 'spot'));
      hooks?.onSubmitting?.();
      return Promise.resolve(success);
    });
    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `source-${++serial}`))
      .toMatchObject({ state: 'failed', stage: 'preparing', error: 'PerpsReviewChanged' });
    expect(requestPerpsPositionsRefresh).not.toHaveBeenCalled();
    expect(publishedStages()).toEqual([['failed', 'preparing']]);
  });

  test.each([
    ['the build refuses the amount', new ApiServerError('amount exceeds the balance', 400), 'PerpsReviewChanged'],
    ['the build is unavailable', new ApiServerError('HTTP Error 502', 502), 'HTTP Error 502'],
    ['the backend cannot be reached', new Error('Failed to fetch'), 'Failed to fetch'],
  ])('nothing moves when %s before submission', async (_title, error, expected) => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    jest.mocked(executePerpsWithdrawMargin).mockRejectedValueOnce(error);
    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `build-${++serial}`))
      .toMatchObject({ state: 'failed', stage: 'preparing', error: expected });
    await expect(perpsPrepareBalanceWithdrawal(account)).resolves.toMatchObject({ amount: '99.97' });
  });

  test('a refused password fails without submitting', async () => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    jest.mocked(executePerpsWithdrawMargin).mockResolvedValueOnce({ error: ApiCommonError.InvalidPassword });
    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `password-${++serial}`))
      .toMatchObject({ state: 'failed', error: ApiCommonError.InvalidPassword });
    expect(requestPerpsPositionsRefresh).not.toHaveBeenCalled();
  });

  test.each([
    ['[HL_EXCHANGE_ERROR] Insufficient balance', () => Promise.reject(
      new ApiServerError('[HL_EXCHANGE_ERROR] Insufficient balance', 500),
    )],
    ['error: Insufficient balance', () => Promise.resolve({ ...success, status: 'error: Insufficient balance' })],
  ])('a venue rejection fails and releases the account: %s', async (message, outcome) => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    submitWith(outcome);
    expect(await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `rejected-${++serial}`))
      .toMatchObject({ state: 'failed', stage: 'finished', error: `PerpsWithdrawalRejected: ${message}` });
    expect(requestPerpsPositionsRefresh).toHaveBeenCalledWith(account);
    await expect(perpsPrepareBalanceWithdrawal(account)).resolves.toMatchObject({ amount: '99.97' });
  });

  test.each([
    ['a timeout', () => Promise.reject(new Error('Request timed out'))],
    ['a gateway error', () => Promise.reject(new ApiServerError('HTTP Error 502', 502))],
    ['a backend failure', () => Promise.reject(new ApiServerError('Exchange request timed out', 500))],
    ['an unrecognized status', () => Promise.resolve({ ...success, status: 'unknown' })],
  ])('%s after submission stays unknown until acknowledged, without a retry', async (_title, outcome) => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    submitWith(outcome);
    const unknown = await perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `unknown-${++serial}`);
    expect(unknown).toMatchObject({ state: 'unknown', kind: 'withdraw' });
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsOperationPending');
    const order = await perpsPrepareOrder(account, draft);
    await expect(perpsExecuteReviewedOrder(account, 'token', order.id, `blocked-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');

    await perpsAcknowledgeOperation(account, unknown);
    await expect(perpsPrepareBalanceWithdrawal(account)).resolves.toMatchObject({ amount: '99.97' });
    expect(executePerpsWithdrawMargin).toHaveBeenCalledTimes(1);
    expect(executePerpsOpenPosition).not.toHaveBeenCalled();
  });

  test('a running withdrawal holds the account lock until it settles', async () => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    const order = await perpsPrepareOrder(account, draft);
    const sent = new Deferred<typeof success>();
    const submitted = new Deferred();
    jest.mocked(executePerpsWithdrawMargin).mockImplementation((_a, _t, _r, hooks) => {
      hooks?.onSubmitting?.();
      submitted.resolve();
      return sent.promise;
    });
    const execution = perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `held-${++serial}`);
    await submitted.promise;

    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsOperationPending');
    await expect(perpsDepositMargin(account, 'token', '10.2')).rejects.toThrow('PerpsOperationPending');
    await expect(perpsWithdrawMargin(account, 'token', '10.2')).rejects.toThrow('PerpsOperationPending');
    await expect(perpsExecuteReviewedOrder(account, 'token', order.id, `blocked-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');
    expect(executePerpsDepositMargin).not.toHaveBeenCalled();
    expect(executePerpsOpenPosition).not.toHaveBeenCalled();
    expect(executePerpsWithdrawMargin).toHaveBeenCalledTimes(1);

    sent.resolve(success);
    await expect(execution).resolves.toMatchObject({ state: 'completed' });
    await expect(perpsPrepareBalanceWithdrawal(account)).resolves.toMatchObject({ amount: '99.97' });
  });

  test('an unresolved operation refuses both the review and an earlier quote', async () => {
    const quote = await perpsPrepareBalanceWithdrawal(account);
    await perpsReconcileOperation(account, savedOperation('partial'));
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsOperationPending');
    await expect(perpsExecuteBalanceWithdrawal(account, 'token', quote.id, `blocked-${++serial}`))
      .rejects.toThrow('PerpsOperationPending');
    expect(executePerpsWithdrawMargin).not.toHaveBeenCalled();
  });

  test('an interrupted withdrawal restores as unknown and has no withdrawal retry', async () => {
    const saved = { ...savedOperation('running'), assetId: 'USDC', kind: 'withdraw' as const };
    expect(await perpsReconcileOperation(account, saved)).toMatchObject({ state: 'unknown', kind: 'withdraw' });
    await expect(perpsPrepareBalanceWithdrawal(account)).rejects.toThrow('PerpsOperationPending');
    await expect(perpsPrepareWithdrawal(account, saved.id)).rejects.toThrow('PerpsInvalidOperation');
    expect(perpsBuildWithdrawal).not.toHaveBeenCalled();
  });
});
