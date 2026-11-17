import { addCallback } from '../../../lib/teact/teactn';

import type { GlobalState, PerpsTradeState } from '../../types';

import { IS_PERPS_SUPPORTED } from '../../../config';
import { SECOND } from '../../../util/dateFormat';
import { areSortedArraysEqual } from '../../../util/iteratees';
import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../../util/priceHistory';
import { getPerpsFractionAmount } from '../../helpers/perps';
import {
  buildPerpsReadCache, clearPerpsReadCache, loadPerpsReadCache, savePerpsReadCache,
} from '../../helpers/perpsReadCache';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  clearPerpsOpenedActivity,
  clearPerpsTrade,
  hidePerpsOperationBanner,
  resetPerpsAccountScreens,
  restorePerpsReadCache,
  setPerpsOpenedActivity,
  updateCurrentAccountState,
  updatePerpsTrade,
} from '../../reducers';
import {
  selectCurrentAccountId,
  selectCurrentAccountPerpsOperation,
  selectCurrentAccountState,
} from '../../selectors';

// The estimates of the previous draft are wrong for the new one, so the form waits for a new quote, as on iOS
const CLEARED_ESTIMATES: Partial<PerpsTradeState> = {
  preview: undefined,
  isPreviewLoading: true,
  error: undefined,
};

// The history of a Futures screen refreshes every 20 seconds, so the saved copy lags behind it by at most this much
const READ_CACHE_SAVE_DELAY = 30 * SECOND;

let prevAccountId: string | undefined;
let isReadCacheRestored = false;
let readCacheSaveTimeout: number | undefined;
let savedReadSources: unknown[] = [];
// The sources change only with these two objects, so most global changes skip building the list
let checkedByAccountId: GlobalState['byAccountId'] | undefined;
let checkedChartsByAssetId: GlobalState['perps']['chartsByAssetId'] | undefined;

// The current account changes on a switch, an import, a removal or a network change, and each of these paths sets it
// differently. Watching the result resets the Futures screens after any of them.
addCallback((global: GlobalState) => {
  const accountId = global.currentAccountId;
  if (accountId === prevAccountId) return;

  const isSwitch = prevAccountId !== undefined;
  prevAccountId = accountId;
  if (!isSwitch) return;

  // In debug builds the global a callback gets is stamped as outdated, so `setGlobal` would throw on it
  global = getGlobal();
  const newGlobal = resetPerpsAccountScreens(global);
  if (newGlobal !== global) setGlobal(newGlobal);
});

addActionHandler('afterInit', async () => {
  if (!IS_PERPS_SUPPORTED) return;

  const cache = await loadPerpsReadCache();
  if (cache) setGlobal(restorePerpsReadCache(getGlobal(), cache));

  savedReadSources = getPerpsReadSources(getGlobal());
  isReadCacheRestored = true;
});

// Saving waits for the restore, which would otherwise be overwritten by the empty state of the launch
addCallback((global: GlobalState) => {
  if (!isReadCacheRestored || readCacheSaveTimeout !== undefined) return;
  if (global.byAccountId === checkedByAccountId && global.perps.chartsByAssetId === checkedChartsByAssetId) return;

  checkedByAccountId = global.byAccountId;
  checkedChartsByAssetId = global.perps.chartsByAssetId;

  const sources = getPerpsReadSources(global);
  if (areSortedArraysEqual(sources, savedReadSources)) return;

  readCacheSaveTimeout = window.setTimeout(() => {
    readCacheSaveTimeout = undefined;
    const latest = getGlobal();
    savedReadSources = getPerpsReadSources(latest);
    void savePerpsReadCache(buildPerpsReadCache(latest));
  }, READ_CACHE_SAVE_DELAY);
});

// A reset removes every wallet, so the saved Futures data goes too. A pending save would bring it back.
addActionHandler('afterSignOut', (global, actions, payload) => {
  if (!IS_PERPS_SUPPORTED || !payload?.shouldReset) return;

  window.clearTimeout(readCacheSaveTimeout);
  readCacheSaveTimeout = undefined;
  void clearPerpsReadCache();
});

