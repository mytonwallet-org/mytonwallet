import type {
  ApiPortfolioHistoryDataset, ApiPortfolioHistoryList, ApiPortfolioHistoryResponse,
} from '../../../api/types';
import type { LangFn } from '../../../hooks/useLang';

// Values smaller than this (in absolute terms) are clamped to 0 to avoid
// chart noise from rounding-dust amounts. Matches iOS `normalizedForPortfolioDisplay`.
const MIN_VISIBLE_VALUE = 0.01;

// Backend density (point spacing) drives the x-axis label format.
// LovelyChart renders `'5min'/'hour'` as HH:mm and `'day'` as date
const LABEL_TYPE_BY_DENSITY: Record<string, GraphKitParams['labelType']> = {
  '5m': '5min',
  '1h': 'hour',
  '4h': 'dayHour',
  '1d': 'day',
};

export type GraphKitDataset = {
  name: string;
  // Omitted when the backend provides no color; LovelyChart then assigns one from its default palette
  color?: string;
  values: number[];
};

export type GraphKitParams = {
  title: string;
  type: 'area' | 'pie' | 'line' | 'bar';
  labelType: 'day' | 'hour' | '5min' | 'dayHour' | 'text';
  labels: number[];
  datasets: GraphKitDataset[];
  valuePrefix?: string;
  // When true, a leading minus sign is moved before the currency prefix: `-$0.1` instead of `$-0.1`
  prefixIsCurrency?: boolean;
  isStacked?: boolean;
  isPercentage?: boolean;
  limitDate?: number;
  hideCaption?: boolean;
  onLimitedRangeClick?: NoneToVoidFunction;
};

export interface ChartData {
  params: GraphKitParams;
  isAssetLimitExceeded?: boolean;
}

type DatasetSelection = 'portfolioValue' | 'signedValues';
type ChartStyle = 'area' | 'pie' | 'line' | 'bar';

interface ChartOptions {
  lang: LangFn;
  title: string;
  type: ChartStyle;
  response: ApiPortfolioHistoryResponse;
  selection: DatasetSelection;
  isPercentage: boolean;
  baseCurrencySymbol: string;
  onLimitedRangeClick?: NoneToVoidFunction;
  noCaption?: boolean;
}

interface DatasetSummary {
  dataset: ApiPortfolioHistoryDataset;
  displayName: string;
  hasValues: boolean;
  hasPositiveValues: boolean;
  latestValue: number;
  valueByTimestamp: Map<number, number>;
}

export function buildNetWorthChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
  onLimitedRangeClick?: NoneToVoidFunction,
) {
  return buildChart({
    title: lang('Total Value'),
    type: 'area',
    response: makeChartResponse(response),
    selection: 'portfolioValue',
    isPercentage: false,
    lang,
    baseCurrencySymbol,
    onLimitedRangeClick,
  });
}

export function buildShareChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildChart({
    title: lang('Portfolio Share'),
    type: 'pie',
    response: makeChartResponse(response),
    selection: 'portfolioValue',
    isPercentage: true,
    lang,
    baseCurrencySymbol,
    noCaption: true,
  });
}

export function buildTotalPnlChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildChart({
    title: lang('Total P&L'),
    type: 'line',
    response,
    selection: 'signedValues',
    isPercentage: false,
    lang,
    baseCurrencySymbol,
  });
}

export function buildDailyPnlChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildChart({
    title: lang('Daily P&L'),
    type: 'bar',
    response,
    selection: 'signedValues',
    isPercentage: false,
    lang,
    baseCurrencySymbol,
  });
}

function buildChart(options: ChartOptions) {
  // Backend pads response with future timestamps holding `null`. LovelyChart opens the last 20% of
  // the x-axis on first render, so leaving the future tail in place makes 1D charts look empty
  const trimmedResponse = trimFutureTail(options.response);
  const activeSummaries = makeActiveSummaries(options.lang, trimmedResponse, options.selection);
  if (activeSummaries.length === 0) return undefined;

  if (options.type === 'pie') {
    return buildPieChartParams(activeSummaries, options);
  }

  const allTimestamps = collectAllTimestamps(activeSummaries);
  if (allTimestamps.length === 0) return undefined;

  const datasets: GraphKitDataset[] = activeSummaries.map((summary) => ({
    name: summary.displayName,
    color: summary.dataset.color,
    values: allTimestamps.map((t) => summary.valueByTimestamp.get(t) ?? 0),
  }));

  const limitDate = options.response.historyScanCursor !== undefined
    ? options.response.historyScanCursor * 1000
    : undefined;

  const isStacked = (options.type === 'area' || options.type === 'bar')
    && datasets.length > 1;

  const params: GraphKitParams = {
    title: options.title,
    type: options.type,
    labelType: LABEL_TYPE_BY_DENSITY[options.response.density] ?? 'day',
    labels: allTimestamps.map((t) => t * 1000),
    datasets,
    valuePrefix: options.baseCurrencySymbol,
    prefixIsCurrency: true,
    isStacked,
    isPercentage: options.isPercentage,
    limitDate,
    hideCaption: options.noCaption,
    onLimitedRangeClick: limitDate !== undefined ? options.onLimitedRangeClick : undefined,
  };

  return { params, isAssetLimitExceeded: options.response.isAssetLimitExceeded };
}

