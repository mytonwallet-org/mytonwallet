import type { ApiPortfolioHistoryResponse, ApiPriceHistoryPeriod } from '../../../api/types';
import type { PortfolioHistoryBundle } from '../../types';

import { areDeepEqual } from '../../../util/areDeepEqual';
import { callApi } from '../../../api';
import { DEFAULT_PORTFOLIO_TIME_RANGE, getTimeRangeStartTs } from '../../../components/portfolio/helpers/timeRange';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updatePortfolio, writeHistoryBundle } from '../../reducers';
import { selectCurrentAccountId, selectPortfolioMainnetWalletKeys } from '../../selectors';

const HISTORY_REFRESH_DELAY_MS = 8000;
const HISTORY_REFRESH_MAX_ATTEMPTS = 6;
const PORTFOLIO_UNAVAILABLE_ERROR = 'Unavailable';
const ALL_TIME_START_ISO = '2020-01-01T00:00:00.000Z';
const DAY_START_SUFFIX = 'T00:00:00.000Z';
const DAY_END_SUFFIX = 'T23:59:59.000Z';
const ISO_DATE_LENGTH = 10;

// Point density per range
const DENSITY_BY_RANGE: Record<ApiPriceHistoryPeriod, string> = {
  '1D': '5m',
  '7D': '1h',
  '1M': '4h',
  '3M': '1d',
  '1Y': '1d',
  ALL: '1d',
};

let historyRefreshTimerId: number | undefined;
let historyRefreshAttempts = 0;
let historyRefreshAccountId: string | undefined;
let activeRequestId = 0;

addActionHandler('loadPortfolioHistory', (global, actions, payload) => {
  const { range } = payload || {};

  cancelScheduledHistoryRefresh();
  historyRefreshAttempts = 0;

  if (range && range !== global.portfolio?.activeRange) {
    setGlobal(updatePortfolio(global, { activeRange: range }));
  }

  void runLoadPortfolioHistory();
});

addActionHandler('closePortfolio', () => {
  cancelScheduledHistoryRefresh();
  historyRefreshAttempts = 0;
  // Invalidate any in-flight `runLoadPortfolioHistory` so its post-await `setGlobal` is dropped
  activeRequestId += 1;
});

async function runLoadPortfolioHistory() {
  const requestId = ++activeRequestId;
  let global = getGlobal();

  const accountId = selectCurrentAccountId(global);
  if (!accountId) return;

  // Reset attempts when the account changes so each account gets a full retry budget
  if (accountId !== historyRefreshAccountId) {
    historyRefreshAttempts = 0;
    historyRefreshAccountId = accountId;
  }

  const wallets = selectPortfolioMainnetWalletKeys(global);
  const { baseCurrency } = global.settings;
  const range = global.portfolio?.activeRange ?? DEFAULT_PORTFOLIO_TIME_RANGE;

  const baseSlice = global.portfolio?.historyByAccountId ?? {};

  if (wallets.length === 0) {
    setGlobal(updatePortfolio(global, {
      historyByAccountId: writeHistoryBundle(baseSlice, accountId, baseCurrency, range, {}),
      activeRange: range,
      isLoading: false,
      isRefreshing: false,
      error: PORTFOLIO_UNAVAILABLE_ERROR,
    }));
    return;
  }

  const existingBundle = baseSlice[accountId]?.[baseCurrency]?.[range];
  const isRefresh = Boolean(
    existingBundle?.netWorth || existingBundle?.pnlCumulative || existingBundle?.pnl,
  );

  setGlobal(updatePortfolio(global, {
    historyByAccountId: baseSlice,
    activeRange: range,
    isLoading: !isRefresh,
    isRefreshing: isRefresh,
    error: undefined,
  }));

  const params = buildRangeParams(range);

  const [netWorth, pnlCumulative, pnl] = await Promise.all([
    callApi('fetchPortfolioNetWorthHistory', wallets, baseCurrency, params),
    callApi('fetchPortfolioPnlCumulativeHistory', wallets, baseCurrency, params),
    callApi('fetchPortfolioPnlHistory', wallets, baseCurrency, params),
  ]);

  if (requestId !== activeRequestId) return;

  global = getGlobal();
  const updatedSlice = global.portfolio?.historyByAccountId ?? {};
  const currentRange = global.portfolio?.activeRange ?? range;

  if (currentRange !== range) return;

  if (!netWorth && !pnlCumulative && !pnl) {
    const existingAfter = updatedSlice[accountId]?.[baseCurrency]?.[range];
    const hasExistingBundle = Boolean(
      existingAfter?.netWorth || existingAfter?.pnlCumulative || existingAfter?.pnl,
    );

    setGlobal(updatePortfolio(global, {
      historyByAccountId: updatedSlice,
      activeRange: range,
      isLoading: false,
      isRefreshing: false,
      error: hasExistingBundle ? undefined : PORTFOLIO_UNAVAILABLE_ERROR,
    }));

    return;
  }

  const bundle: PortfolioHistoryBundle = {};
  if (netWorth) bundle.netWorth = netWorth;
  if (pnlCumulative) bundle.pnlCumulative = pnlCumulative;
  if (pnl) bundle.pnl = pnl;

  const prevBundle = updatedSlice[accountId]?.[baseCurrency]?.[range];
  // Keep previously fetched series that failed this round (each `callApi` can fail independently)
  const mergedBundle: PortfolioHistoryBundle = { ...prevBundle, ...bundle };
  const isSameBundle = prevBundle !== undefined && areDeepEqual(prevBundle, mergedBundle);

  setGlobal(updatePortfolio(global, {
    historyByAccountId: isSameBundle
      ? updatedSlice
      : writeHistoryBundle(updatedSlice, accountId, baseCurrency, range, mergedBundle),
    activeRange: range,
    isLoading: false,
    isRefreshing: false,
    error: undefined,
  }));

  scheduleHistoryRefreshIfNeeded(netWorth, pnlCumulative, pnl);
}

function buildRangeParams(range: ApiPriceHistoryPeriod) {
  const now = new Date();
  const startTs = getTimeRangeStartTs(range, now.getTime());
  const toDay = now.toISOString().slice(0, ISO_DATE_LENGTH);
  return {
    from: startTs === undefined
      ? ALL_TIME_START_ISO
      : `${new Date(startTs).toISOString().slice(0, ISO_DATE_LENGTH)}${DAY_START_SUFFIX}`,
    to: `${toDay}${DAY_END_SUFFIX}`,
    density: DENSITY_BY_RANGE[range],
  };
}

function scheduleHistoryRefreshIfNeeded(
  netWorth: ApiPortfolioHistoryResponse | undefined,
  pnlCumulative: ApiPortfolioHistoryResponse | undefined,
  pnl: ApiPortfolioHistoryResponse | undefined,
) {
  const hasCursor = netWorth?.historyScanCursor !== undefined
    || pnlCumulative?.historyScanCursor !== undefined
    || pnl?.historyScanCursor !== undefined;

  if (!hasCursor || historyRefreshAttempts >= HISTORY_REFRESH_MAX_ATTEMPTS) {
    return;
  }

  historyRefreshAttempts += 1;
  historyRefreshTimerId = window.setTimeout(() => {
    historyRefreshTimerId = undefined;
    void runLoadPortfolioHistory();
  }, HISTORY_REFRESH_DELAY_MS);
}

function cancelScheduledHistoryRefresh() {
  if (historyRefreshTimerId !== undefined) {
    window.clearTimeout(historyRefreshTimerId);
    historyRefreshTimerId = undefined;
  }
}
