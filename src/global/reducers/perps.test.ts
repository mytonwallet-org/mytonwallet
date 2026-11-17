import type {
  ApiPerpsActivityHistory,
  ApiPerpsFill,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsSnapshot,
  ApiPriceHistoryPeriod,
} from '../../api/types';
import type { GlobalState } from '../types';

import { buildPerpsMarketFixture } from '../../../tests/helpers/perpsMarket';
import { buildPerpsReadCache } from '../helpers/perpsReadCache';
import { INITIAL_STATE } from '../initialState';
import {
  mergePerpsHistory,
  resetPerpsAccountScreens,
  restorePerpsReadCache,
  setPerpsTrade,
  updateAccountPerps,
  updatePerpsChart,
  updatePerpsMarket,
  updatePerpsMarketAsset,
  updatePerpsNavigation,
  updatePerpsOperation,
  updatePerpsSnapshot,
  updatePerpsTrade,
} from './perps';

const ACCOUNT_ID = '0-mainnet';

describe('mergePerpsHistory', () => {
  it('merges a page by stable keys, newest first, without duplicates', () => {
    const first = mergePerpsHistory(buildPage([buildFill('a', 3), buildFill('b', 2)], 'cursor-1'));
    const next = mergePerpsHistory(buildPage([buildFill('b', 2), buildFill('d', 0)], 'cursor-2'), first, true);

    expect(next.fills.map(({ activityId }) => activityId)).toEqual(['a', 'b', 'd']);
    expect(next.nextCursor).toBe('cursor-2');
  });

  it('keeps the older pages and their cursor when the first page refreshes', () => {
    const loaded = mergePerpsHistory(
      buildPage([buildFill('b', 1)], 'cursor-2'),
      mergePerpsHistory(buildPage([buildFill('a', 3)], 'cursor-1')),
      true,
    );

    const refreshed = mergePerpsHistory(buildPage([buildFill('new', 4), buildFill('a', 3)], 'cursor-1'), loaded);

    expect(refreshed.fills.map(({ activityId }) => activityId)).toEqual(['new', 'a', 'b']);
    expect(refreshed.nextCursor).toBe('cursor-2');
  });

  it('loads the fills between a refreshed page and the older pages it does not reach', () => {
    const loaded = mergePerpsHistory(buildPage([buildFill('a', 3), buildFill('b', 1)]));

    const refreshed = mergePerpsHistory(buildPage([buildFill('new-2', 6), buildFill('new-1', 5)], 'cursor-2'), loaded);

    expect(refreshed.fills.map(({ activityId }) => activityId)).toEqual(['new-2', 'new-1', 'a', 'b']);
    expect(refreshed.nextCursor).toBe('cursor-2');
  });

  it('falls back to the time, the market and the order for fills without an id', () => {
    const history = mergePerpsHistory(buildPage([buildFill(undefined, 1, 7), buildFill(undefined, 1, 7)]));

    expect(history.fills).toHaveLength(1);
  });
});

describe('updatePerpsSnapshot', () => {
  it('keeps only the account part of the snapshot', () => {
    const global = updatePerpsSnapshot({
      ...INITIAL_STATE,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
    }, ACCOUNT_ID, {
      ...buildPerpsMarketFixture(),
      positions: [],
      totalEquity: '0',
      totalPnl: '0',
      timestamp: 1,
      unavailableDexs: [],
    } as ApiPerpsSnapshot);

    const { snapshot } = global.byAccountId[ACCOUNT_ID].perps!;
    expect(snapshot).not.toHaveProperty('assets');
    expect(snapshot).not.toHaveProperty('marketSections');
    expect(snapshot).toMatchObject({ positions: [], totalEquity: '0' });
  });

  it('keeps the last positions and totals with the books the new snapshot misses', () => {
    const base = {
      ...buildPerpsMarketFixture(), positions: [], totalPnl: '0', timestamp: 1, unavailableDexs: [],
    };
    let global = updatePerpsSnapshot({
      ...INITIAL_STATE,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
    }, ACCOUNT_ID, { ...base, totalEquity: '10', tradingAvailability: { isAvailable: true } } as ApiPerpsSnapshot);
    global = updatePerpsSnapshot(global, ACCOUNT_ID, {
      ...base,
      totalEquity: '5',
      timestamp: 2,
      unavailableDexs: ['xyz'],
      tradingAvailability: { isAvailable: false, reason: 'PerpsTradingUnavailable' },
    } as ApiPerpsSnapshot);

    expect(global.byAccountId[ACCOUNT_ID].perps!.snapshot).toMatchObject({
      totalEquity: '10',
      timestamp: 1,
      unavailableDexs: ['xyz'],
      tradingAvailability: { isAvailable: false, reason: 'PerpsTradingUnavailable' },
    });
  });
});

