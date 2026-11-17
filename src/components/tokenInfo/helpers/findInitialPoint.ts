import type { ApiHistoryList } from '../../../api/types';

// A zero price gives no baseline for the change, so the period starts at the first traded point
export function findInitialPoint(history: ApiHistoryList) {
  return history.find(([, value]) => Boolean(value));
}
