import * as idb from 'idb-keyval';

import type { NftSyncSnapshot } from '../../common/nftSync';
import type { WalletWatcher } from '../../common/websocket/abstractWsClient';
import type { ApiAccountWithChain, ApiNft, ApiNftUpdate } from '../../types';
import type { ToncenterSocket } from './toncenter/socket';

import Deferred from '../../../util/Deferred';
import { setIsAppFocused } from '../../../util/focusAwareDelay';
import { logDebugError } from '../../../util/logs';
import * as randomModule from '../../../util/random';
import { toRawAddress } from './util/tonCore';
import { callBackendGet } from '../../common/backend';
import { MINUTE, SEC } from '../../constants';
import { getCurrentStorage } from '../../storages';
import { fetchActions, fetchPendingActions } from './toncenter/actions';
import { getToncenterSocket } from './toncenter/socket';
import { fetchDomains } from './domains';
import { createTonNftSync, getNftUpdates, streamAllAccountNfts } from './nfts';
import { setupActivePolling, setupNftPolling } from './polling';
import { getWalletInfo } from './wallet';

jest.mock('idb-keyval', () => {
  const items = new Map();
  return {
    createStore: jest.fn(() => jest.fn()),
    get: jest.fn((key) => Promise.resolve(items.get(key))),
    set: jest.fn((key, value) => {
      items.set(key, value);
      return Promise.resolve();
    }),
    keys: jest.fn(() => Promise.resolve([...items.keys()])),
    del: jest.fn((key) => {
      items.delete(key);
      return Promise.resolve();
    }),
    delMany: jest.fn((keys) => {
      keys.forEach((key: string) => items.delete(key));
      return Promise.resolve();
    }),
    clear: jest.fn(() => {
      items.clear();
      return Promise.resolve();
    }),
  };
});

jest.mock('../../../util/logs', () => ({
  logDebug: jest.fn(),
  logDebugError: jest.fn(),
}));

jest.mock('./nfts', () => ({
  createTonNftSync: jest.fn(),
  getNftUpdates: jest.fn(),
  streamAllAccountNfts: jest.fn(),
}));

jest.mock('./toncenter/socket', () => ({
  ...jest.requireActual('./toncenter/socket'),
  getToncenterSocket: jest.fn(),
}));

jest.mock('./toncenter/actions', () => ({
  fetchActions: jest.fn(),
  fetchPendingActions: jest.fn(),
  parseToncenterNft: (...args: Parameters<typeof import('./toncenter/actions')['parseToncenterNft']>) => (
    jest.requireActual<typeof import('./toncenter/actions')>('./toncenter/actions').parseToncenterNft(...args)
  ),
}));
jest.mock('./domains', () => ({ fetchDomains: jest.fn() }));
jest.mock('./wallet', () => ({ getWalletInfo: jest.fn() }));
jest.mock('../../common/accounts', () => ({
  fetchStoredAccount: jest.fn(() => Promise.resolve(MOCK_ACCOUNT)),
  fetchStoredWallet: jest.fn(() => Promise.resolve(MOCK_ACCOUNT.byChain.ton)),
}));
jest.mock('../../common/cache', () => ({
  getBackendConfigCache: jest.fn().mockResolvedValue({ isVestingEnabled: false }),
}));
jest.mock('../../common/addresses', () => ({
  getNftSuperCollectionsByCollectionAddress: jest.fn().mockResolvedValue({}),
  checkIsTrustedCollection: () => false,
  checkHasScamLink: () => false,
  getHasTrustedCollections: () => true,
}));
jest.mock('../../common/backend', () => ({
  ...jest.requireActual('../../common/backend'), callBackendGet: jest.fn(),
}));
jest.mock('../../storages', () => ({
  ...jest.requireActual('../../storages'), getCurrentStorage: jest.fn(),
}));
jest.mock('../../common/websocket/balanceStream', () => ({
  BalanceStream: jest.fn(() => ({
    start: jest.fn(), destroy: jest.fn(), onUpdate: jest.fn(() => jest.fn()), onLoadingChange: jest.fn(),
  })),
}));
jest.mock('./richActivityStream', () => ({
  RichActivityStream: jest.fn(() => ({
    destroy: jest.fn(), onUpdate: jest.fn(), onLoadingChange: jest.fn(),
  })),
}));

const ACCOUNT_ID = '0-testnet';
const ADDRESS = 'UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e';
const MOCK_ACCOUNT: ApiAccountWithChain<'ton'> = {
  type: 'view', byChain: { ton: { address: ADDRESS, index: 0, isInitialized: true } },
};
const DOMAIN_DATA: Awaited<ReturnType<typeof fetchDomains>> = {
  expirationByAddress: { 'nft-1': 123 }, linkedAddressByAddress: { 'nft-1': ADDRESS }, nfts: {},
};
const BATCH_NFTS: ApiNft[] = ['nft-1', 'nft-2'].map((address, index) => ({
  address,
  index,
  chain: 'ton',
  isOnSale: false,
  metadata: {},
  interface: 'default',
}));
const NFT_UPDATE: ApiNftUpdate = {
  type: 'nftSent',
  accountId: ACCOUNT_ID,
  chain: 'ton',
  nftAddress: 'nft-1',
  newOwnerAddress: 'new-owner',
};

const mockedStreamAllAccountNfts = jest.mocked(streamAllAccountNfts);
const mockedGetNftUpdates = jest.mocked(getNftUpdates);
const walletWatcher = { isConnected: false, destroy: jest.fn() };
const watchWallets = jest.fn<WalletWatcher, Parameters<ToncenterSocket['watchWallets']>>();
let polling: ReturnType<typeof setupNftPolling> | undefined;
let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

