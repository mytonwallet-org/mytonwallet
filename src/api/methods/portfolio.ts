import type { ApiBaseCurrency, ApiHistoryList } from '../types';

import { DEFAULT_PRICE_CURRENCY, PORTFOLIO_API_URL } from '../../config';
import { fetchJson } from '../../util/fetch';

export type ApiPortfolioHistoryDataset = {
  assetId: number;
  symbol: string;
  contractAddress: string;
  color?: string;
  points: ApiHistoryList;
  impact?: number;
};

export type ApiPortfolioHistoryResponse = {
  status: string;
  points?: ApiHistoryList;
  datasets?: ApiPortfolioHistoryDataset[];
  base: string;
  density: string;
  historyScanCursor?: number;
  assetLimitExceeded?: true;
};

const PORTFOLIO_HISTORY_DAYS = 365;
const PORTFOLIO_HISTORY_DENSITY = '1d';

function computePortfolioHistoryParams() {
  const to = new Date();
  const from = new Date(to.getTime() - PORTFOLIO_HISTORY_DAYS * 86_400_000);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    density: PORTFOLIO_HISTORY_DENSITY,
  };
}

function buildPortfolioHistoryUrl(wallets: string[], baseCurrency: ApiBaseCurrency) {
  const { from, to, density } = computePortfolioHistoryParams();
  const url = new URL(`${PORTFOLIO_API_URL}/net-worth-history`);

  url.searchParams.set('wallets', wallets.join(','));
  url.searchParams.set('from', from);
  url.searchParams.set('to', to);
  url.searchParams.set('density', density);
  url.searchParams.set('base', baseCurrency.toLowerCase());

  return url.toString();
}

export async function fetchPortfolioNetWorthHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
): Promise<ApiPortfolioHistoryResponse> {
  const url = buildPortfolioHistoryUrl(wallets, baseCurrency);

  return fetchJson<ApiPortfolioHistoryResponse>(url);
}
