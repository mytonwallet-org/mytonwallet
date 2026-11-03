import type { ApiPerpsListedAsset, ApiPerpsPosition } from '../types/perps';

import { Big } from '../../lib/big.js';
import depositFixture from '../../../tests/fixtures/perpsDeposit.json';
import {
  applyPerpsLeverageChangeDeposit, getPerpsFundingRequirements, getPerpsMarketTradingAvailability,
  getPerpsOpenInterestUsd, getPerpsReviewedLimitPrice, getPerpsWireAssetIndex,
  isPerpsPositionNearLiquidation, normalizePerpsPosition,
  resolvePerpsDraft, validatePerpsReviewedBuild,
} from './perpsPresentation';

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
  image: 'https://example.org/btc.svg',
  context: { markPx: '100000', prevDayPx: '99000' },
} as ApiPerpsListedAsset;
const raw = {
  coin: 'BTC',
  leverage: { type: 'isolated', value: 10 },
  szi: '0.01',
  marginUsed: '110',
  unrealizedPnl: '10',
  entryPx: '99000',
  liquidationPx: '90500',
  positionValue: '1000',
} as ApiPerpsPosition;
const depositLimits = {
  minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '0.2', minPositionMarginUsdc: '10',
};
const params = {
  accountId: '0-mainnet',
  address: '0x1111111111111111111111111111111111111111',
  asset,
  availableUsdc: '200',
  depositLimits,
  now: Date.now(),
  id: 'quote',
  draft: { assetId: asset.id, side: 'long' as const, amount: '50', unit: 'currency' as const, leverage: 10 },
};

test.each(['', 'xyz'])('a market on %s without the canonical wire index cannot be traded', (dex) => {
  const market = { ...asset, dex, wireAssetIndex: undefined };
  expect(getPerpsWireAssetIndex(market)).toBeUndefined();
  expect(getPerpsMarketTradingAvailability(market).isAvailable).toBe(false);
  expect(() => resolvePerpsDraft({ ...params, asset: market })).toThrow('PerpsTradingUnavailable');
  expect(getPerpsWireAssetIndex({ ...market, wireAssetIndex: 110005 })).toBe(110005);
});

// eslint-disable-next-line no-null/no-null -- Invalid JSON metadata makes the market untradable.
test.each([-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '1', null])(
  'invalid wire index %s makes the market untradable', (wireAssetIndex) => {
    const invalid = { ...asset, wireAssetIndex } as ApiPerpsListedAsset;
    expect(getPerpsWireAssetIndex(invalid)).toBeUndefined();
    expect(getPerpsMarketTradingAvailability(invalid).isAvailable).toBe(false);
  },
);

test.each([{ wireAssetIndex: -1 }, { isDelisted: true }])('unavailable market %j cannot resolve an order', (fields) => {
  const unsupported = { ...asset, ...fields };
  expect(getPerpsMarketTradingAvailability(unsupported))
    .toEqual({ isAvailable: false, reason: 'PerpsTradingUnavailable' });
  expect(() => resolvePerpsDraft({ ...params, asset: unsupported })).toThrow('PerpsTradingUnavailable');
  expect(() => getPerpsFundingRequirements({ ...params, asset: unsupported, availableEth: '1' }))
    .toThrow('PerpsTradingUnavailable');
});

test('an empty opening checks both Arbitrum funding minimums without requiring an order amount', () => {
  expect(getPerpsFundingRequirements({
    ...params, draft: { ...params.draft, amount: '' }, availableUsdc: '0', availableEth: '0',
  })).toEqual({
    requiredUsdc: '10.2', requiredEth: '0.0001', requiredEthUsd: '0.25',
    usdcBalance: '0', availableCollateral: '0', ethBalance: '0', needsUsdc: true, needsEth: true,
  });
});

