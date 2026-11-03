import type { ApiBaseCurrency, ApiHistoryList, ApiPriceHistoryPeriod, ApiToken } from '../types';

import { DEFAULT_PRICE_CURRENCY } from '../../config';
import { callBackendGet } from '../common/backend';
import { getTokenBySlug, tokensPreload } from '../common/tokens';

export async function fetchPriceHistory(
  slug: string,
  period: ApiPriceHistoryPeriod,
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  fallbackToken?: Pick<ApiToken, 'chain' | 'tokenAddress' | 'symbol'>,
): Promise<ApiHistoryList | undefined> {
  await tokensPreload.promise;
  const token = getTokenBySlug(slug) ?? fallbackToken;

  if (!token) {
    throw new Error('Token not found');
  }

  const assetId = `${token.chain}:${token.tokenAddress ?? token.symbol}`;

  return callBackendGet<ApiHistoryList>(`/prices/chart/${encodeURIComponent(assetId)}`, {
    base: baseCurrency,
    period,
  });
}

export async function fetchTokenNetWorthHistory(
  accountAddress: string,
  assetId: string,
  period: ApiPriceHistoryPeriod,
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
): Promise<ApiHistoryList | { error: string }> {
  return callBackendGet('/portfolio/net-worth-by-asset', {
    base: baseCurrency,
    period,
    walletAddress: accountAddress,
    assetAddress: assetId,
  });
}
