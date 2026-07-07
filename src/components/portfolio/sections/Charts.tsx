import React, { memo, useMemo, useRef } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { PortfolioHistoryBundle } from '../../../global/types';

import buildClassName from '../../../util/buildClassName';
import {
  buildDailyPnlChartParams,
  buildNetWorthChartParams,
  buildShareChartParams,
  buildTotalPnlChartParams,
} from '../helpers/graphKitAdapter';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Chart from './Chart';

import styles from './Charts.module.scss';

interface OwnProps {
  noAnimation?: boolean;
  bundle?: PortfolioHistoryBundle;
  baseCurrencySymbol: string;
  dateRange?: string;
  error?: string;
  // Identity of the portfolio the bundle belongs to (account + base currency); a change drops the
  // remembered previous bundle so we never show one portfolio's charts while another is loading
  dataKey: string;
}

function Charts({
  bundle, baseCurrencySymbol, dateRange, error, dataKey, noAnimation,
}: OwnProps) {
  const { showToast } = getActions();
  const lang = useLang();

  const hasData = Boolean(bundle?.netWorth || bundle?.pnlCumulative || bundle?.pnl);

  // Remember the last bundle that had data so switching the time range keeps the previous charts
  // on screen (dimmed) instead of flashing skeletons; reset when the portfolio identity changes
  const lastBundleRef = useRef<PortfolioHistoryBundle>();
  const lastKeyRef = useRef<string>();

  if (lastKeyRef.current !== dataKey) {
    lastKeyRef.current = dataKey;
    lastBundleRef.current = undefined;
  }

  if (hasData) lastBundleRef.current = bundle;

  const displayBundle = hasData ? bundle : lastBundleRef.current;
  const isStale = !hasData && Boolean(displayBundle);
  const { netWorth, pnlCumulative, pnl } = displayBundle ?? {};

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

  // A range switch that genuinely failed replaces the kept-on-screen charts with the placeholder
  if (error) {
    return <div className={styles.placeholder}>{lang('Unavailable')}</div>;
  }

  // No bundle yet: render every slot so each card shows its skeleton
  const isInitialLoad = !displayBundle;

  return (
    <div className={buildClassName(styles.grid, isStale && styles.stale)}>
      {(isInitialLoad || shareData) && (
        <Chart
          key={`${dataKey}_share`}
          title={lang('Portfolio Share')}
          dateRange={dateRange}
          data={shareData}
          cardClassName="portfolio-chart-card-share"
          noAnimation={noAnimation}
        />
      )}

      {(isInitialLoad || netWorthData) && (
        <Chart
          key={`${dataKey}_networth`}
          title={lang('Total Value')}
          dateRange={dateRange}
          data={netWorthData}
          noAnimation={noAnimation}
        />
      )}

      {(isInitialLoad || totalPnlData) && (
        <Chart
          key={`${dataKey}_totalpnl`}
          title={lang('Total P&L')}
          dateRange={dateRange}
          data={totalPnlData}
          noAnimation={noAnimation}
        />
      )}

      {(isInitialLoad || dailyPnlData) && (
        <Chart
          key={`${dataKey}_dailypnl`}
          title={lang('Daily P&L')}
          dateRange={dateRange}
          data={dailyPnlData}
          noAnimation={noAnimation}
        />
      )}
    </div>
  );
}

export default memo(Charts);