describe('updatePerpsMarketAsset', () => {
  it('puts the market of the detail into the catalogue and keeps its sparkline', () => {
    const btc = { id: 'btc', context: { markPx: '100' }, sparkline: [1, 2] } as unknown as ApiPerpsMarketAsset;
    const eth = { id: 'eth', context: { markPx: '10' } } as unknown as ApiPerpsMarketAsset;
    const global = updatePerpsMarket(INITIAL_STATE, buildPerpsMarketFixture([btc, eth]));

    const fresh = { ...btc, context: { ...btc.context, markPx: '101' }, sparkline: undefined };
    const updated = updatePerpsMarketAsset(global, fresh);

    expect(updated.perps.market!.assets).toEqual([{ ...fresh, sparkline: [1, 2] }, eth]);
    expect(updatePerpsMarketAsset(global, { ...btc, id: 'sol' })).toBe(global);
  });
});

describe('updatePerpsChart', () => {
  it('drops the oldest chart beyond 24 charts', () => {
    const periods: ApiPriceHistoryPeriod[] = ['1D', '7D', '1M', '3M', '1Y', 'ALL'];
    let global = INITIAL_STATE;
    for (let i = 0; i < 25; i++) {
      global = updatePerpsChart(global, `asset-${Math.floor(i / 6)}`, periods[i % 6], {
        points: [[1, 1]],
        fetchedAt: i + 1,
      });
    }

    const charts = Object.values(global.perps.chartsByAssetId).flatMap((byPeriod) => Object.values(byPeriod));
    expect(charts).toHaveLength(24);
    expect(global.perps.chartsByAssetId['asset-0']['1D']).toBeUndefined();
    expect(global.perps.chartsByAssetId['asset-4']['1D']).toBeDefined();
  });
});

describe('resetPerpsAccountScreens', () => {
  it('returns Futures to its home screen and closes the trade of the previous account', () => {
    let global = updatePerpsNavigation(INITIAL_STATE, { screen: 'position', assetId: 'hyperliquid:hl:BTC' });
    global = setPerpsTrade(global, {
      id: 'trade-1',
      kind: 'open',
      accountId: '0-mainnet',
      step: 'password',
      assetId: 'hyperliquid:hl:BTC',
      side: 'long',
      amount: '100',
      leverage: 2,
    });

    const { perps } = resetPerpsAccountScreens(global);
    expect(perps.navigation).toEqual({ screen: 'home' });
    expect(perps.trade).toBeUndefined();
  });

  it('keeps the state that is already on the home screen', () => {
    expect(resetPerpsAccountScreens(INITIAL_STATE)).toBe(INITIAL_STATE);
  });

  it('keeps the form that moved to the new account, and the market under it', () => {
    let global = updatePerpsNavigation(
      { ...INITIAL_STATE, currentAccountId: '1-mainnet' },
      { screen: 'market', assetId: 'hyperliquid:hl:BTC' },
    );
    global = setPerpsTrade(global, {
      id: 'trade-1',
      kind: 'open',
      accountId: '1-mainnet',
      step: 'selectAccount',
      assetId: 'hyperliquid:hl:BTC',
      side: 'long',
      amount: '',
      leverage: 2,
    });

    expect(resetPerpsAccountScreens(global)).toBe(global);
  });
});

describe('updatePerpsTrade', () => {
  const global = setPerpsTrade(INITIAL_STATE, {
    id: 'trade-1',
    kind: 'open',
    accountId: ACCOUNT_ID,
    step: 'form',
    assetId: 'hyperliquid:hl:BTC',
    side: 'long',
    amount: '5',
    leverage: 2,
    error: 'PerpsAmountTooSmall',
    errorDetails: { minimumAmount: '10' },
  });

  it('keeps the amounts of an error while the error stays', () => {
    expect(updatePerpsTrade(global, { isPreparing: true }).perps.trade?.errorDetails).toEqual({ minimumAmount: '10' });
  });

  it.each([
    ['another error', 'PerpsQuoteExpired'],
    ['no error', undefined],
  ])('drops the amounts of an error replaced by %s', (_, error) => {
    expect(updatePerpsTrade(global, { error }).perps.trade?.errorDetails).toBeUndefined();
  });
});

