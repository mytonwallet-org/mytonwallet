import type { LovelyChartDatasetParams, LovelyChartParams } from 'lovely-chart';

import type {
  ApiPortfolioHistoryDataset, ApiPortfolioHistoryResponse,
} from '../../../api/types';
import type { LangFn } from '../../../hooks/useLang';

// Dust threshold for stacked area; matches iOS `normalizedForPortfolioDisplay`
const MIN_VISIBLE_VALUE = 0.01;

// LovelyChart renders '5min'/'hour' as HH:mm and 'day' as a date
const LABEL_TYPE_BY_DENSITY: Record<string, LovelyChartParams['labelType']> = {
  '5m': '5min',
  '1h': 'hour',
  '4h': 'dayHour',
  '1d': 'day',
};

export interface ChartData {
  params: LovelyChartParams;
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
): ChartData | undefined {
  // 100%-stacked area of allocation over time; clicking a date zooms into the donut for that date.
  // With `isPercentage` set and no custom `onZoom`, LovelyChart's `shouldZoomToShares` builds the
  // per-date circle itself, reusing the overview datasets and their colors
  const base = buildSeriesChartParams(lang, 'area', lang('Portfolio Share'), response, baseCurrencySymbol);
  if (!base) return undefined;

  // Zero-sum columns make LovelyChart's percentage path divide 0/0 = NaN and break the render
  const { datasets, labels } = dropEmptyColumns(base.params.datasets, base.params.labels);

  return {
    params: {
      ...base.params,
      datasets,
      labels,
      isPercentage: true,
      zoomType: 'donut',
      initialZoom: 'last',
      zoomOutLabel: lang('Zoom Out'),
    },
    isAssetLimitExceeded: base.isAssetLimitExceeded,
  };
}

function buildSeriesChartParams(
  lang: LangFn,
  type: 'area' | 'line' | 'bar',
  title: string,
  response: ApiPortfolioHistoryResponse,
  baseCurrencySymbol: string,
  onLimitedRangeClick?: NoneToVoidFunction,
): ChartData | undefined {
  // The minimap opens full-width (minimapRange 'full'), so drop the backend's future `null` tail to avoid an empty right edge
  const trimmed = trimFutureTail(response.datasets);

  // Area can't show gaps: dust and `null` collapse to `0`, fully-dust assets dropped. Line/bar keep `null` as a gap.
  const isArea = type === 'area';
  const kept = trimmed.filter((dataset) => (isArea ? hasVisibleValue(dataset) : hasValue(dataset)));
  if (kept.length === 0) return undefined;

  // Backend guarantees every dataset shares one timestamp grid, so read the labels once
  const grid = kept[0].points;
  if (grid.length === 0) return undefined;

  const valuesByDataset = kept.map(
    (dataset) => dataset.points.map(([, value]) => (isArea ? clampToVisible(value) : value)),
  );

  // Drop the empty leading points the backend pads onto the grid. A `LovelyChart` bug divides each
  // `isPercentage` point by the per-point sum, so an all-zero leading point gives `0 / 0 = NaN` and
  // breaks the stacked-area path.
  const startIndex = findFirstNonEmptyIndex(valuesByDataset, isArea);

  const datasets: LovelyChartDatasetParams[] = kept.map((dataset, i) => ({
    name: getDisplayName(lang, dataset),
    color: dataset.color,
    values: valuesByDataset[i].slice(startIndex),
  }));

  const limitDate = response.historyScanCursor !== undefined ? response.historyScanCursor * 1000 : undefined;

  const params: LovelyChartParams = {
    title,
    type,
    labelType: LABEL_TYPE_BY_DENSITY[response.density] ?? 'day',
    dateLocale: buildDateLocale(lang),
    labels: grid.slice(startIndex).map(([timestamp]) => timestamp * 1000),
    datasets,
    valuePrefix: baseCurrencySymbol,
    isCurrencyPrefix: true,
    isStacked: type !== 'line' && datasets.length > 1,
    // Show the minimap opened on the full range (the library default would be the last 20%)
    withMinimap: true,
    minimapRange: 'full',
    limitDate,
    onLimitedRangeClick: limitDate !== undefined ? onLimitedRangeClick : undefined,
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

// First index with content (clamped non-zero for area, non-null for line/bar); everything before it
// is an empty leading block the backend padded onto the grid
function findFirstNonEmptyIndex(valuesByDataset: Array<Array<number | null>>, isArea: boolean) {
  const length = valuesByDataset[0]?.length ?? 0;
  for (let i = 0; i < length; i++) {
    // eslint-disable-next-line no-null/no-null
    const hasContent = valuesByDataset.some((values) => (isArea ? values[i] !== 0 : values[i] !== null));
    if (hasContent) return i;
  }
  return 0;
}

// Keep only the columns where some dataset is non-zero, dropping the matching labels in sync
function dropEmptyColumns(datasets: LovelyChartDatasetParams[], labels: LovelyChartParams['labels']) {
  const kept: number[] = [];
  for (let j = 0; j < labels.length; j++) {
    if (datasets.some((dataset) => (dataset.values[j] ?? 0) !== 0)) kept.push(j);
  }
  if (kept.length === labels.length) return { datasets, labels };

  return {
    datasets: datasets.map((dataset) => ({ ...dataset, values: kept.map((j) => dataset.values[j]) })),
    labels: kept.map((j) => labels[j]),
  };
}

function getDisplayName(lang: LangFn, dataset: ApiPortfolioHistoryDataset) {
  const symbol = dataset.symbol.trim();
  if (symbol) return symbol;

  const contract = dataset.contractAddress.trim();
  if (contract) return contract;

  return lang('Asset %1$@').replace('%1$@', String(dataset.assetId));
}

function buildDateLocale(lang: LangFn): LovelyChartParams['dateLocale'] {
  return {
    months: lang('$chart_months_short').split(',').map((s) => s.trim()),
    weekDays: lang('$chart_week_days').split(',').map((s) => s.trim()),
    weekDaysShort: lang('$chart_week_days_short').split(',').map((s) => s.trim()),
  };
}