test('funding checks honor backend minimums, the current draft and exact boundary balances', () => {
  const limits = { minOpenDepositUsdc: '12.2', minIncreaseDepositUsdc: '15.2' };
  const empty = {
    ...params, depositLimits: limits, draft: { ...params.draft, amount: '' },
    availableUsdc: '12.2', availableEth: '0.0001',
  };
  expect(getPerpsFundingRequirements(empty)).toMatchObject({ requiredUsdc: '12.2', needsUsdc: false, needsEth: false });
  expect(getPerpsFundingRequirements({ ...empty, draft: params.draft }))
    .toMatchObject({ requiredUsdc: '50.2', needsUsdc: true, needsEth: false });
  expect(getPerpsFundingRequirements({ ...empty, availableEth: '0.000099999999999999' }))
    .toMatchObject({ needsUsdc: false, needsEth: false });
  const position = normalizePerpsPosition(params.accountId, asset, raw);
  expect(getPerpsFundingRequirements({ ...empty, position, draft: { ...params.draft, editing: true, amount: '110' } }))
    .toMatchObject({ requiredUsdc: '15.2', needsUsdc: true });
});

test.each([
  { amount: '100' }, { amount: '75' }, { amount: '0', close: true }, { amount: '100', leverage: 5 },
])('nondepositing edits do not require Arbitrum funds: %s', (change) => {
  const position = normalizePerpsPosition(params.accountId, asset, raw);
  expect(getPerpsFundingRequirements({
    ...params, position, availableUsdc: '0', availableEth: '0', draft: { ...params.draft, editing: true, ...change },
  })).toMatchObject({ requiredUsdc: '0', requiredEth: '0', needsUsdc: false, needsEth: false });
});

test('funding requirements share fraction and token amount interpretation with order preparation', () => {
  expect(getPerpsFundingRequirements({ ...params, availableEth: '0.0001', draft: { ...params.draft, fraction: 100 } }))
    .toMatchObject({ requiredUsdc: '200', needsUsdc: false });
  expect(getPerpsFundingRequirements({
    ...params, availableEth: '0.0001', draft: { ...params.draft, unit: 'asset', amount: '0.005' },
  }))
    .toMatchObject({ requiredUsdc: '50.2', needsUsdc: false });
});

test.each(['200', '200.123456'])(
  'the available collateral input uses the same maximum as order preparation for %s USDC', (availableUsdc) => {
    const context = { ...params, availableUsdc };
    const funding = getPerpsFundingRequirements({ ...context, availableEth: '0.0001' });
    const maximum = resolvePerpsDraft({ ...context, draft: { ...params.draft, fraction: 100 } });
    expect(funding.availableCollateral).toBe(maximum.inputAmount);
    const entered = resolvePerpsDraft({ ...context,
      draft: { ...params.draft, amount: funding.availableCollateral! } });
    expect(entered.paymentAmount).toBe(availableUsdc);
  },
);

test.each(['0', '0.1', '0.2'])('available collateral cannot be negative for %s USDC', (availableUsdc) => {
  expect(getPerpsFundingRequirements({ ...params, availableUsdc, availableEth: '0',
    draft: { ...params.draft, amount: '' } }).availableCollateral).toBe('0');
});

test('reductions round up to release the requested USDC amount', () => {
  const liveAsset = { ...asset, context: { ...asset.context, markPx: '79604.675' } };
  const position = normalizePerpsPosition(params.accountId, liveAsset, {
    ...raw, szi: '0.00025', leverage: { type: 'isolated', value: 2 },
    marginUsed: '9.935083', unrealizedPnl: '0.016925', entryPx: '79551',
  });
  const editing = {
    ...params,
    asset: liveAsset,
    position,
    depositLimits: { ...depositLimits, minPositionMarginUsdc: '1' },
    draft: { ...params.draft, editing: true, leverage: 2, amount: '5' },
  };
  expect(resolvePerpsDraft(editing).orderSize).toBe('0.00013');
  const valid = resolvePerpsDraft({ ...editing, draft: { ...editing.draft, amount: '4.5' } });
  expect(valid.orderSize).toBe('0.00014');
  expect(Big(valid.orderSize!).mul(valid.markPrice).gte(10)).toBe(true);
  expect(resolvePerpsDraft({ ...editing, draft: { ...editing.draft, close: true } }).kind).toBe('close');
});

test('minimum order validation checks rounded leveraged size but leaves full dust closes available', () => {
  expect(() => resolvePerpsDraft({ ...params, draft: { ...params.draft, amount: '5', leverage: 1 } }))
    .toThrow('PerpsAmountTooSmall');
  const position = normalizePerpsPosition(params.accountId, asset, { ...raw, szi: '0.00001' });
  const close = resolvePerpsDraft({ ...params, position, draft: { ...params.draft, editing: true, close: true } });
  expect(close.orderSize).toBe('0.00001');
});

