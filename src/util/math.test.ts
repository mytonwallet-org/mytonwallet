import { clamp, getPseudoRandom, isBetween, lerp, round, roundToNearestEven } from './math';

describe('clamp', () => {
  test('returns value when within range', () => {
    expect(clamp(5, 0, 10)).toBe(5);
    expect(clamp(0, -10, 10)).toBe(0);
    expect(clamp(-5, -10, 0)).toBe(-5);
  });

  test('returns min when value is below range', () => {
    expect(clamp(-5, 0, 10)).toBe(0);
    expect(clamp(-100, -10, 10)).toBe(-10);
  });

  test('returns max when value is above range', () => {
    expect(clamp(15, 0, 10)).toBe(10);
    expect(clamp(100, -10, 10)).toBe(10);
  });

  test('handles edge cases', () => {
    expect(clamp(0, 0, 10)).toBe(0);
    expect(clamp(10, 0, 10)).toBe(10);
    expect(clamp(5, 5, 5)).toBe(5);
  });

  test('handles negative ranges', () => {
    expect(clamp(-5, -10, -1)).toBe(-5);
    expect(clamp(0, -10, -1)).toBe(-1);
    expect(clamp(-15, -10, -1)).toBe(-10);
  });

  test('handles decimal values', () => {
    expect(clamp(5.5, 0, 10)).toBe(5.5);
    expect(clamp(0.1, 0, 1)).toBe(0.1);
    expect(clamp(-0.5, 0, 1)).toBe(0);
  });
});

describe('isBetween', () => {
  test('returns true when value is within range (inclusive)', () => {
    expect(isBetween(5, 0, 10)).toBe(true);
    expect(isBetween(0, -10, 10)).toBe(true);
    expect(isBetween(-5, -10, 0)).toBe(true);
  });

  test('returns true for boundary values', () => {
    expect(isBetween(0, 0, 10)).toBe(true);
    expect(isBetween(10, 0, 10)).toBe(true);
    expect(isBetween(-10, -10, 0)).toBe(true);
  });

  test('returns false when value is outside range', () => {
    expect(isBetween(-5, 0, 10)).toBe(false);
    expect(isBetween(15, 0, 10)).toBe(false);
    expect(isBetween(100, -10, 10)).toBe(false);
  });

  test('handles negative ranges', () => {
    expect(isBetween(-5, -10, -1)).toBe(true);
    expect(isBetween(0, -10, -1)).toBe(false);
    expect(isBetween(-15, -10, -1)).toBe(false);
  });

  test('handles decimal values', () => {
    expect(isBetween(5.5, 0, 10)).toBe(true);
    expect(isBetween(0.1, 0, 1)).toBe(true);
    expect(isBetween(1.1, 0, 1)).toBe(false);
  });
});

describe('round', () => {
  test('rounds to 0 decimals by default', () => {
    expect(round(5.4)).toBe(5);
    expect(round(5.5)).toBe(6);
    expect(round(5.6)).toBe(6);
  });

  test('rounds to specified decimals', () => {
    expect(round(5.123, 2)).toBe(5.12);
    expect(round(5.126, 2)).toBe(5.13);
    expect(round(5.125, 2)).toBe(5.13);
  });

  test('handles negative numbers', () => {
    expect(round(-5.4)).toBe(-5);
    expect(round(-5.5)).toBe(-5);
    expect(round(-5.123, 2)).toBe(-5.12);
  });

  test('handles zero decimals explicitly', () => {
    expect(round(123.456, 0)).toBe(123);
    expect(round(123.567, 0)).toBe(124);
  });

  test('handles large decimal places', () => {
    expect(round(1.23456789, 5)).toBe(1.23457);
    expect(round(1.23456789, 8)).toBe(1.23456789);
  });

  test('handles edge cases', () => {
    expect(round(0, 2)).toBe(0);
    expect(round(0.001, 2)).toBe(0);
    expect(round(0.009, 2)).toBe(0.01);
  });
});

describe('lerp', () => {
  test('returns start when ratio is 0', () => {
    expect(lerp(0, 10, 0)).toBe(0);
    expect(lerp(5, 15, 0)).toBe(5);
    expect(lerp(-10, 10, 0)).toBe(-10);
  });

  test('returns end when ratio is 1', () => {
    expect(lerp(0, 10, 1)).toBe(10);
    expect(lerp(5, 15, 1)).toBe(15);
    expect(lerp(-10, 10, 1)).toBe(10);
  });

  test('interpolates correctly at 0.5', () => {
    expect(lerp(0, 10, 0.5)).toBe(5);
    expect(lerp(0, 100, 0.5)).toBe(50);
    expect(lerp(-10, 10, 0.5)).toBe(0);
  });

  test('interpolates at various ratios', () => {
    expect(lerp(0, 10, 0.25)).toBe(2.5);
    expect(lerp(0, 10, 0.75)).toBe(7.5);
    expect(lerp(0, 100, 0.1)).toBe(10);
  });

  test('handles negative values', () => {
    expect(lerp(-100, 0, 0.5)).toBe(-50);
    expect(lerp(-10, -5, 0.5)).toBe(-7.5);
  });

  test('handles decimal start and end', () => {
    expect(lerp(1.5, 2.5, 0.5)).toBe(2);
    expect(lerp(0.1, 0.9, 0.5)).toBe(0.5);
  });

  test('handles ratios outside 0-1 range (extrapolation)', () => {
    expect(lerp(0, 10, 2)).toBe(20);
    expect(lerp(0, 10, -1)).toBe(-10);
  });
});

