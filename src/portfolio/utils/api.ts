const API_URL = 'https://mtw-portfolio-a62e64ba29f9.herokuapp.com/api';
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

export async function fetchChartData(
  wallets: string,
  baseCurrency: string,
  onProgress?: (attempt: number, maxRetries: number) => void,
) {
  const { from, to, density } = computeChartParams();
  const params = new URLSearchParams({
    from, to, density, base: baseCurrency.toLowerCase(),
  });

  return fetchWithRetry(
    `${API_URL}/net-worth-history?wallets=${wallets}&${params}`,
    onProgress,
  );
}