test.each([
  ['79762', 5, true, '82155'],
  ['79762', 5, false, '77369'],
  ['1.23456', 4, true, '1.27'],
  ['1.23456', 4, false, '1.2'],
  ['100000', 5, true, '103000'],
  ['1.1985', 3, true, '1.234'],
  ['138.397', 5, true, '142.6'],
  ['100.01', 5, true, '103'],
  ['0.000123456', 0, true, '0.000127'],
  ['0.000123456', 0, false, '0.00012'],
])('reviewed IOC price %s (%s decimals, buy=%s) is rounded within the limit', (price, decimals, buy, expected) => {
  expect(getPerpsReviewedLimitPrice(Big(price), decimals, buy)).toBe(expected);
});

test('market requests preserve amount intent and use shared backend sizing', () => {
  const position = normalizePerpsPosition(params.accountId, asset, raw);
  for (const quote of [
    resolvePerpsDraft(params),
    resolvePerpsDraft({ ...params, position, draft: { ...params.draft, editing: true, amount: '120' } }),
    resolvePerpsDraft({ ...params, position, draft: { ...params.draft, editing: true, amount: '75' } }),
  ]) {
    const request = quote.open ?? quote.modify!;
    expect(request).toMatchObject({ asset: asset.id, slippage: 0.03 });
    for (const field of ['price', 'size', 'tif']) expect(request).not.toHaveProperty(field);
  }
  const close = resolvePerpsDraft({ ...params, position, draft: { ...params.draft, editing: true, close: true } });
  expect(close.close).toMatchObject({ asset: asset.id, slippage: 0.03 });
  expect(close.orderSize).toBe('0.01');
});

test.each([
  ['long before threshold', '84.01', '1', '80', false],
  ['long at threshold', '84', '1', '80', true],
  ['long beyond liquidation', '79', '1', '80', true],
  ['long profitable', '110', '1', '80', false],
  ['short before threshold', '115.99', '-1', '120', false],
  ['short at threshold', '116', '-1', '120', true],
  ['short beyond liquidation', '121', '-1', '120', true],
  ['short profitable', '90', '-1', '120', false],
  ['missing liquidation', '84', '1', null, false], // eslint-disable-line no-null/no-null -- API uses null for missing liquidation prices.
  ['invalid liquidation direction', '110', '1', '120', false],
  ['zero entry distance', '100', '1', '100', false],
  ['closed position', '80', '0', '80', false],
  ['invalid price', 'bad', '1', '80', false],
])('liquidation warning: %s', (_, mark, size, liquidation, expected) => {
  const position = { ...raw, entryPx: '100', szi: size, liquidationPx: liquidation };
  expect(isPerpsPositionNearLiquidation(mark, position)).toBe(expected);
  expect(normalizePerpsPosition('a', { ...asset, context: { ...asset.context, markPx: mark } }, position)
    .isNearLiquidation).toBe(expected);
});

test('open keeps gross deposit, collateral and leveraged base quantity distinct', () => {
  const q = resolvePerpsDraft(params);
  expect(q.paymentAmount).toBe('50.2');
  expect(q.collateral).toBe('50');
  expect(q.orderSize).toBe('0.005');
  expect(q.notional).toBe('500');
});
test('isolated equity already includes P&L; cross margin does not', () => {
  expect(normalizePerpsPosition('a', asset, raw)).toMatchObject({
    equity: '110', collateral: '100', returnOnEquity: '0.1',
  });
  expect(
    normalizePerpsPosition('a', asset, { ...raw, leverage: { type: 'cross', value: 10 } }),
  ).toMatchObject({ equity: '120', collateral: '110' });
});
test('increase sends the delta size and deposit, not the new target', () => {
  const q = resolvePerpsDraft({
    ...params,
    position: normalizePerpsPosition('a', asset, raw),
    draft: { ...params.draft, amount: '150', editing: true },
  });
  expect(q.kind).toBe('increase');
  expect(q.modify).not.toHaveProperty('size');
  expect(q.orderSize).toBe('0.005');
  expect(q.modify?.depositAmount).toBe('50.2');
  expect(q.size).toBe('0.015');
});
test('partial reduction releases a gross USDC amount with no incoming payment', () => {
  const q = resolvePerpsDraft({
    ...params,
    position: normalizePerpsPosition('a', asset, raw),
    draft: { ...params.draft, amount: '75', editing: true },
  });
  expect(q.kind).toBe('reduce');
  expect(q.modify).toMatchObject({ depositAmount: '25', reduceOnly: true });
  expect(q.paymentAmount).toBe('0');
  expect(q.size).toBe('0.0075');
  expect(q.previousNotional).toBe('1000');
  expect(q.notional).toBe('750');
  expect(q.receiveStatus).toBe('pending');
  expect(q).not.toHaveProperty('receiveAmount');
  expect(q.liquidationPrice).toBe('90500');
  expect(q.estimatedLiquidationPrice).toBeUndefined();
});

