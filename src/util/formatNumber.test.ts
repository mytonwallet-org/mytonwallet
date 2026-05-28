import { WHOLE_PART_DELIMITER } from '../config';
import { formatCurrencyExtended, formatNumber, formatPercent } from './formatNumber';

describe('formatNumber', () => {
  const testCasesTruncate = [
    [44.0074, 2, '44'],
    [44.074, 2, '44.07'],
    [1.00032, 2, '1'],
    [0.2857, 2, '0.28'],
    [0.02857, 2, '0.028'],
    [0.002857, 2, '0.0028'],
    [0.00002857, 2, '0.000028'],
    [-123.456, 2, '-123.45'],
    [-100500, 2, `-100${WHOLE_PART_DELIMITER}500`],
    [-0.000012345, 2, '-0.000012'],
  ] as const;

  const testCasesNoTruncate = [
    [0.09739, 2, '0.097'],
    [0.09759, 2, '0.098'],
    [0.0009759, 2, '0.00098'],
    [0.0000069759, 2, '0.000007'],
    [44.0074, 2, '44.01'],
    [12.3456, 2, '12.35'],
    [0.08279, 2, '0.083'],
    [1.00032, 2, '1'],
    [0.095121, 4, '0.09512'],
    [1.09518, 4, '1.0952'],
    [1.00168, 4, '1.0017'],
    [1.0000901, 4, '1.0001'],
    [1000.03957, 2, `1${WHOLE_PART_DELIMITER}000.04`],
    [349230.03957, 2, `349${WHOLE_PART_DELIMITER}230.04`],
    [999.3456, 2, '999.35'],
    [999.99999, 2, `1${WHOLE_PART_DELIMITER}000`],
    [-123.456, 2, '-123.46'],
  ] as const;

  describe(
    'Rounding mode: Big.roundDown (Rounds towards zero. I.e. truncate, no rounding.)',
    () => {
      for (const [input, fractionDigits, expected] of testCasesTruncate) {
        test(`${input} => ${expected}`, () => {
          expect(formatNumber(input, fractionDigits)).toBe(expected);
        });
      }
    },
  );

  describe(
    'Rounding mode: Big.roundHalfUp (Rounds towards nearest neighbour.'
    + ' If equidistant, rounds away from zero.)',
    () => {
      for (const [input, fractionDigits, expected] of testCasesNoTruncate) {
        test(`${input} => ${expected}`, () => {
          expect(formatNumber(input, fractionDigits, true)).toBe(expected);
        });
      }
    },
  );
});

describe('formatCurrencyExtended', () => {
  test('plain value', () => {
    expect(formatCurrencyExtended(123.45678, 'TON')).toBe('+ 123.45 TON');
    expect(formatCurrencyExtended(456, 'USDT')).toBe('+ 456 USDT');
    expect(formatCurrencyExtended(0, 'NOT')).toBe('+ 0 NOT');
  });

  test('negative value', () => {
    expect(formatCurrencyExtended(-123.45678, 'TON')).toBe('− 123.45 TON');
    expect(formatCurrencyExtended(-456, 'USDT')).toBe('− 456 USDT');
  });

  test('long integer part', () => {
    expect(formatCurrencyExtended(1234567.89, 'TON'))
      .toBe(`+\u202F1${WHOLE_PART_DELIMITER}234${WHOLE_PART_DELIMITER}567.89 TON`);
    expect(formatCurrencyExtended(-1234.56789, 'USDT'))
      .toBe(`−\u202F1${WHOLE_PART_DELIMITER}234.56 USDT`);
  });

  test('modulo < 1', () => {
    expect(formatCurrencyExtended(0.99999, 'TON')).toBe('+ 0.99 TON');
    expect(formatCurrencyExtended(-0.00000012345, 'USDT')).toBe('− 0.00000012 USDT');
  });

  test('string value', () => {
    expect(formatCurrencyExtended('45.678', 'TON')).toBe('+ 45.67 TON');
    expect(formatCurrencyExtended('-45.678', 'USDT')).toBe('− 45.67 USDT');
  });

  test('fiat currency', () => {
    expect(formatCurrencyExtended(100, '$')).toBe('+ $100');
    expect(formatCurrencyExtended(-99.999, '₽')).toBe('− ₽99.99');
  });

  test('noSign', () => {
    expect(formatCurrencyExtended(123.456, 'TON', true)).toBe('123.45 TON');
    expect(formatCurrencyExtended(-123.456, 'USDT', true)).toBe('-123.45 USDT');
  });

  test('fractionDigits', () => {
    expect(formatCurrencyExtended(99.9999999, 'TON', false, 4)).toBe('+ 99.9999 TON');
    expect(formatCurrencyExtended(-0.00000012345, 'USDT', false, 3)).toBe('− 0.000000123 USDT');
    expect(formatCurrencyExtended(12.345, 'USDT', false, 10)).toBe('+ 12.345 USDT');
  });

  test('isZeroNegative', () => {
    expect(formatCurrencyExtended(0, 'TON', false, undefined, true)).toBe('− 0 TON');
    expect(formatCurrencyExtended(1, 'TON', false, undefined, true)).toBe('+ 1 TON');
    expect(formatCurrencyExtended(-1, 'TON', false, undefined, true)).toBe('− 1 TON');
  });
});

describe('formatPercent', () => {
  test('below 10 keeps one decimal', () => {
    expect(formatPercent(0)).toBe('0%');
    expect(formatPercent(0.1)).toBe('0.1%');
    expect(formatPercent(1.23)).toBe('1.2%');
    expect(formatPercent(5.55)).toBe('5.6%');
    expect(formatPercent(9.94)).toBe('9.9%');
  });

  test('at or above 10 rounds to integer', () => {
    expect(formatPercent(10)).toBe('10%');
    expect(formatPercent(15.7)).toBe('16%');
    expect(formatPercent(99.4)).toBe('99%');
    expect(formatPercent(100)).toBe('100%');
    expect(formatPercent(1234.5)).toBe('1235%');
  });

  test('boundary at 10', () => {
    expect(formatPercent(9.95)).toBe('10%');
    expect(formatPercent(9.99)).toBe('10%');
  });

  test('preserves sign for negative values', () => {
    expect(formatPercent(-0.5)).toBe('-0.5%');
    expect(formatPercent(-9.94)).toBe('-9.9%');
    expect(formatPercent(-10)).toBe('-10%');
    expect(formatPercent(-15.7)).toBe('-16%');
  });

  test('rounds .5 ties away from zero symmetrically', () => {
    expect(formatPercent(9.95)).toBe('10%');
    expect(formatPercent(-9.95)).toBe('-10%');
    expect(formatPercent(5.55)).toBe('5.6%');
    expect(formatPercent(-5.55)).toBe('-5.6%');
  });
});
