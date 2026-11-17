import type {
  ApiPerpsAccountPosition,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsSnapshot,
} from '../../api/types';
import type { GlobalState, PerpsAccountSnapshot } from '../types';

import * as config from '../../config';
import { buildPerpsMarketFixture } from '../../../tests/helpers/perpsMarket';
import { INITIAL_STATE } from '../initialState';
import { updateAccountPerps, updatePerpsMarket, updatePerpsSnapshot } from '../reducers/perps';
import {
  isPerpsSnapshotStale,
  selectCanReadPerps,
  selectHasOtherPerpsAccount,
  selectIsPerpsOnboardingExpected,
  selectPerpsBannerOperation,
  selectPerpsMarketAssetsById,
  selectPerpsTradeBlockReason,
  selectPerpsUnavailableReason,
  selectShouldShowPerpsOnboarding,
} from './perps';

jest.mock('../../config', () => ({
  __esModule: true,
  ...jest.requireActual('../../config'),
  IS_PERPS_SUPPORTED: true,
}));

const ACCOUNT_ID = '0-mainnet';
const BTC_ID = 'hyperliquid:hl:BTC';
const ETH_ID = 'hyperliquid:hl:ETH';

describe('selectCanReadPerps and selectPerpsTradeBlockReason', () => {
  it.each([
    { name: 'a software wallet', canRead: true, canTrade: true },
    { name: 'testnet', isTestnet: true, canRead: false, canTrade: false },
    { name: 'an account without an Arbitrum address', hasArbitrum: false, canRead: false, canTrade: false },
    { name: 'a view-only or Ledger account', isTradingAvailable: false, canRead: true, canTrade: false },
    { name: 'an account before its snapshot loads', hasSnapshot: false, canRead: true, canTrade: false },
  ])('$name: reads $canRead, trades $canTrade', ({
    canRead, canTrade, ...params
  }) => {
    const global = buildGlobal(params);

    expect(selectCanReadPerps(global)).toBe(canRead);
    expect(selectPerpsTradeBlockReason(global, BTC_ID) === undefined).toBe(canTrade);
  });

  it('reads nothing in a build without Perps', () => {
    const unsupported = jest.replaceProperty(config, 'IS_PERPS_SUPPORTED', false);
    try {
      expect(selectCanReadPerps(buildGlobal())).toBe(false);
    } finally {
      unsupported.restore();
    }
  });
});

describe('selectPerpsTradeBlockReason', () => {
  it('lets a tradable market through', () => {
    expect(selectPerpsTradeBlockReason(buildGlobal(), BTC_ID)).toBeUndefined();
  });

  it('gives the account reason first', () => {
    expect(selectPerpsTradeBlockReason(buildGlobal({ isTradingAvailable: false }), BTC_ID))
      .toBe('PerpsUnsupportedAccount');
  });

  it('gives the market reason for a market that cannot be traded', () => {
    expect(selectPerpsTradeBlockReason(buildGlobal(), ETH_ID)).toBe('PerpsTradingUnavailable');
  });

  it.each<[string, Partial<ApiPerpsOperation>, string | undefined]>([
    ['a running operation', { state: 'running' }, 'PerpsOperationPending'],
    ['an unknown outcome', { state: 'unknown' }, 'PerpsOperationPending'],
    ['an acknowledged unknown outcome', { state: 'unknown', acknowledgedAt: 1 }, undefined],
    ['a completed operation', { state: 'completed' }, undefined],
  ])('treats %s as blocking: %s', (_, operation, reason) => {
    expect(selectPerpsTradeBlockReason(buildGlobal({ operations: [operation] }), BTC_ID)).toBe(reason);
  });

  it('lets a filled close waiting for its withdrawal through for a reduce of another market', () => {
    const global = buildGlobal({
      operations: [{
        state: 'partial', kind: 'close', assetId: ETH_ID, orderStatus: 'filled', orderId: 1,
      }],
    });

    expect(selectPerpsTradeBlockReason(global, BTC_ID, 'reduce')).toBeUndefined();
    expect(selectPerpsTradeBlockReason(global, BTC_ID, 'open')).toBe('PerpsOperationPending');
  });
});

