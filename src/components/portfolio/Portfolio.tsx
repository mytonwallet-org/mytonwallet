import React, { memo, useEffect, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiPriceHistoryPeriod, ApiStakingState } from '../../api/types';
import type { PortfolioHistoryBundle, PortfolioPnlChange, UserToken } from '../../global/types';

import { ANIMATION_LEVEL_MIN } from '../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
  selectPortfolioHistoryBundle,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { calculateFullBalance } from '../../util/calculateFullBalance';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { formatDateRange } from '../../util/dateFormat';
import { toBig } from '../../util/decimals';
import { getShortCurrencySymbol } from '../../util/formatNumber';
import { DEFAULT_PORTFOLIO_TIME_RANGE, getTimeRangeStartTs } from '../../util/portfolio/timeRange';
import { getFullStakingBalance } from '../../util/staking';
import { captureControlledSwipe, SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { buildSegmentsByChain, buildSegmentsByStacked, buildSegmentsByTokenKind } from './helpers/buildStackSegments';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrollButtonsVisibility from '../../hooks/useScrollButtonsVisibility';
import useScrolledState from '../../hooks/useScrolledState';

import BackHeader from '../common/BackHeader';
import EdgeScrollButton from '../common/EdgeScrollButton';
import Balance from './sections/Balance';
import Charts from './sections/Charts';
import InsightCard from './sections/InsightCard';
import SectionHeader from './sections/SectionHeader';
import TimeRangeSelector from './sections/TimeRangeSelector';

import './sections/chartOverrides.scss';
import styles from './Portfolio.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  currentAccountId?: string;
  bundle?: PortfolioHistoryBundle;
  pnlChange?: PortfolioPnlChange;
  isPnlChangeUpdating?: boolean;
  error?: string;
  tokens?: UserToken[];
  stakingStates?: ApiStakingState[];
  baseCurrency: ApiBaseCurrency;
  currencyRate: string;
  timeRange: ApiPriceHistoryPeriod;
  noAnimation: boolean;
}

