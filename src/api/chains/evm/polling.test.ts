import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiNft,
  EVMChain,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { getChainConfig } from '../../../util/chain';
import { fetchEvmWallet } from './util/account';
import { NftStream } from './util/nftStream';
import { fetchStoredAddress } from '../../common/accounts';
import { applyPendingBalances, clearPendingBalances } from '../../common/pendingBalances';
import { balanceRefreshRequests } from '../../common/polling/balanceRefresh';
import { swapReplaceActivities } from '../../common/swap';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { MINUTE, SEC } from '../../constants';
import { initTransfer, submitTransfer } from '../../methods/transfer';
import chains from '../index';
import { getTokenActivitySlice } from './activities';
import { setupActivePolling } from './polling';
import { getIsWalletActive } from './wallet';

jest.mock('../index', () => ({
  __esModule: true,
  default: {
    arbitrum: {
      submitGasfullTransfer: jest.fn(),
      normalizeAddress: jest.fn((address: string) => address),
    },
  },
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredAddress: jest.fn(),
}));

jest.mock('../../methods/tokens', () => ({
  buildTokenSlug: jest.fn(),
}));

jest.mock('./util/account', () => ({
  fetchEvmWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId, activities) => Promise.resolve(activities)),
}));

jest.mock('../../common/tokens', () => ({
  sendUpdateTokens: jest.fn(),
}));

jest.mock('../../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId: string, activities: ApiActivity[]) => activities),
}));

jest.mock('../../common/txCallbacks', () => ({
  txCallbacks: { runCallbacks: jest.fn() },
}));

jest.mock('../../common/websocket/balanceStream', () => ({
  BalanceStream: jest.fn().mockImplementation(() => ({
    onUpdate: jest.fn(),
    onLoadingChange: jest.fn(),
    start: jest.fn(),
    destroy: jest.fn(),
    markWalletActiveAndForcePoll: jest.fn(),
  })),
}));

jest.mock('./activities', () => ({
  getTokenActivitySlice: jest.fn(),
}));

jest.mock('./util/nftStream', () => ({
  NftStream: jest.fn().mockImplementation(() => ({
    onUpdate: jest.fn(),
    destroy: jest.fn(),
    activate: jest.fn(),
  })),
}));

jest.mock('./util/socket', () => ({
  getAlchemySocket: jest.fn(() => ({
    watchWallets: jest.fn(() => ({ isConnected: false, destroy: jest.fn() })),
  })),
}));

jest.mock('./wallet', () => ({
  fetchAccountAssets: jest.fn(),
  fetchCrosschainAccountAssets: jest.fn(),
  getIsWalletActive: jest.fn(),
}));

const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';
const NEWEST_ACTIVITY_TIMESTAMP = 1_773_000_000_000;
const LATE_ACTIVITY = {
  id: '0xlate-indexed',
  timestamp: NEWEST_ACTIVITY_TIMESTAMP + SEC,
  kind: 'transaction',
  slug: getChainConfig('bnb').nativeToken.slug,
} as ApiActivity;
const FAST_CATCH_UP_DURATION = 59 * 2 * SEC;
const CATCH_UP_TAIL_DELAYS = [
  30 * SEC, MINUTE, 2 * MINUTE, 4 * MINUTE, 8 * MINUTE, ...Array<number>(11).fill(15 * MINUTE),
];

const mockedFetchEvmWallet = jest.mocked(fetchEvmWallet);
const mockedGetIsWalletActive = jest.mocked(getIsWalletActive);
const mockedSwapReplaceActivities = jest.mocked(swapReplaceActivities);
const mockedGetTokenActivitySlice = jest.mocked(getTokenActivitySlice);
const MockedBalanceStream = jest.mocked(BalanceStream);
const MockedNftStream = jest.mocked(NftStream);
const pollingCleanups: NoneToVoidFunction[] = [];

type MockedBalanceStreamInstance = jest.Mocked<{
  onUpdate: jest.Mock;
  onLoadingChange: jest.Mock;
  start: jest.Mock;
  destroy: jest.Mock;
  markWalletActiveAndForcePoll: jest.Mock;
}>;

