import type { ApiHistoryList, ApiPriceHistoryPeriod } from '../../../api/types';
import type { LangCode } from '../../../global/types';

import { formatShortDay, formatShortMonth, formatTime, SECOND } from '../../../util/dateFormat';

const AXIS_LABEL_COUNT = 4;

// The plot spaces points by time, so the labels split the time span evenly, in the formats of the native apps
export function buildAxisLabels(langCode: LangCode, period: ApiPriceHistoryPeriod, history: ApiHistoryList) {
  const first = history[0][0];
  const span = history[history.length - 1][0] - first;

  return Array.from({ length: AXIS_LABEL_COUNT }, (_, index) => {
    const timestamp = (first + (span * index) / (AXIS_LABEL_COUNT - 1)) * SECOND;

    if (period === '1D') return formatTime(timestamp);
    if (period === 'ALL') return formatShortMonth(langCode, timestamp);
    return formatShortDay(langCode, timestamp, false, true);
  });
}
