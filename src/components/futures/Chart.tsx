import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsMarketAsset, ApiPriceHistoryPeriod, ApiToken } from '../../api/types';
import type { PerpsChartState } from '../../global/types';

import { isPerpsChartStale, selectPerpsMarketAsset } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { MINUTE } from '../../util/dateFormat';
import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../util/priceHistory';
import { findInitialPoint } from '../tokenInfo/helpers/findInitialPoint';
import { resolveChartChange } from '../tokenInfo/helpers/resolveChartChange';
import { PERPS_CURRENCY_SYMBOL } from './helpers/formatPerps';

import useLastCallback from '../../hooks/useLastCallback';
import usePerpsPolling from './hooks/usePerpsPolling';
import usePerpsStaleness from './hooks/usePerpsStaleness';

import ChartCard from '../tokenInfo/sections/ChartCard';
import LoadError from './LoadError';

import futuresStyles from './Futures.module.scss';

interface OwnProps {
  assetId: string;
  /** Shown next to the starting price */
  token?: ApiToken;
  isActive?: boolean;
  className?: string;
}

interface StateProps {
  chartsByPeriod?: Partial<Record<ApiPriceHistoryPeriod, PerpsChartState>>;
  /**
   * The market price and day change. The chart shows the price until its points load, and the day change on the `1D`
   * period without a selection.
   */
  context?: ApiPerpsMarketAsset['context'];
}

// The action skips a chart fetched less than five minutes ago, so a shorter interval only checks its age
const REFRESH_INTERVAL = MINUTE;

const NO_SELECTION = -1;

function Chart({
  assetId, token, isActive, className, chartsByPeriod, context,
}: OwnProps & StateProps) {
  const { loadPerpsCandles } = getActions();
  const [period, setPeriod] = useState<ApiPriceHistoryPeriod>(DEFAULT_PRICE_HISTORY_PERIOD);
  const [selectedIndex, setSelectedIndex] = useState(NO_SELECTION);

  const chart = chartsByPeriod?.[period];
  // A failed request keeps the shown series, and without one the panel offers a retry before the next refresh
  const history = chart?.points;
  const isLoadFailed = Boolean(chart?.hasError) && !history;
  // A chart from the last launch stays dimmed until its refresh
  const isStale = usePerpsStaleness(isPerpsChartStale(chart), Boolean(chart?.points?.length));

  const loadHistory = useLastCallback(() => {
    loadPerpsCandles({ assetId, period });
  });

  usePerpsPolling(loadHistory, isActive, REFRESH_INTERVAL, [period]);

  const lastPoint = history?.length ? history[history.length - 1] : undefined;
  const selectedPoint = selectedIndex >= 0 ? history?.[selectedIndex] : undefined;
  const shownPoint = selectedPoint ?? lastPoint;
  // Before the points arrive, the chart shows the mark price, as on iOS
  const shownPrice = shownPoint?.[1] ?? (context?.markPx ? Number(context.markPx) : undefined);

  const initialPoint = useMemo(() => history && findInitialPoint(history), [history]);
  // The day change comes from the market, which compares the mark price with the price a day ago, as on iOS
  const { changePercent } = resolveChartChange({
    period,
    isPointSelected: Boolean(selectedPoint),
    dayChangePercent: context?.percentChange24h,
    initialPrice: initialPoint?.[1],
    price: shownPoint?.[1],
  });

  // The selection points into the shown series, so a new period drops it
  const handlePeriodChange = useLastCallback((newPeriod: ApiPriceHistoryPeriod) => {
    setPeriod(newPeriod);
    setSelectedIndex(NO_SELECTION);
  });

  if (isLoadFailed) {
    return <LoadError className={buildClassName(futuresStyles.card, className)} onRetry={loadHistory} />;
  }

  return (
    <ChartCard
      history={history}
      selectedIndex={selectedIndex}
      initialPoint={initialPoint}
      price={shownPrice}
      changePercent={changePercent}
      currencySymbol={PERPS_CURRENCY_SYMBOL}
      period={period}
      token={token}
      className={className}
      plotClassName={buildClassName(futuresStyles.dimmable, isStale && futuresStyles.stale)}
      onSelectIndex={setSelectedIndex}
      onPeriodChange={handlePeriodChange}
    />
  );
}

export default memo(withGlobal<OwnProps>((global, { assetId }): StateProps => {
  return {
    chartsByPeriod: global.perps.chartsByAssetId[assetId],
    context: selectPerpsMarketAsset(global, assetId)?.context,
  };
})(Chart));