describe('roundToNearestEven', () => {
  test('rounds to nearest even number', () => {
    expect(roundToNearestEven(5)).toBe(6);
    expect(roundToNearestEven(6)).toBe(6);
    expect(roundToNearestEven(7)).toBe(8);
    expect(roundToNearestEven(8)).toBe(8);
  });

  test('handles odd numbers', () => {
    expect(roundToNearestEven(1)).toBe(2);
    expect(roundToNearestEven(3)).toBe(4);
    expect(roundToNearestEven(9)).toBe(10);
  });

  test('handles even numbers', () => {
    expect(roundToNearestEven(2)).toBe(2);
    expect(roundToNearestEven(4)).toBe(4);
    expect(roundToNearestEven(10)).toBe(10);
  });

  test('handles zero and negative numbers', () => {
    expect(roundToNearestEven(0)).toBe(0);
    expect(roundToNearestEven(-1)).toBe(-0); // Math.round(-1/2) * 2 = Math.round(-0.5) * 2 = -0
    expect(roundToNearestEven(-2)).toBe(-2);
    expect(roundToNearestEven(-5)).toBe(-4); // Math.round(-5/2) * 2 = Math.round(-2.5) * 2 = -4
  });

  test('rounds decimal values', () => {
    expect(roundToNearestEven(5.3)).toBe(6); // Math.round(5.3/2) * 2 = Math.round(2.65) * 2 = 3 * 2 = 6
    expect(roundToNearestEven(5.7)).toBe(6); // Math.round(5.7/2) * 2 = Math.round(2.85) * 2 = 3 * 2 = 6
    expect(roundToNearestEven(6.3)).toBe(6); // Math.round(6.3/2) * 2 = Math.round(3.15) * 2 = 3 * 2 = 6
    expect(roundToNearestEven(6.8)).toBe(6); // Math.round(6.8/2) * 2 = Math.round(3.4) * 2 = 3 * 2 = 6
  });

  test('rounds half values correctly', () => {
    expect(roundToNearestEven(5.5)).toBe(6);
    expect(roundToNearestEven(6.5)).toBe(6);
    expect(roundToNearestEven(7.5)).toBe(8);
  });
});

describe('getPseudoRandom', () => {
  test('returns value within range', () => {
    for (let i = 0; i < 20; i++) {
      const result = getPseudoRandom(0, 10, i);
      expect(result).toBeGreaterThanOrEqual(0);
      expect(result).toBeLessThanOrEqual(10);
    }
  });

  test('returns same value for same index (deterministic)', () => {
    expect(getPseudoRandom(0, 100, 5)).toBe(getPseudoRandom(0, 100, 5));
    expect(getPseudoRandom(10, 50, 42)).toBe(getPseudoRandom(10, 50, 42));
  });

  test('returns different values for different indices', () => {
    const value1 = getPseudoRandom(0, 100, 1);
    const value2 = getPseudoRandom(0, 100, 2);
    const value3 = getPseudoRandom(0, 100, 3);

    const uniqueValues = new Set([value1, value2, value3]);
    expect(uniqueValues.size).toBeGreaterThan(1);
  });

  test('handles single value range', () => {
    expect(getPseudoRandom(5, 5, 0)).toBe(5);
    expect(getPseudoRandom(5, 5, 10)).toBe(5);
  });

  test('handles negative ranges', () => {
    for (let i = 0; i < 20; i++) {
      const result = getPseudoRandom(-10, -5, i);
      expect(result).toBeGreaterThanOrEqual(-10);
      expect(result).toBeLessThanOrEqual(-5);
    }
  });

  test('handles large ranges', () => {
    for (let i = 0; i < 100; i++) {
      const result = getPseudoRandom(0, 10000, i);
      expect(result).toBeGreaterThanOrEqual(0);
      expect(result).toBeLessThanOrEqual(10000);
    }
  });

  test('handles zero index', () => {
    const result = getPseudoRandom(0, 100, 0);
    expect(result).toBeGreaterThanOrEqual(0);
    expect(result).toBeLessThanOrEqual(100);
  });

  test('produces reasonable distribution', () => {
    const results: number[] = [];
    for (let i = 0; i < 1000; i++) {
      results.push(getPseudoRandom(0, 9, i));
    }

    // Check that we get variety of values (not all the same)
    const uniqueValues = new Set(results);
    expect(uniqueValues.size).toBeGreaterThan(5); // Should have at least half of possible values

    // Check that values are distributed across the range
    const min = Math.min(...results);
    const max = Math.max(...results);
    expect(min).toBe(0);
    expect(max).toBe(9);
  });
});
