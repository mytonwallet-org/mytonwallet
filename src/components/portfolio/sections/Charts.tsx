import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { PortfolioHistoryBundle } from '../../../global/types';

import {
  buildDailyPnlChartParams,
  buildNetWorthChartParams,
  buildShareChartParams,
  buildTotalPnlChartParams,
} from '../helpers/graphKitAdapter';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Spinner from '../../ui/Spinner';
import Chart from './Chart';

import styles from './Charts.module.scss';

interface OwnProps {
  isRefreshing?: boolean;
  bundle?: PortfolioHistoryBundle;
  baseCurrencySymbol: string;
  dateRange?: string;
  error?: string;
}

function Charts({
  isRefreshing, bundle, baseCurrencySymbol, dateRange, error,
}: OwnProps) {
  const { showToast } = getActions();
  const lang = useLang();
  const { netWorth, pnlCumulative, pnl } = bundle ?? {};

  const handleLimitedRangeClick = useLastCallback(() => {
    showToast({ message: lang('Deep history analysis will be available in upcoming updates.') });
  });

  const netWorthData = useMemo(() => (
    netWorth ? buildNetWorthChartParams(lang, netWorth, baseCurrencySymbol, handleLimitedRangeClick) : undefined
  ), [netWorth, baseCurrencySymbol, lang, handleLimitedRangeClick]);

  const totalPnlData = useMemo(() => (
    pnlCumulative ? buildTotalPnlChartParams(lang, pnlCumulative, baseCurrencySymbol) : undefined
  ), [pnlCumulative, baseCurrencySymbol, lang]);

  const dailyPnlData = useMemo(() => (
    pnl ? buildDailyPnlChartParams(lang, pnl, baseCurrencySymbol) : undefined
  ), [pnl, baseCurrencySymbol, lang]);

  const shareData = useMemo(() => (
    netWorth ? buildShareChartParams(lang, netWorth, baseCurrencySymbol) : undefined
  ), [netWorth, baseCurrencySymbol, lang]);

  if (netWorth || pnlCumulative || pnl) {
    return (
      <div className={styles.grid}>
        {netWorth && (
          <Chart title={lang('Total Value')} dateRange={dateRange} data={netWorthData} isRefreshing={isRefreshing} />
        )}

        {pnlCumulative && (
          <Chart title={lang('Total P&L')} dateRange={dateRange} data={totalPnlData} isRefreshing={isRefreshing} />
        )}

        {pnl && (
          <Chart title={lang('Daily P&L')} dateRange={dateRange} data={dailyPnlData} isRefreshing={isRefreshing} />
        )}

        {netWorth && (
          <Chart
            title={lang('Portfolio Share')}
            dateRange={dateRange}
            data={shareData}
            cardClassName="portfolio-chart-card-pie"
          />
        )}
      </div>
    );
  }

  if (error) return <div className={styles.placeholder}>{lang('Unavailable')}</div>;

  // No data yet: either loading or the brief pre-load gap before the loading flag is set
  return (
    <div className={styles.placeholder}>
      <Spinner />
    </div>
  );
}

export default memo(Charts);
