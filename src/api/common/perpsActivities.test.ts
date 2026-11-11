import type { ApiPerpsTradeActivity } from '../types';

import { normalizePerpsActivityPage } from './perpsActivities';

const trade: ApiPerpsTradeActivity = {
  id: 'BTC/42/close', orderId: 42, fillIds: [1, 2], assetId: 'hyperliquid:hl:BTC', dex: '',
  kind: 'reduce', side: 'long', timestamp: 1700000000000, size: '0.0001', notional: '10',
  entryPrice: '95000', exitPrice: '100000', realizedPnl: '0.5',
  fees: { trading: '0.08', builder: '0.03', bridge: '0.2' },
};

test('backend grouped trades preserve identity and do not fabricate final position values', () => {
  const result = normalizePerpsActivityPage({ address: '0xAbC', activities: [trade], nextCursor: 'older' }, '0xabc');
  expect(result.nextCursor).toBe('older');
  expect(result.hasActivity).toBe(true);
  expect(result.fills[0]).toMatchObject({ activityId: trade.id, oid: 42, eventKind: 'reduced', positionSide: 'long',
    coin: 'BTC', time: trade.timestamp, notional: '10', netPnl: '0.42', entryPrice: '95000', px: '100000',
    receiptFees: { trading: '0.08', exchange: '0.05', service: '0.03', bridge: '0.2', total: '0.28' } });
  expect(result.fills[0].positionSize).toBeUndefined();
  expect(result.fills[0].positionNotional).toBeUndefined();
  expect(result.fills[0].collateralAfter).toBeUndefined();
});

test('increase and reduce keep the reported position sizes', () => {
  const increase = normalizePerpsActivityPage({ address: 'wallet', activities: [{
    ...trade, kind: 'increase', exitPrice: undefined, realizedPnl: undefined, entryPrice: '100', size: '1',
    positionSizeBefore: '1', positionSizeAfter: '2',
  }] }, 'wallet');
  expect(increase.fills[0]).toMatchObject({
    eventKind: 'increased', previousSize: '1', positionSize: '2', previousNotional: '100', positionNotional: '200',
    px: '100',
  });

  const reduce = normalizePerpsActivityPage({ address: 'wallet', activities: [{
    ...trade, positionSizeBefore: '2', positionSizeAfter: '1.5',
  }] }, 'wallet');
  expect(reduce.fills[0]).toMatchObject({
    eventKind: 'reduced', previousSize: '2', positionSize: '1.5', previousNotional: '200000',
    positionNotional: '150000', px: '100000',
  });
});

test('unavailable historical fees and order IDs remain absent', () => {
  const result = normalizePerpsActivityPage({ address: 'wallet',
    activities: [{ ...trade, orderId: undefined, fees: undefined }] }, 'wallet');
  expect(result.fills[0].oid).toBeUndefined();
  expect(result.fills[0].fee).toBeUndefined();
  expect(result.fills[0].netPnl).toBeUndefined();
  expect(result.fills[0].receiptFees).toBeUndefined();
});

test('wrong-account responses fail', () => {
  expect(() => normalizePerpsActivityPage({ address: 'another', activities: [] }, 'wallet'))
    .toThrow('PerpsIncompleteData');
});

test.each([
  { activities: [], nextCursor: undefined, expected: false },
  { activities: [], nextCursor: 'older', expected: true },
  { activities: [trade], nextCursor: undefined, expected: true },
])('activity evidence counts every trade and older pages: %j', ({ activities, nextCursor, expected }) => {
  const result = normalizePerpsActivityPage({ address: 'wallet', activities, nextCursor }, 'wallet');
  expect(result.hasActivity).toBe(expected);
});

test('trades without a catalogue asset are evidence but not rows', () => {
  const result = normalizePerpsActivityPage(
    { address: 'wallet', activities: [{ ...trade, assetId: undefined }] }, 'wallet',
  );
  expect(result.fills).toEqual([]);
  expect(result.hasActivity).toBe(true);
});
