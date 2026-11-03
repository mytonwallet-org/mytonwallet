import type { ApiHistoryList, ApiPriceHistoryPeriod } from '../api/types';

import { DAY, HOUR, SECOND } from './dateFormat';

export const DEFAULT_PRICE_HISTORY_PERIOD: ApiPriceHistoryPeriod = '1D';

const PRICE_HISTORY_MAX_AGE: Record<ApiPriceHistoryPeriod, number> = {
  '1D': 3 * HOUR,
  '7D': DAY,
  '1M': 4 * DAY,
  '3M': 12 * DAY,
  '1Y': 45 * DAY,
  ALL: 45 * DAY,
};

export function isPriceHistoryFresh(history: ApiHistoryList, period: ApiPriceHistoryPeriod, now = Date.now()) {
  const [lastTimestamp] = history[history.length - 1];

  return now - lastTimestamp * SECOND <= PRICE_HISTORY_MAX_AGE[period];
}
