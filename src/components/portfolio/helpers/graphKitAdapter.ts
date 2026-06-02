import type {
  ApiPortfolioHistoryDataset, ApiPortfolioHistoryResponse,
} from '../../../api/types';
import type { LangFn } from '../../../hooks/useLang';

// Dust threshold for stacked area; matches iOS `normalizedForPortfolioDisplay`
const MIN_VISIBLE_VALUE = 0.01;

// LovelyChart renders '5min'/'hour' as HH:mm and 'day' as a date
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
  // null marks a gap: LovelyChart breaks the line there (line/bar); area collapses it to 0 upstream
  values: (number | null)[];
};

export type GraphKitParams = {
  title: string;
  type: 'area' | 'pie' | 'line' | 'bar';
  labelType: 'day' | 'hour' | '5min' | 'dayHour' | 'text';
  labels: number[];
  datasets: GraphKitDataset[];
  valuePrefix?: string;
  // When `true`, a leading minus sign is moved before the currency prefix: -$0.1 instead of $-0.1
  prefixIsCurrency?: boolean;
  isStacked?: boolean;
  isDonut?: boolean;
  withGradient?: boolean;
  limitDate?: number;
  hideCaption?: boolean;
  onLimitedRangeClick?: NoneToVoidFunction;
};

export interface ChartData {
  params: GraphKitParams;
  isAssetLimitExceeded?: boolean;
}

export function buildNetWorthChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
  onLimitedRangeClick?: NoneToVoidFunction,
) {
  return buildSeriesChartParams(lang, 'area', lang('Total Value'), response, baseCurrencySymbol, onLimitedRangeClick);
}

export function buildTotalPnlChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildSeriesChartParams(lang, 'line', lang('Total P&L'), response, baseCurrencySymbol);
}

export function buildDailyPnlChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildSeriesChartParams(lang, 'bar', lang('Daily P&L'), response, baseCurrencySymbol);
}

export function buildShareChartParams(
  lang: LangFn,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
) {
  return buildPieChartParams(lang, lang('Portfolio Share'), response, baseCurrencySymbol);
}

function buildSeriesChartParams(
  lang: LangFn,
  type: 'area' | 'line' | 'bar',
  title: string,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
  onLimitedRangeClick?: NoneToVoidFunction,
): ChartData | undefined {
  // LovelyChart opens on the last 20% of the x-axis, so the backend's future null tail would render short ranges empty
  const trimmed = trimFutureTail(response.datasets);

  // Area can't show gaps: dust and null collapse to 0, fully-dust assets dropped. Line/bar keep null as a gap
  const isArea = type === 'area';
  const kept = trimmed.filter((dataset) => (isArea ? hasVisibleValue(dataset) : hasValue(dataset)));
  if (kept.length === 0) return undefined;

  // Backend guarantees every dataset shares one timestamp grid, so read the labels once
  const grid = kept[0].points;
  if (grid.length === 0) return undefined;

  const datasets: GraphKitDataset[] = kept.map((dataset) => ({
    name: getDisplayName(lang, dataset),
    color: dataset.color,
    values: dataset.points.map(([, value]) => (isArea ? clampToVisible(value) : value)),
  }));

  const limitDate = response.historyScanCursor !== undefined ? response.historyScanCursor * 1000 : undefined;

  const params: GraphKitParams = {
    title,
    type,
    labelType: LABEL_TYPE_BY_DENSITY[response.density] ?? 'day',
    labels: grid.map(([timestamp]) => timestamp * 1000),
    datasets,
    valuePrefix: baseCurrencySymbol,
    prefixIsCurrency: true,
    isStacked: type !== 'line' && datasets.length > 1,
    limitDate,
    onLimitedRangeClick: limitDate !== undefined ? onLimitedRangeClick : undefined,
  };

  return { params, isAssetLimitExceeded: response.isAssetLimitExceeded };
}

function buildPieChartParams(
  lang: LangFn,
  title: string,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
): ChartData | undefined {
  // LovelyChart sorts tooltip stats by value desc but draws sectors in array order; sort here so
  // sectors and tooltip labels stay aligned
  const slices = (response.datasets ?? [])
    .map((dataset) => ({ dataset, value: getLatestValue(dataset) }))
    .filter((slice) => slice.value > 0)
    .sort((a, b) => b.value - a.value);
  if (slices.length === 0) return undefined;

  const datasets: GraphKitDataset[] = slices.map(({ dataset, value }) => ({
    name: getDisplayName(lang, dataset),
    color: dataset.color,
    values: [value],
  }));

  const params: GraphKitParams = {
    title,
    type: 'pie',
    labelType: 'text',
    labels: [Date.now()],
    datasets,
    valuePrefix: baseCurrencySymbol,
    prefixIsCurrency: true,
    isStacked: true,
    isDonut: true,
    withGradient: true,
    hideCaption: true,
  };

  return { params, isAssetLimitExceeded: response.isAssetLimitExceeded };
}

function trimFutureTail(datasets: ApiPortfolioHistoryDataset[] = []): ApiPortfolioHistoryDataset[] {
  const nowSec = Math.floor(Date.now() / 1000);
  return datasets.map((dataset) => ({
    ...dataset,
    points: dataset.points.filter(([timestamp]) => timestamp <= nowSec),
  }));
}

function hasVisibleValue(dataset: ApiPortfolioHistoryDataset) {
  return dataset.points.some(([, value]) => typeof value === 'number' && value >= MIN_VISIBLE_VALUE);
}

function hasValue(dataset: ApiPortfolioHistoryDataset) {
  return dataset.points.some(([, value]) => typeof value === 'number');
}

function clampToVisible(value: number | null) {
  return typeof value === 'number' && value >= MIN_VISIBLE_VALUE ? value : 0;
}

function getLatestValue(dataset: ApiPortfolioHistoryDataset) {
  let latestValue = 0;
  let latestTimestamp = -Infinity;
  for (const [timestamp, value] of dataset.points) {
    if (typeof value === 'number' && timestamp > latestTimestamp) {
      latestTimestamp = timestamp;
      latestValue = value;
    }
  }

  return latestValue;
}

function getDisplayName(lang: LangFn, dataset: ApiPortfolioHistoryDataset) {
  const symbol = dataset.symbol.trim();
  if (symbol) return symbol;

  const contract = dataset.contractAddress.trim();
  if (contract) return contract;

  return lang('Asset %1$@').replace('%1$@', String(dataset.assetId));
}
