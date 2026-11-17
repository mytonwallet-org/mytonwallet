import React, { memo, useEffect, useMemo, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiPriceHistoryPeriod } from '../../../api/types';
import type {
  PriceHistoryBackfillPeriods, PriceHistoryPeriods, TokenChartMode, UserToken,
} from '../../../global/types';
import type { TokenBalanceChange } from '../helpers/resolveBalanceChange';

import { DEFAULT_PRICE_CURRENCY } from '../../../config';
import { selectCurrentAccount, selectCurrentAccountState } from '../../../global/selectors';
import { isNetWorthChartAvailable } from '../../../util/assets/netWorth';
import { SECOND } from '../../../util/dateFormat';
import { getShortCurrencySymbol } from '../../../util/formatNumber';
import getTestId from '../../../util/getTestId';
import { vibrate } from '../../../util/haptics';
import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../../util/priceHistory';
import { IS_IOS } from '../../../util/windowEnvironment';
import { findInitialPoint } from '../helpers/findInitialPoint';
import { resolveBalanceChange } from '../helpers/resolveBalanceChange';
import { resolveChartChange } from '../helpers/resolveChartChange';

import useInterval from '../../../hooks/useInterval';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

import ChartCard from './ChartCard';

interface OwnProps {
  token: UserToken;
  chartMode: TokenChartMode;
  isActive?: boolean;
  className?: string;
  onChartModeChange: (mode: TokenChartMode) => void;
  onBalanceChangeUpdate: (change: TokenBalanceChange) => void;
}

interface StateProps {
  period: ApiPriceHistoryPeriod;
  baseCurrency: ApiBaseCurrency;
  backendPercentChange24h?: number;
  historyPeriods?: PriceHistoryPeriods;
  restoredHistoryPeriods?: PriceHistoryPeriods;
  backfillPeriods?: PriceHistoryBackfillPeriods;
  netWorthHistoryPeriods?: PriceHistoryPeriods;
  hasTokenChainWallet: boolean;
}

// An open chart keeps polling the price, at the same cadence as the native apps
const REFRESH_INTERVAL = 15 * SECOND;

const NO_SELECTION = -1;

