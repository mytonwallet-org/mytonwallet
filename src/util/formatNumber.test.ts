import { WHOLE_PART_DELIMITER } from '../config';
import {
  formatCompactCurrency,
  formatCompactNumber,
  formatCurrency,
  formatCurrencyExtended,
  formatNumber,
  formatPercent,
  formatSignedPercent,
} from './formatNumber';

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

  describe('Zero count subscript', () => {
    const testCases = [
      [0.0000056, 2, '0.0000056'], // 5 zeros - below the threshold
      [0.00000056, 2, '0.0₆56'], // 6 zeros - at the threshold
      [-0.00000056, 2, '-0.0₆56'],
      [1e-18, 2, '0.0₁₇1'], // Multi-digit zero count
    ] as const;

    for (const [input, fractionDigits, expected] of testCases) {
      test(`${input} => ${expected}`, () => {
        expect(formatNumber(input, fractionDigits)).toBe(expected);
      });
    }

    test('noZeroCountSubscript disables the notation', () => {
      expect(formatNumber(0.00000056, 2, false, true)).toBe('0.00000056');
    });

    test('formatCurrency forwards noZeroCountSubscript', () => {
      expect(formatCurrency(0.00000056, 'TON')).toBe('0.0₆56 TON');
      expect(formatCurrency(0.00000056, 'TON', undefined, undefined, true)).toBe('0.00000056 TON');
    });
  });
});

describe('formatCompactNumber', () => {
  const testCases = [
    [0, '0'],
    [999, '999'],
    [1000, '1K'],
    [12_345, '12.34K'],
    [999_999, '999.99K'],
    [4_030_000, '4.03M'],
    [7_580_000_000, '7.58B'],
    [5_120_000_000, '5.12B'],
    [-2_440_000, '-2.44M'],
  ] as const;

  for (const [input, expected] of testCases) {
    test(`${input} => ${expected}`, () => {
      expect(formatCompactNumber(input)).toBe(expected);
    });
  }

  test('formatCompactCurrency places the symbol as the currency config demands', () => {
    expect(formatCompactCurrency(7_580_000_000, '$')).toBe('$7.58B');
    expect(formatCompactCurrency(4_030_000, 'TON')).toBe('4.03M TON');
    expect(formatCompactCurrency(-1_580_000, '$')).toBe('-$1.58M');
  });
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
    expect(formatCurrencyExtended(-0.00000012345, 'USDT')).toBe('− 0.0₆12 USDT');
  });

  test('string value', () => {
    expect(formatCurrencyExtended('45.678', 'TON')).toBe('+ 45.67 TON');
    expect(formatCurrencyExtended('-45.678', 'USDT')).toBe('− 45.67 USDT');
  });

  test('fiat currency', () => {
    expect(formatCurrencyExtended(100, '$')).toBe('+ $100');
    expect(formatCurrencyExtended(-99.999, '₽')).toBe('− ₽99.99');
  });

  test('suffix short symbol (Gram)', () => {
    expect(formatCurrencyExtended(123.45678, 'GRAM')).toBe(`+\u202F123.45 GRAM`);
    expect(formatCurrencyExtended(-1234.56789, 'GRAM'))
      .toBe(`−\u202F1${WHOLE_PART_DELIMITER}234.56 GRAM`);
  });

  test('noSign', () => {
    expect(formatCurrencyExtended(123.456, 'TON', true)).toBe('123.45 TON');
    expect(formatCurrencyExtended(-123.456, 'USDT', true)).toBe('-123.45 USDT');
  });

  test('fractionDigits', () => {
    expect(formatCurrencyExtended(99.9999999, 'TON', false, 4)).toBe('+ 99.9999 TON');
    expect(formatCurrencyExtended(-0.00000012345, 'USDT', false, 3)).toBe('− 0.0₆123 USDT');
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

describe('formatSignedPercent', () => {
  test('prefixes growth with a plus', () => {
    expect(formatSignedPercent(0.1)).toBe('+0.1%');
    expect(formatSignedPercent(15.7)).toBe('+16%');
  });

  test('prefixes a drop with a minus sign', () => {
    expect(formatSignedPercent(-0.5)).toBe('−0.5%');
    expect(formatSignedPercent(-15.7)).toBe('−16%');
  });

  test('leaves zero unsigned', () => {
    expect(formatSignedPercent(0)).toBe('0%');
  });
});