// Legacy regression assertions inspect ownership/data events. Freshness-only events are
// asserted separately below; they deliberately carry no replacement inventory.
function nftDataUpdates(onUpdate: jest.Mock) {
  const data = jest.fn();
  for (const [update] of onUpdate.mock.calls) {
    if (update.type === 'updateNfts') {
      const { inventoryStatus, ...rest } = update;
      if (inventoryStatus && rest.isFullLoading === undefined && !rest.streamedAddresses && !rest.nfts.length) continue;
      data(rest);
    } else data(update);
  }
  return data;
}
describe('TON NFT polling', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-10-22T12:00:00Z'));
    jest.clearAllMocks();
    setIsAppFocused(true);
    randomSpy = jest.spyOn(randomModule, 'random').mockReturnValue(0);
    walletWatcher.isConnected = false;
    watchWallets.mockReturnValue(walletWatcher);
    jest.mocked(getToncenterSocket).mockReturnValue({ watchWallets } as unknown as ToncenterSocket);
    mockedStreamAllAccountNfts.mockReset().mockResolvedValue(undefined);
    mockedGetNftUpdates.mockReset().mockResolvedValue([Math.round(Date.now() / 1000), []]);
  });

  afterEach(() => {
    polling?.stop();
    polling = undefined;
    jest.clearAllTimers();
    jest.restoreAllMocks();
    setIsAppFocused(true);
    jest.useRealTimers();
  });

  it('silently delivers hidden Telegram gifts from partial polling without surfacing other hidden NFTs', async () => {
    const hiddenGift = { ...BATCH_NFTS[0], isHidden: true, isTelegramGift: true };
    const hiddenOther = { ...BATCH_NFTS[1], isHidden: true };
    const visibleGift = { ...BATCH_NFTS[0], address: 'visible-gift', isTelegramGift: true };
    const updates: ApiNftUpdate[] = [hiddenGift, hiddenOther, visibleGift].map((nft) => ({
      type: 'nftReceived', accountId: ACCOUNT_ID, nftAddress: nft.address, nft,
    }));
    mockedGetNftUpdates.mockResolvedValue([Math.round(Date.now() / 1000), updates]);
    const { firstFullLoadPromise, onUpdate, poll } = startPolling();
    await firstFullLoadPromise;
    onUpdate.mockClear();
    poll();
    await jest.advanceTimersByTimeAsync(1);
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: [hiddenGift],
    });
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'nftReceived', accountId: ACCOUNT_ID, nftAddress: visibleGift.address, nft: visibleGift,
    });
    expect(onUpdate).toHaveBeenCalledTimes(2);
  });

  it('loads once on start and resolves the first-load promise after the stream finishes', async () => {
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    const { firstFullLoadPromise, onUpdate, poll } = startPolling();
    const onFirstFullLoad = jest.fn();
    void firstFullLoadPromise.then(onFirstFullLoad);
    connectSocket();

    expect(getToncenterSocket).toHaveBeenCalledWith('testnet');
    expect(watchWallets).toHaveBeenCalledWith([{ address: ADDRESS, chain: 'ton' }], expect.any(Object));
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    const [accountId, options] = mockedStreamAllAccountNfts.mock.calls[0];
    expect(accountId).toBe(ACCOUNT_ID);
    expect(options.signal?.aborted).toBe(false);
    options.onBatch(BATCH_NFTS);

    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(onFirstFullLoad).not.toHaveBeenCalled();
    expect(nftDataUpdates(onUpdate).mock.calls).toEqual([[{
      type: 'updateNfts',
      accountId: ACCOUNT_ID,
      chain: 'ton',
      nfts: BATCH_NFTS,
      isFullLoading: true,
    }]]);

    fullLoad.resolve();
    await firstFullLoadPromise;
    expect(onFirstFullLoad).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate)).toHaveBeenLastCalledWith({
      type: 'updateNfts',
      accountId: ACCOUNT_ID,
      chain: 'ton',
      nfts: [],
      isFullLoading: false,
      streamedAddresses: ['nft-1', 'nft-2'],
    });

    poll();
    expect(mockedGetNftUpdates).toHaveBeenCalledWith(ACCOUNT_ID, Math.round(Date.now() / 1000));
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
  });

  it.each([false, true])('reports freshness after a direct stream with failure=%s', async (shouldFail) => {
    const pending = new Deferred<void>();
    mockedStreamAllAccountNfts.mockImplementationOnce((_, { onBatch }) => {
      onBatch(BATCH_NFTS);
      return pending.promise;
    });
    const { onUpdate, firstFullLoadPromise } = startPolling();
    await jest.advanceTimersByTimeAsync(1);
    const statuses = () => onUpdate.mock.calls.map(([update]) => update.inventoryStatus).filter(Boolean);
    expect(statuses()).toEqual(['loading']);
    if (shouldFail) pending.reject(new Error('page two unavailable'));
    else pending.resolve();
    await firstFullLoadPromise;
    expect(statuses()).toEqual(['loading', shouldFail ? 'error' : 'complete']);
    if (shouldFail) expect(onUpdate.mock.calls.every(([update]) => update.streamedAddresses === undefined)).toBe(true);
  });

  it('resolves the first-load promise on failure without emitting a final empty NFT update', async () => {
    const fullLoad = new Deferred<void>();
    const error = new Error('NFT stream failed');
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    const { firstFullLoadPromise, onUpdate } = startPolling();
    const onFirstFullLoad = jest.fn();
    void firstFullLoadPromise.then(onFirstFullLoad);

    await jest.advanceTimersByTimeAsync(0);
    expect(onFirstFullLoad).not.toHaveBeenCalled();

    fullLoad.reject(error);
    await firstFullLoadPromise;
    expect(onFirstFullLoad).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
    expect(logDebugError).toHaveBeenCalledWith('setupNftPolling updateFull', error);
  });

  it.each([false, true])('handles the first socket connection after startup success=%s', async (didSucceed) => {
    if (!didSucceed) {
      mockedStreamAllAccountNfts.mockRejectedValueOnce(new Error('Offline'));
    }
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    connectSocket();
    const expectedFullLoads = didSucceed ? 1 : 2;
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(expectedFullLoads);
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(expectedFullLoads);
  });

  it.each([
    { isFocused: true, period: 5 * MINUTE, jitter: 0 },
    { isFocused: true, period: 5 * MINUTE, jitter: 200 },
    { isFocused: false, period: 10 * MINUTE, jitter: 0 },
    { isFocused: false, period: 10 * MINUTE, jitter: 200 },
  ])('forces a connected reload after $period ms with focus=$isFocused and jitter=$jitter', async ({
    isFocused, period, jitter,
  }) => {
    setIsAppFocused(isFocused);
    randomSpy.mockReturnValue(jitter);
    const { firstFullLoadPromise } = startPolling();
    connectSocket();
    await firstFullLoadPromise;

    await jest.advanceTimersByTimeAsync(period - 1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(period * 0.2 + 1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
  });

  it('postpones the forced full reload on a socket message while fetching partial updates', async () => {
    mockedGetNftUpdates.mockResolvedValue([Math.round(Date.now() / 1000), [NFT_UPDATE]]);
    const { firstFullLoadPromise, onUpdate, poll } = startPolling();
    connectSocket();
    await firstFullLoadPromise;

    await jest.advanceTimersByTimeAsync(4 * MINUTE);
    poll();
    await jest.advanceTimersByTimeAsync(0);
    expect(mockedGetNftUpdates).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate).mock.calls.map(([update]) => update)).toContainEqual(NFT_UPDATE);

    await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
    expect(mockedGetNftUpdates).toHaveBeenCalledTimes(2);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
  });

  it.each([
    { isFocused: true, period: MINUTE },
    { isFocused: false, period: 5 * MINUTE },
  ])('retries disconnected after 3 s and then every $period ms with focus=$isFocused', async ({
    isFocused, period,
  }) => {
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;

    await jest.advanceTimersByTimeAsync(3 * SEC - 1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);

    setIsAppFocused(isFocused);
    await jest.advanceTimersByTimeAsync(period - 1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(3);
    await jest.advanceTimersByTimeAsync(period);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(4);
  });

  it.each([false, true])('keeps disconnected fallback polling after a partial update with prior connection=%s', async (
    hasConnected,
  ) => {
    const { firstFullLoadPromise, poll } = startPolling();
    if (hasConnected) {
      connectSocket();
    }
    await firstFullLoadPromise;

    if (hasConnected) {
      await jest.advanceTimersByTimeAsync(10 * SEC);
      walletWatcher.isConnected = false;
      watchWallets.mock.calls[0][1]!.onDisconnect!();
    }

    await jest.advanceTimersByTimeAsync(SEC);
    poll();
    await jest.advanceTimersByTimeAsync(0);
    expect(mockedGetNftUpdates).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(MINUTE);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(3);
  });

  it('reloads immediately on reconnect after a disconnect', async () => {
    const { firstFullLoadPromise } = startPolling();
    connectSocket();
    await firstFullLoadPromise;
    await jest.advanceTimersByTimeAsync(10 * SEC);

    walletWatcher.isConnected = false;
    watchWallets.mock.calls[0][1]!.onDisconnect!();
    await jest.advanceTimersByTimeAsync(SEC);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    connectSocket();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
  });

  it('stops the watcher, aborts the stream, resolves the first load and cancels queued partial updates', async () => {
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    const { firstFullLoadPromise, onUpdate, poll, stop } = startPolling();
    connectSocket();
    const signal = mockedStreamAllAccountNfts.mock.calls[0][1].signal!;

    poll();
    poll();
    await jest.advanceTimersByTimeAsync(0);
    expect(mockedGetNftUpdates).toHaveBeenCalledTimes(1);

    stop();
    await firstFullLoadPromise;
    expect(walletWatcher.destroy).toHaveBeenCalledTimes(1);
    expect(signal.aborted).toBe(true);

    fullLoad.resolve();
    poll();
    await jest.advanceTimersByTimeAsync(15 * MINUTE);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(mockedGetNftUpdates).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });
});

