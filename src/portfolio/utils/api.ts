import { PORTFOLIO_API_URL } from '../config';

const HISTORY_DAYS = 365;
const MAX_RETRIES = 30;

export class RetryExhaustedError extends Error {
  constructor() {
    super('This takes longer than expected, re-open the app in a few minutes');
    this.name = 'RetryExhaustedError';
  }
}

function computeChartParams() {
  const to = new Date();
  const from = new Date(to.getTime() - HISTORY_DAYS * 86400000);
  return { from: from.toISOString(), to: to.toISOString(), density: '1d' };
}

async function fetchWithRetry(url: string, onProgress?: (attempt: number, maxRetries: number) => void) {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      const res = await fetch(url);
      if (res.ok) return res.json();
      const body = await res.text();
      throw new Error(body || `HTTP ${res.status}`);
    } catch (err) {
      if (err instanceof TypeError && attempt < MAX_RETRIES) {
        onProgress?.(attempt + 1, MAX_RETRIES);
        continue;
      }
      if (err instanceof TypeError) {
        throw new RetryExhaustedError();
      }
      throw err;
    }
  }
}

export function fetchNetWorthHistory(
  wallets: string,
  baseCurrency: string,
  onProgress?: (attempt: number, maxRetries: number) => void,
) {
  return fetchChartHistory('net-worth-history', wallets, baseCurrency, onProgress);
}

export function fetchPnlCumulativeHistory(
  wallets: string,
  baseCurrency: string,
  onProgress?: (attempt: number, maxRetries: number) => void,
) {
  return fetchChartHistory('pnl-cumulative-history', wallets, baseCurrency, onProgress);
}

export function fetchPnlHistory(
  wallets: string,
  baseCurrency: string,
  onProgress?: (attempt: number, maxRetries: number) => void,
) {
  return fetchChartHistory('pnl-history', wallets, baseCurrency, onProgress);
}

async function fetchChartHistory(
  endpoint: string,
  wallets: string,
  baseCurrency: string,
  onProgress?: (attempt: number, maxRetries: number) => void,
) {
  const { from, to, density } = computeChartParams();
  const params = new URLSearchParams({
    from, to, density, base: baseCurrency.toLowerCase(),
  });

  return fetchWithRetry(
    `${PORTFOLIO_API_URL}/${endpoint}?wallets=${wallets}&${params}`,
    onProgress,
  );
}
