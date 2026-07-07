import type {
  ApiBaseCurrency,
  ApiPortfolioHistoryParams,
  ApiPortfolioHistoryResponse,
  ApiPortfolioPnlChangeResponse,
} from '../types';

import { DEFAULT_PRICE_CURRENCY, PORTFOLIO_API_URL } from '../../config';
import { DAY } from '../../util/dateFormat';
import { fetchJson } from '../../util/fetch';

const DEFAULT_PORTFOLIO_HISTORY_DAYS = 365;
const DEFAULT_PORTFOLIO_HISTORY_DENSITY = '1d';
const ALLOWED_DENSITIES = new Set(['5m', '1h', '4h', '1d']);

type PortfolioHistoryEndpoint = 'net-worth-history' | 'pnl-cumulative-history' | 'pnl-history' | 'pnl-change';

export async function fetchPortfolioNetWorthHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
) {
  return fetchJson<ApiPortfolioHistoryResponse>(
    buildPortfolioHistoryUrl('net-worth-history', wallets, baseCurrency, params),
  );
}

export async function fetchPortfolioPnlCumulativeHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
) {
  return fetchJson<ApiPortfolioHistoryResponse>(
    buildPortfolioHistoryUrl('pnl-cumulative-history', wallets, baseCurrency, params),
  );
}

export async function fetchPortfolioPnlHistory(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
) {
  return fetchJson<ApiPortfolioHistoryResponse>(
    buildPortfolioHistoryUrl('pnl-history', wallets, baseCurrency, params),
  );
}

export async function fetchPortfolioPnlChange(
  wallets: string[],
  baseCurrency: ApiBaseCurrency = DEFAULT_PRICE_CURRENCY,
  params?: ApiPortfolioHistoryParams,
) {
  return fetchJson<ApiPortfolioPnlChangeResponse>(
    buildPortfolioHistoryUrl('pnl-change', wallets, baseCurrency, params),
  );
}

function buildPortfolioHistoryUrl(
  endpoint: PortfolioHistoryEndpoint,
  wallets: string[],
  baseCurrency: ApiBaseCurrency,
  params: ApiPortfolioHistoryParams = {},
) {
  const to = (params.to !== undefined ? parseDate(params.to) : undefined) ?? new Date();
  const from = (params.from !== undefined ? parseDate(params.from) : undefined)
    ?? new Date(to.getTime() - DEFAULT_PORTFOLIO_HISTORY_DAYS * DAY);
  const density = params.density && ALLOWED_DENSITIES.has(params.density)
    ? params.density
    : DEFAULT_PORTFOLIO_HISTORY_DENSITY;

  const url = new URL(`${PORTFOLIO_API_URL}/${endpoint}`);
  url.searchParams.set('wallets', wallets.join(','));
  url.searchParams.set('base', baseCurrency.toLowerCase());
  url.searchParams.set('from', from.toISOString());
  url.searchParams.set('to', to.toISOString());
  url.searchParams.set('density', density);

  return url.toString();
}

// Native iOS sends `from` as unix seconds; web and Android send an ISO string
function parseDate(value: number | string) {
  const date = typeof value === 'number'
    ? new Date(value * 1000)
    : new Date(value);

  return Number.isNaN(date.getTime()) ? undefined : date;
}