function startPolling() {
  const onUpdate = jest.fn();
  polling = setupNftPolling(ACCOUNT_ID, ADDRESS, onUpdate);
  return { ...polling, onUpdate };
}

function connectSocket() {
  walletWatcher.isConnected = true;
  watchWallets.mock.calls[0][1]!.onConnect!();
}

describe('TON domain polling', () => {
  let stop: NoneToVoidFunction;
  let onUpdate: jest.Mock;
  let watchers: { isConnected: boolean; destroy: jest.Mock }[];
  const originalNoExtraFeatures = process.env.NO_EXTRA_FEATURES;

  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    setIsAppFocused(true);
    jest.spyOn(randomModule, 'random').mockReturnValue(0);
    process.env.NO_EXTRA_FEATURES = '1';
    watchers = [];
    watchWallets.mockImplementation(() => {
      const watcher = { isConnected: false, destroy: jest.fn() };
      watchers.push(watcher);
      return watcher;
    });
    jest.mocked(getToncenterSocket).mockReturnValue({ watchWallets } as unknown as ToncenterSocket);
    jest.mocked(fetchActions).mockResolvedValue([]);
    jest.mocked(fetchPendingActions).mockResolvedValue([]);
    jest.mocked(getWalletInfo).mockReset().mockResolvedValue({
      domain: 'wolf.t.me',
    } as Awaited<ReturnType<typeof getWalletInfo>>);
    jest.mocked(fetchDomains).mockReset().mockResolvedValue(DOMAIN_DATA);
    mockedStreamAllAccountNfts.mockReset().mockResolvedValue(undefined);
    mockedGetNftUpdates.mockReset().mockResolvedValue([Math.round(Date.now() / 1000), []]);
    onUpdate = jest.fn();
  });

  afterEach(() => {
    stop?.();
    jest.clearAllTimers();
    jest.restoreAllMocks();
    setIsAppFocused(true);
    jest.useRealTimers();
    if (originalNoExtraFeatures === undefined) delete process.env.NO_EXTRA_FEATURES;
    else process.env.NO_EXTRA_FEATURES = originalNoExtraFeatures;
  });

  function start(isConnected = false) {
    stop = setupActivePolling(ACCOUNT_ID, MOCK_ACCOUNT, onUpdate, jest.fn(), { toncoin: 1 });
    if (isConnected) {
      watchers.forEach((watcher, index) => {
        watcher.isConnected = true;
        watchWallets.mock.calls[index][1]!.onConnect!();
      });
    }
  }

  function expectPolls(count: number) {
    expect(getWalletInfo).toHaveBeenCalledTimes(count);
    expect(fetchDomains).toHaveBeenCalledTimes(count);
  }

  function emitWalletUpdate() {
    const callbacks = watchWallets.mock.calls.find(([, handlers]) => handlers?.onNewActivities)![1]!;
    callbacks.onNewActivities!({
      address: ADDRESS, messageHashNormalized: 'wallet-event', finality: 'finalized',
      activities: [{
        kind: 'transaction', id: 'new-activity', timestamp: 2, status: 'completed',
        amount: 1n, fromAddress: ADDRESS, toAddress: ADDRESS, normalizedAddress: ADDRESS,
        slug: 'toncoin', isIncoming: true, fee: 0n,
      }],
    });
  }

  it.each([
    { isConnected: true, isFocused: true, period: 5 * MINUTE },
    { isConnected: true, isFocused: false, period: 10 * MINUTE },
    { isConnected: false, isFocused: true, period: MINUTE },
    { isConnected: false, isFocused: false, period: 5 * MINUTE },
  ])('polls every $period ms with socket=$isConnected and focus=$isFocused', async ({
    isConnected, isFocused, period,
  }) => {
    setIsAppFocused(isFocused);
    start(isConnected);
    await jest.advanceTimersByTimeAsync(0);
    expectPolls(1);

    await jest.advanceTimersByTimeAsync(period - 1);
    expectPolls(1);
    await jest.advanceTimersByTimeAsync(1);
    expectPolls(2);
    await jest.advanceTimersByTimeAsync(period);
    expectPolls(3);
  });

  it('refreshes both domains on wallet events, disconnection fallback and reconnection', async () => {
    start(true);
    await jest.advanceTimersByTimeAsync(MINUTE);
    expectPolls(1);
    emitWalletUpdate();
    await jest.advanceTimersByTimeAsync(3 * SEC - 1);
    expectPolls(1);
    await jest.advanceTimersByTimeAsync(1);
    expectPolls(2);

    watchers.forEach((watcher, index) => {
      watcher.isConnected = false;
      watchWallets.mock.calls[index][1]!.onDisconnect!();
    });
    await jest.advanceTimersByTimeAsync(MINUTE - 1);
    expectPolls(2);
    await jest.advanceTimersByTimeAsync(1);
    expectPolls(3);

    watchers.forEach((watcher, index) => {
      watcher.isConnected = true;
      watchWallets.mock.calls[index][1]!.onConnect!();
    });
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(getWalletInfo).toHaveBeenCalledTimes(4);
    expect(fetchDomains).toHaveBeenCalledTimes(3);
    await jest.advanceTimersByTimeAsync(MINUTE - 2 * SEC - 1);
    expect(fetchDomains).toHaveBeenCalledTimes(3);
    await jest.advanceTimersByTimeAsync(1);
    expectPolls(4);
  });

  it('limits TON DNS to once a minute while refreshing the domain for every wallet event', async () => {
    const dnsPollTimes: number[] = [];
    jest.mocked(fetchDomains).mockImplementation(() => {
      dnsPollTimes.push(Date.now());
      return Promise.resolve(DOMAIN_DATA);
    });
    start(true);
    await jest.advanceTimersByTimeAsync(MINUTE);
    const firstEventAt = Date.now();
    expectPolls(1);

    for (let eventIndex = 0; eventIndex < 18; eventIndex++) {
      emitWalletUpdate();
      await jest.advanceTimersByTimeAsync(3 * SEC - 1);
      expect(getWalletInfo).toHaveBeenCalledTimes(eventIndex + 1);
      if (eventIndex === 0) expect(fetchDomains).toHaveBeenCalledTimes(1);
      await jest.advanceTimersByTimeAsync(1);
      expect(getWalletInfo).toHaveBeenCalledTimes(eventIndex + 2);
      await jest.advanceTimersByTimeAsync(7 * SEC);
    }

    expect(dnsPollTimes.slice(1)).toEqual([
      firstEventAt + 3 * SEC,
      firstEventAt + MINUTE + 3 * SEC,
      firstEventAt + 2 * MINUTE + 3 * SEC,
    ]);
  });

  it('starts the TON DNS schedule after the first NFT load without queuing early timer polls', async () => {
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    start(true);
    await jest.advanceTimersByTimeAsync(6 * MINUTE);
    expect(getWalletInfo).toHaveBeenCalledTimes(2);
    expect(fetchDomains).not.toHaveBeenCalled();

    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(fetchDomains).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
    expect(fetchDomains).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchDomains).toHaveBeenCalledTimes(2);
  });

  it('logs failures, preserves known data and continues on the five-minute schedule', async () => {
    start(true);
    await jest.advanceTimersByTimeAsync(0);
    const domainUpdates = () => nftDataUpdates(onUpdate).mock.calls.filter(([update]) => (
      update.type === 'updateAccount' || update.type === 'updateAccountDomainData'
    ));
    expect(domainUpdates()).toHaveLength(2);
    const error = new Error('Offline');
    jest.mocked(getWalletInfo).mockRejectedValueOnce(error);
    jest.mocked(fetchDomains).mockRejectedValueOnce(error);

    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    expectPolls(2);
    expect(logDebugError).toHaveBeenCalledWith('setupDomainPolling', error);
    expect(logDebugError).toHaveBeenCalledWith('setupTonDnsPolling', error);
    expect(domainUpdates()).toHaveLength(2);
    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    expectPolls(3);
    expect(domainUpdates()).toHaveLength(2);
  });

  it('removes socket watchers and prevents delayed wallet events or timers from polling after stop', async () => {
    start(true);
    await jest.advanceTimersByTimeAsync(MINUTE);
    emitWalletUpdate();
    stop();
    watchers.forEach((watcher) => expect(watcher.destroy).toHaveBeenCalledTimes(1));
    onUpdate.mockClear();

    await jest.advanceTimersByTimeAsync(15 * MINUTE);
    expectPolls(1);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });

  it('does not request TON DNS when stopped while waiting for the NFT load', async () => {
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    start(true);
    await jest.advanceTimersByTimeAsync(0);
    expect(fetchDomains).not.toHaveBeenCalled();
    stop();
    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(15 * MINUTE);
    expect(fetchDomains).not.toHaveBeenCalled();
    expect(getWalletInfo).toHaveBeenCalledTimes(1);
  });

  it('ignores domain responses that finish after the account polling is stopped', async () => {
    const walletInfo = new Deferred<Awaited<ReturnType<typeof getWalletInfo>>>();
    const domains = new Deferred<Awaited<ReturnType<typeof fetchDomains>>>();
    jest.mocked(getWalletInfo).mockReturnValueOnce(walletInfo.promise);
    jest.mocked(fetchDomains).mockReturnValueOnce(domains.promise);
    start(true);
    await jest.advanceTimersByTimeAsync(0);
    expectPolls(1);

    stop();
    onUpdate.mockClear();
    walletInfo.resolve({ domain: 'wolf.t.me' } as Awaited<ReturnType<typeof getWalletInfo>>);
    domains.resolve(DOMAIN_DATA);
    await jest.advanceTimersByTimeAsync(15 * MINUTE);
    expectPolls(1);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });
});