test.each(['10', '-10', '0'])('close review keeps P&L %s distinct from equity and pending withdrawal', (pnl) => {
  const position = normalizePerpsPosition('a', asset, { ...raw, unrealizedPnl: pnl });
  const q = resolvePerpsDraft({
    ...params, position, draft: { ...params.draft, amount: '0', editing: true, close: true },
  });
  expect(q.profitLoss).toBe(pnl);
  expect(q.equity).toBe('110');
  expect(q.profitLoss).not.toBe(q.equity);
  expect(q.returnOnEquity).toBe(position.returnOnEquity);
  expect(q.receiveStatus).toBe('pending');
  expect(q).not.toHaveProperty('receiveAmount');
  expect(q.paymentAmount).toBe('0');
});

test('open interest is converted to USD with decimal precision and unavailable data stays absent', () => {
  const withContext = (openInterest: string, markPx: string) => ({
    ...asset, context: { ...asset.context, openInterest, markPx },
  });
  expect(getPerpsOpenInterestUsd(withContext('171497500.0', '1.3375'))).toBe('229377906.25');
  expect(getPerpsOpenInterestUsd(withContext('0', '100'))).toBe('0');
  expect(getPerpsOpenInterestUsd(asset)).toBeUndefined();
  expect(getPerpsOpenInterestUsd(withContext('100', '0'))).toBeUndefined();
  expect(getPerpsOpenInterestUsd(withContext('-1', '100'))).toBeUndefined();
});
test('zero target uses close; unchanged leverage-only does not make a deposit', () => {
  const position = normalizePerpsPosition('a', asset, raw);
  expect(
    resolvePerpsDraft({ ...params, position, draft: { ...params.draft, amount: '0', editing: true } }).kind,
  ).toBe('close');
  const q = resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '100', leverage: 5, editing: true },
  });
  expect(q.modify).toMatchObject({ leverage: 5 });
  expect(q.paymentAmount).toBe('0');
  expect(q.modify?.depositAmount).toBeUndefined();
});
test('modify estimate deposit funds a leverage decrease and stays zero on an increase', () => {
  const position = normalizePerpsPosition('a', asset, raw);
  const decrease = resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '100', leverage: 5, editing: true },
  });
  applyPerpsLeverageChangeDeposit(decrease, '100.2', params.availableUsdc);
  expect(decrease.paymentAmount).toBe('100.2');
  expect(decrease.bridgeFee).toBe('0.2');
  expect(decrease.collateral).toBe('200');
  expect(decrease.size).toBe('0.01');
  expect(decrease.modify).toMatchObject({ leverage: 5, depositAmount: '100.2' });

  const quoted = resolvePerpsDraft({
    ...params,
    position,
    availableUsdc: '80',
    draft: { ...params.draft, amount: '100', leverage: 5, editing: true },
  });
  applyPerpsLeverageChangeDeposit(quoted, '50.2', '80');
  expect(() => validatePerpsReviewedBuild(quoted, asset, {
    updateLeverage: { action: { asset: 0, leverage: 5, isCross: false } },
    updateIsolatedMargin: { action: { type: 'updateIsolatedMargin', asset: 0, isBuy: true, ntli: 50_000_000 } },
    deposit: { ...depositFixture, requiresPermitSignature: true as const },
  })).not.toThrow();
  expect(() => validatePerpsReviewedBuild(quoted, asset, {
    updateLeverage: { action: { asset: 0, leverage: 5, isCross: false } },
    deposit: { ...depositFixture, requiresPermitSignature: true as const },
  })).toThrow('PerpsReviewChanged');

  const increase = resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '100', leverage: 20, editing: true },
  });
  applyPerpsLeverageChangeDeposit(increase, '0', params.availableUsdc);
  expect(increase.paymentAmount).toBe('0');
  expect(increase.collateral).toBe('100');
  expect(increase.modify?.depositAmount).toBe('0');
  expect(() => validatePerpsReviewedBuild(increase, asset, {
    updateLeverage: { action: { asset: 0, leverage: 20, isCross: false } },
  })).not.toThrow();
  expect(() => validatePerpsReviewedBuild(increase, asset, {
    updateLeverage: { action: { asset: 0, leverage: 20, isCross: false } },
    deposit: { ...depositFixture, requiresPermitSignature: true as const },
  })).toThrow('PerpsReviewChanged');
  expect(() => applyPerpsLeverageChangeDeposit(increase, '500', '10')).toThrow('PerpsInsufficientUsdc');
});
test('fractions reserve bridge fee and enforce available collateral', () => {
  const q = resolvePerpsDraft({ ...params, draft: { ...params.draft, fraction: 100 } });
  expect(q.paymentAmount).toBe('200');
  expect(() => resolvePerpsDraft({ ...params, availableUsdc: '50' })).toThrow('PerpsInsufficientUsdc');
});
test('rejects unsupported leverage, dust and stale position intentions', () => {
  expect(() => resolvePerpsDraft({ ...params, draft: { ...params.draft, leverage: 41 } })).toThrow(
    'PerpsInvalidLeverage',
  );
  expect(() => resolvePerpsDraft({ ...params, draft: { ...params.draft, amount: '0.01' } })).toThrow(
    'PerpsAmountTooSmall',
  );
  expect(() => resolvePerpsDraft({
    ...params,
    depositLimits: { minOpenDepositUsdc: '60', minIncreaseDepositUsdc: '0.2', minPositionMarginUsdc: '10' },
  })).toThrow('PerpsAmountTooSmall');
  expect(() => resolvePerpsDraft({
    ...params,
    position: normalizePerpsPosition('a', asset, raw),
    depositLimits: { minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '80', minPositionMarginUsdc: '10' },
    draft: { ...params.draft, amount: '150', editing: true },
  })).toThrow('PerpsAmountTooSmall');
  const position = normalizePerpsPosition('a', asset, raw);
  const smallIncrease = resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '102', editing: true },
  });
  expect(smallIncrease.kind).toBe('increase');
  expect(smallIncrease.paymentAmount).toBe('2.2');
  expect(() => resolvePerpsDraft({
    ...params,
    position,
    depositLimits: { minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '0.5', minPositionMarginUsdc: '10' },
    draft: { ...params.draft, amount: '100.3', editing: true },
  })).toThrow('PerpsAmountTooSmall');
  expect(resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '10', editing: true },
  }).kind).toBe('reduce');
  expect(resolvePerpsDraft({
    ...params,
    position,
    draft: { ...params.draft, amount: '9', editing: true },
  }).kind).toBe('reduce');
  expect(() => resolvePerpsDraft({ ...params, draft: { ...params.draft, editing: true } })).toThrow(
    'PerpsPositionChanged',
  );
});
test.each([
  { marginUsed: '120', unrealizedPnl: '20', rawUsd: undefined, amount: '5', accepted: true },
  { marginUsed: '80', unrealizedPnl: '-20', rawUsd: undefined, amount: '25', accepted: false },
  { marginUsed: '80', unrealizedPnl: '-20', rawUsd: '120', amount: '5', accepted: true },
  { marginUsed: '120', unrealizedPnl: '20', rawUsd: '80', amount: '25', accepted: false },
])('minimum margin uses the backend balance independently of invested collateral: %j', (values) => {
  const position = normalizePerpsPosition('a', asset, {
    ...raw, marginUsed: values.marginUsed, unrealizedPnl: values.unrealizedPnl,
    leverage: { ...raw.leverage, rawUsd: values.rawUsd },
  });
  const resolve = () => resolvePerpsDraft({
    ...params, position, draft: { ...params.draft, editing: true, amount: values.amount },
  });
  if (values.accepted) expect(resolve().kind).toBe('reduce');
  else expect(resolve).toThrow('PerpsAmountTooSmall');
});

