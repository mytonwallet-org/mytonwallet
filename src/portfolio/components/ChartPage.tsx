import LovelyChart from 'lovely-chart';
import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import { NEW_CHARTS_ENABLED, SHORT_CURRENCY_SYMBOL_MAP } from '../config';

import 'lovely-chart/LovelyChart.css';
import styles from './ChartPage.module.scss';

// Mirrors DEFAULT_COLORS from the LovelyChart lib so we can pre-assign palette
// slots by token symbol and keep coloring consistent across all three charts.
const DEFAULT_COLORS = [
  '#3497ED', '#2373DB', '#9ED448', '#5FB641',
  '#F5BD25', '#F79E39', '#E65850', '#5D5CDC',
];
const AGGREGATED_COLOR = DEFAULT_COLORS[0];
const MIN_VALUE = 0.01;

type ColorAssigner = (symbol: string) => string;

function createColorAssigner(): ColorAssigner {
  const colorBySymbol = new Map<string, string>();
  let nextColorIndex = 0;
  return (symbol) => {
    let color = colorBySymbol.get(symbol);
    if (!color) {
      color = DEFAULT_COLORS[nextColorIndex++ % DEFAULT_COLORS.length];
      colorBySymbol.set(symbol, color);
    }
    return color;
  };
}

interface OwnProps {
  netWorthData: any;
  pnlCumulativeData: any;
  pnlData: any;
  baseCurrency: string;
}

function ChartPage({ netWorthData, pnlCumulativeData, pnlData, baseCurrency }: OwnProps) {
  const netWorthRef = useRef<HTMLDivElement>();
  const pnlCumulativeRef = useRef<HTMLDivElement>();
  const pnlRef = useRef<HTMLDivElement>();

  useEffect(() => {
    const assignColor = createColorAssigner();
    if (netWorthRef.current) {
      renderChart(netWorthRef.current, netWorthData, baseCurrency, 'Portfolio Value', 'area', assignColor);
    }
    if (NEW_CHARTS_ENABLED && pnlCumulativeRef.current) {
      renderChart(pnlCumulativeRef.current, pnlCumulativeData, baseCurrency, 'Total P&L', 'line', assignColor);
    }
    if (NEW_CHARTS_ENABLED && pnlRef.current) {
      renderChart(pnlRef.current, pnlData, baseCurrency, 'Daily P&L', 'bar', assignColor);
    }
  }, [netWorthData, pnlCumulativeData, pnlData, baseCurrency]);

  return (
    <>
      <div ref={netWorthRef} className={styles.chartContainer} data-stricterdom-ignore />
      {NEW_CHARTS_ENABLED && (
        <>
          <div ref={pnlCumulativeRef} className={styles.chartContainer} data-stricterdom-ignore />
          <div ref={pnlRef} className={styles.chartContainer} data-stricterdom-ignore />
        </>
      )}
    </>
  );
}

export default memo(ChartPage);

function renderChart(
  container: HTMLDivElement,
  data: any,
  baseCurrency: string,
  titlePrefix: string,
  chartType: 'area' | 'line' | 'bar',
  assignColor: ColorAssigner,
) {
  container.innerHTML = '';

  const currencySymbol = SHORT_CURRENCY_SYMBOL_MAP[baseCurrency as keyof typeof SHORT_CURRENCY_SYMBOL_MAP]
    || baseCurrency;
  const title = `${titlePrefix}, ${currencySymbol}`;
  const valuePrefix = SHORT_CURRENCY_SYMBOL_MAP[baseCurrency as keyof typeof SHORT_CURRENCY_SYMBOL_MAP];
  const isStacked = chartType === 'area' || chartType === 'bar';
  const shouldClampDust = chartType === 'area';

  if (data.datasets) {
    if (data.datasets.length === 0) {
      throw new Error('No chart data available');
    }

    const labels = data.datasets[0].points.map((p: number[]) => p[0] * 1000);
    const datasets = (shouldClampDust
      ? data.datasets.filter((ds: any) => Math.max(...ds.points.map((p: number[]) => p[1])) >= MIN_VALUE)
      : data.datasets
    ).map((ds: any) => ({
      name: ds.symbol,
      color: assignColor(ds.symbol),
      values: ds.points.map((p: number[]) => (!shouldClampDust || p[1] >= MIN_VALUE ? p[1] : 0)),
    }));

    new LovelyChart(container, {
      title,
      type: chartType,
      labelType: 'day',
      labels,
      isStacked,
      valuePrefix,
      datasets,
      limitDate: data.historyScanCursor ? data.historyScanCursor * 1000 : undefined,
      onLimitedRangeClick: data.historyScanCursor ? handleLimitedRangeClick : undefined,
    });
  } else {
    if (!data.points || data.points.length === 0) {
      throw new Error('No chart data available');
    }

    const labels = data.points.map((p: number[]) => p[0] * 1000);
    const values = data.points.map((p: number[]) => p[1]);

    new LovelyChart(container, {
      title,
      type: chartType,
      labelType: 'day',
      labels,
      valuePrefix,
      datasets: [{ name: baseCurrency, color: AGGREGATED_COLOR, values }],
      limitDate: data.historyScanCursor ? data.historyScanCursor * 1000 : undefined,
      onLimitedRangeClick: data.historyScanCursor ? handleLimitedRangeClick : undefined,
    });
  }
}

function handleLimitedRangeClick() {
  alert('Deep history analysis will be available in upcoming updates.');
}