describe('TON NFT sync polling', () => {
  const ACCOUNT_ID = '0-mainnet';
  const syncClient = {
    restore: jest.fn<Promise<void>, []>(),
    poll: jest.fn<Promise<boolean>, [AbortSignal?, boolean?, NoneToVoidFunction?]>(),
    getRetryAt: jest.fn<number | undefined, []>(),
  };

  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-10-31T12:00:00Z'));
    jest.clearAllMocks();
    setIsAppFocused(true);
    jest.spyOn(randomModule, 'random').mockReturnValue(0);
    walletWatcher.isConnected = true;
    watchWallets.mockReset().mockReturnValue(walletWatcher);
    jest.mocked(getToncenterSocket).mockReturnValue({ watchWallets } as unknown as ToncenterSocket);
    mockedStreamAllAccountNfts.mockReset().mockResolvedValue(undefined);
    mockedGetNftUpdates.mockReset().mockResolvedValue([Math.round(Date.now() / 1000), []]);
    syncClient.restore.mockReset().mockResolvedValue(undefined);
    syncClient.poll.mockReset().mockImplementation((_signal, shouldEmitFull, onBeforeEmitFull) => {
      if (shouldEmitFull) onBeforeEmitFull?.();
      return Promise.resolve(true);
    });
    syncClient.getRetryAt.mockReset().mockReturnValue(undefined);
    jest.mocked(createTonNftSync).mockReturnValue(syncClient);
  });

  afterEach(() => {
    polling?.stop();
    polling = undefined;
    jest.mocked(createTonNftSync).mockReset();
    jest.clearAllTimers();
    jest.restoreAllMocks();
    setIsAppFocused(true);
    jest.useRealTimers();
  });

  function emitWalletUpdate() {
    watchWallets.mock.calls[0][1]!.onNewActivities!({
      address: ADDRESS, messageHashNormalized: 'wallet-event', finality: 'finalized', activities: [],
    });
  }

  function startPolling() {
    const onUpdate = jest.fn();
    polling = setupNftPolling(ACCOUNT_ID, ADDRESS, onUpdate);
    return { ...polling, onUpdate };
  }

  it('restores the saved snapshot before requesting changes and skips the direct path', async () => {
    const restored = new Deferred<void>();
    syncClient.restore.mockReturnValueOnce(restored.promise);
    const { firstFullLoadPromise } = startPolling();
    expect(syncClient.restore).toHaveBeenCalledTimes(1);
    expect(syncClient.poll).not.toHaveBeenCalled();

    restored.resolve();
    await firstFullLoadPromise;

    expect(syncClient.poll).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).not.toHaveBeenCalled();
    expect(mockedGetNftUpdates).not.toHaveBeenCalled();
  });

  it.each([
    { isConnected: true, isFocused: true, period: 5 * MINUTE },
    { isConnected: false, isFocused: true, period: MINUTE },
    { isConnected: false, isFocused: false, period: 5 * MINUTE },
  ])('requests changes every $period ms with socket=$isConnected and focus=$isFocused', async ({
    isConnected, isFocused, period,
  }) => {
    walletWatcher.isConnected = isConnected;
    setIsAppFocused(isFocused);
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;

    await jest.advanceTimersByTimeAsync(period - 1);
    expect(syncClient.poll).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(1);
    expect(syncClient.poll).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(period);
    expect(syncClient.poll).toHaveBeenCalledTimes(3);
    expect(mockedStreamAllAccountNfts).not.toHaveBeenCalled();
  });

  it('requests changes 30 seconds after the latest socket message and keeps periodic reconciliation', async () => {
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;
    emitWalletUpdate();
    await jest.advanceTimersByTimeAsync(25 * SEC);
    expect(syncClient.poll).toHaveBeenCalledTimes(3);

    emitWalletUpdate();
    await jest.advanceTimersByTimeAsync(3 * SEC);
    expect(syncClient.poll).toHaveBeenCalledTimes(4);
    await jest.advanceTimersByTimeAsync(5 * SEC);
    expect(syncClient.poll).toHaveBeenCalledTimes(5);
    await jest.advanceTimersByTimeAsync(22 * SEC - 1);
    expect(syncClient.poll).toHaveBeenCalledTimes(5);
    await jest.advanceTimersByTimeAsync(1);
    expect(syncClient.poll).toHaveBeenCalledTimes(6);

    await jest.advanceTimersByTimeAsync(5 * MINUTE - 55 * SEC - 2 * SEC);
    emitWalletUpdate();
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(syncClient.poll).toHaveBeenCalledTimes(7);
  });

  it('keeps early requests during a burst and requests again 30 seconds after the last message', async () => {
    const startedAt = Date.now();
    const requestedAt: number[] = [];
    syncClient.poll.mockImplementation(() => {
      requestedAt.push(Date.now() - startedAt);
      return Promise.resolve(true);
    });
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;
    requestedAt.length = 0;
    emitWalletUpdate();

    for (let seconds = 2; seconds <= 20; seconds += 2) {
      await jest.advanceTimersByTimeAsync(2 * SEC);
      emitWalletUpdate();
    }

    expect(requestedAt[0]).toBe(3 * SEC);
    expect(requestedAt).toContain(8 * SEC);
    await jest.advanceTimersByTimeAsync(10 * SEC);
    expect(requestedAt).not.toContain(30 * SEC);
    const requestsBeforeLast = [...requestedAt];
    await jest.advanceTimersByTimeAsync(20 * SEC - 1);
    expect(requestedAt).toEqual(requestsBeforeLast);
    await jest.advanceTimersByTimeAsync(1);
    expect(requestedAt).toEqual([...requestsBeforeLast, 50 * SEC]);
  });

  it('switches to the unchanged direct poller for the rest of the session after a protocol fallback', async () => {
    syncClient.poll.mockResolvedValueOnce(false);
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(5 * MINUTE);

    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    expect(syncClient.poll).toHaveBeenCalledTimes(1);
  });

  it('keeps direct loading during a 404 cooldown and resumes sync after one hour in the same session', async () => {
    syncClient.poll.mockResolvedValueOnce(false);
    syncClient.getRetryAt.mockReturnValue(Date.now() + 60 * MINUTE);
    const { firstFullLoadPromise } = startPolling();
    await firstFullLoadPromise;
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(60 * MINUTE - 1);
    expect(syncClient.poll).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(12);
    const directLoads = mockedStreamAllAccountNfts.mock.calls.length;

    await jest.advanceTimersByTimeAsync(1);
    expect(syncClient.poll).toHaveBeenCalledTimes(2);
    expect(syncClient.poll).toHaveBeenLastCalledWith(expect.any(AbortSignal), true, expect.any(Function));
    expect(walletWatcher.destroy).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    expect(syncClient.poll).toHaveBeenCalledTimes(3);
    expect(syncClient.poll).toHaveBeenLastCalledWith(expect.any(AbortSignal), false, expect.any(Function));
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(directLoads);
  });

  it('loads testnet directly without creating an endpoint session', async () => {
    polling = setupNftPolling('0-testnet', ADDRESS, jest.fn());
    await polling.firstFullLoadPromise;

    expect(createTonNftSync).not.toHaveBeenCalled();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledWith('0-testnet', expect.any(Object));
  });

  it('cancels all delayed requests and aborts the active sync when stopped', async () => {
    const { firstFullLoadPromise, stop } = startPolling();
    await firstFullLoadPromise;
    emitWalletUpdate();
    const signal = syncClient.poll.mock.calls[0][0]!;

    stop();
    await jest.advanceTimersByTimeAsync(10 * MINUTE);

    expect(signal.aborted).toBe(true);
    expect(syncClient.poll).toHaveBeenCalledTimes(1);
    expect(walletWatcher.destroy).toHaveBeenCalledTimes(1);
  });
});