addActionHandler('hidePerpsOperationBanner', (global, _, { operationId }) => {
  const operation = selectCurrentAccountPerpsOperation(global, operationId);
  if (!operation) return undefined;

  return hidePerpsOperationBanner(global, operation);
});

addActionHandler('setPerpsTradeAmount', (global, _, { amount }) => {
  const { trade } = global.perps;
  if (!trade || trade.amount === amount) return undefined;

  return updatePerpsTrade(global, {
    amount,
    fraction: undefined,
    ...CLEARED_ESTIMATES,
    leverageEstimates: undefined,
  });
});

addActionHandler('applyPerpsTradeFraction', (global, _, { fraction }) => {
  const { trade } = global.perps;
  const amount = trade && getPerpsFractionAmount(trade, fraction);
  if (amount === undefined || (trade!.amount === amount && trade!.fraction === fraction)) return undefined;

  // The field shows the share at once, and the quote prices the exact share
  return updatePerpsTrade(global, {
    amount,
    fraction: amount ? fraction : undefined,
    ...CLEARED_ESTIMATES,
    leverageEstimates: undefined,
  });
});

addActionHandler('setPerpsTradeLeverage', (global, _, { leverage }) => {
  const { trade } = global.perps;
  if (!trade || trade.leverage === leverage) return undefined;

  return updatePerpsTrade(global, { leverage, ...CLEARED_ESTIMATES });
});

addActionHandler('setPerpsTradeFundingSource', (global, actions, { fundingSource }) => {
  const { trade } = global.perps;
  if (!trade || (trade.fundingSource ?? 'wallet') === fundingSource) return;

  // The requirements and the estimates of one source say nothing about the other
  setGlobal(updatePerpsTrade(global, {
    fundingSource,
    funding: undefined,
    fundingError: undefined,
    ...CLEARED_ESTIMATES,
    leverageEstimates: undefined,
  }));
  actions.loadPerpsFundingRequirements();
});

addActionHandler('setPerpsTradeStep', (global, _, { step }) => {
  const { trade } = global.perps;
  // During a wallet switch the trade already belongs to the new wallet, and it opens its form once the switch ends
  if (!trade || trade.step === 'progress' || trade.accountId !== selectCurrentAccountId(global)) return undefined;

  return updatePerpsTrade(global, { step, error: undefined, reviewNotice: undefined });
});

addActionHandler('cancelPerpsTrade', (global) => {
  // A running operation cannot be stopped, so its modal stays until the result arrives
  if (global.perps.trade?.step === 'progress') return undefined;

  return clearPerpsTrade(global);
});

addActionHandler('openPerpsActivity', (global, _, activity) => {
  return setPerpsOpenedActivity(global, activity);
});

addActionHandler('closePerpsActivity', (global) => {
  return clearPerpsOpenedActivity(global);
});

addActionHandler('openPerpsAsset', (global, _actions, { assetId }) => {
  const period = selectCurrentAccountState(global)?.currentPerpsAssetPeriod ?? DEFAULT_PRICE_HISTORY_PERIOD;

  return updateCurrentAccountState(global, {
    currentPerpsAssetId: assetId,
    currentPerpsAssetPeriod: period,
  });
});

addActionHandler('closePerpsAsset', (global) => {
  return updateCurrentAccountState(global, {
    currentPerpsAssetId: undefined,
  });
});

addActionHandler('setCurrentPerpsAssetPeriod', (global, _actions, { period }) => {
  return updateCurrentAccountState(global, {
    currentPerpsAssetPeriod: period,
  });
});

// The parts of the state the saved copy is built from, compared by reference to tell that it changed
function getPerpsReadSources(global: GlobalState): unknown[] {
  return [
    global.perps.chartsByAssetId,
    ...Object.values(global.byAccountId).map(({ perps }) => perps?.history),
  ];
}
