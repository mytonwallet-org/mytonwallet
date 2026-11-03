import type { ApiPerpsRawActivityItem } from '../types/perps';

import { normalizePerpsCashFlows } from './perpsCashFlows';

const wallet = '0x1111111111111111111111111111111111111111';
const other = '0x2222222222222222222222222222222222222222';
const row = (delta: Record<string, unknown>, time = 1000): ApiPerpsRawActivityItem => ({
  kind: 'ledgerUpdate', dex: '', time, hash: '0xabc', delta,
});
const funding = (coin: string, usdc: string, time = 1000): ApiPerpsRawActivityItem => ({
  ...row({ type: 'funding', coin, usdc, szi: '0.001', fundingRate: '0.0000125' }, time),
  kind: 'fundingPayment', hash: '0x00000000', asset: `hyperliquid:hl:${coin}`,
});
const normalize = (...items: ApiPerpsRawActivityItem[]) => normalizePerpsCashFlows(items, wallet);

test('funding preserves exact signed cash flow, market identity and rate, without a fake transaction hash', () => {
  const flows = normalize(funding('BTC', '-0.00001234'), funding('ETH', '0.00002468'), funding('BTC', '-0.00001234'));
  expect(flows).toHaveLength(2);
  expect(flows.find((flow) => flow.coin === 'BTC')).toMatchObject({
    kind: 'funding', direction: 'outgoing', amount: '0.00001234', token: 'USDC',
    fundingRate: '0.0000125', positionSide: 'long', positionSize: '0.001', assetId: 'hyperliquid:hl:BTC',
  });
  expect(flows.find((flow) => flow.coin === 'ETH')).toMatchObject({ direction: 'incoming', amount: '0.00002468' });
  expect(flows.every((flow) => flow.hash === undefined)).toBe(true);
  expect(normalize(...[funding('xyz:BTC', '1'), funding('BTC', '1')])).toHaveLength(2);
});

test('deposits and withdrawals preserve the ledger quantity without subtracting or adding fees', () => {
  expect(normalize(row({ type: 'deposit', usdc: '10.117612' }))[0]).toMatchObject({
    kind: 'deposit', direction: 'incoming', amount: '10.117612', fees: [],
  });
  expect(normalize(row({ type: 'withdraw', usdc: '10', fee: '0.2' }))[0]).toMatchObject({
    kind: 'withdrawal', direction: 'outgoing', amount: '10', fees: [{ amount: '0.2', token: 'USDC' }],
  });
});

test.each([true, false])('spot/perps moves use toPerp=%s without mistaking them for external deposits', (toPerp) => {
  expect(normalize(row({ type: 'accountClassTransfer', usdc: '10', toPerp }))[0]).toMatchObject({
    kind: 'transfer', direction: toPerp ? 'incoming' : 'outgoing',
    sourceDex: toPerp ? 'spot' : '', destinationDex: toPerp ? '' : 'spot', amount: '10',
  });
});

test.each(['internalTransfer', 'subAccountTransfer', 'send'])('normalizes %s from the account perspective', (type) => {
  const delta = { type, user: wallet, destination: other, amount: '10', usdc: '10', token: 'USDC',
    sourceDex: '', destinationDex: '', fee: '0.1', feeToken: 'USDC' };
  expect(normalize(row(delta))[0]).toMatchObject({
    direction: 'outgoing', amount: '10', fees: [{ amount: '0.1', token: 'USDC' }],
  });
  expect(normalize(row({ ...delta, user: other, destination: wallet.toUpperCase() }))[0]).toMatchObject({
    direction: 'incoming', amount: '10', fees: [],
  });
  expect(normalize(row({ ...delta, user: other, destination: other }))).toEqual([]);
});

test('moves between owned perps books are neutral, and spot-only transfers do not enter Futures activity', () => {
  const delta = { type: 'send', user: wallet, destination: wallet, amount: '10', token: 'USDC',
    sourceDex: '', destinationDex: 'xyz' };
  expect(normalize(row(delta))[0]).toMatchObject({ direction: 'internal', sourceDex: '', destinationDex: 'xyz' });
  expect(normalize(row({ ...delta, destinationDex: 'spot' }))[0].direction).toBe('outgoing');
  expect(normalize(row({ ...delta, sourceDex: 'spot' }))[0].direction).toBe('incoming');
  expect(normalize(row({ ...delta, sourceDex: 'spot', destinationDex: 'spot' }))).toEqual([]);
  expect(normalize(row({ ...delta, type: 'spotTransfer' }))).toEqual([]);
});

test('keeps token units and native fees separate from USDC valuation', () => {
  const delta = { type: 'send', user: wallet, destination: other,
    amount: '2.5', token: 'USDH', usdcValue: '2.49',
    sourceDex: '', destinationDex: 'xyz', fee: '0.1', feeToken: 'USDH', nativeTokenFee: '0.001' };
  expect(normalize(row(delta))[0]).toMatchObject({ amount: '2.5', token: 'USDH',
    fees: [{ amount: '0.1', token: 'USDH' }, { amount: '0.001', token: 'HYPE' }] });
  expect(normalize(row({ ...delta, user: other, destination: wallet }))[0].fees).toEqual([]);
});

test('stable identity deduplicates rereads but keeps same-hash markets, routes and cash-flow directions', () => {
  const items = [funding('BTC', '-1'), funding('ETH', '-1'), funding('BTC', '1'),
    row({ type: 'deposit', usdc: '2' }, 1001)];
  expect(normalize(...items, ...items)).toHaveLength(4);
  expect(normalize(...items).map((flow) => flow.id)).toEqual(normalize(...items.reverse()).map((flow) => flow.id));
  expect(normalize(...items)[0].time).toBe(1001);
});

test('unknown ledger types are not falsely rendered as transfers', () => {
  expect(normalize(row({ type: 'vaultDeposit', usdc: '5' }), row({ type: 'futureType' }))).toEqual([]);
});

test.each([
  row({ type: 'deposit', usdc: '-1' }), row({ type: 'withdraw', usdc: 'NaN' }),
  row({ type: 'accountClassTransfer', usdc: '5' }),
  { ...funding('BTC', '1'), time: 1.5 }, funding('BTC', 'bad'),
])('malformed supported events reject rather than turn financial data into zero', (item) => {
  expect(() => normalize(item)).toThrow('PerpsIncompleteData');
});
