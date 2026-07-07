import type { ApiAccountWithChain, ApiActivity, ApiNft, OnApiUpdate, OnUpdatingStatusChange } from '../../types';

import { getChainConfig } from '../../../util/chain';
import { NftStream } from './util/nftStream';
import { fetchStoredWallet } from '../../common/accounts';
import { swapReplaceActivities } from '../../common/swap';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { getTokenActivitySlice } from './activities';
import { setupActivePolling } from './polling';

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId, activities) => Promise.resolve(activities)),
}));

jest.mock('../../common/tokens', () => ({
  sendUpdateTokens: jest.fn(),
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

const mockedFetchStoredWallet = jest.mocked(fetchStoredWallet);
const mockedSwapReplaceActivities = jest.mocked(swapReplaceActivities);
const mockedGetTokenActivitySlice = jest.mocked(getTokenActivitySlice);
const MockedBalanceStream = jest.mocked(BalanceStream);
const MockedNftStream = jest.mocked(NftStream);

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

type ApiUpdatePayload = Parameters<OnApiUpdate>[0];
type InitialActivitiesUpdate = Extract<ApiUpdatePayload, { type: 'initialActivities' }>;

function getInitialActivitiesUpdate(onUpdate: OnApiUpdate) {
  return (onUpdate as jest.Mock).mock.calls
    .map((call) => call[0] as ApiUpdatePayload)
    .find((update): update is InitialActivitiesUpdate => update.type === 'initialActivities');
}

// The catch-up chain awaits several mocked async hops (stored wallet, activity slice, swap merge)
// before dispatching; drain enough microtasks that the assertions see the settled result.
async function flushPromises() {
  for (let i = 0; i < 10; i++) {
    await Promise.resolve();
  }
}

describe('EVM polling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedFetchStoredWallet.mockResolvedValue({ address: ADDRESS, index: 0 });
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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, { bnb: startTimestamp });

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, {});

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

    setupActivePolling('bnb', '0-mainnet', account, onUpdate, onUpdatingStatusChange, { bnb: 1_773_000_000_000 });

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
});