describe('selectHasOtherPerpsAccount', () => {
  const byChain = { arbitrum: { address: '0x2' } };

  it.each([
    ['no other wallet', {}, false],
    ['another wallet that can trade', { '1-mainnet': { type: 'mnemonic', byChain } }, true],
    ['another wallet that is view-only', { '1-mainnet': { type: 'view', byChain } }, false],
    ['a wallet of the other network', { '1-testnet': { type: 'mnemonic', byChain } }, false],
  ])('%s', (_, otherAccounts, expected) => {
    const global = buildGlobal();

    expect(selectHasOtherPerpsAccount({
      ...global,
      accounts: { ...global.accounts!, byId: { ...global.accounts!.byId, ...otherAccounts } },
    } as GlobalState)).toBe(expected);
  });
});

describe('selectPerpsBannerOperation', () => {
  it('skips an operation whose banner the user hid until its state changes', () => {
    const global = buildGlobal({ operations: [{ id: 'op-1', state: 'unknown' }] });

    expect(selectPerpsBannerOperation(global)?.id).toBe('op-1');
    expect(selectPerpsBannerOperation({
      ...global,
      perps: { ...global.perps, hiddenOperationStates: { 'op-1': 'unknown' } },
    })).toBeUndefined();
    expect(selectPerpsBannerOperation({
      ...global,
      perps: { ...global.perps, hiddenOperationStates: { 'op-1': 'running' } },
    })?.id).toBe('op-1');
  });
});

describe('selectPerpsUnavailableReason', () => {
  it.each([
    { name: 'a software wallet', expected: undefined },
    { name: 'an account without an Arbitrum address', hasArbitrum: false, expected: 'PerpsRequiresMultichainWallet' },
    {
      name: 'a viewed wallet without an Arbitrum address',
      hasArbitrum: false,
      isViewAccount: true,
      expected: 'PerpsRequiresOwnWallet',
    },
    { name: 'testnet', isTestnet: true, expected: 'PerpsUnsupportedAccount' },
  ])('$name: $expected', ({ name: _, expected, ...params }) => {
    expect(selectPerpsUnavailableReason(buildGlobal(params))).toBe(expected);
  });
});

describe('selectShouldShowPerpsOnboarding', () => {
  it('shows onboarding to an account with no positions that has never traded', () => {
    expect(selectShouldShowPerpsOnboarding(buildGlobal({ positions: [], hasActivityHistory: false }))).toBe(true);
  });

  it.each([
    ['the history has not loaded', { positions: [] }],
    ['the account has traded', { positions: [], hasActivityHistory: true }],
    ['a position is open', { hasActivityHistory: false }],
    ['a trade is pending', { positions: [], hasActivityHistory: false, operations: [{ state: 'running' as const }] }],
    ['a trade of this session has completed', {
      positions: [], hasActivityHistory: false, operations: [{ state: 'completed' as const }],
    }],
    ['the user closed it', { positions: [], hasActivityHistory: false, dismissedHomeBannerIds: ['perps-onboarding'] }],
  ])('hides onboarding when %s', (_, params) => {
    expect(selectShouldShowPerpsOnboarding(buildGlobal(params))).toBe(false);
  });

  it('expects onboarding before the first snapshot only once the history loads', () => {
    expect(selectIsPerpsOnboardingExpected(buildGlobal({ hasSnapshot: false, hasActivityHistory: false }))).toBe(true);
    expect(selectIsPerpsOnboardingExpected(buildGlobal({ hasSnapshot: false }))).toBe(false);
  });

  it('keeps onboarding after a withdrawal from the balance, which is not a trade', () => {
    expect(selectShouldShowPerpsOnboarding(buildGlobal({
      positions: [], hasActivityHistory: false, operations: [{ kind: 'withdraw', state: 'completed' }],
    }))).toBe(true);
  });

  it('hides onboarding while a withdrawal from the balance is pending', () => {
    expect(selectShouldShowPerpsOnboarding(buildGlobal({
      positions: [], hasActivityHistory: false, operations: [{ kind: 'withdraw', state: 'running' }],
    }))).toBe(false);
  });
});

