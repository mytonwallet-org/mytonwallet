import type { ApiPerpsRawFill } from '../types/perpsTrading';

import { normalizePerpsActivityFills, normalizePerpsFills } from './perpsFills';

const opened: ApiPerpsRawFill = {
  coin: 'BTC', tid: 1, oid: 1, time: 1000, px: '100', sz: '2', side: 'B', dir: 'Open Long',
  startPosition: '0', closedPnl: '0', fee: '0.1', feeToken: 'USDC', hash: 'open',
};
const increased: ApiPerpsRawFill = {
  ...opened, tid: 2, oid: 2, time: 2000, px: '130', sz: '1', startPosition: '2', hash: 'increase',
};
const reduced: ApiPerpsRawFill = {
  ...opened, tid: 3, oid: 3, time: 3000, px: '140', sz: '1', side: 'A', dir: 'Close Long',
  startPosition: '3', closedPnl: '30', hash: 'reduce',
};
const closed: ApiPerpsRawFill = {
  ...reduced, tid: 4, oid: 4, time: 4000, sz: '2', startPosition: '2', closedPnl: '60', hash: 'close',
};

test('backend activity fills retain HIP-3 identity and normalize liquidation decimals for native decoding', () => {
  const fills = normalizePerpsActivityFills([
    { ...closed, coin: 'xyz:BTC', kind: 'fill', dex: 'xyz', asset: 'hyperliquid:xyz:BTC',
      liquidation: { markPx: 98.75, method: 'market' } },
    // eslint-disable-next-line no-null/no-null -- Raw backend JSON can explicitly omit optional fields with null.
    { ...opened, kind: 'fill', dex: '', liquidation: null, builderFee: null },
    { ...opened, kind: 'fill', dex: '', coin: '@123' },
    { ...opened, kind: 'fill', dex: '', coin: 'HYPE/USDC' },
  ]);
  expect(fills).toHaveLength(2);
  expect(fills[0]).toMatchObject({ coin: 'xyz:BTC', eventKind: 'liquidated',
    liquidation: { markPx: '98.75', method: 'market' } });
  expect(fills[1]).toMatchObject({ eventKind: 'opened', builderFee: '0' });
  expect(fills[1].liquidation).toBeUndefined();
});

test.each([
  { tid: 1.5 }, { oid: Number.MAX_SAFE_INTEGER + 1 }, { time: -1 },
  // eslint-disable-next-line no-null/no-null -- Exercise malformed raw backend JSON.
  { px: 'invalid' }, { sz: null }, { coin: undefined }, { builderFee: 1 },
  { liquidation: { markPx: 'invalid', method: 'market' } },
])('rejects malformed backend executions instead of returning partial history: %j', (invalid) => {
  expect(() => normalizePerpsActivityFills([
    { ...opened, kind: 'fill', dex: '' },
    { ...increased, kind: 'fill', dex: '', ...invalid } as any,
  ])).toThrow('PerpsIncompleteData');
});

test('reconstructs entry and duration only through a complete, continuous position lifecycle', () => {
  const fills = normalizePerpsFills([closed, reduced, increased, opened, opened]);
  expect(fills).toHaveLength(4);
  expect(fills[0]).toMatchObject({
    eventKind: 'closed', entryPrice: '110', positionOpenedAt: 1000, netPnl: '59.9',
    previousSize: '2', positionSize: '0', endPosition: '0', notional: '280', previousNotional: '280',
  });
  expect(fills[1]).toMatchObject({ eventKind: 'reduced', entryPrice: '110', positionOpenedAt: 1000 });
  expect(fills[2]).toMatchObject({
    eventKind: 'increased', entryPrice: '110', positionOpenedAt: 1000,
    previousSize: '2', positionSize: '3', previousNotional: '260', positionNotional: '390',
  });
  expect(fills[3]).toMatchObject({ eventKind: 'opened', entryPrice: '100', positionOpenedAt: 1000 });
  for (const fill of fills) {
    expect(fill).not.toHaveProperty('margin');
    expect(fill).not.toHaveProperty('leverage');
    expect(fill).not.toHaveProperty('paymentAmount');
  }
});