function getBalanceStreamInstance() {
  return MockedBalanceStream.mock.results[0].value as MockedBalanceStreamInstance;
}

function getNftStreamInstance() {
  return MockedNftStream.mock.results[0].value as jest.Mocked<{
    onUpdate: jest.Mock;
    destroy: jest.Mock;
    activate: jest.Mock;
  }>;
}

type ApiUpdatePayload = Parameters<OnApiUpdate>[0];
type InitialActivitiesUpdate = Extract<ApiUpdatePayload, { type: 'initialActivities' }>;

function getInitialActivitiesUpdate(onUpdate: OnApiUpdate) {
  return (onUpdate as jest.Mock).mock.calls
    .map((call) => call[0] as ApiUpdatePayload)
    .find((update): update is InitialActivitiesUpdate => update.type === 'initialActivities');
}

// The catch-up chain awaits several mocked async hops (stored wallet, activity slice, swap merge)
// before dispatching; drain enough microtasks that the assertions see the settled result.
async function flushPromises(count = 10) {
  for (let i = 0; i < count; i++) {
    await Promise.resolve();
  }
}

afterEach(() => {
  for (const stop of pollingCleanups) {
    stop();
  }
  pollingCleanups.length = 0;
});

function startActivePolling<C extends EVMChain>(...args: Parameters<typeof setupActivePolling<C>>) {
  const stop = setupActivePolling(...args);
  pollingCleanups.push(stop);
  return stop;
}

