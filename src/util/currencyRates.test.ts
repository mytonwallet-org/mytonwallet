import type { ApiCurrencyRates } from '../api/types';

import { CURRENCIES } from '../config';
import { Big } from '../lib/big.js';
import { calculateTokenPrice } from './calculatePrice';
import { sanitizeCurrencyRates } from './currencyRates';

const GOOD_RATES: ApiCurrencyRates = {
  USD: '1',
  EUR: '0.85999000',
  RUB: '86.63811900',
  CNY: '6.71915000',
  BTC: '0.000012594155896938',
  TON: '0.734524104',
};

const UNUSABLE_RATES = [
  'Infinity',
  '-Infinity',
  'NaN',
  '',
  '   ',
  '0',
  '0.0',
  '-1',
  '0x10',
  ' 1 ',
  'abc',
  undefined,
];

describe('sanitizeCurrencyRates', () => {
  it('passes usable rates through untouched', () => {
    expect(sanitizeCurrencyRates(GOOD_RATES)).toEqual(GOOD_RATES);
  });

  it.each(UNUSABLE_RATES)('replaces %p with the fallback rate', (rate) => {
    const rates = { ...GOOD_RATES, TON: rate } as ApiCurrencyRates;

    expect(sanitizeCurrencyRates(rates).TON).toBe(CURRENCIES.TON.fallbackRate);
  });

  it('keeps the other currencies when one is unusable', () => {
    const rates = { ...GOOD_RATES, TON: 'Infinity' } as ApiCurrencyRates;

    expect(sanitizeCurrencyRates(rates).EUR).toBe(GOOD_RATES.EUR);
  });

  it('fills in a currency the payload omits', () => {
    const { BTC, ...withoutBtc } = GOOD_RATES;

    expect(sanitizeCurrencyRates(withoutBtc).BTC).toBe(CURRENCIES.BTC.fallbackRate);
  });

  it('returns every currency when handed nothing at all', () => {
    expect(Object.keys(sanitizeCurrencyRates(undefined))).toEqual(Object.keys(CURRENCIES));
  });

  it('keeps a token price computable from a payload carrying a divide-by-zero rate', () => {
    const served = {
      USD: '1',
      EUR: '0.85994000',
      RUB: '86.65004100',
      CNY: '6.71915000',
      BTC: '0.000012511930678636',
      TON: 'Infinity',
    } as ApiCurrencyRates;

    const rates = sanitizeCurrencyRates(served);

    expect(() => calculateTokenPrice(1.36, 'TON', rates)).not.toThrow();
    expect(calculateTokenPrice(1.36, 'EUR', rates)).toBeCloseTo(1.169518);
  });

  it('produces rates that Big can always multiply by', () => {
    const poisoned = Object.fromEntries(
      Object.keys(CURRENCIES).map((currency) => [currency, 'Infinity']),
    ) as ApiCurrencyRates;

    const rates = sanitizeCurrencyRates(poisoned);

    for (const currency of Object.keys(CURRENCIES)) {
      expect(() => new Big(1).mul(rates[currency as keyof typeof CURRENCIES])).not.toThrow();
    }
  });
});
