import type {
  ApiBaseCurrency, ApiPortfolioHistoryResponse, ApiPortfolioPnlChangeResponse, ApiPriceHistoryPeriod,
} from '../../../api/types';
import type { PortfolioHistoryBundle, PortfolioPnlChange } from '../../types';

import { areDeepEqual } from '../../../util/areDeepEqual';
import {
  buildPortfolioHistoryParams,
  DEFAULT_PORTFOLIO_TIME_RANGE,
  getPortfolioHistorySlot,
} from '../../../util/portfolio/timeRange';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateHistoryBundle, updatePnlChangeByAccountId, updatePortfolio } from '../../reducers';
import { selectCurrentAccountId, selectPortfolioMainnetWalletKeys } from '../../selectors';

const HISTORY_REFRESH_DELAY_MS = 8000;
const HISTORY_REFRESH_MAX_ATTEMPTS = 6;
const PORTFOLIO_UNAVAILABLE_ERROR = 'Unavailable';
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

// `force=true` is used by the `historyScanCursor` poll - it must bypass the slot cache because
// the cursor signals "backend is still backfilling history" regardless of the current slot
async function runLoadPortfolioHistory(force = false) {
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
  const currentSlot = getPortfolioHistorySlot(range);

  if (wallets.length === 0) {
    setGlobal(updatePortfolio(global, {
      historyByAccountId: updateHistoryBundle(baseSlice, accountId, baseCurrency, range, {
        fetchedAtSlot: currentSlot,
      }),
      pnlChangeByAccountId: updatePnlChangeByAccountId(global.portfolio?.pnlChangeByAccountId, accountId),
      activeRange: range,
      isLoading: false,
      isRefreshing: false,
      error: PORTFOLIO_UNAVAILABLE_ERROR,
    }));
    return;
  }

  const existingBundle = baseSlice[accountId]?.[baseCurrency]?.[range];
  const hasSeries = Boolean(
    existingBundle?.netWorth || existingBundle?.pnlCumulative || existingBundle?.pnl,
  );

  // Failed requests can stamp a slot without series, and series are not persisted across reloads
  if (!force && hasSeries && existingBundle?.fetchedAtSlot === currentSlot) {
    return;
  }

  const isRefresh = hasSeries;

  setGlobal(updatePortfolio(global, {
    historyByAccountId: baseSlice,
    activeRange: range,
    isLoading: !isRefresh,
    isRefreshing: isRefresh,
    error: undefined,
  }));

  const params = buildPortfolioHistoryParams(range);

  const [netWorth, pnlCumulative, pnl, pnlChangeResponse] = await Promise.all([
    callApi('fetchPortfolioNetWorthHistory', wallets, baseCurrency, params),
    callApi('fetchPortfolioPnlCumulativeHistory', wallets, baseCurrency, params),
    callApi('fetchPortfolioPnlHistory', wallets, baseCurrency, params),
    callApi('fetchPortfolioPnlChange', wallets, baseCurrency, params),
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

    // Stamp the slot even on full series failure so the slot-cache check doesn't re-fire every tick
    const pnlChangeOnFailure = buildPnlChange(pnlChangeResponse, range, baseCurrency);
    const bundleOnFailure: PortfolioHistoryBundle = {
      ...(existingAfter ?? {}),
      fetchedAtSlot: currentSlot,
      ...(pnlChangeOnFailure ? { pnlChange: pnlChangeOnFailure } : {}),
    };
    setGlobal(updatePortfolio(global, {
      historyByAccountId: updateHistoryBundle(updatedSlice, accountId, baseCurrency, range, bundleOnFailure),
      pnlChangeByAccountId: pnlChangeOnFailure
        ? updatePnlChangeByAccountId(global.portfolio?.pnlChangeByAccountId, accountId, pnlChangeOnFailure)
        : hasExistingBundle
          ? global.portfolio?.pnlChangeByAccountId
          : updatePnlChangeByAccountId(global.portfolio?.pnlChangeByAccountId, accountId),
      activeRange: range,
      isLoading: false,
      isRefreshing: false,
      error: hasExistingBundle ? undefined : PORTFOLIO_UNAVAILABLE_ERROR,
    }));

    return;
  }

  const pnlChange = buildPnlChange(pnlChangeResponse, range, baseCurrency);

  const bundle: PortfolioHistoryBundle = {};
  if (netWorth) bundle.netWorth = netWorth;
  if (pnlCumulative) bundle.pnlCumulative = pnlCumulative;
  if (pnl) bundle.pnl = pnl;
  if (pnlChange) bundle.pnlChange = pnlChange;

  const prevBundle = updatedSlice[accountId]?.[baseCurrency]?.[range];
  // Keep previously fetched series/value that failed this round (each `callApi` can fail independently)
  const mergedBundle: PortfolioHistoryBundle = {
    ...prevBundle,
    ...bundle,
    fetchedAtSlot: currentSlot,
  };
  const isSameBundle = prevBundle !== undefined && areDeepEqual(prevBundle, mergedBundle);

  setGlobal(updatePortfolio(global, {
    historyByAccountId: isSameBundle
      ? updatedSlice
      : updateHistoryBundle(updatedSlice, accountId, baseCurrency, range, mergedBundle),
    // Keep the last value visible while Portfolio loads a different range
    pnlChangeByAccountId: pnlChange
      ? updatePnlChangeByAccountId(global.portfolio?.pnlChangeByAccountId, accountId, pnlChange)
      : global.portfolio?.pnlChangeByAccountId,
    activeRange: range,
    isLoading: false,
    isRefreshing: false,
    error: undefined,
  }));

  scheduleHistoryRefreshIfNeeded(netWorth, pnlCumulative, pnl);
}

// Maps the backend's precomputed P&L-change response into the persisted shape. Returns undefined when
// the response is missing (transport error) or carries no usable amount, so callers keep the prior value
function buildPnlChange(
  response: ApiPortfolioPnlChangeResponse | undefined,
  range: ApiPriceHistoryPeriod,
  baseCurrency: ApiBaseCurrency,
): PortfolioPnlChange | undefined {
  if (!response || typeof response.amount !== 'number' || !Number.isFinite(response.amount)) {
    return undefined;
  }

  return {
    range,
    baseCurrency,
    amount: response.amount,
    percent: response.percent,
    startTs: response.startTs,
    endTs: response.endTs,
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
    // Bypass the slot cache - the cursor poll means "backend has more history to backfill"
    void runLoadPortfolioHistory(true);
  }, HISTORY_REFRESH_DELAY_MS);
}

function cancelScheduledHistoryRefresh() {
  if (historyRefreshTimerId !== undefined) {
    window.clearTimeout(historyRefreshTimerId);
    historyRefreshTimerId = undefined;
  }
}
