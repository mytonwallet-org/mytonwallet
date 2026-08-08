import React, { memo, useEffect, useMemo, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiHistoryList, ApiPriceHistoryPeriod } from '../../../api/types';
import type { LangCode, PriceHistoryPeriods, TokenChartMode, UserToken } from '../../../global/types';
import type { TabWithProperties } from '../../ui/TabList';

import { DEFAULT_PRICE_CURRENCY } from '../../../config';
import { selectCurrentAccountState } from '../../../global/selectors';
import { isNetWorthChartAvailable } from '../../../util/assets/netWorth';
import buildClassName from '../../../util/buildClassName';
import { formatChartDate, formatShortDay, formatTime, SECOND } from '../../../util/dateFormat';
import { formatCurrency, formatPercent, getShortCurrencySymbol } from '../../../util/formatNumber';
import { vibrate } from '../../../util/haptics';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../util/swipeController';
import { IS_IOS } from '../../../util/windowEnvironment';

import useInterval from '../../../hooks/useInterval';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

import TimeRangeSelector from '../../common/TimeRangeSelector';
import Skeleton from '../../ui/Skeleton';
import TabList from '../../ui/TabList';
import Plot from './Plot';

import styles from './Chart.module.scss';

export interface TokenPricePoint {
  price: number;
  initialPrice: number;
}

interface OwnProps {
  token: UserToken;
  chartMode: TokenChartMode;
  className?: string;
  onChartModeChange: (mode: TokenChartMode) => void;
  onPricePointChange: (point?: TokenPricePoint) => void;
}

interface StateProps {
  period: ApiPriceHistoryPeriod;
  baseCurrency: ApiBaseCurrency;
  historyPeriods?: PriceHistoryPeriods;
  netWorthHistoryPeriods?: PriceHistoryPeriods;
}

const DEFAULT_PERIOD: ApiPriceHistoryPeriod = '1D';

// An open chart keeps polling the price, at the same cadence as the native apps
const REFRESH_INTERVAL = 15 * SECOND;

const NO_SELECTION = -1;
const PRICE_TAB = 0;
const NET_WORTH_TAB = 1;
const AXIS_LABEL_COUNT = 4;
const PRICE_FRACTION_DIGITS = 2;
const SELECTED_PRICE_FRACTION_DIGITS = 4;

