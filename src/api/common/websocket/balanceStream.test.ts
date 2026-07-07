import type { ApiBalanceBySlug } from '../../types';
import type {
  AbstractWebsocketClient,
  BalanceUpdateCallback,
  WalletWatcher,
  WalletWatcherInternal,
} from './abstractWsClient';

import Deferred from '../../../util/Deferred';
import * as randomModule from '../../../util/random';
import { tokensPreload } from '../../common/tokens';
import { BalanceStream } from './balanceStream';

const POLLING_OPTIONS = {
  pollOnStart: true,
  minPollDelay: 60_000,
  pollingStartDelay: 60_000,
  pollingPeriod: 60_000,
  forcedPollingPeriod: 60_000,
};

const FAST_POLLING_OPTIONS = {
  pollOnStart: true,
  minPollDelay: 1,
  pollingStartDelay: 60_000,
  pollingPeriod: 60_000,
  forcedPollingPeriod: 60_000,
};

// Matches the socket update throttle inside `balanceStream.ts`.
const SOCKET_THROTTLE_DELAY = 100;

describe('BalanceStream', () => {
  let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

  beforeEach(() => {
    // Pin scheduler jitter to zero so the fake-timer advances are deterministic.
    randomSpy = jest.spyOn(randomModule, 'random').mockReturnValue(0);
  });

  afterEach(() => {
    randomSpy.mockRestore();
    jest.useRealTimers();
  });

  it('starts initial polling only after consumers register listeners', async () => {
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const fetchBalances = jest.fn(() => Promise.resolve({ toncoin: 123n }));
    const loadingEvents: boolean[] = [];
    const updateEvents: unknown[] = [];

    const stream = new BalanceStream({
      chain: 'ton',
      wsClient,
      network: 'mainnet',
      address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: POLLING_OPTIONS,
      fetchBalancesCb: fetchBalances,
    });

    await Promise.resolve();
    expect(fetchBalances).not.toHaveBeenCalled();

    const firstLoad = new Promise<void>((resolve) => {
      stream.onLoadingChange((isLoading) => {
        loadingEvents.push(isLoading);
        if (!isLoading) resolve();
      });
    });
    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();

    await firstLoad;
    stream.destroy();

    expect(fetchBalances).toHaveBeenCalledTimes(1);
    expect(updateEvents).toEqual([{ toncoin: 123n }]);
    expect(loadingEvents).toEqual([true, false]);
  });

  it('does not start polling after destroy', async () => {
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const fetchBalances = jest.fn(() => Promise.resolve({ toncoin: 123n }));

    const stream = new BalanceStream({
      chain: 'ton',
      wsClient,
      network: 'mainnet',
      address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: POLLING_OPTIONS,
      fetchBalancesCb: fetchBalances,
    });

    stream.destroy();
    stream.start();
    await Promise.resolve();

    expect(fetchBalances).not.toHaveBeenCalled();
  });

  it('does not re-check inactive wallets on scheduled polls', async () => {
    jest.useFakeTimers();
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const ensureIsPollingNeeded = jest.fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true);
    const fetchBalances = jest.fn(() => Promise.resolve({ bnb: 123n }));
    const updateEvents: unknown[] = [];

    const stream = new BalanceStream({
      chain: 'bnb',
      wsClient,
      network: 'mainnet',
      address: '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: {
        pollOnStart: true,
        minPollDelay: 1,
        pollingStartDelay: 100,
        pollingPeriod: 100,
        forcedPollingPeriod: 100,
      },
      fetchBalancesCb: fetchBalances,
      ensureIsPollingNeeded,
    });

    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(ensureIsPollingNeeded).toHaveBeenCalledTimes(1);
    expect(fetchBalances).not.toHaveBeenCalled();
    expect(updateEvents).toEqual([]);

    await jest.advanceTimersByTimeAsync(100);
    stream.destroy();

    expect(ensureIsPollingNeeded).toHaveBeenCalledTimes(1);
    expect(fetchBalances).not.toHaveBeenCalled();
    expect(updateEvents).toEqual([]);
  });

  it('allows activity polling to mark an inactive wallet active and fetch balances immediately', async () => {
    jest.useFakeTimers();
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const ensureIsPollingNeeded = jest.fn().mockResolvedValue(false);
    const fetchBalances = jest.fn(() => Promise.resolve({ 'bnb-0x8ac76a51': 456n }));
    const updateEvents: unknown[] = [];

    const stream = new BalanceStream({
      chain: 'bnb',
      wsClient,
      network: 'mainnet',
      address: '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: {
        pollOnStart: true,
        minPollDelay: 1,
        pollingStartDelay: 60_000,
        pollingPeriod: 60_000,
        forcedPollingPeriod: 60_000,
      },
      fetchBalancesCb: fetchBalances,
      ensureIsPollingNeeded,
    });

    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(updateEvents).toEqual([]);
    expect(fetchBalances).not.toHaveBeenCalled();

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    stream.destroy();

    expect(ensureIsPollingNeeded).toHaveBeenCalledTimes(1);
    expect(fetchBalances).toHaveBeenCalledTimes(1);
    expect(updateEvents).toEqual([{ 'bnb-0x8ac76a51': 456n }]);
  });

  it('does not re-run the inactive pre-check on normal polls after signal activation', async () => {
    jest.useFakeTimers();
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const ensureIsPollingNeeded = jest.fn().mockResolvedValue(false);
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ bnb: 1n })
      .mockResolvedValueOnce({ bnb: 2n });
    const updateEvents: unknown[] = [];

    const stream = new BalanceStream({
      chain: 'bnb',
      wsClient,
      network: 'mainnet',
      address: '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: {
        pollOnStart: true,
        minPollDelay: 1,
        pollingStartDelay: 60_000,
        pollingPeriod: 60_000,
        forcedPollingPeriod: 60_000,
      },
      fetchBalancesCb: fetchBalances,
      ensureIsPollingNeeded,
    });

    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    await jest.advanceTimersByTimeAsync(60_000);
    stream.destroy();

    expect(ensureIsPollingNeeded).toHaveBeenCalledTimes(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(updateEvents).toEqual([{ bnb: 1n }, { bnb: 2n }]);
  });
});