test('signed order must match reviewed asset, size, direction, slippage and deposit', () => {
  const q = resolvePerpsDraft({ ...params, now: Date.now() });
  const order = { a: 0, b: true, r: false, s: '0.00497', p: '100500', t: { limit: { tif: 'Ioc' } } };
  const build = {
    marketReferencePrice: '100000',
    action: { orders: [order] }, deposit: { ...depositFixture, requiresPermitSignature: true as const },
    updateLeverage: { action: { asset: 0, leverage: 10, isCross: false } },
  };
  expect(() => validatePerpsReviewedBuild(q, asset, build)).not.toThrow();
  for (const change of [{ a: 1 }, { b: false }, { s: '0.05' }, { p: '103001' }, { r: true },
    { t: { limit: { tif: 'Gtc' } } }, { t: { limit: { tif: 'Alo' } } },
    { t: { trigger: { isMarket: true, triggerPx: '100000', tpsl: 'tp' } } },
    { t: { limit: { tif: 'Ioc' }, trigger: { isMarket: true } } },
    { t: undefined },
  ]) {
    expect(() =>
      validatePerpsReviewedBuild(q, asset, { ...build, action: { orders: [{ ...order, ...change }] } }),
    ).toThrow('PerpsReviewChanged');
  }
  expect(() => validatePerpsReviewedBuild(q, asset, {
    ...build, deposit: { ...build.deposit, amountUsdc: '51' },
  })).toThrow('PerpsReviewChanged');
});

