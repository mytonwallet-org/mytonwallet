import type {
  ApiPortfolioHistoryDataset,
  ApiPortfolioHistoryList,
  ApiPortfolioHistoryResponse,
  ApiPriceHistoryPeriod,
} from '../../api/types';

import { getTimeRangeStartTs } from './timeRange';

export interface NetChange {
  amount: number;
  percent?: number;
  startTs: number;
  endTs: number;
}

interface RangeEndpoints {
  startTs: number;
  endTs: number;
  startValue: number;
  endValue: number;
}

export function computeNetChange(
  netWorth: ApiPortfolioHistoryResponse,
  range: ApiPriceHistoryPeriod,
) {
  const startThresholdMs = getTimeRangeStartTs(range);

  if (netWorth.points?.length) {
    return computeFromPoints(netWorth.points, startThresholdMs);
  }

  if (netWorth.datasets?.length) {
    return computeFromDatasets(netWorth.datasets, startThresholdMs);
  }

  return undefined;
}

function computeFromPoints(
  points: ApiPortfolioHistoryList,
  startThresholdMs?: number,
) {
  const endpoints = findRangeEndpoints(points, startThresholdMs);
  if (!endpoints) return undefined;

  return buildResult(endpoints.startValue, endpoints.endValue, endpoints.startTs, endpoints.endTs);
}

// Merges dataset values per timestamp into a single series before picking endpoints, so the
// start denominator reflects the full portfolio at that timestamp rather than a single asset
function computeFromDatasets(
  datasets: ApiPortfolioHistoryDataset[],
  startThresholdMs?: number,
) {
  const valuesByTs = new Map<number, number>();

  for (const { points } of datasets) {
    if (!points?.length) continue;

    for (const [tsSec, value] of points) {
      if (typeof tsSec !== 'number' || typeof value !== 'number') continue;

      const tsMs = tsSec * 1000;
      valuesByTs.set(tsMs, (valuesByTs.get(tsMs) ?? 0) + value);
    }
  }

  if (!valuesByTs.size) return undefined;

  const merged: ApiPortfolioHistoryList = Array.from(valuesByTs.entries())
    .sort(([a], [b]) => a - b)
    .map(([tsMs, value]) => [tsMs / 1000, value]);

  return computeFromPoints(merged, startThresholdMs);
}

// Returns the first in-range point and the latest point with a non-null value.
// Assumes `points` are ordered by `timestamp` ascending.
function findRangeEndpoints(
  points: ApiPortfolioHistoryList,
  startThresholdMs?: number,
): RangeEndpoints | undefined {
  let start: { ts: number; value: number; index: number } | undefined;

  for (let i = 0; i < points.length; i++) {
    const [tsSec, value] = points[i];
    if (typeof value !== 'number') continue;

    if (startThresholdMs !== undefined && tsSec * 1000 < startThresholdMs) continue;

    start = { ts: tsSec * 1000, value, index: i };
    break;
  }

  if (!start) return undefined;

  let end: { ts: number; value: number } | undefined;

  for (let i = points.length - 1; i >= start.index; i--) {
    const [tsSec, value] = points[i];
    if (typeof value !== 'number') continue;

    end = { ts: tsSec * 1000, value };
    break;
  }

  if (!end) return undefined;

  return {
    startTs: start.ts,
    endTs: end.ts,
    startValue: start.value,
    endValue: end.value,
  };
}

function buildResult(startValue: number, endValue: number, startTs: number, endTs: number): NetChange {
  const amount = endValue - startValue;
  const percent = startValue !== 0 ? (amount / startValue) * 100 : undefined;

  return { amount, percent, startTs, endTs };
}
