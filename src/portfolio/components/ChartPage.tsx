import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import { SHORT_CURRENCY_SYMBOL_MAP } from '../config';
import LovelyChart from '../../lib/LovelyChart/LovelyChart';

import '../../lib/LovelyChart/LovelyChart.css';
import styles from './ChartPage.module.scss';

const AGGREGATED_COLOR = '#3497ED';
const MIN_VALUE = 0.01;

interface OwnProps {
  data: any;
  baseCurrency: string;
}

function ChartPage({ data, baseCurrency }: OwnProps) {
  const chartRef = useRef<HTMLDivElement>();

  useEffect(() => {
    const container = chartRef.current;
    if (!container) return;

    renderChart(container, data, baseCurrency);
  }, [data, baseCurrency]);

  return <div ref={chartRef} className={styles.chartContainer} />;
}

export default memo(ChartPage);

function renderChart(container: HTMLDivElement, data: any, baseCurrency: string) {
  container.innerHTML = '';

  const currencySymbol = SHORT_CURRENCY_SYMBOL_MAP[baseCurrency as keyof typeof SHORT_CURRENCY_SYMBOL_MAP]
    || baseCurrency;
  const title = `Portfolio Value, ${currencySymbol}`;
  const valuePrefix = SHORT_CURRENCY_SYMBOL_MAP[baseCurrency as keyof typeof SHORT_CURRENCY_SYMBOL_MAP];

  if (data.datasets) {
    if (data.datasets.length === 0) {
      throw new Error('No chart data available');
    }

    const labels = data.datasets[0].points.map((p: number[]) => p[0] * 1000);
    const datasets = data.datasets
      .filter((ds: any) => Math.max(...ds.points.map((p: number[]) => p[1])) >= MIN_VALUE)
      .map((ds: any) => ({
        name: ds.symbol,
        color: ds.color,
        values: ds.points.map((p: number[]) => (p[1] >= MIN_VALUE ? p[1] : 0)),
      }));

    LovelyChart.create(container, {
      title,
      type: 'area',
      labelType: 'day',
      labels,
      isStacked: true,
      valuePrefix,
      datasets,
    });
  } else {
    if (!data.points || data.points.length === 0) {
      throw new Error('No chart data available');
    }

    const labels = data.points.map((p: number[]) => p[0] * 1000);
    const values = data.points.map((p: number[]) => p[1]);

    LovelyChart.create(container, {
      title,
      type: 'area',
      labelType: 'day',
      labels,
      valuePrefix,
      datasets: [{ name: baseCurrency, color: AGGREGATED_COLOR, values }],
    });
  }
}