test.each(['open', 'increase', 'reduce', 'close', 'leverage'] as const)(
  '%s validates every action against the pinned canonical wire index', (kind) => {
    const canonical = { ...asset, wireAssetIndex: 110005 };
    const position = kind === 'open' ? undefined : normalizePerpsPosition(params.accountId, canonical, raw);
    const quote = resolvePerpsDraft({ ...params, asset: canonical, position,
      draft: { ...params.draft, editing: kind !== 'open',
        amount: kind === 'open' ? '50' : kind === 'increase' ? '150' : kind === 'reduce' ? '75' : '100',
        leverage: kind === 'leverage' ? 5 : 10, close: kind === 'close' } });
    expect(quote.kind).toBe(kind);
    expect(quote.wireAssetIndex).toBe(110005);
    const order = { a: 110005, b: kind === 'open' || kind === 'increase', r: kind === 'reduce' || kind === 'close',
      s: quote.orderSize, p: '99500', t: { limit: { tif: 'Ioc' } } };
    const build = {
      marketReferencePrice: '100000',
      action: kind === 'leverage' ? undefined : { orders: [order] },
      updateLeverage: { action: { asset: 110005, leverage: quote.leverage, isCross: quote.isCross } },
      deposit: kind === 'open' || kind === 'increase'
        ? { ...depositFixture, requiresPermitSignature: true as const } : undefined,
    };
    expect(() => validatePerpsReviewedBuild(quote, canonical, build)).not.toThrow();
    expect(() => validatePerpsReviewedBuild(quote, canonical, {
      ...build, updateLeverage: { action: { ...build.updateLeverage.action, asset: canonical.index } },
    })).toThrow('PerpsReviewChanged');
    if (kind !== 'leverage') {
      expect(() => validatePerpsReviewedBuild(quote, canonical, {
        ...build, action: { orders: [{ ...order, a: canonical.index }] },
      })).toThrow('PerpsReviewChanged');
    }
    expect(() => validatePerpsReviewedBuild(quote, { ...canonical, wireAssetIndex: 110006 }, build))
      .toThrow('PerpsReviewChanged');
    expect(() => validatePerpsReviewedBuild(quote, { ...canonical, id: 'another-market' }, build))
      .toThrow('PerpsReviewChanged');
    expect(() => validatePerpsReviewedBuild({ ...quote, wireAssetIndex: undefined }, canonical, build))
      .toThrow('PerpsReviewChanged');
  },
);

