import { calcBigChangeValue, calcChangeValue } from './calcChangeValue';

it('computes the change from the current value and the change factor', () => {
  expect(calcChangeValue(150, 0.5)).toBe(50);
  expect(calcBigChangeValue('150', 0.5).toNumber()).toBe(50);
});

it.each([-1, -1.5])('reports no change for a factor of %s instead of dividing by zero', (changeFactor) => {
  expect(calcChangeValue(10, changeFactor)).toBe(0);
  expect(calcBigChangeValue('10', changeFactor).toNumber()).toBe(0);
});