describe('BalanceStream freshness guard', () => {
  let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

  // The socket path awaits `tokensPreload` before applying deltas. It is a module-level
  // Deferred that the production code resolves on token load; resolve it once for the suite.
  beforeAll(() => {
    tokensPreload.resolve();
  });

  beforeEach(() => {
    // Pin scheduler jitter to zero so the fake-timer advances are deterministic.
    randomSpy = jest.spyOn(randomModule, 'random').mockReturnValue(0);
  });

  afterEach(() => {
    randomSpy.mockRestore();
    jest.useRealTimers();
  });

  interface SocketScenario {
    stream: BalanceStream;
    /** Fires a native-token (toncoin) socket delta and applies it (advances the 100ms throttle). */
    deliverNativeSocketBalance: (balance: bigint) => Promise<void>;
    updateEvents: Array<{ balances: ApiBalanceBySlug; source: string }>;
  }

  /**
   * Builds a `'ton'` BalanceStream wired so the test can drive the socket path. The socket
   * `onBalanceUpdate` callback registered in the constructor is captured from the `watchWallets`
   * mock so the test can simulate live deltas arriving out of order with HTTP polls.
   */
  function createSocketScenario(fetchBalancesCb: jest.Mock): SocketScenario {
    let onBalanceUpdate: BalanceUpdateCallback | undefined;

    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn((_wallets, callbacks: Partial<WalletWatcherInternal>) => {
        onBalanceUpdate = callbacks.onBalanceUpdate;
        return watcher;
      }),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;

    const updateEvents: Array<{ balances: ApiBalanceBySlug; source: string }> = [];

    const stream = new BalanceStream({
      chain: 'ton',
      wsClient,
      network: 'mainnet',
      address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb,
    });

    stream.onUpdate((balances, source) => updateEvents.push({ balances: { ...balances }, source }));

    const deliverNativeSocketBalance = async (balance: bigint) => {
      // `tokenAddress: undefined` denotes the chain native token (toncoin).
      onBalanceUpdate!({ address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ', balance, finality: 'confirmed' });
      // The socket handler is throttled by 100ms, then awaits token preload before committing.
      await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
    };

    return { stream, deliverNativeSocketBalance, updateEvents };
  }

  it('keeps a fresher socket balance when an older poll (started before the delta) resolves later', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<ApiBalanceBySlug>({ toncoin: 100n });
    // The second poll is slow: it captures its freshness version, then a socket delta arrives,
    // and only afterwards does the poll resolve with a now-stale value for `toncoin`.
    const slowPoll = new Deferred<ApiBalanceBySlug>();
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockReturnValueOnce(slowPoll.promise);

    const { stream, deliverNativeSocketBalance } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });

    // Begin the slow second poll; its version is captured now, before the await resolves.
    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    expect(fetchBalances).toHaveBeenCalledTimes(2);

    // A live socket delta for `toncoin` arrives while the slow poll is still in flight.
    await deliverNativeSocketBalance(555n);
    expect(await stream.getBalances()).toEqual({ toncoin: 555n });

    // The slow poll finally resolves with a stale `toncoin` plus a genuinely new slug.
    slowPoll.resolve({ toncoin: 100n, 'ton-fresh': 999n });
    await jest.advanceTimersByTimeAsync(1);

    const balances = await stream.getBalances();
    // The fresher socket value for `toncoin` survives; the new slug from the poll still applies.
    expect(balances).toEqual({ toncoin: 555n, 'ton-fresh': 999n });

    stream.destroy();
  });

  it('lets a poll that started after a socket delta overwrite that slug', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<ApiBalanceBySlug>({ toncoin: 100n });
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockResolvedValueOnce({ toncoin: 777n });

    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });

    await deliverNativeSocketBalance(555n);
    expect(await stream.getBalances()).toEqual({ toncoin: 555n });

    // A poll started strictly after the delta is fresher and must win.
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 777n });

    expect(updateEvents.at(-1)).toEqual({ balances: { toncoin: 777n }, source: 'poll' });

    stream.destroy();
  });

  it('does not let a stale poll drop a slug a newer socket delta added', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<ApiBalanceBySlug>({ toncoin: 100n });
    const slowPoll = new Deferred<ApiBalanceBySlug>();
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockReturnValueOnce(slowPoll.promise);

    const { stream, deliverNativeSocketBalance } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });

    // Begin the slow poll (version captured), then a socket delta updates `toncoin`.
    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    await deliverNativeSocketBalance(555n);

    // The stale poll's snapshot omits `toncoin` entirely (e.g. it predates the change).
    slowPoll.resolve({ 'ton-other': 42n });
    await jest.advanceTimersByTimeAsync(1);

    const balances = await stream.getBalances();
    // The stale poll must not remove the slug refreshed by the newer socket delta.
    expect(balances).toEqual({ toncoin: 555n, 'ton-other': 42n });

    stream.destroy();
  });

  it('lets a fresh poll drop a slug that is absent from its snapshot', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ toncoin: 100n, 'ton-gone': 5n })
      .mockResolvedValueOnce({ toncoin: 100n });

    const { stream, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n, 'ton-gone': 5n });

    // A later poll no longer reports `ton-gone`; with no fresher delta protecting it, it is dropped.
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });

    expect(updateEvents.at(-1)).toEqual({ balances: { toncoin: 100n }, source: 'poll' });

    stream.destroy();
  });

  it('replaces balances exactly as before when polls do not interleave with socket deltas', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ toncoin: 1n, 'ton-aaa': 2n })
      .mockResolvedValueOnce({ toncoin: 3n, 'ton-bbb': 4n });

    const { stream, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 1n, 'ton-aaa': 2n });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    // A normal (non-interleaved) poll is a full replace, identical to the pre-guard behaviour.
    expect(await stream.getBalances()).toEqual({ toncoin: 3n, 'ton-bbb': 4n });

    expect(updateEvents).toEqual([
      { balances: { toncoin: 1n, 'ton-aaa': 2n }, source: 'poll' },
      { balances: { toncoin: 3n, 'ton-bbb': 4n }, source: 'poll' },
    ]);

    stream.destroy();
  });

  it('applies a non-interleaved poll via the fast path and skips an identical second poll', async () => {
    jest.useFakeTimers();

    // Both polls return the same snapshot, and no socket delta interleaves, so each poll runs the
    // O(1) fast path (`#clock === pollVersion`). The first poll is a full replace that fires one
    // update; the identical second poll is short-circuited by `areDeepEqual` and fires nothing.
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ toncoin: 1n, 'ton-aaa': 2n })
      .mockResolvedValueOnce({ toncoin: 1n, 'ton-aaa': 2n });

    const { stream, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 1n, 'ton-aaa': 2n });
    expect(updateEvents).toEqual([
      { balances: { toncoin: 1n, 'ton-aaa': 2n }, source: 'poll' },
    ]);

    // A second identical poll must not fire any update.
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ toncoin: 1n, 'ton-aaa': 2n });
    expect(updateEvents).toEqual([
      { balances: { toncoin: 1n, 'ton-aaa': 2n }, source: 'poll' },
    ]);

    stream.destroy();
  });

  it('does not let a no-op socket re-emit block a genuinely fresher in-flight poll', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<ApiBalanceBySlug>({ toncoin: 100n });
    // The second poll is slow: it captures its freshness version, then a no-op socket delta arrives
    // (the same value already stored), and only afterwards does the poll resolve with a fresher value.
    const slowPoll = new Deferred<ApiBalanceBySlug>();
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockReturnValueOnce(slowPoll.promise);

    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });

    // Begin the slow second poll; its version is captured now, before the await resolves.
    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    expect(fetchBalances).toHaveBeenCalledTimes(2);

    const eventsBeforeNoop = updateEvents.length;

    // A no-op socket re-emit for `toncoin` arrives mid-flight: same value already stored.
    await deliverNativeSocketBalance(100n);
    // The no-op delta must neither change the balance nor fire an update.
    expect(await stream.getBalances()).toEqual({ toncoin: 100n });
    expect(updateEvents.length).toBe(eventsBeforeNoop);

    // The slow poll resolves with a genuinely fresher `toncoin`; the no-op delta must not block it.
    slowPoll.resolve({ toncoin: 200n });
    await jest.advanceTimersByTimeAsync(1);

    expect(await stream.getBalances()).toEqual({ toncoin: 200n });
    expect(updateEvents.at(-1)).toEqual({ balances: { toncoin: 200n }, source: 'poll' });

    stream.destroy();
  });
});