function Chart({
  token,
  chartMode,
  className,
  period,
  baseCurrency,
  historyPeriods,
  netWorthHistoryPeriods,
  onChartModeChange,
  onPricePointChange,
}: OwnProps & StateProps) {
  const { loadPriceHistory, loadTokenNetWorthHistory, setCurrentTokenPeriod } = getActions();

  const lang = useLang();
  const [selectedIndex, setSelectedIndex] = useState(NO_SELECTION);

  const { slug, symbol } = token;
  // If the base currency equals the token, the chart would be a flat line, so it falls back to USD.
  // A currency code and a token slug never match directly, so the symbols are compared.
  const chartCurrency = getShortCurrencySymbol(baseCurrency) === symbol ? DEFAULT_PRICE_CURRENCY : baseCurrency;
  const currencySymbol = getShortCurrencySymbol(chartCurrency);

  const isNetWorthMode = chartMode === 'netWorth' && isNetWorthChartAvailable(token);
  const canSwitchMode = isNetWorthChartAvailable(token);
  const history = isNetWorthMode ? netWorthHistoryPeriods?.[period] : historyPeriods?.[period];
  const isLoading = !history;

  const refreshHistory = useLastCallback((newPeriod: ApiPriceHistoryPeriod = period) => {
    if (isNetWorthMode) {
      loadTokenNetWorthHistory({ slug, period: newPeriod, currency: chartCurrency });
    } else {
      loadPriceHistory({ slug, period: newPeriod, currency: chartCurrency });
    }
  });

  useEffect(refreshHistory, [slug, period, chartCurrency, isNetWorthMode, refreshHistory]);

  useInterval(refreshHistory, REFRESH_INTERVAL, true);

  // The selection points into the shown series, so switching the token, the period or the mode drops it
  useEffect(() => {
    setSelectedIndex(NO_SELECTION);
  }, [slug, period, isNetWorthMode]);

  useSyncEffect(([prevSelectedIndex]) => {
    if (IS_IOS && prevSelectedIndex !== undefined) vibrate();
  }, [selectedIndex]);

  const lastPoint = history?.length ? history[history.length - 1] : undefined;
  const selectedPoint = selectedIndex >= 0 ? history?.[selectedIndex] : undefined;
  const shownPoint = selectedPoint ?? lastPoint;

  // A zero price gives no baseline for the change, so the period starts at the first traded point.
  // The caption on the left shows that same point.
  const initialPoint = useMemo(() => history?.find(([, value]) => Boolean(value)), [history]);
  const initialPrice = initialPoint?.[1];
  const changePercent = initialPrice && shownPoint ? (shownPoint[1] / initialPrice - 1) * 100 : undefined;

  // A price quoted in another currency would make the balance above jump between currencies
  const shownPrice = isNetWorthMode || chartCurrency !== baseCurrency ? undefined : shownPoint?.[1];

  useEffect(() => {
    onPricePointChange(shownPrice !== undefined && initialPrice
      ? { price: shownPrice, initialPrice }
      : undefined);
  }, [shownPrice, initialPrice, onPricePointChange]);

  const axisLabels = useMemo(() => buildAxisLabels(lang.code!, period, history), [lang.code, period, history]);

  const handlePeriodChange = useLastCallback((newPeriod: ApiPriceHistoryPeriod) => {
    setCurrentTokenPeriod({ period: newPeriod });
    refreshHistory(newPeriod);
  });

  const modeTabs = useMemo<TabWithProperties[]>(() => [
    { id: PRICE_TAB, title: lang('Price') },
    { id: NET_WORTH_TAB, title: lang('Net Worth') },
  ], [lang]);

  const handleModeSwitch = useLastCallback((tabId: number) => {
    onChartModeChange(tabId === NET_WORTH_TAB ? 'netWorth' : 'price');
  });

  // Dragging over the plot shows the price at that point, so the card is excluded from the swipe
  // between content tabs and from the swipe back
  const fullClassName = buildClassName(styles.root, 'no-swipe', SWIPE_DISABLED_CLASS_NAME, className);

  return (
    <section className={fullClassName}>
      {canSwitchMode && (
        <TabList
          tabs={modeTabs}
          activeTab={isNetWorthMode ? NET_WORTH_TAB : PRICE_TAB}
          className={styles.modes}
          overlayClassName={styles.modesOverlay}
          onSwitchTab={handleModeSwitch}
        />
      )}

      <div className={styles.summary}>
        <div className={styles.summarySide}>
          <span className={styles.summaryCaption}>
            {initialPoint
              ? formatShortDay(lang.code!, initialPoint[0] * 1000)
              : isLoading && <Skeleton className={styles.captionSkeleton} />}
          </span>
          <span className={styles.summaryValue}>
            {initialPoint
              ? formatCurrency(initialPoint[1], currencySymbol, PRICE_FRACTION_DIGITS, true)
              : isLoading && <Skeleton className={styles.valueSkeleton} />}
          </span>
        </div>

        <div className={buildClassName(styles.summarySide, styles.summarySideEnd)}>
          <span className={styles.summaryCaption}>
            {selectedPoint ? formatChartDate(lang.code!, selectedPoint[0] * 1000) : lang('Now')}
          </span>
          <span className={styles.summaryValue}>
            {shownPoint ? (
              <>
                {formatCurrency(
                  shownPoint[1],
                  currencySymbol,
                  selectedPoint ? SELECTED_PRICE_FRACTION_DIGITS : PRICE_FRACTION_DIGITS,
                  true,
                )}
                {Boolean(changePercent) && (
                  <span
                    className={buildClassName(
                      styles.change,
                      changePercent > 0 ? styles.changePositive : styles.changeNegative,
                    )}
                  >
                    {changePercent > 0 ? '↑' : '↓'}&thinsp;{formatPercent(Math.abs(changePercent))}
                  </span>
                )}
              </>
            ) : isLoading && <Skeleton className={styles.valueSkeleton} />}
          </span>
        </div>
      </div>

      {history?.length ? (
        <Plot
          prices={history}
          selectedIndex={selectedIndex}
          className={styles.plot}
          onSelectIndex={setSelectedIndex}
        />
      ) : isLoading ? (
        <Skeleton className={styles.plotSkeleton} />
      ) : (
        // The backend knows the asset but has no points for this period (e.g. rarely traded tokens
        // on short ranges), so a longer period may still chart
        <div className={styles.plotEmpty}>{lang('No price data')}</div>
      )}

      <div className={styles.axis}>
        {axisLabels?.map((label, index) => (
          <span key={index}>{label}</span>
        ))}
      </div>

      <TimeRangeSelector value={period} isPlain className={styles.timeRange} onChange={handlePeriodChange} />
    </section>
  );
}

function buildAxisLabels(langCode: LangCode, period: ApiPriceHistoryPeriod, history?: ApiHistoryList) {
  if (!history?.length) return undefined;

  const lastIndex = history.length - 1;

  return Array.from({ length: AXIS_LABEL_COUNT }, (_, index) => {
    const [timestamp] = history[Math.round((index / (AXIS_LABEL_COUNT - 1)) * lastIndex)];

    return period === '1D'
      ? formatTime(timestamp * 1000)
      : formatShortDay(langCode, timestamp * 1000, false, true);
  });
}

export default memo(
  withGlobal<OwnProps>((global, { token }): StateProps => {
    const accountState = selectCurrentAccountState(global);

    return {
      period: accountState?.currentTokenPeriod ?? DEFAULT_PERIOD,
      baseCurrency: global.settings.baseCurrency,
      historyPeriods: global.tokenPriceHistory.bySlug[token.slug],
      netWorthHistoryPeriods: accountState?.tokenNetWorthHistory?.[token.slug],
    };
  })(Chart),
);