describe('isPerpsSnapshotStale', () => {
  const snapshot = { positions: [], unavailableDexs: [] } as unknown as PerpsAccountSnapshot;

  it('treats positions as fresh for a minute after a complete read', () => {
    expect(isPerpsSnapshotStale({ ...snapshot, timestamp: Date.now() - 30_000 })).toBe(false);
    expect(isPerpsSnapshotStale({ ...snapshot, timestamp: Date.now() - 61_000 })).toBe(true);
  });

  it('treats a read that missed a book as stale at once', () => {
    expect(isPerpsSnapshotStale({ ...snapshot, timestamp: Date.now(), unavailableDexs: ['xyz'] })).toBe(true);
  });
});

describe('selectPerpsMarketAssetsById', () => {
  it('returns the same object while the catalogue stays the same', () => {
    const global = buildGlobal();

    expect(selectPerpsMarketAssetsById({ ...global, isFuturesOpen: true })).toBe(selectPerpsMarketAssetsById(global));
  });
});

function buildGlobal({
  isTestnet = false,
  hasArbitrum = true,
  isViewAccount = false,
  hasSnapshot = true,
  isTradingAvailable = true,
  positions = [buildPosition(BTC_ID)],
  operations = [],
  hasActivityHistory,
  dismissedHomeBannerIds,
}: {
  isTestnet?: boolean;
  hasArbitrum?: boolean;
  isViewAccount?: boolean;
  hasSnapshot?: boolean;
  isTradingAvailable?: boolean;
  positions?: ApiPerpsAccountPosition[];
  operations?: Partial<ApiPerpsOperation>[];
  hasActivityHistory?: boolean;
  dismissedHomeBannerIds?: string[];
} = {}): GlobalState {
  let global: GlobalState = {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: {
      byId: {
        [ACCOUNT_ID]: {
          type: isViewAccount ? 'view' : 'mnemonic',
          byChain: {
            ton: { address: 'ton-address' },
            ...(hasArbitrum && { arbitrum: { address: '0x1' } }),
          },
        },
      },
    },
    settings: { ...INITIAL_STATE.settings, isTestnet, byAccountId: { [ACCOUNT_ID]: { dismissedHomeBannerIds } } },
    byAccountId: {
      [ACCOUNT_ID]: {
        perpsOperations: Object.fromEntries(operations.map((operation, index) => {
          const id = operation.id ?? `op-${index}`;
          return [id, {
            id,
            accountId: ACCOUNT_ID,
            assetId: BTC_ID,
            kind: 'open',
            state: 'running',
            stage: 'preparing',
            createdAt: index,
            ...operation,
          } as ApiPerpsOperation];
        })),
      },
    },
  };

  global = updatePerpsMarket(global, buildPerpsMarketFixture([
    buildAsset(BTC_ID, true),
    buildAsset(ETH_ID, false),
  ]));

  if (hasSnapshot) {
    global = updatePerpsSnapshot(global, ACCOUNT_ID, {
      ...buildPerpsMarketFixture(),
      positions,
      totalEquity: '0',
      totalPnl: '0',
      timestamp: 1,
      unavailableDexs: [],
      tradingAvailability: isTradingAvailable
        ? { isAvailable: true }
        : { isAvailable: false, reason: 'PerpsUnsupportedAccount' },
    } as ApiPerpsSnapshot);
  }

  return updateAccountPerps(global, ACCOUNT_ID, { hasActivityHistory });
}

function buildAsset(id: string, isAvailable: boolean) {
  return {
    id,
    tradingAvailability: isAvailable ? { isAvailable } : { isAvailable, reason: 'PerpsTradingUnavailable' },
  } as ApiPerpsMarketAsset;
}

function buildPosition(assetId: string) {
  return { id: `${ACCOUNT_ID}/${assetId}`, assetId } as ApiPerpsAccountPosition;
}