test('does not guess entry, opening time or historical margin from truncated or discontinuous history', () => {
  const truncated = normalizePerpsFills([closed, reduced, increased]);
  const discontinuous = normalizePerpsFills([opened, reduced, closed]);
  for (const fill of [...truncated, ...discontinuous.filter((value) => value.tid !== opened.tid)]) {
    expect(fill.entryPrice).toBeUndefined();
    expect(fill.positionOpenedAt).toBeUndefined();
  }
});

test('a new position lifecycle starts a new duration after the prior close', () => {
  const reopened = { ...opened, tid: 5, oid: 5, time: 5000 };
  const fills = normalizePerpsFills([opened, increased, reduced, closed, reopened]);
  expect(fills[0]).toMatchObject({ eventKind: 'opened', positionOpenedAt: 5000, entryPrice: '100' });
  expect(fills[1].positionOpenedAt).toBe(1000);
});

test('aggregates contiguous partial fills of an order, retaining source IDs and a truthful hash', () => {
  const partial = { ...opened, sz: '1' };
  const second = { ...partial, tid: 2, time: 1001, px: '110', startPosition: '1', fee: '0.2', hash: 'other' };
  const third = { ...partial, tid: 3, time: 1002, px: '120', startPosition: '2', fee: '0.3', hash: 'other' };
  const unrelated = { ...opened, coin: 'ETH', tid: 10, time: 1001 };
  const fills = normalizePerpsFills([partial, second, third, unrelated]);
  expect(fills).toHaveLength(2);
  expect(fills[0]).toMatchObject({
    eventKind: 'opened', fillIds: [1, 2, 3], sz: '3', px: '110', notional: '330', fee: '0.6',
    netPnl: '-0.6', previousSize: '0', positionSize: '3', entryPrice: '110', positionOpenedAt: 1000,
  });
  expect(fills[0].hash).toBeUndefined();
  expect(normalizePerpsFills([partial, { ...second, hash: partial.hash }])[0].hash).toBe(partial.hash);
});

test('does not combine interrupted orders, incompatible fee tokens or discontinuous partial fills', () => {
  const fill = { ...opened, sz: '1' };
  const next = { ...fill, tid: 3, time: 3000, startPosition: '2' };
  const between = { ...fill, tid: 2, oid: 2, time: 2000, startPosition: '1' };
  expect(normalizePerpsFills([fill, between, next])).toHaveLength(3);
  expect(normalizePerpsFills([fill, next])).toHaveLength(2);
  const otherFee = { ...next, startPosition: '1', feeToken: 'HYPE' };
  const result = normalizePerpsFills([fill, otherFee]);
  expect(result).toHaveLength(2);
  expect(result[0].netPnl).toBeUndefined();
});

test('same-block fills follow position quantities instead of the numeric trade hashes', () => {
  const first = { ...opened, tid: 900, sz: '1' };
  const second = { ...first, tid: 20, startPosition: '1', px: '110' };
  const third = { ...first, tid: 400, startPosition: '2', px: '120' };
  const fills = normalizePerpsFills([third, second, first]);
  expect(fills).toHaveLength(1);
  expect(fills[0]).toMatchObject({
    eventKind: 'opened', fillIds: [900, 20, 400], entryPrice: '110', sz: '3', positionOpenedAt: 1000,
  });
  const separateOrders = normalizePerpsFills([
    { ...increased, time: opened.time, tid: 20 }, { ...opened, tid: 900 },
  ]);
  expect(separateOrders.map((fill) => fill.tid)).toEqual([20, 900]);
  expect(separateOrders[0].entryPrice).toBe('110');
});

