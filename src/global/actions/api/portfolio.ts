import type {
  ApiBaseCurrency, ApiPortfolioHistoryResponse, ApiPortfolioPnlChangeResponse, ApiPriceHistoryPeriod,
} from '../../../api/types';
import type { GlobalState, PortfolioHistoryBundle, PortfolioPnlChange } from '../../types';

import { areDeepEqual } from '../../../util/areDeepEqual';
import {
  DEFAULT_PORTFOLIO_TIME_RANGE,
  getPortfolioHistorySlot,
  getTimeRangeStartTs,
} from '../../../util/portfolio/timeRange';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateHistoryBundle, updatePnlChangeByAccountId, updatePortfolio } from '../../reducers';
import { selectCurrentAccountId, selectPortfolioMainnetWalletKeys } from '../../selectors';

const HISTORY_REFRESH_DELAY_MS = 8000;
const HISTORY_REFRESH_MAX_ATTEMPTS = 6;
// Throttle window for the card's per-tick P&L-change refresh (see `runLoadPortfolioPnlChange`)
const PNL_CHANGE_THROTTLE_MS = 30_000;
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
let activePnlChangeRequestId = 0;
// Single-slot throttle for the card's P&L-change refresh: only the current (account, currency, range)
// is ever checked, so the latest key/time is all we keep - it self-evicts when the key changes
let lastPnlChangeFetch: { key: string; at: number } | undefined;

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

// Lightweight counterpart of `loadPortfolioHistory` for the wallet card
addActionHandler('loadPortfolioPnlChange', (global) => {
  void runLoadPortfolioPnlChange(global);
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

  // Slot cache hit: skip the fetch only if the series are actually here. The card's pnl-change path
  // stamps the same slot without them, and series aren't persisted - so a slot-only match would leave
  // the charts empty after a reload.
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

  const params = buildRangeParams(range);

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
    // Single-slot mirror for the wallet card (it never loads the full bundle)
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

async function runLoadPortfolioPnlChange(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  if (!accountId) return;

  const wallets = selectPortfolioMainnetWalletKeys(global);
  // Portfolio history is mainnet-only; leave the card on its 24h fallback otherwise
  if (wallets.length === 0) return;

  const { baseCurrency } = global.settings;
  const range = global.portfolio?.activeRange ?? DEFAULT_PORTFOLIO_TIME_RANGE;

  // The card re-requests on every balance tick; skip if this (account, currency, range) was fetched
  // within the throttle window. Stamped before the request so rapid ticks neither spam nor pile up
  // parallel in-flight calls
  const throttleKey = `${accountId}_${baseCurrency}_${range}`;
  if (lastPnlChangeFetch?.key === throttleKey && Date.now() - lastPnlChangeFetch.at < PNL_CHANGE_THROTTLE_MS) {
    return;
  }
  lastPnlChangeFetch = { key: throttleKey, at: Date.now() };

  const requestId = ++activePnlChangeRequestId;
  const params = buildRangeParams(range);
  const pnlChangeResponse = await callApi('fetchPortfolioPnlChange', wallets, baseCurrency, params);

  if (requestId !== activePnlChangeRequestId) return;

  const pnlChange = buildPnlChange(pnlChangeResponse, range, baseCurrency);
  if (!pnlChange) {
    // Reset the throttle so the next balance tick can retry rather than waiting out the window
    lastPnlChangeFetch = undefined;
    return;
  }

  global = getGlobal();
  // Drop the result if the account, range or currency changed while awaiting
  if (
    selectCurrentAccountId(global) !== accountId
    || (global.portfolio?.activeRange ?? DEFAULT_PORTFOLIO_TIME_RANGE) !== range
    || global.settings.baseCurrency !== baseCurrency
  ) {
    return;
  }

  // Store per-range in the bundle (so the card and portfolio show the right value across range switches),
  // plus the single-slot mirror that the card reads on cold start before any bundle exists
  const baseSlice = global.portfolio?.historyByAccountId ?? {};
  const existingBundle = baseSlice[accountId]?.[baseCurrency]?.[range];
  global = updatePortfolio(global, {
    historyByAccountId: updateHistoryBundle(baseSlice, accountId, baseCurrency, range, {
      ...existingBundle,
      pnlChange,
      // Stamp the slot so a subsequent `runLoadPortfolioHistory` doesn't fire immediately after this
      fetchedAtSlot: existingBundle?.fetchedAtSlot ?? getPortfolioHistorySlot(range),
    }),
    pnlChangeByAccountId: updatePnlChangeByAccountId(global.portfolio?.pnlChangeByAccountId, accountId, pnlChange),
  });

  setGlobal(global);
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