function buildPieChartParams(
  summaries: DatasetSummary[],
  options: ChartOptions,
) {
  // LovelyChart sorts tooltip statistics by value desc internally but draws pie
  // sectors in dataset array order. If these orders diverge, tooltip labels are
  // attributed to wrong sectors. Sort here to keep both orders aligned.
  const pieSummaries = summaries
    .filter((summary) => summary.latestValue > 0)
    .sort((a, b) => b.latestValue - a.latestValue);
  if (pieSummaries.length === 0) return undefined;

  const datasets: GraphKitDataset[] = pieSummaries.map((summary) => ({
    name: summary.displayName,
    color: summary.dataset.color,
    values: [summary.latestValue],
  }));

  const params: GraphKitParams = {
    title: options.title,
    type: 'pie',
    labelType: 'text',
    labels: [Date.now()],
    datasets,
    valuePrefix: options.baseCurrencySymbol,
    prefixIsCurrency: true,
    isStacked: true,
    hideCaption: options.noCaption,
  };

  return { params, isAssetLimitExceeded: options.response.isAssetLimitExceeded };
}

function makeActiveSummaries(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  selection: DatasetSelection,
) {
  const summaries = (response.datasets ?? []).map((dataset) => summarizeDataset(lang, dataset));

  if (selection === 'portfolioValue') {
    return summaries
      .filter((summary) => summary.hasPositiveValues)
      .sort((a, b) => b.latestValue - a.latestValue);
  }

  return summaries.filter((summary) => summary.hasValues);
}

function summarizeDataset(lang: LangFn, dataset: ApiPortfolioHistoryDataset): DatasetSummary {
  const valueByTimestamp = new Map<number, number>();
  let hasValues = false;
  let hasPositiveValues = false;
  let latestValue = 0;
  let latestTimestamp = -Infinity;

  for (const [timestamp, value] of dataset.points) {
    if (typeof value !== 'number') continue;

    valueByTimestamp.set(timestamp, value);
    hasValues = true;
    if (value > 0) hasPositiveValues = true;
    if (timestamp > latestTimestamp) {
      latestTimestamp = timestamp;
      latestValue = value;
    }
  }

  return {
    dataset,
    displayName: getDisplayName(lang, dataset),
    hasValues,
    hasPositiveValues,
    latestValue,
    valueByTimestamp,
  };
}

function collectAllTimestamps(summaries: DatasetSummary[]): number[] {
  const all = new Set<number>();
  for (const summary of summaries) {
    for (const timestamp of summary.valueByTimestamp.keys()) {
      all.add(timestamp);
    }
  }
  return Array.from(all).sort((a, b) => a - b);
}

function makeChartResponse(response: ApiPortfolioHistoryResponse): ApiPortfolioHistoryResponse {
  const normalized = normalizeForPortfolioDisplay(response);
  const chartDatasets = (normalized.datasets ?? []).filter((dataset) => {
    return dataset.points.some(([, value]) => typeof value === 'number' && value > 0);
  });

  return {
    ...normalized,
    points: mergePoints(chartDatasets),
    datasets: chartDatasets,
  };
}

function trimFutureTail(response: ApiPortfolioHistoryResponse): ApiPortfolioHistoryResponse {
  const nowSec = Math.floor(Date.now() / 1000);
  const datasets = response.datasets?.map((dataset): ApiPortfolioHistoryDataset => ({
    ...dataset,
    points: dataset.points.filter(([timestamp]) => timestamp <= nowSec),
  }));
  const points = response.points?.filter(([timestamp]) => timestamp <= nowSec);

  return { ...response, datasets, points };
}

function normalizeForPortfolioDisplay(response: ApiPortfolioHistoryResponse): ApiPortfolioHistoryResponse {
  const datasets = response.datasets?.map((dataset): ApiPortfolioHistoryDataset => ({
    ...dataset,
    points: dataset.points.map((point): [number, number | null] => {
      const value = point[1];
      if (typeof value === 'number' && value > 0 && value < MIN_VISIBLE_VALUE) {
        return [point[0], 0];
      }
      return point;
    }),
  }));
  return { ...response, datasets };
}

function mergePoints(datasets: ApiPortfolioHistoryDataset[]) {
  if (datasets.length === 0) return undefined;

  const valuesByTimestamp = new Map<number, number>();
  for (const dataset of datasets) {
    for (const [timestamp, value] of dataset.points) {
      if (typeof value !== 'number') continue;

      valuesByTimestamp.set(timestamp, (valuesByTimestamp.get(timestamp) ?? 0) + value);
    }
  }

  return Array.from(valuesByTimestamp.entries())
    .sort(([a], [b]) => a - b) as ApiPortfolioHistoryList;
}

function getDisplayName(lang: LangFn, dataset: ApiPortfolioHistoryDataset) {
  const symbol = dataset.symbol.trim();
  if (symbol) return symbol;

  const contract = dataset.contractAddress.trim();
  if (contract) return contract;

  return lang('Asset %1$@').replace('%1$@', String(dataset.assetId));
}
