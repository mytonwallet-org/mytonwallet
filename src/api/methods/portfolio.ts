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

export type ApiPortfolioHistoryParams = {
  from?: number | string;
  to?: number | string;
  density?: string;
};

const DEFAULT_PORTFOLIO_HISTORY_DAYS = 365;
const DEFAULT_PORTFOLIO_HISTORY_DENSITY = '1d';

type PortfolioHistoryEndpoint = 'net-worth-history' | 'pnl-cumulative-history' | 'pnl-history';

function toDate(value: number | string) {
  if (typeof value === 'number') {
    return new Date(value * 1000);
  }

  return new Date(value);
}

function computePortfolioHistoryParams(params: ApiPortfolioHistoryParams = {}) {
  const to = params.to !== undefined ? toDate(params.to) : new Date();
  const from = params.from !== undefined
    ? toDate(params.from)
    : new Date(to.getTime() - DEFAULT_PORTFOLIO_HISTORY_DAYS * 86_400_000);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    density: params.density ?? DEFAULT_PORTFOLIO_HISTORY_DENSITY,
  };
}

function buildPortfolioHistoryUrl(
  endpoint: PortfolioHistoryEndpoint,
  wallets: string[],
  baseCurrency: ApiBaseCurrency,
  params?: ApiPortfolioHistoryParams,
) {
  const { from, to, density } = computePortfolioHistoryParams(params);
  const url = new URL(`${PORTFOLIO_API_URL}/${endpoint}`);

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
  params?: ApiPortfolioHistoryParams,
): Promise<ApiPortfolioHistoryResponse> {
  const url = buildPortfolioHistoryUrl('net-worth-history', wallets, baseCurrency, params);

  return fetchJson<ApiPortfolioHistoryResponse>(url);
}

export async function fetchPortfolioPnlCumulativeHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
): Promise<ApiPortfolioHistoryResponse> {
  const url = buildPortfolioHistoryUrl('pnl-cumulative-history', wallets, baseCurrency, params);

  return fetchJson<ApiPortfolioHistoryResponse>(url);
}

export async function fetchPortfolioPnlHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
): Promise<ApiPortfolioHistoryResponse> {
  const url = buildPortfolioHistoryUrl('pnl-history', wallets, baseCurrency, params);

  return fetchJson<ApiPortfolioHistoryResponse>(url);
}