describe('TON NFT protocol polling', () => {
  const accountId = '0-mainnet';
  const snapshotKey = `${accountId}:ton`;
  const item = {
    address: `0:${'1'.repeat(64)}`,
    init: true,
    index: '1',
    owner_address: toRawAddress(ADDRESS),
    on_sale: false,
  };
  const snapshot: NftSyncSnapshot = {
    schemaVersion: 1,
    syncToken: 'version-0',
    items: { [item.address]: item },
    metadata: { [item.address]: { is_indexed: true, token_info: [{ type: 'nft_items', name: 'Owned NFT' }] } },
  };
  let storage: {
    getItem: jest.Mock;
    setItem: jest.Mock;
    removeItem: jest.Mock;
    clear: jest.Mock;
  };

  beforeEach(async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-10-31T12:00:00Z'));
    jest.clearAllMocks();
    setIsAppFocused(true);
    jest.spyOn(randomModule, 'random').mockReturnValue(0);
    walletWatcher.isConnected = true;
    watchWallets.mockReset().mockReturnValue(walletWatcher);
    jest.mocked(getToncenterSocket).mockReturnValue({ watchWallets } as unknown as ToncenterSocket);
    jest.mocked(createTonNftSync).mockImplementation(jest.requireActual('./nfts').createTonNftSync);
    mockedStreamAllAccountNfts.mockReset().mockResolvedValue(undefined);
    await idb.clear();
    await idb.set(snapshotKey, snapshot);
    const db: Record<string, unknown> = { accounts: { [accountId]: MOCK_ACCOUNT } };
    storage = {
      getItem: jest.fn((key: string) => Promise.resolve(db[key])),
      setItem: jest.fn((key: string, value: unknown) => {
        db[key] = value;
        return Promise.resolve();
      }),
      removeItem: jest.fn((key: string) => {
        delete db[key];
        return Promise.resolve();
      }),
      clear: jest.fn(),
    };
    jest.mocked(getCurrentStorage).mockReturnValue(storage);
    jest.mocked(callBackendGet).mockReset().mockImplementation(() => Promise.resolve({
      status: 200,
      json: () => Promise.resolve({
        syncToken: 'version-0', reset: false, hasMore: false, items: [], removed: [], metadata: {},
      }),
    } as Response));
  });

  afterEach(() => {
    polling?.stop();
    polling = undefined;
    jest.mocked(createTonNftSync).mockReset();
    jest.clearAllTimers();
    jest.restoreAllMocks();
    setIsAppFocused(true);
    jest.useRealTimers();
  });

  function emitWalletUpdate() {
    watchWallets.mock.calls[0][1]!.onNewActivities!({
      address: ADDRESS, messageHashNormalized: 'wallet-event', finality: 'finalized', activities: [],
    });
  }

  it.each([false, true])('forwards direct fallback updates unchanged with saved snapshot=%s', async (hasSnapshot) => {
    if (!hasSnapshot) await idb.del(snapshotKey);
    jest.mocked(callBackendGet).mockResolvedValueOnce({ status: 202 } as Response);
    mockedStreamAllAccountNfts.mockImplementationOnce((_, { onBatch }) => {
      onBatch(BATCH_NFTS);
      return Promise.resolve();
    });
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);

    await polling.firstFullLoadPromise;

    const statuses = onUpdate.mock.calls.map(([update]) => update.inventoryStatus).filter(Boolean);
    expect(statuses).toEqual(hasSnapshot
      ? ['loading', 'cached', 'cached', 'loading', 'complete'] : ['loading', 'loading', 'complete']);

    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledTimes(hasSnapshot ? 4 : 2);
    if (hasSnapshot) {
      expect(nftDataUpdates(onUpdate).mock.calls[0][0]).toMatchObject({
        type: 'updateNfts', isFullLoading: true, nfts: [{ name: 'Owned NFT' }],
      });
      expect(nftDataUpdates(onUpdate).mock.calls[1][0]).toMatchObject({
        type: 'updateNfts', isFullLoading: false, nfts: [{ name: 'Owned NFT' }],
      });
    }
    expect(nftDataUpdates(onUpdate).mock.calls.slice(hasSnapshot ? 2 : 0)).toEqual([
      [{ type: 'updateNfts', accountId, chain: 'ton', nfts: BATCH_NFTS, isFullLoading: true }],
      [{
        type: 'updateNfts', accountId, chain: 'ton', nfts: [], isFullLoading: false,
        streamedAddresses: BATCH_NFTS.map(({ address }) => address),
      }],
    ]);
  });

  it('completes a full sync after the 404 cooldown aborts a direct stream, even for an empty delta', async () => {
    const fullLoad = new Deferred<void>();
    jest.mocked(callBackendGet).mockResolvedValueOnce({ status: 404 } as Response);
    mockedStreamAllAccountNfts.mockImplementationOnce((_, { onBatch }) => {
      onBatch(BATCH_NFTS);
      return fullLoad.promise;
    });
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);
    await jest.advanceTimersByTimeAsync(0);

    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    const directSignal = mockedStreamAllAccountNfts.mock.calls[0][1].signal!;
    const restoredNfts: ApiNft[] = nftDataUpdates(onUpdate).mock.calls[0][0].nfts;
    expect(nftDataUpdates(onUpdate)).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'updateNfts', isFullLoading: true, nfts: BATCH_NFTS,
    }));
    onUpdate.mockClear();
    await jest.advanceTimersByTimeAsync(60 * MINUTE - 1);
    expect(directSignal.aborted).toBe(false);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(1);

    expect(directSignal.aborted).toBe(true);
    expect(callBackendGet).toHaveBeenCalledTimes(2);
    expect(nftDataUpdates(onUpdate).mock.calls).toEqual([
      [{ type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: true }],
      [{
        type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: false,
        streamedAddresses: restoredNfts.map((nft) => nft.address),
      }],
    ]);
    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledTimes(2);
    onUpdate.mockClear();
    emitWalletUpdate();
    await jest.advanceTimersByTimeAsync(3 * SEC);
    expect(callBackendGet).toHaveBeenCalledTimes(3);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });

  it.each([
    ['202 with retryAfter 30', 202, 30, 30 * SEC, true],
    ['202 without retryAfter', 202, undefined, MINUTE, true],
    ['202 with retryAfter 1', 202, 1, 5 * SEC, true],
    ['202 with retryAfter 3600', 202, 3600, 5 * MINUTE, true],
    ['503', 503, undefined, 5 * MINUTE, true],
    ['transport error', undefined, undefined, 5 * MINUTE, true],
    ['202 with retryAfter 30 without a socket', 202, 30, 30 * SEC, false],
  ] as const)('resumes sync after %s at the retry time', async (
    _name, status, retryAfter, retryDelay, isConnected,
  ) => {
    // Scheduler ticks get the largest jitter, so they cannot stand in for the retry timer
    jest.spyOn(randomModule, 'random').mockReturnValue(200);
    walletWatcher.isConnected = isConnected;
    if (status === undefined) {
      jest.mocked(callBackendGet).mockRejectedValueOnce(new TypeError('Failed to fetch'));
    } else {
      jest.mocked(callBackendGet).mockResolvedValueOnce({
        status, json: () => Promise.resolve({ retryAfter }),
      } as Response);
    }
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockImplementationOnce((_, { onBatch }) => {
      onBatch(BATCH_NFTS);
      return fullLoad.promise;
    });
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);
    await jest.advanceTimersByTimeAsync(0);

    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    const directSignal = mockedStreamAllAccountNfts.mock.calls[0][1].signal!;
    const restoredNfts: ApiNft[] = nftDataUpdates(onUpdate).mock.calls[0][0].nfts;
    expect(nftDataUpdates(onUpdate)).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'updateNfts', isFullLoading: true, nfts: BATCH_NFTS,
    }));
    onUpdate.mockClear();
    await jest.advanceTimersByTimeAsync(retryDelay - 1);
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(directSignal.aborted).toBe(false);
    expect(await idb.get(snapshotKey)).toBe(snapshot);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(1);

    expect(callBackendGet).toHaveBeenCalledTimes(2);
    expect(directSignal.aborted).toBe(true);
    expect(nftDataUpdates(onUpdate).mock.calls).toEqual([
      [{ type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: true }],
      [{
        type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: false,
        streamedAddresses: restoredNfts.map((nft) => nft.address),
      }],
    ]);
    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledTimes(2);
    onUpdate.mockClear();
    const nextTick = (isConnected ? 5 * MINUTE : MINUTE) * 1.2;
    await jest.advanceTimersByTimeAsync(nextTick - retryDelay - 1);
    expect(callBackendGet).toHaveBeenCalledTimes(2);
    await jest.advanceTimersByTimeAsync(1);
    expect(callBackendGet).toHaveBeenCalledTimes(3);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });

  it('retries at the retry time after the clock steps back', async () => {
    jest.mocked(callBackendGet).mockResolvedValueOnce({
      status: 202, json: () => Promise.resolve({ retryAfter: 30 }),
    } as Response);
    polling = setupNftPolling(accountId, ADDRESS, jest.fn());
    await jest.advanceTimersByTimeAsync(0);
    expect(callBackendGet).toHaveBeenCalledTimes(1);

    jest.setSystemTime(Date.now() - 2 * SEC);
    await jest.advanceTimersByTimeAsync(30 * SEC);
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(callBackendGet).toHaveBeenCalledTimes(2);
  });

  it('keeps one direct load through repeated 503 responses and stops it before a successful full sync', async () => {
    const fullLoad = new Deferred<void>();
    const successfulRetry = new Deferred<Response>();
    for (let attempt = 0; attempt < 3; attempt++) {
      jest.mocked(callBackendGet).mockResolvedValueOnce({ status: 503 } as Response);
    }
    jest.mocked(callBackendGet).mockReturnValueOnce(successfulRetry.promise);
    mockedStreamAllAccountNfts.mockImplementationOnce((_, { onBatch }) => {
      onBatch(BATCH_NFTS);
      return fullLoad.promise;
    });
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);
    await jest.advanceTimersByTimeAsync(0);
    const directSignal = mockedStreamAllAccountNfts.mock.calls[0][1].signal!;
    const restoredNfts: ApiNft[] = nftDataUpdates(onUpdate).mock.calls[0][0].nfts;
    onUpdate.mockClear();

    for (let attempt = 2; attempt <= 3; attempt++) {
      await jest.advanceTimersByTimeAsync(5 * MINUTE);
      expect(callBackendGet).toHaveBeenCalledTimes(attempt);
      expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
      expect(directSignal.aborted).toBe(false);
      expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
    }

    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    expect(callBackendGet).toHaveBeenCalledTimes(4);
    expect(directSignal.aborted).toBe(false);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    onUpdate.mockImplementation(() => expect(directSignal.aborted).toBe(true));
    successfulRetry.resolve({
      status: 200,
      json: () => Promise.resolve({
        syncToken: snapshot.syncToken, reset: false, hasMore: false, items: [], removed: [], metadata: {},
      }),
    } as Response);
    await jest.advanceTimersByTimeAsync(0);

    expect(directSignal.aborted).toBe(true);
    expect(nftDataUpdates(onUpdate).mock.calls).toEqual([
      [{ type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: true }],
      [{
        type: 'updateNfts', accountId, chain: 'ton', nfts: restoredNfts, isFullLoading: false,
        streamedAddresses: restoredNfts.map((nft) => nft.address),
      }],
    ]);
    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledTimes(2);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(callBackendGet).toHaveBeenCalledTimes(5);
  });

  it.each([400, 'invalid response'] as const)(
    'keeps the direct poller running when a retry after 202 returns %s',
    async (outcome) => {
      const fullLoad = new Deferred<void>();
      jest.mocked(callBackendGet).mockResolvedValueOnce({
        status: 202, json: () => Promise.resolve({ retryAfter: 30 }),
      } as Response);
      jest.mocked(callBackendGet).mockResolvedValueOnce({
        status: outcome === 400 ? 400 : 200,
        json: () => Promise.resolve({
          syncToken: 'invalid', reset: false, hasMore: false, items: [{}], removed: [], metadata: {},
        }),
      } as Response);
      mockedStreamAllAccountNfts.mockImplementationOnce(() => fullLoad.promise);
      const onUpdate = jest.fn();
      polling = setupNftPolling(accountId, ADDRESS, onUpdate);
      await jest.advanceTimersByTimeAsync(0);
      const directOptions = mockedStreamAllAccountNfts.mock.calls[0][1];
      onUpdate.mockClear();

      await jest.advanceTimersByTimeAsync(5 * MINUTE);

      expect(callBackendGet).toHaveBeenCalledTimes(2);
      expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
      expect(directOptions.signal!.aborted).toBe(false);
      expect(walletWatcher.destroy).toHaveBeenCalledTimes(1);
      await jest.advanceTimersByTimeAsync(10 * MINUTE);
      expect(callBackendGet).toHaveBeenCalledTimes(2);
      expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
      expect(directOptions.signal!.aborted).toBe(false);
      expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();

      directOptions.onBatch(BATCH_NFTS);
      fullLoad.resolve();
      await jest.advanceTimersByTimeAsync(0);
      expect(nftDataUpdates(onUpdate).mock.calls).toEqual([
        [{ type: 'updateNfts', accountId, chain: 'ton', nfts: BATCH_NFTS, isFullLoading: true }],
        [{
          type: 'updateNfts', accountId, chain: 'ton', nfts: [], isFullLoading: false,
          streamedAddresses: BATCH_NFTS.map((nft) => nft.address),
        }],
      ]);
    },
  );

  it('waits for a later shared 404 pause without restarting the direct poller', async () => {
    const startedAt = Date.now();
    const fullLoad = new Deferred<void>();
    jest.mocked(callBackendGet).mockResolvedValueOnce({
      status: 202, json: () => Promise.resolve({ retryAfter: 30 }),
    } as Response);
    mockedStreamAllAccountNfts.mockImplementationOnce(() => fullLoad.promise);
    polling = setupNftPolling(accountId, ADDRESS, jest.fn());
    await jest.advanceTimersByTimeAsync(0);
    const sync = jest.mocked(createTonNftSync).mock.results[0].value;
    expect(sync.getRetryAt()).toBe(startedAt + 30 * SEC);
    jest.mocked(callBackendGet).mockResolvedValueOnce({ status: 404 } as Response);
    const otherSync = createTonNftSync('1-mainnet', ADDRESS, jest.fn());
    expect(await otherSync.poll()).toBe(false);
    expect(sync.getRetryAt()).toBe(startedAt + 60 * MINUTE);

    await jest.advanceTimersByTimeAsync(5 * MINUTE);

    expect(callBackendGet).toHaveBeenCalledTimes(2);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    expect(mockedStreamAllAccountNfts.mock.calls[0][1].signal!.aborted).toBe(false);
    fullLoad.resolve();
    await jest.advanceTimersByTimeAsync(0);
  });

  it('writes nothing and emits no UI changes for all empty deltas after one socket message', async () => {
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);
    await polling.firstFullLoadPromise;
    onUpdate.mockClear();
    storage.getItem.mockClear();
    storage.setItem.mockClear();
    jest.mocked(idb.get).mockClear();
    jest.mocked(idb.set).mockClear();
    emitWalletUpdate();

    await jest.advanceTimersByTimeAsync(30 * SEC);

    expect(callBackendGet).toHaveBeenCalledTimes(4);
    expect(storage.getItem).not.toHaveBeenCalled();
    expect(storage.setItem).not.toHaveBeenCalled();
    expect(idb.get).not.toHaveBeenCalled();
    expect(idb.set).not.toHaveBeenCalled();
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
  });

  it('emits nftChanged only when the protocol returns a late sale change at 30 seconds', async () => {
    jest.mocked(callBackendGet).mockImplementation(() => {
      const isCommitted = jest.mocked(callBackendGet).mock.calls.length === 4;
      return Promise.resolve({
        status: 200,
        json: () => Promise.resolve({
          syncToken: isCommitted ? 'version-1' : 'version-0', reset: false, hasMore: false,
          items: isCommitted ? [{ ...item, on_sale: true }] : [], removed: [], metadata: {},
        }),
      } as Response);
    });
    const onUpdate = jest.fn();
    polling = setupNftPolling(accountId, ADDRESS, onUpdate);
    await polling.firstFullLoadPromise;
    onUpdate.mockClear();
    emitWalletUpdate();

    await jest.advanceTimersByTimeAsync(3 * SEC);
    expect(callBackendGet).toHaveBeenCalledTimes(2);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(5 * SEC);
    expect(callBackendGet).toHaveBeenCalledTimes(3);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(22 * SEC - 1);
    expect(callBackendGet).toHaveBeenCalledTimes(3);
    expect(nftDataUpdates(onUpdate)).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(1);

    expect(callBackendGet).toHaveBeenCalledTimes(4);
    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledTimes(1);
    expect(nftDataUpdates(onUpdate)).toHaveBeenCalledWith({
      type: 'nftChanged', accountId, chain: 'ton',
      nft: expect.objectContaining({ name: 'Owned NFT', isOnSale: true }),
    });
  });
});
