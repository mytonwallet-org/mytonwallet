import {
  getAssetAmountPrecision,
  pricePrecisionFromUsdPrice,
} from './assetPrecision';

describe('pricePrecisionFromUsdPrice', () => {
  test.each([
    [0, 0],
    [0.0001, 0],
    [0.97, 0],
    [0.98, 2],
    [1, 2],
    [999.99, 2],
    [1000, 4],
    [95000, 4],
  ] as const)('%s → %s', (priceUsd, expected) => {
    expect(pricePrecisionFromUsdPrice(priceUsd)).toBe(expected);
  });
});

describe('getAssetAmountPrecision', () => {
  test('prefers the backend field', () => {
    expect(getAssetAmountPrecision({ precision: 4, priceUsd: 0.0001 })).toBe(4);
  });

  test('derives from priceUsd when precision is absent', () => {
    expect(getAssetAmountPrecision({ priceUsd: 95000 })).toBe(4);
    expect(getAssetAmountPrecision({ priceUsd: 2 })).toBe(2);
    expect(getAssetAmountPrecision({ priceUsd: 0.0001 })).toBe(0);
  });

  test('ignores a backend field outside the whole range 0..18', () => {
    expect(getAssetAmountPrecision({ precision: -6, priceUsd: 2 })).toBe(2);
    expect(getAssetAmountPrecision({ precision: 1.5, priceUsd: 2 })).toBe(2);
    expect(getAssetAmountPrecision({ precision: 400, priceUsd: 95000 })).toBe(4);
  });

  test('falls back to 2 when price is missing or zero', () => {
    expect(getAssetAmountPrecision({})).toBe(2);
    expect(getAssetAmountPrecision({ priceUsd: 0 })).toBe(2);
  });
});