function buildFill(activityId: string | undefined, time: number, oid?: number) {
  return { activityId, time, coin: 'BTC', oid, feeToken: 'USDC' } as ApiPerpsFill;
}

function buildPage(fills: ApiPerpsFill[], nextCursor?: string) {
  return { fills, nextCursor } as ApiPerpsActivityHistory;
}

describe('restorePerpsReadCache', () => {
  const global = {
    ...INITIAL_STATE,
    accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: { arbitrum: { address: '0xfirst' } } } } },
  } as typeof INITIAL_STATE;
  const fill = { activityId: 'a', coin: 'BTC', time: 1, feeToken: 'USDC' } as ApiPerpsFill;

  it('restores the charts and the history', () => {
    const restored = restorePerpsReadCache(global, {
      chartsByAssetId: { btc: { '1D': { points: [[1, 2]], fetchedAt: 1 } } },
      historyByAccountId: { [ACCOUNT_ID]: { address: '0xfirst', fills: [fill], fetchedAt: 1 } },
    });

    expect(restored.perps.chartsByAssetId.btc?.['1D']?.points).toEqual([[1, 2]]);
    expect(restored.byAccountId[ACCOUNT_ID].perps?.history).toMatchObject({ fills: [fill], isRestored: true });
  });

  it('gives a saved history only to its wallet, not to a later wallet with the same account id', () => {
    const saved = buildPerpsReadCache(updateAccountPerps(global, ACCOUNT_ID, { history: { fills: [fill] } }));
    const laterWallet = {
      ...global,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: { arbitrum: { address: '0xsecond' } } } } },
    } as typeof INITIAL_STATE;

    expect(restorePerpsReadCache(global, saved).byAccountId[ACCOUNT_ID].perps?.history?.fills).toEqual([fill]);
    expect(restorePerpsReadCache(laterWallet, saved).byAccountId[ACCOUNT_ID]?.perps?.history).toBeUndefined();
  });

  it('takes the cursor of the first refresh of a restored history', () => {
    const merged = mergePerpsHistory(
      { fills: [], nextCursor: 'next', hasActivity: true } as ApiPerpsActivityHistory,
      { fills: [fill], isRestored: true },
    );

    expect(merged).toMatchObject({ fills: [fill], nextCursor: 'next' });
    expect(merged.isRestored).toBeUndefined();
  });
});

describe('updatePerpsOperation', () => {
  it('retains unresolved operations when pruning resolved history and isolates wallet state', () => {
    const states: ApiPerpsOperation['state'][] = ['running', 'partial', 'unknown'];
    const unresolved = states.map((state) => buildOperation(state, state));
    const completed = Array.from({ length: 25 }, (_, index) => buildOperation(String(index + 1), 'completed'));
    const global: GlobalState = {
      ...INITIAL_STATE,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
      byAccountId: {
        [ACCOUNT_ID]: {
          perpsOperations: Object.fromEntries([...unresolved, ...completed].map((value) => [value.id, value])),
        },
        other: { savedAddresses: [] },
      },
    };

    const updated = updatePerpsOperation(global, buildOperation('26', 'completed'));
    const retained = updated.byAccountId[ACCOUNT_ID].perpsOperations!;
    expect(Object.keys(retained)).toHaveLength(23);
    for (const operation of unresolved) expect(retained[operation.id]).toEqual(operation);
    expect(retained['1']).toBeUndefined();
    expect(updated.byAccountId.other).toBe(global.byAccountId.other);
    expect(updatePerpsOperation(updated, { ...unresolved[0], accountId: 'removed' })).toBe(updated);
  });
});

function buildOperation(id: string, state: ApiPerpsOperation['state']): ApiPerpsOperation {
  return { id, accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'reduce',
    state, stage: 'withdrawal', createdAt: Number(id) || 0 };
}
