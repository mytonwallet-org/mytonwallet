import type { ApiPriceHistoryPeriod } from '../../../api/types';

import { DAY } from '../../../util/dateFormat';

export const PORTFOLIO_TIME_RANGES: readonly ApiPriceHistoryPeriod[] = ['ALL', '1Y', '3M', '1M', '7D', '1D'];

export const DEFAULT_PORTFOLIO_TIME_RANGE: ApiPriceHistoryPeriod = '3M';

const DURATION_MS: Record<Exclude<ApiPriceHistoryPeriod, 'ALL'>, number> = {
  '1Y': 365 * DAY,
  '3M': 90 * DAY,
  '1M': 30 * DAY,
  '7D': 7 * DAY,
  '1D': DAY,
};

export function getTimeRangeStartTs(range: ApiPriceHistoryPeriod, nowTs: number = Date.now()) {
  if (range === 'ALL') return undefined;

  return nowTs - DURATION_MS[range];
}
