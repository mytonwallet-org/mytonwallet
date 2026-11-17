import React, { memo, useMemo } from '../../../lib/teact/teact';

import type { ApiHistoryList, ApiPriceHistoryPeriod, ApiToken } from '../../../api/types';
import type { TokenChartMode } from '../../../global/types';
import type { TabWithProperties } from '../../ui/TabList';

import buildClassName from '../../../util/buildClassName';
import { formatChartDate, formatShortDay, SECOND } from '../../../util/dateFormat';
import { formatCurrency, formatPercent } from '../../../util/formatNumber';
import { TIME_RANGES } from '../../../util/portfolio/timeRange';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../util/swipeController';
import { buildAxisLabels } from '../helpers/buildAxisLabels';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TimeRangeSelector from '../../common/TimeRangeSelector';
import TokenIcon from '../../common/TokenIcon';
import Spinner from '../../ui/Spinner';
import TabList from '../../ui/TabList';
import Transition from '../../ui/Transition';
import Plot from './Plot';

import styles from './ChartCard.module.scss';

interface OwnProps {
  /** The plotted series, absent while it loads */
  history?: ApiHistoryList;
  /** The leading points of `history` that belong to the underlying stock */
  backfillCount?: number;
  selectedIndex: number;
  /** The point the summary starts from */
  initialPoint?: ApiHistoryList[number];
  /** The price at the end of the summary */
  price?: number;
  changePercent?: number;
  /** Replaces the change while a point of the underlying stock is selected */
  stockSymbol?: string;
  currencySymbol: string;
  period: ApiPriceHistoryPeriod;
  /** Shown next to the starting price */
  token?: ApiToken;
  canSwitchMode?: boolean;
  isNetWorthMode?: boolean;
  className?: string;
  plotClassName?: string;
  testId?: string;
  onSelectIndex: (index: number) => void;
  onPeriodChange: (period: ApiPriceHistoryPeriod) => void;
  onChartModeChange?: (mode: TokenChartMode) => void;
}

const PRICE_TAB = 0;
const NET_WORTH_TAB = 1;
const LOADING_SLIDE_KEY = 0;
const CHART_MODE_COUNT = 2;
const PRICE_FRACTION_DIGITS = 2;
const SELECTED_PRICE_FRACTION_DIGITS = 4;

function ChartCard({
  history,
  backfillCount,
  selectedIndex,
  initialPoint,
  price,
  changePercent,
  stockSymbol,
  currencySymbol,
  period,
  token,
  canSwitchMode,
  isNetWorthMode,
  className,
  plotClassName,
  testId,
  onSelectIndex,
  onPeriodChange,
  onChartModeChange,
}: OwnProps) {
  const lang = useLang();

  const isLoading = !history;
  const selectedPoint = selectedIndex >= 0 ? history?.[selectedIndex] : undefined;

  const axisLabels = useMemo(
    () => (history?.length ? buildAxisLabels(lang.code!, period, history) : undefined),
    [lang.code, period, history],
  );

  const modeTabs = useMemo<TabWithProperties[]>(() => [
    { id: PRICE_TAB, title: lang('Price') },
    { id: NET_WORTH_TAB, title: lang('Net Worth') },
  ], [lang]);

  const handleModeSwitch = useLastCallback((tabId: number) => {
    onChartModeChange!(tabId === NET_WORTH_TAB ? 'netWorth' : 'price');
  });

  // Dragging over the plot shows the price at that point, so the card is excluded from the swipe
  // between content tabs and from the swipe back
  const fullClassName = buildClassName(styles.root, 'no-swipe', SWIPE_DISABLED_CLASS_NAME, className);

  // Every swap of the shown series cross-fades, so the key covers both the period and the mode
  const modeIndex = isNetWorthMode ? NET_WORTH_TAB : PRICE_TAB;
  const contentKey = isLoading
    ? LOADING_SLIDE_KEY
    : TIME_RANGES.indexOf(period) * CHART_MODE_COUNT + modeIndex + LOADING_SLIDE_KEY + 1;

  function renderStart() {
    return (
      <div className={styles.summarySide}>
        <span className={styles.summaryCaption}>
          {initialPoint && formatShortDay(lang.code!, initialPoint[0] * SECOND)}
        </span>
        <span className={styles.summaryValue}>
          {initialPoint && formatCurrency(initialPoint[1], currencySymbol, PRICE_FRACTION_DIGITS, true)}
        </span>
      </div>
    );
  }

  function renderPlot() {
    if (history?.length) {
      return (
        <Plot
          prices={history}
          backfillCount={backfillCount}
          selectedIndex={selectedIndex}
          className={buildClassName(styles.plot, plotClassName)}
          onSelectIndex={onSelectIndex}
        />
      );
    }

    if (isLoading) {
      return (
        <div className={styles.plotLoading}>
          <Spinner className={styles.spinner} />
        </div>
      );
    }

    return <div className={styles.plotEmpty}>{lang('No price data')}</div>;
  }

  return (
    <section className={fullClassName} data-testid={testId}>
      {canSwitchMode && (
        <TabList
          tabs={modeTabs}
          activeTab={isNetWorthMode ? NET_WORTH_TAB : PRICE_TAB}
          className={styles.modes}
          overlayClassName={styles.modesOverlay}
          onSwitchTab={handleModeSwitch}
        />
      )}

      <Transition name="fade" activeKey={contentKey} shouldRestoreHeight shouldCleanup>
        <div className={styles.slide}>
          <div className={styles.summary}>
            {token ? (
              <div className={styles.summaryStart}>
                <TokenIcon token={token} size="large" />
                {renderStart()}
              </div>
            ) : renderStart()}

            <div className={buildClassName(styles.summarySide, styles.summarySideEnd)}>
              <span className={styles.summaryCaption}>
                {selectedPoint ? formatChartDate(lang.code!, selectedPoint[0] * SECOND) : lang('Now')}
              </span>
              <span className={styles.summaryValue}>
                {price !== undefined && formatCurrency(
                  price,
                  currencySymbol,
                  selectedPoint ? SELECTED_PRICE_FRACTION_DIGITS : PRICE_FRACTION_DIGITS,
                  true,
                )}
                {stockSymbol ? (
                  <span className={buildClassName(styles.change, styles.changeStock)}>
                    {lang('$underlying_stock', { symbol: stockSymbol })}
                  </span>
                ) : Boolean(changePercent) && (
                  <span
                    className={buildClassName(
                      styles.change,
                      changePercent > 0 ? styles.changePositive : styles.changeNegative,
                    )}
                  >
                    {changePercent > 0 ? '↑' : '↓'}&thinsp;{formatPercent(Math.abs(changePercent))}
                  </span>
                )}
              </span>
            </div>
          </div>

          {renderPlot()}

          <div className={styles.axis}>
            {axisLabels?.map((label, index) => (
              <span key={index}>{label}</span>
            ))}
          </div>
        </div>
      </Transition>

      <TimeRangeSelector value={period} isPlain className={styles.timeRange} onChange={onPeriodChange} />
    </section>
  );
}

export default memo(ChartCard);