test.each(['open', 'increase', 'reduce', 'close', 'leverage'] as const)(
  'HIP-3 %s validates backend builds against the canonical index', (kind) => {
    const market = { ...asset, id: 'hyperliquid:xyz:NVDA', name: 'xyz:NVDA', symbol: 'NVDA', dex: 'xyz', index: 12,
      wireAssetIndex: 110012, szDecimals: 2, context: { ...asset.context, markPx: '190', prevDayPx: '189' } };
    const position = kind === 'open' ? undefined : normalizePerpsPosition(params.accountId, market, {
      ...raw, coin: market.name, szi: '10', marginUsed: '200', unrealizedPnl: '0',
    });
    const quote = resolvePerpsDraft({ ...params, asset: market, position, now: Date.now(),
      draft: { ...params.draft, assetId: market.id, editing: kind !== 'open',
        amount: kind === 'open' ? '50' : kind === 'increase' ? '250' : kind === 'reduce' ? '150' : '200',
        leverage: kind === 'leverage' ? 5 : 10, close: kind === 'close' } });
    if (kind === 'leverage') applyPerpsLeverageChangeDeposit(quote, '50.2', params.availableUsdc);
    const isBuy = kind === 'open' || kind === 'increase';
    const order = { a: 110012, b: isBuy, r: !isBuy, s: quote.orderSize,
      p: isBuy ? '195.7' : '184.3', t: { limit: { tif: 'Ioc' } } };
    const build = {
      marketReferencePrice: '190',
      action: kind === 'leverage' ? undefined : { type: 'order', grouping: 'na', orders: [order] },
      updateLeverage: kind === 'open' || kind === 'leverage'
        ? { action: { type: 'updateLeverage', asset: 110012, leverage: quote.leverage, isCross: false } } : undefined,
      updateIsolatedMargin: kind === 'leverage'
        ? { action: { type: 'updateIsolatedMargin', asset: 110012, isBuy: true, ntli: 50000000 } } : undefined,
      deposit: kind === 'open' || kind === 'increase' || kind === 'leverage'
        ? { ...depositFixture, requiresPermitSignature: true as const } : undefined,
    };
    expect(quote.wireAssetIndex).toBe(110012);
    expect(() => validatePerpsReviewedBuild(quote, market, build)).not.toThrow();
    if (kind === 'leverage') {
      expect(() => validatePerpsReviewedBuild(quote, market, {
        ...build, updateIsolatedMargin: { action: { ...build.updateIsolatedMargin!.action, asset: 110013 } },
      })).toThrow('PerpsReviewChanged');
    } else {
      for (const a of [-1, 1.5, '110012', Number.MAX_SAFE_INTEGER + 1]) {
        expect(() => validatePerpsReviewedBuild(quote, market, {
          ...build, action: { orders: [{ ...order, a }] },
        })).toThrow('PerpsReviewChanged');
      }
      if (build.updateLeverage) {
        expect(() => validatePerpsReviewedBuild(quote, market, {
          ...build, updateLeverage: { action: { ...build.updateLeverage!.action, asset: 110013 } },
        })).toThrow('PerpsReviewChanged');
      }
    }
  },
);

test('unit conversion and reset can describe an unchanged position without creating an order', () => {
  const position = normalizePerpsPosition('a', asset, raw);
  const quote = resolvePerpsDraft({ ...params, position,
    draft: { ...params.draft, amount: '100', editing: true, convertFrom: 'currency', unit: 'asset' } });
  expect(quote.kind).toBe('unchanged');
  expect(quote.inputAmount).toBe('0.01');
  expect(quote.currentInputAmount).toBe('0.01');
  expect(quote.modify).toBeUndefined();
  expect(() => validatePerpsReviewedBuild(quote, asset, {})).toThrow('PerpsUnchanged');
  const reset = resolvePerpsDraft({ ...params, position,
    draft: { ...params.draft, amount: '0.1', unit: 'asset', editing: true, reset: true } });
  expect(reset.kind).toBe('unchanged');
  expect(reset.inputAmount).toBe('0.01');
});

test('short reductions buy back only the reviewed delta and keep the margin mode', () => {
  const position = normalizePerpsPosition('a', asset, { ...raw, szi: '-0.01' });
  const quote = resolvePerpsDraft({ ...params, position, draft: { ...params.draft, amount: '75', editing: true } });
  expect(quote.side).toBe('short');
  const build = { marketReferencePrice: '100000', action: {
    orders: [{ a: 0, b: true, r: true, s: '0.00249', p: '100500', t: { limit: { tif: 'Ioc' } } }],
  } };
  expect(() => validatePerpsReviewedBuild(quote, asset, build)).not.toThrow();
  expect(() => validatePerpsReviewedBuild(quote, asset, {
    ...build, updateLeverage: { action: { asset: 0, leverage: 10, isCross: true } },
  })).toThrow('PerpsReviewChanged');
});