function Portfolio({
  isActive,
  currentAccountId,
  bundle,
  pnlChange,
  isPnlChangeUpdating,
  error,
  tokens,
  stakingStates,
  baseCurrency,
  currencyRate,
  timeRange,
  noAnimation,
}: OwnProps & StateProps) {
  const { closePortfolio, openPortfolio, loadPortfolioHistory } = getActions();

  const lang = useLang();
  const baseCurrencySymbol = getShortCurrencySymbol(baseCurrency);
  const rootRef = useRef<HTMLDivElement>();
  const railRef = useRef<HTMLDivElement>();
  const railContainerRef = useRef<HTMLDivElement>();

  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose(isActive);

  useHistoryBack({ isActive, onBack: closePortfolio });

  useEffect(
    () => (isActive ? captureEscKeyListener(closePortfolio) : undefined),
    [isActive],
  );

  useEffect(() => {
    if (!IS_TOUCH_ENV) return undefined;

    return captureControlledSwipe(rootRef.current!, {
      onSwipeRightStart: () => {
        closePortfolio();
        disableSwipeToClose();
      },
      onCancel: () => {
        openPortfolio();
        enableSwipeToClose();
      },
    });
  }, [disableSwipeToClose, enableSwipeToClose]);

  // Load on open and when the account or base currency changes; the handler reads the active range
  // from global. Range changes are loaded by `onChange` alone, so this effect must not depend on `timeRange`.
  useEffect(() => {
    if (isActive) loadPortfolioHistory();
  }, [isActive, currentAccountId, baseCurrency]);

  const { handleScroll, isScrolled } = useScrolledState();

  const { isLeftButtonVisible, isRightButtonVisible, scrollByOneCell } = useScrollButtonsVisibility({
    containerRef: railRef,
    viewportRef: railContainerRef,
    isDisabled: IS_TOUCH_ENV,
    noAnimation,
  });

  const handleTimeRangeChange = useLastCallback((range: ApiPriceHistoryPeriod) => {
    loadPortfolioHistory({ range });
  });

  const balanceValues = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRate) : undefined;
  }, [tokens, stakingStates, currencyRate]);

  const stakedAmount = useMemo(() => {
    if (!stakingStates?.length || !tokens?.length) return 0;

    const priceBySlug = new Map<string, number>();
    const decimalsBySlug = new Map<string, number>();
    for (const token of tokens) {
      priceBySlug.set(token.slug, token.price);
      decimalsBySlug.set(token.slug, token.decimals);
    }

    let total = 0;
    for (const state of stakingStates) {
      const price = priceBySlug.get(state.tokenSlug);
      const decimals = decimalsBySlug.get(state.tokenSlug);
      if (price === undefined || decimals === undefined) continue;

      total += toBig(getFullStakingBalance(state), decimals).mul(price).toNumber();
    }

    return total;
  }, [stakingStates, tokens]);

  const totalAmount = balanceValues ? Number(balanceValues.primaryValue) : 0;

  const dateRange = useMemo(() => {
    // While updating, `pnlChange` may be buffered from a previous range - don't show its stale window
    if (!isPnlChangeUpdating && pnlChange?.startTs !== undefined && pnlChange.endTs !== undefined) {
      return formatDateRange(lang.code!, pnlChange.startTs, pnlChange.endTs);
    }

    // Fall back to the nominal selected period
    const startTs = getTimeRangeStartTs(timeRange);
    return startTs !== undefined ? formatDateRange(lang.code!, startTs, Date.now()) : undefined;
  }, [pnlChange, isPnlChangeUpdating, lang.code, timeRange]);

  const segmentsByTokenKind = useMemo(
    () => (tokens ? buildSegmentsByTokenKind(lang, tokens, baseCurrency) : []),
    [tokens, baseCurrency, lang],
  );

  const segmentsByChain = useMemo(
    () => (tokens ? buildSegmentsByChain(tokens, baseCurrency) : []),
    [tokens, baseCurrency],
  );

  const segmentsByStacked = useMemo(
    () => buildSegmentsByStacked(lang, totalAmount, stakedAmount, baseCurrency),
    [totalAmount, stakedAmount, baseCurrency, lang],
  );

  return (
    <div ref={rootRef} className={styles.root}>
      <BackHeader title={lang('Portfolio')} withNotchOnScroll isScrolled={isScrolled} onBackClick={closePortfolio} />

      <div className={buildClassName(styles.body, 'custom-scroll')} onScroll={handleScroll}>
        <div className={styles.content}>
          <section className={styles.section}>
            <SectionHeader title={lang('Overview')} range={dateRange} />

            <Balance
              totalAmount={totalAmount}
              baseCurrency={baseCurrency}
              pnlChange={pnlChange}
              isPnlChangeUpdating={isPnlChangeUpdating}
            />
          </section>

          <div ref={railContainerRef} className={styles.insightsRailContainer}>
            <div ref={railRef} className={buildClassName(styles.insightsRail, 'no-swipe', SWIPE_DISABLED_CLASS_NAME)}>
              <div className={styles.insightsCol}>
                <SectionHeader title={lang('By Chain')} />

                <InsightCard segments={segmentsByChain} emptyText={lang('No chain balances')} />
              </div>
              <div className={styles.insightsCol}>
                <SectionHeader title={lang('Asset Mix')} />

                <InsightCard segments={segmentsByTokenKind} emptyText={lang('No asset balances')} />
              </div>
              <div className={styles.insightsCol}>
                <SectionHeader title={lang('Staked')} />

                <InsightCard segments={segmentsByStacked} emptyText={lang('No staked assets')} />
              </div>
            </div>
            <EdgeScrollButton
              direction="left"
              isVisible={isLeftButtonVisible}
              onClick={scrollByOneCell}
            />
            <EdgeScrollButton
              direction="right"
              isVisible={isRightButtonVisible}
              onClick={scrollByOneCell}
            />
          </div>

          <Charts
            bundle={bundle}
            baseCurrencySymbol={baseCurrencySymbol}
            dateRange={dateRange}
            error={error}
            dataKey={`${currentAccountId}_${baseCurrency}`}
            noAnimation={noAnimation}
          />
        </div>

        <div className={styles.bottomBar}>
          <TimeRangeSelector value={timeRange} onChange={handleTimeRangeChange} />
        </div>
      </div>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const { portfolio, settings: { baseCurrency } } = global;
    const currentAccountId = selectCurrentAccountId(global);
    const timeRange = portfolio?.activeRange ?? DEFAULT_PORTFOLIO_TIME_RANGE;
    const bundle = currentAccountId
      ? selectPortfolioHistoryBundle(global, currentAccountId, baseCurrency, timeRange)
      : undefined;
    const freshPnlChange = bundle?.pnlChange;
    const lastPnlChange = currentAccountId ? portfolio?.pnlChangeByAccountId?.[currentAccountId] : undefined;
    const isPortfolioLoading = Boolean(portfolio?.isLoading || portfolio?.isRefreshing);
    const pnlChange = freshPnlChange
      ?? (isPortfolioLoading && lastPnlChange?.baseCurrency === baseCurrency ? lastPnlChange : undefined);
    const isPnlChangeUpdating = isPortfolioLoading && (pnlChange === undefined || pnlChange !== freshPnlChange);

    return {
      currentAccountId,
      bundle,
      pnlChange,
      isPnlChangeUpdating,
      error: portfolio?.error,
      tokens: selectCurrentAccountTokens(global),
      stakingStates: currentAccountId ? selectAccountStakingStates(global, currentAccountId) : undefined,
      baseCurrency,
      currencyRate: global.currencyRates[baseCurrency],
      timeRange,
      noAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
    };
  })(Portfolio),
);
