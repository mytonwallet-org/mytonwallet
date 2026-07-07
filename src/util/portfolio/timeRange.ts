import type { ApiPriceHistoryPeriod } from '../../api/types';

import { DAY } from '../dateFormat';

export const PORTFOLIO_TIME_RANGES: readonly ApiPriceHistoryPeriod[] = ['ALL', '1Y', '3M', '1M', '7D', '1D'];

export const DEFAULT_PORTFOLIO_TIME_RANGE: ApiPriceHistoryPeriod = '3M';

const DURATION_MS: Record<Exclude<ApiPriceHistoryPeriod, 'ALL'>, number> = {
  '1Y': 365 * DAY,
  '3M': 90 * DAY,
  '1M': 30 * DAY,
  '7D': 7 * DAY,
  '1D': DAY,
};

const FIVE_MINUTES_MS = 5 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;

export type PortfolioHistorySlot = number;

export function getTimeRangeStartTs(range: ApiPriceHistoryPeriod, nowTs: number = Date.now()) {
  if (range === 'ALL') return undefined;

  return nowTs - DURATION_MS[range];
}

// Quantizes `nowTs` to the backend point density for `range`. While the slot matches the one
// stored alongside cached data, refetching can only return the same series the cache already holds
export function getPortfolioHistorySlot(
  range: ApiPriceHistoryPeriod,
  nowTs: number = Date.now(),
): PortfolioHistorySlot {
  if (range === '1D') return Math.floor(nowTs / FIVE_MINUTES_MS);
  if (range === '7D') return Math.floor(nowTs / ONE_HOUR_MS);
  // 1M / 3M / 1Y / ALL run on `1d` density - one UTC day per slot
  return Math.floor(nowTs / DAY);
}
