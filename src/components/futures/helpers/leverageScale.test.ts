import { buildLeverageScale, leverageToPosition, positionToLeverage } from './leverageScale';

describe('leverageScale', () => {
  it('spreads the minimum, the presets inside the range and the maximum evenly over the track', () => {
    const scale = buildLeverageScale(1, 40);

    expect(scale.stops).toEqual([1, 2, 5, 10, 20, 40]);
    expect(scale.positions).toEqual([0, 0.2, 0.4, 0.6, 0.8, 1]);
    expect(leverageToPosition(scale, 10)).toBeCloseTo(0.6, 4);
    expect(positionToLeverage(scale, 0.5)).toBe(8);
    expect(positionToLeverage(scale, 1)).toBe(40);
  });

  it('puts a single preset in the middle', () => {
    const scale = buildLeverageScale(1, 3);

    expect(scale.positions).toEqual([0, 0.5, 1]);
    expect(positionToLeverage(scale, 0.5)).toBe(2);
  });

  it('keeps a market without leverage at its only value', () => {
    const scale = buildLeverageScale(1, 1);

    expect(leverageToPosition(scale, 1)).toBe(0);
    expect(positionToLeverage(scale, 0.7)).toBe(1);
  });
});