test('ambiguous same-block cycles do not establish a position lifecycle or merge fills', () => {
  const first = { ...opened, sz: '1' };
  const second = { ...reduced, time: first.time, startPosition: '1', sz: '1' };
  const fills = normalizePerpsFills([second, first]);
  expect(fills).toHaveLength(2);
  expect(fills.every((fill) => fill.positionOpenedAt === undefined)).toBe(true);
  expect(fills.find((fill) => fill.eventKind === 'closed')?.entryPrice).toBeUndefined();
});

test('trade hashes repeated in different blocks or markets are distinct executions', () => {
  const fills = normalizePerpsFills([
    opened, opened, { ...opened, coin: 'ETH' }, { ...closed, tid: opened.tid },
  ]);
  expect(fills).toHaveLength(3);
});

test('partial closing executions form one closed receipt with total P&L and weighted exit price', () => {
  const first = { ...reduced, oid: 3, px: '120', startPosition: '2', closedPnl: '20' };
  const second = { ...first, tid: 4, time: 3001, px: '130', startPosition: '1', closedPnl: '30' };
  const fills = normalizePerpsFills([opened, first, second]);
  expect(fills).toHaveLength(2);
  expect(fills[0]).toMatchObject({
    eventKind: 'closed', sz: '2', px: '125', closedPnl: '50', netPnl: '49.8', fee: '0.2',
    entryPrice: '100', positionOpenedAt: 1000, previousSize: '2', positionSize: '0',
    previousNotional: '250', positionNotional: '0', notional: '250', fillIds: [3, 4],
  });
});

test('short positions use absolute sizes and preserve weighted entry through liquidation', () => {
  const openShort = { ...opened, dir: 'Open Short', side: 'A' };
  const increaseShort = { ...increased, dir: 'Open Short', side: 'A', startPosition: '-2' };
  const liquidation = {
    ...closed, dir: 'Close Short', side: 'B', sz: '3', startPosition: '-3', closedPnl: '-90',
    liquidation: { liquidatedUser: '0x123', markPx: '140', method: 'market' },
  };
  const fill = normalizePerpsFills([openShort, increaseShort, liquidation])[0];
  expect(fill).toMatchObject({
    eventKind: 'liquidated', positionSide: 'short', previousSize: '3', positionSize: '0',
    notional: '420', entryPrice: '110', positionOpenedAt: 1000, netPnl: '-90.1',
  });
});

test('normalizes liquidation wire prices for native decoding and accepts missing liquidated user', () => {
  const fill = normalizePerpsFills([{ ...closed, liquidation: { markPx: 140, method: 'market' } } as any])[0];
  expect(fill).toMatchObject({ eventKind: 'liquidated', liquidation: { markPx: '140', method: 'market' } });
});

test('filters spot fills and leaves reversals or malformed fills unclassified', () => {
  const reversal = { ...opened, dir: 'Short > Long', startPosition: '-1' };
  const malformed = { ...opened, tid: 2, sz: 'invalid' };
  const inconsistent = { ...opened, tid: 3, dir: 'Open Short' };
  const fills = normalizePerpsFills([reversal, malformed, inconsistent,
    { ...opened, coin: '@100' }, { ...opened, coin: 'BTC/USDC' }]);
  expect(fills).toHaveLength(3);
  for (const fill of fills) {
    expect(fill.eventKind).toBeUndefined();
    expect(fill.entryPrice).toBeUndefined();
    expect(fill.positionOpenedAt).toBeUndefined();
  }
});

test('builder fees aggregate as a component of the total and omitted zero fees stay zero', () => {
  const first = { ...opened, sz: '1', fee: '0.1', builderFee: '0.08' };
  const second = { ...first, tid: 2, time: 1001, startPosition: '1', fee: '0.2', builderFee: undefined };
  const fill = normalizePerpsFills([second, first])[0];
  expect(fill.fee).toBe('0.3');
  expect(fill.builderFee).toBe('0.08');
});
