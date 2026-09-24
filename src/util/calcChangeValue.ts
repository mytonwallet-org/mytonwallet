import { Big } from '../lib/big.js';

// After a 100% drop, the previous price cannot be found. The factor is rounded, so it reaches -1 even for
// a slightly smaller drop. In this case the change is zero, because the formula would divide by zero.
const LOWEST_CHANGE_FACTOR = -1;

export function calcChangeValue(currentPrice: number, changeFactor: number) {
  if (changeFactor <= LOWEST_CHANGE_FACTOR) return 0;

  return currentPrice - currentPrice / (1 + changeFactor);
}

export function calcBigChangeValue(currentPrice: Big | string, changeFactor: Big | number) {
  currentPrice = Big(currentPrice);
  changeFactor = Big(changeFactor);
  if (changeFactor.lte(LOWEST_CHANGE_FACTOR)) return Big(0);

  return currentPrice.minus(currentPrice.div(changeFactor.plus(1)));
}
