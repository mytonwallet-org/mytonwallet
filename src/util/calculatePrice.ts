import type { ApiBaseCurrency, ApiCurrencyRates } from '../api/types';

import { Big } from '../lib/big.js';

export function calculateTokenPrice(
  priceUsd: number,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
): number {
  const rateString = currencyRates[baseCurrency];

  const priceBig = new Big(priceUsd);
  const rateBig = new Big(rateString);

  return priceBig.mul(rateBig).toNumber();
}