test('backend limits govern the gross deposit and preserve the entered target', () => {
  expect(() => resolvePerpsDraft({
    ...params, depositLimits: {
      minOpenDepositUsdc: '60', minIncreaseDepositUsdc: '10.2', minPositionMarginUsdc: '10',
    },
  }))
    .toThrow('PerpsAmountTooSmall');
  const quote = resolvePerpsDraft({ ...params,
    depositLimits: { minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '10.2', minPositionMarginUsdc: '10' } });
  expect(quote.collateral).toBe('50');
  expect(quote.open?.depositAmount).toBe('50.2');
  expect(quote.open).not.toHaveProperty('size');
});

test('HIP-3 eligibility uses backend canonical metadata without an account-mode policy', () => {
  const hip3 = { ...asset, dex: 'xyz', wireAssetIndex: 110005 };
  expect(getPerpsMarketTradingAvailability(hip3)).toEqual({ isAvailable: true });
  expect(resolvePerpsDraft({ ...params, asset: hip3 }).wireAssetIndex).toBe(110005);
});

test.each(['', 'xyz'])('market builds on %s validate the captured mid across an ordinary tick', (dex) => {
  const market = { ...asset, dex, wireAssetIndex: dex ? 110005 : 0 };
  const quote = resolvePerpsDraft({ ...params, asset: market, now: Date.now() });
  const order = { a: market.wireAssetIndex, b: true, r: false, s: '0.00499', p: '103010',
    t: { limit: { tif: 'Ioc' } } };
  const build = {
    marketReferencePrice: '100010',
    action: { orders: [order] },
    deposit: { ...depositFixture, requiresPermitSignature: true as const },
    updateLeverage: { action: { asset: market.wireAssetIndex, leverage: 10, isCross: false } },
  };
  expect(() => validatePerpsReviewedBuild(quote, market, build)).not.toThrow();
  for (const change of [{ p: '103011' }, { s: '0.01' }, { s: '0.00001' }, { a: 99 }, { b: false }]) {
    expect(() => validatePerpsReviewedBuild(quote, market,
      { ...build, action: { orders: [{ ...order, ...change }] } })).toThrow('PerpsReviewChanged');
  }
  expect(() => validatePerpsReviewedBuild(quote, market, { ...build, marketReferencePrice: '200000' }))
    .toThrow('PerpsReviewChanged');
  expect(() => validatePerpsReviewedBuild(quote, market, { ...build, marketReferencePrice: undefined }))
    .toThrow('PerpsReviewChanged');
});

test('small edits preserve the amount instead of applying a $10 trade delta floor', () => {
  const position = normalizePerpsPosition(params.accountId, asset, raw);
  const increase = resolvePerpsDraft({ ...params, position,
    draft: { ...params.draft, editing: true, amount: '100.5' } });
  const reduce = resolvePerpsDraft({ ...params, position,
    draft: { ...params.draft, editing: true, amount: '99.5' } });
  expect(increase.modify).toMatchObject({ depositAmount: '0.7', reduceOnly: false });
  expect(reduce.modify).toMatchObject({ depositAmount: '0.5', reduceOnly: true });
  expect(() => validatePerpsReviewedBuild(reduce, asset, {
    marketReferencePrice: '100010', action: {
      orders: [{ a: 0, b: false, r: true, s: '0.00005', p: '97010', t: { limit: { tif: 'Ioc' } } }],
    },
  })).not.toThrow();
});

test('leverage-only intent ignores a stale amount field and keeps position size unchanged', () => {
  const position = normalizePerpsPosition(params.accountId, asset, raw);
  const quote = resolvePerpsDraft({ ...params, position,
    draft: { ...params.draft, editing: true, leverageOnly: true, amount: '123', leverage: 5 } });
  expect(quote).toMatchObject({ kind: 'leverage', collateral: '100', size: '0.01', previousLeverage: 10 });
});

test('an explicit resize draft cannot turn into a leverage change when the live position changes', () => {
  const position = normalizePerpsPosition(params.accountId, asset, {
    ...raw, leverage: { type: 'isolated', value: 5 },
  });
  expect(() => resolvePerpsDraft({
    ...params, position,
    draft: { ...params.draft, editing: true, leverageOnly: false, amount: position.collateral },
  })).toThrow('PerpsPositionChanged');
});