describe('EVM polling', () => {
  it('refreshes the requested wallet and stops listening when its stream is removed', () => {
    const account = { type: 'view', byChain: { bnb: { address: ADDRESS, index: 0 } } } as ApiAccountWithChain<'bnb'>;
    const stop = startActivePolling('bnb', 'perps-refresh-mainnet', account, jest.fn(), jest.fn(), {});
    const stream = getBalanceStreamInstance();
    balanceRefreshRequests.runCallbacks('other-mainnet', 'bnb');
    balanceRefreshRequests.runCallbacks('perps-refresh-mainnet', 'arbitrum');
    expect(stream.markWalletActiveAndForcePoll).not.toHaveBeenCalled();
    balanceRefreshRequests.runCallbacks('perps-refresh-mainnet', 'bnb');
    expect(stream.markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
    stop();
    balanceRefreshRequests.runCallbacks('perps-refresh-mainnet', 'bnb');
    expect(stream.markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // `clearAllMocks` keeps implementations, so one test's history response would answer the next test's catch-up
    mockedGetTokenActivitySlice.mockReset().mockResolvedValue({ activities: [], hasMore: false });
    mockedFetchEvmWallet.mockResolvedValue({ address: ADDRESS, index: 0 });
    // The cases below all describe an address that has history to load, so the cheap
    // has-anything-happened-here probe answers yes; the case that answers no is its own test.
    mockedGetIsWalletActive.mockResolvedValue(true);
  });

  it('keeps a sent cross-chain balance deducted through stale socket and poll snapshots', async () => {
    jest.useFakeTimers();
    const accountId = 'pending-stream-mainnet';
    const ethereumSlug = getChainConfig('ethereum').nativeToken.slug;
    const arbitrumSlug = getChainConfig('arbitrum').nativeToken.slug;
    const onUpdate = jest.fn<void, Parameters<OnApiUpdate>>();
    const account: ApiAccountWithChain<'ethereum'> = {
      type: 'bip39', byChain: { ethereum: { address: ADDRESS, index: 0 } },
    };
    jest.mocked(fetchStoredAddress).mockResolvedValue(ADDRESS);
    jest.mocked(chains.arbitrum.submitGasfullTransfer).mockResolvedValue({ txId: '0xsent' });
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [], hasMore: false });
    initTransfer(onUpdate);
    const stop = startActivePolling('ethereum', accountId, account, (update) => {
      onUpdate(update.type === 'updateBalances' ? applyPendingBalances(update) : update);
    }, jest.fn(), { [ethereumSlug]: 1000 });
    const emit = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>, source: 'poll' | 'socket',
    ) => void;
    const observed = { [ethereumSlug]: 5000n, [arbitrumSlug]: 1000n };

    try {
      emit(observed, 'poll');
      await submitTransfer('arbitrum', {
        accountId, toAddress: '0x0000000000000000000000000000000000000001', amount: 200n, realFee: 10n,
      });
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'updateBalances', accountId, chain: 'arbitrum', balances: { [arbitrumSlug]: 790n },
      });

      for (const source of ['socket', 'poll'] as const) {
        onUpdate.mockClear();
        emit(observed, source);
        await flushPromises();
        expect(onUpdate).toHaveBeenCalledWith({
          type: 'updateBalances', accountId, chain: 'arbitrum', balances: { [arbitrumSlug]: 790n },
        });
        expect(onUpdate).toHaveBeenCalledWith({
          type: 'updateBalances', accountId, chain: 'ethereum', balances: { [ethereumSlug]: 5000n },
        });
      }

      onUpdate.mockClear();
      emit({ [arbitrumSlug]: 950n }, 'socket');
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'updateBalances', accountId, chain: 'arbitrum', balances: { [arbitrumSlug]: 950n },
      });
    } finally {
      stop();
      clearPendingBalances(accountId);
      jest.clearAllTimers();
      jest.useRealTimers();
    }
  });

  it('keeps active forced polling at 3 minutes focused and 10 minutes unfocused', async () => {
    mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [], hasMore: false });
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    const stop = startActivePolling('bnb', '0-mainnet', account, jest.fn(), jest.fn(), {});

    expect(MockedBalanceStream).toHaveBeenCalledWith(expect.objectContaining({
      fallbackPollingOptions: expect.objectContaining({
        forcedPollingPeriod: { focused: 3 * MINUTE, notFocused: 10 * MINUTE },
      }),
    }));

    await flushPromises();
    stop();
  });

  it('skips the initial history load for an address with nothing on this chain', async () => {
    // The whole point of the gate: an account holds every EVM chain but uses none of them, and
    // each unused chain would otherwise pay a history call on every launch.
    mockedGetIsWalletActive.mockResolvedValue(false);

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();

    expect(mockedGetTokenActivitySlice).not.toHaveBeenCalled();
    // The feed blocks on `areInitialActivitiesLoaded[chain]`, so the empty result still has to
    // be dispatched - skipping the fetch must not turn into skipping the update.
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'initialActivities',
      chain: 'bnb',
      accountId: '0-mainnet',
      mainActivities: [],
      bySlug: {},
    }));
  });

  // The skip has to declare the history finished. Without the flag the reducer leaves the
  // chain's end state undefined, which reads as "still loading" and sends the UI to
  // `fetchPastActivities` - the same paid history call the skip exists to avoid, one step later.
  it('marks the skipped history as finished so the feed does not paginate for more', async () => {
    mockedGetIsWalletActive.mockResolvedValue(false);

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();

    expect(getInitialActivitiesUpdate(onUpdate)?.mainHistoryHasMore).toBe(false);
  });

  // The failure path emits the same empty shape deliberately WITHOUT the flag: a failed attempt
  // learned nothing about whether history exists, and claiming the end was reached would hide a
  // real feed behind an empty state until something else forced a reload.
  it('leaves the history open when the initial load fails', async () => {
    mockedGetTokenActivitySlice.mockRejectedValue(new Error('history down'));

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();

    expect(getInitialActivitiesUpdate(onUpdate)?.mainHistoryHasMore).toBeUndefined();
  });

  // A probe that cannot answer must not be read as "no history". Its RPC provider is separate
  // from the history provider, so an outage there says nothing about what the feed should show.
  it('loads the initial history anyway when the activity probe fails', async () => {
    mockedGetIsWalletActive.mockRejectedValue(new Error('rpc down'));
    const activity = {
      id: '0xkept',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: getChainConfig('bnb').nativeToken.slug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();

    expect(mockedGetTokenActivitySlice).toHaveBeenCalled();
    expect(getInitialActivitiesUpdate(onUpdate)?.mainActivities).toEqual([activity]);
  });

  it('loads the initial history anyway when a socket event contradicts the skip', async () => {
    // A socket event is evidence that something landed on chain, which outranks a probe taken
    // before it. Without this the first funds an address ever receives would leave the feed
    // empty until the verdict expires.
    mockedGetIsWalletActive.mockResolvedValue(false);
    const activity = { id: '0xfirst', timestamp: 1_773_000_000_000 } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();
    expect(mockedGetTokenActivitySlice).not.toHaveBeenCalled();

    const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>,
      source: 'poll' | 'socket',
    ) => void;
    balanceUpdate({ bnb: 1n }, 'socket');
    await flushPromises();

    expect(mockedGetTokenActivitySlice).toHaveBeenCalled();
  });

  it('forces balance polling when initial activity catch-up finds an EVM transaction', async () => {
    const activity = {
      id: '0xactivity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: getChainConfig('bnb').nativeToken.slug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    expect(MockedBalanceStream).toHaveBeenCalledTimes(1);
    expect(MockedNftStream).toHaveBeenCalledTimes(1);
    await flushPromises();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'initialActivities',
      chain: 'bnb',
      accountId: '0-mainnet',
      mainActivities: [activity],
    }));
  });

  it('records the newest-activity timestamp by emitting the native-token slice in the initial dispatch', async () => {
    // Regression guard: an empty `bySlug` would leave `newestActivitiesBySlug` unset, so the next
    // launch would re-run the timestamp-less initial fetch instead of an incremental one.
    const nativeSlug = getChainConfig('bnb').nativeToken.slug;
    const activity = {
      id: '0xactivity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: nativeSlug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'initialActivities',
      chain: 'bnb',
      bySlug: { [nativeSlug]: [activity] },
    }));
  });

  it('emits an empty bySlug for a wallet with no activity so the reducer dedup guard holds', async () => {
    // An empty wallet keeps `newestConfirmedActivityTimestamp` undefined and re-runs the initial
    // load on every catch-up; a `{ [nativeSlug]: [] }` payload would have one key and defeat the
    // reducer's empty-update short-circuit (which requires zero keys), re-rendering on every poll.
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    expect(getInitialActivitiesUpdate(onUpdate)?.bySlug).toEqual({});
  });

  it('omits the native slug when the initial page has no native-coin activity', async () => {
    // A token-only first page must not write a native key: an empty native slice would both leave
    // the persisted marker unset (so the timestamp-less fetch repeats next launch) and falsely mark
    // the native history as fully loaded.
    const nativeSlug = getChainConfig('bnb').nativeToken.slug;
    const tokenSlug = 'bnb-0xtoken';
    const activity = {
      id: '0xtoken-activity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: tokenSlug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    const update = getInitialActivitiesUpdate(onUpdate);
    expect(update?.bySlug).toEqual({ [tokenSlug]: [activity] });
    expect(update?.bySlug).not.toHaveProperty(nativeSlug);
  });

  it('records the newest timestamp per slug when the feed mixes native and token activities', async () => {
    const nativeSlug = getChainConfig('bnb').nativeToken.slug;
    const tokenSlug = 'bnb-0xtoken';
    const tokenActivity = {
      id: '0xtoken-activity',
      timestamp: 1_773_000_010_000,
      kind: 'transaction',
      slug: tokenSlug,
    } as ApiActivity;
    const nativeActivity = {
      id: '0xnative-activity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: nativeSlug,
    } as ApiActivity;
    // `getTokenActivitySlice` returns activities sorted newest-first.
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [tokenActivity, nativeActivity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    expect(getInitialActivitiesUpdate(onUpdate)?.bySlug).toEqual({
      [tokenSlug]: [tokenActivity],
      [nativeSlug]: [nativeActivity],
    });
  });

  it('merges cross-chain CEX swaps via swapReplaceActivities before building the initial feed', async () => {
    const activity = {
      id: '0xactivity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: getChainConfig('bnb').nativeToken.slug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    expect(mockedSwapReplaceActivities).toHaveBeenCalledWith('0-mainnet', [activity], undefined, true);
  });

  it('keeps the polling cursor on the raw on-chain slice, not a newer merged CEX swap', async () => {
    // Regression guard for the cursor-overshoot: a merged CEX swap can carry a backend timestamp
    // newer than the on-chain leg. The next poll's min_mined_at must come from the raw leg, otherwise
    // an on-chain tx whose timestamp falls between the leg and the swap is skipped forever.
    const nativeSlug = getChainConfig('bnb').nativeToken.slug;
    const startTimestamp = 1_773_000_000_000;
    const onChainLeg = {
      id: '0xleg',
      timestamp: 1_773_000_010_000,
      kind: 'transaction',
      slug: nativeSlug,
    } as ApiActivity;
    const mergedSwap = {
      id: 'backend-swap',
      timestamp: 1_773_000_020_000, // newer than the on-chain leg
      kind: 'swap',
      from: nativeSlug,
      to: 'ton-toncoin',
    } as ApiActivity;

    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [onChainLeg], hasMore: false });
    // swapReplaceActivities prepends the newer swap ahead of the raw leg (sorted newest-first).
    mockedSwapReplaceActivities.mockResolvedValueOnce([mergedSwap, onChainLeg]);

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, { bnb: startTimestamp });

    const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>,
      source: 'poll' | 'socket',
    ) => void;

    balanceUpdate({ bnb: 1n }, 'poll');
    await flushPromises();

    // The merged swap is shown in the feed...
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newActivities',
      chain: 'bnb',
      activities: [mergedSwap, onChainLeg],
    }));

    // ...but the cursor stays on the raw leg, so the next poll resumes from it, not the swap.
    balanceUpdate({ bnb: 2n }, 'poll');
    await flushPromises();

    const lastSliceCall = mockedGetTokenActivitySlice.mock.calls.at(-1)!;
    expect(lastSliceCall[5]).toBe(onChainLeg.timestamp);
  });

  it('falls back to a native-token timestamp when the initial page is NFT-only', async () => {
    const nftActivity = {
      id: '0xnft-activity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: 'bnb-0xnft-collection',
      nft: {} as ApiNft,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [nftActivity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

    await flushPromises();

    // NFT-only page: bySlug stays empty, so the native history isn't falsely marked as loaded.
    expect(getInitialActivitiesUpdate(onUpdate)?.bySlug).toEqual({});

    // The newest-activity marker is still set from the fallback, so the next catch-up polls
    // incrementally (`since` defined) instead of repeating the full initial load (`since` undefined).
    const newActivity = {
      id: '0xnew-activity',
      timestamp: 1_773_000_010_000,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [newActivity], hasMore: false });

    const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>,
      source: 'poll' | 'socket',
    ) => void;
    balanceUpdate({ bnb: 1n }, 'poll');

    await flushPromises();

    expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(2);
    expect(mockedGetTokenActivitySlice.mock.calls[1][5]).toBe(nftActivity.timestamp);
  });

  it('forces balance polling when balance updates trigger catch-up that finds a new EVM transaction', async () => {
    const activity = {
      id: '0xnew-activity',
      timestamp: 1_773_000_010_000,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValue({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: {
        bnb: { address: ADDRESS, index: 0 },
      },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, { bnb: 1_773_000_000_000 });

    const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
      balances: Record<string, bigint>,
      source: 'poll' | 'socket',
    ) => void;
    balanceUpdate({ bnb: 1n }, 'poll');

    await flushPromises();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newActivities',
      chain: 'bnb',
      accountId: '0-mainnet',
      activities: [activity],
    }));
  });

  it('wakes the NFT stream when initial activity catch-up finds an EVM transaction', async () => {
    const activity = {
      id: '0xactivity',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: getChainConfig('bnb').nativeToken.slug,
    } as ApiActivity;
    mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [activity], hasMore: false });
    const account = { type: 'view', byChain: { bnb: { address: ADDRESS, index: 0 } } } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, jest.fn(), jest.fn(), {});
    await flushPromises();

    expect(getNftStreamInstance().activate).toHaveBeenCalledTimes(1);
  });

  it('forces balance polling when an NFT arrives on a skipped chain', async () => {
    mockedGetIsWalletActive.mockResolvedValue(false);

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
    await flushPromises();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).not.toHaveBeenCalled();

    const nftUpdate = getNftStreamInstance().onUpdate.mock.calls[0][0] as (params: {
      direction: 'receive';
      nft: ApiNft;
      nftAddress: string;
    }) => void;
    nftUpdate({
      direction: 'receive',
      nft: { address: '0xnft' } as ApiNft,
      nftAddress: '0xnft',
    });
    await flushPromises();

    expect(getBalanceStreamInstance().markWalletActiveAndForcePoll).toHaveBeenCalledTimes(1);
  });

  it('retries the socket-triggered history load when the indexer has not caught up', async () => {
    jest.useFakeTimers();
    mockedGetIsWalletActive.mockResolvedValue(false);
    const activity = {
      id: '0xfirst',
      timestamp: 1_773_000_000_000,
      kind: 'transaction',
      slug: getChainConfig('bnb').nativeToken.slug,
    } as ApiActivity;
    mockedGetTokenActivitySlice
      .mockResolvedValueOnce({ activities: [], hasMore: false })
      .mockResolvedValueOnce({ activities: [activity], hasMore: false });

    const onUpdate = jest.fn() as OnApiUpdate;
    const onUpdatingStatusChange = jest.fn() as OnUpdatingStatusChange;
    const account = {
      type: 'view',
      byChain: { bnb: { address: ADDRESS, index: 0 } },
    } as ApiAccountWithChain<'bnb'>;

    try {
      startActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});
      await jest.advanceTimersByTimeAsync(1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).not.toHaveBeenCalled();

      const balanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0] as (
        balances: Record<string, bigint>,
        source: 'poll' | 'socket',
      ) => void;
      balanceUpdate({ bnb: 1n }, 'socket');
      await flushPromises();

      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(1);

      await jest.advanceTimersByTimeAsync(2000);
      await flushPromises();

      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(2);
      expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
        type: 'initialActivities',
        chain: 'bnb',
        accountId: '0-mainnet',
        mainActivities: [activity],
      }));
    } finally {
      jest.useRealTimers();
    }
  });

  describe('balance-triggered history catch-up tail', () => {
    let stop: NoneToVoidFunction;
    let onUpdate: jest.Mock<void, Parameters<OnApiUpdate>>;
    let emitBalanceUpdate: (balances: Record<string, bigint>, source: 'poll' | 'socket') => void;

    beforeEach(() => {
      jest.useFakeTimers();
      onUpdate = jest.fn();
      const account: ApiAccountWithChain<'bnb'> = {
        type: 'view', byChain: { bnb: { address: ADDRESS, index: 0 } },
      };
      stop = startActivePolling('bnb', '0-mainnet', account, onUpdate, jest.fn(), {
        [getChainConfig('bnb').nativeToken.slug]: NEWEST_ACTIVITY_TIMESTAMP,
      });
      emitBalanceUpdate = getBalanceStreamInstance().onUpdate.mock.calls[0][0];
    });

    afterEach(() => {
      try {
        stop();
      } finally {
        jest.clearAllTimers();
        jest.useRealTimers();
      }
    });

    it.each([
      { tailDelay: 30 * SEC, attempt: 61 },
      { tailDelay: 60.5 * MINUTE, attempt: 68 },
    ])('finds indexed activity after $tailDelay ms of the socket tail', async ({ tailDelay, attempt }) => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(60);

      await jest.advanceTimersByTimeAsync(tailDelay - 1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(attempt - 1);

      const activity = {
        id: '0xlate-indexed',
        timestamp: NEWEST_ACTIVITY_TIMESTAMP + SEC,
        kind: 'transaction',
        slug: getChainConfig('bnb').nativeToken.slug,
      } as ApiActivity;
      mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [activity], hasMore: false });
      await jest.advanceTimersByTimeAsync(1);
      await flushPromises();

      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(attempt);
      expect(mockedGetTokenActivitySlice.mock.calls.at(-1)![5]).toBe(NEWEST_ACTIVITY_TIMESTAMP);
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'newActivities', chain: 'bnb', accountId: '0-mainnet', activities: [activity],
      });

      await jest.advanceTimersByTimeAsync(4 * 60 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(attempt);
    });

    it('exhausts exactly 60 fast and 16 slow attempts when no activity is indexed', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(60);

      for (const delay of CATCH_UP_TAIL_DELAYS) {
        const previousCalls = mockedGetTokenActivitySlice.mock.calls.length;
        await jest.advanceTimersByTimeAsync(delay - 1);
        await flushPromises();
        expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(previousCalls);

        await jest.advanceTimersByTimeAsync(1);
        await flushPromises();
        expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(previousCalls + 1);
      }
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(76);

      await jest.advanceTimersByTimeAsync(4 * 60 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(76);
    });

    it('cancels the old tail when another socket balance event starts a new catch-up', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION + 15.5 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(65);

      await jest.advanceTimersByTimeAsync(MINUTE);
      await flushPromises();
      emitBalanceUpdate({ bnb: 2n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION + 7.5 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(129);

      // The old tail is due in this window while the new catch-up is in its eight-minute pause
      await jest.advanceTimersByTimeAsync(5 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(129);

      await jest.advanceTimersByTimeAsync(3 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(130);
    });

    it('stops the tail during its fifteen-minute pause when active polling is cleaned up', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION + 15.5 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(65);

      stop();
      await jest.advanceTimersByTimeAsync(4 * 60 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(65);
    });

    it('makes only one history request for a poll balance event', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'poll');
      await jest.advanceTimersByTimeAsync(3 * 60 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(1);
    });

    it('keeps the socket tail running when a poll balance event finds nothing', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION + 30 * SEC);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(61);

      emitBalanceUpdate({ bnb: 2n }, 'poll');
      await jest.advanceTimersByTimeAsync(1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(62);

      mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [LATE_ACTIVITY], hasMore: false });
      await jest.advanceTimersByTimeAsync(MINUTE - 1);
      await flushPromises();

      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(63);
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'newActivities', chain: 'bnb', accountId: '0-mainnet', activities: [LATE_ACTIVITY],
      });
    });

    it('stops the socket tail when a poll balance event finds the activity', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION + 30 * SEC);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(61);

      mockedGetTokenActivitySlice.mockResolvedValueOnce({ activities: [LATE_ACTIVITY], hasMore: false });
      emitBalanceUpdate({ bnb: 2n }, 'poll');
      await jest.advanceTimersByTimeAsync(1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(62);
      expect(onUpdate).toHaveBeenCalledWith({
        type: 'newActivities', chain: 'bnb', accountId: '0-mainnet', activities: [LATE_ACTIVITY],
      });

      await jest.advanceTimersByTimeAsync(4 * 60 * MINUTE);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(62);
    });

    it('continues the tail on schedule after a history request fails', async () => {
      emitBalanceUpdate({ bnb: 1n }, 'socket');
      await jest.advanceTimersByTimeAsync(FAST_CATCH_UP_DURATION);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(60);

      mockedGetTokenActivitySlice.mockRejectedValueOnce(new Error('Indexer unavailable'));
      await jest.advanceTimersByTimeAsync(30 * SEC);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(61);

      await jest.advanceTimersByTimeAsync(MINUTE - 1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(61);

      await jest.advanceTimersByTimeAsync(1);
      await flushPromises();
      expect(mockedGetTokenActivitySlice).toHaveBeenCalledTimes(62);
    });
  });
});
