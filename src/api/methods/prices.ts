import type { ApiBaseCurrency, ApiHistoryList, ApiPriceHistoryPeriod } from '../types';

import { DEFAULT_PRICE_CURRENCY, TONCOIN } from '../../config';
import { callBackendGet } from '../common/backend';
import { tokensPreload } from '../common/tokens';
import { getTokenBySlug } from './tokens';

export async function fetchPriceHistory(
  slug: string,
  period: ApiPriceHistoryPeriod,
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
): Promise<ApiHistoryList | undefined> {
  await tokensPreload.promise;
  const token = getTokenBySlug(slug);

  if (!token) {
    return [];
  }

  const assetId = token.chain === TONCOIN.chain && token.tokenAddress ? token.tokenAddress : token.symbol;

  return callBackendGet(`/prices/chart/${assetId}`, {
    base: baseCurrency,
    period,
  });
}