function Chart({
  token,
  chartMode,
  isActive,
  className,
  period,
  baseCurrency,
  backendPercentChange24h,
  historyPeriods,
  restoredHistoryPeriods,
  backfillPeriods,
  netWorthHistoryPeriods,
  hasTokenChainWallet,
  onChartModeChange,
  onBalanceChangeUpdate,
}: OwnProps & StateProps) {
  const { loadPriceHistory, loadTokenNetWorthHistory, setCurrentTokenPeriod } = getActions();

  const [selectedIndex, setSelectedIndex] = useState(NO_SELECTION);

  const { slug, symbol } = token;
  // If the base currency equals the token, the chart would be a flat line, so it falls back to USD.
  // A currency code and a token slug never match directly, so the symbols are compared.
  const chartCurrency = getShortCurrencySymbol(baseCurrency) === symbol ? DEFAULT_PRICE_CURRENCY : baseCurrency;
  const currencySymbol = getShortCurrencySymbol(chartCurrency);

  // Net worth history is loaded by the wallet address, so it exists only when the account has a wallet in the
  // token's network
  const canSwitchMode = hasTokenChainWallet && isNetWorthChartAvailable(token);
  const isNetWorthMode = chartMode === 'netWorth' && canSwitchMode;
  const sessionHistory = isNetWorthMode ? netWorthHistoryPeriods?.[period] : historyPeriods?.[period];
  const restoredHistory = isNetWorthMode ? undefined : restoredHistoryPeriods?.[period];
  // A restored series ends with an old price, so the price, change and balance wait until this session loads one
  const isRestored = !sessionHistory?.length && Boolean(restoredHistory?.length);
  const history = isRestored ? restoredHistory : sessionHistory;
  const isLoading = !history;
  // The backfill arrives with the session series only
  const backfill = isNetWorthMode || isRestored ? undefined : backfillPeriods?.[period];
  const stockCount = backfill?.points.length ?? 0;
  const plotHistory = useMemo(() => (
    history && backfill ? [...backfill.points, ...history] : history
  ), [backfill, history]);

  const refreshHistory = useLastCallback(() => {
    if (isNetWorthMode) {
      loadTokenNetWorthHistory({ slug, period, currency: chartCurrency });
    } else {
      loadPriceHistory({ slug, period, currency: chartCurrency });
    }
  });

  // Any base currency change clears the stored series, even when `chartCurrency` stays the same
  useEffect(() => {
    if (isActive) refreshHistory();
  }, [isActive, slug, period, baseCurrency, isNetWorthMode, refreshHistory]);

  useInterval(refreshHistory, isActive ? REFRESH_INTERVAL : undefined, true);

  // The selection points into the shown series, so switching the token, the period or the mode drops it
  useEffect(() => {
    setSelectedIndex(NO_SELECTION);
  }, [slug, period, isNetWorthMode]);

  useSyncEffect(([prevSelectedIndex]) => {
    if (IS_IOS && prevSelectedIndex !== undefined) vibrate();
  }, [selectedIndex]);

  const lastPoint = history?.length && !isRestored ? history[history.length - 1] : undefined;
  const selectedPoint = selectedIndex >= 0 ? plotHistory?.[selectedIndex] : undefined;
  const isStockSelected = selectedIndex >= 0 && selectedIndex < stockCount;
  const shownPoint = selectedPoint ?? lastPoint;
  const shownPrice = shownPoint?.[1];

  const initialPoint = useMemo(() => history && findInitialPoint(history), [history]);
  const initialPrice = initialPoint?.[1];
  const { isDayChange: shouldUseTokenChange24h, changePercent } = resolveChartChange({
    period,
    isPointSelected: Boolean(selectedPoint),
    dayChangePercent: isNetWorthMode ? undefined : backendPercentChange24h,
    initialPrice,
    price: isStockSelected ? undefined : shownPrice,
  });

  // A price quoted in another currency would make the balance above jump between currencies
  const isBalanceFollowingChart = !isNetWorthMode && chartCurrency === baseCurrency && !isStockSelected;

  useEffect(() => {
    onBalanceChangeUpdate(resolveBalanceChange({
      shouldUseChange24h: shouldUseTokenChange24h || !isBalanceFollowingChart,
      isLoading: isLoading || isRestored,
      price: shownPrice,
      initialPrice,
    }));
  }, [
    shouldUseTokenChange24h, isBalanceFollowingChart, isLoading, isRestored, shownPrice, initialPrice,
    onBalanceChangeUpdate,
  ]);

  // The new period reaches the effect above through the global state, which loads the series
  const handlePeriodChange = useLastCallback((newPeriod: ApiPriceHistoryPeriod) => {
    setCurrentTokenPeriod({ period: newPeriod });
  });

  const handleSelectIndex = useLastCallback((index: number) => {
    if (isRestored) return;

    setSelectedIndex(index);
  });

  return (
    <ChartCard
      history={plotHistory}
      backfillCount={stockCount}
      selectedIndex={selectedIndex}
      initialPoint={initialPoint}
      price={shownPrice}
      changePercent={shownPoint ? changePercent : undefined}
      stockSymbol={isStockSelected ? backfill!.symbol : undefined}
      currencySymbol={currencySymbol}
      period={period}
      canSwitchMode={canSwitchMode}
      isNetWorthMode={isNetWorthMode}
      className={className}
      testId={isActive ? getTestId('token_price_card') : undefined}
      onSelectIndex={handleSelectIndex}
      onPeriodChange={handlePeriodChange}
      onChartModeChange={onChartModeChange}
    />
  );
}

export default memo(
  withGlobal<OwnProps>((global, { token }): StateProps => {
    const accountState = selectCurrentAccountState(global);
    const apiToken = global.tokenInfo.bySlug[token.slug];
    const backendPercentChange24h = apiToken?.isPriceFromBackend && Number.isFinite(apiToken.percentChange24h)
      ? apiToken.percentChange24h
      : undefined;

    return {
      period: accountState?.currentTokenPeriod ?? DEFAULT_PRICE_HISTORY_PERIOD,
      baseCurrency: global.settings.baseCurrency,
      backendPercentChange24h,
      historyPeriods: global.tokenPriceHistory.bySlug[token.slug],
      restoredHistoryPeriods: global.tokenPriceHistory.restoredBySlug[token.slug],
      backfillPeriods: global.tokenPriceHistory.backfillBySlug?.[token.slug],
      netWorthHistoryPeriods: accountState?.tokenNetWorthHistory?.[token.slug],
      hasTokenChainWallet: Boolean(selectCurrentAccount(global)?.byChain[token.chain]),
    };
  })(Chart),
);
