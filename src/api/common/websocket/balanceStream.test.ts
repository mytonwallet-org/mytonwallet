import type { ApiBalanceBySlug } from '../../types';
import type { StampedBalances } from '../../types';
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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { toncoin: 123n } }));
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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { toncoin: 123n } }));

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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { bnb: 123n } }));
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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { 'bnb-0x8ac76a51': 456n } }));
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
      .mockResolvedValueOnce({ balances: { bnb: 1n } })
      .mockResolvedValueOnce({ balances: { bnb: 2n } });
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

  it('applies a socket delta that arrives on an inactive wallet and fetches balances', async () => {
    jest.useFakeTimers();
    tokensPreload.resolve();

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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { bnb: 7n } }));
    const updateEvents: unknown[] = [];
    const address = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

    const stream = new BalanceStream({
      chain: 'bnb',
      wsClient,
      network: 'mainnet',
      address,
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: {
        pollOnStart: true,
        minPollDelay: 1,
        pollingStartDelay: 60_000,
        pollingPeriod: 60_000,
        forcedPollingPeriod: 60_000,
      },
      fetchBalancesCb: fetchBalances,
      ensureIsPollingNeeded: jest.fn().mockResolvedValue(false),
    });

    stream.onUpdate((balances) => updateEvents.push({ ...balances }));
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).not.toHaveBeenCalled();
    expect(updateEvents).toEqual([]);

    onBalanceUpdate!({ address, balance: 5n, finality: 'confirmed' });
    await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
    await jest.advanceTimersByTimeAsync(1);
    stream.destroy();

    expect(updateEvents).toContainEqual({ bnb: 5n });
    expect(fetchBalances).toHaveBeenCalledTimes(1);
  });

  it('applies a socket delta that arrives while the inactive precheck is still in flight', async () => {
    jest.useFakeTimers();
    tokensPreload.resolve();

    const precheck = new Deferred<boolean>();
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
    const fetchBalances = jest.fn(() => Promise.resolve({ balances: { bnb: 9n } }));
    const updateEvents: unknown[] = [];
    const address = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

    const stream = new BalanceStream({
      chain: 'bnb',
      wsClient,
      network: 'mainnet',
      address,
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: {
        pollOnStart: true,
        minPollDelay: 1,
        pollingStartDelay: 60_000,
        pollingPeriod: 60_000,
        forcedPollingPeriod: 60_000,
      },
      fetchBalancesCb: fetchBalances,
      ensureIsPollingNeeded: () => precheck.promise,
    });

    stream.onUpdate((balances) => updateEvents.push({ ...balances }));
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).not.toHaveBeenCalled();

    onBalanceUpdate!({ address, balance: 3n, finality: 'confirmed' });
    await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);

    expect(updateEvents).toEqual([{ bnb: 3n }]);

    precheck.resolve(false);
    await jest.advanceTimersByTimeAsync(1);
    stream.destroy();

    expect(fetchBalances).toHaveBeenCalled();
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
   * Builds a BalanceStream on the given chain, wired so the test can drive the socket path. The socket
   * `onBalanceUpdate` callback registered in the constructor is captured from the `watchWallets`
   * mock so the test can simulate live deltas arriving out of order with HTTP polls.
   */
  function createSocketScenario(
    fetchBalancesCb: jest.Mock,
    chain: 'ton' | 'polygon' = 'ton',
    address = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
  ): SocketScenario {
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
      chain,
      wsClient,
      network: 'mainnet',
      address,
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb,
    });

    stream.onUpdate((balances, source) => updateEvents.push({ balances: { ...balances }, source }));

    const deliverNativeSocketBalance = async (balance: bigint) => {
      // `tokenAddress: undefined` denotes the chain native token.
      onBalanceUpdate!({ address, balance, finality: 'confirmed' });
      // The socket handler is throttled by 100ms, then awaits token preload before committing.
      await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
    };

    return { stream, deliverNativeSocketBalance, updateEvents };
  }

  it('keeps a fresher socket balance when an older poll (started before the delta) resolves later', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { toncoin: 100n } });
    // The second poll is slow: it captures its freshness version, then a socket delta arrives,
    // and only afterwards does the poll resolve with a now-stale value for `toncoin`.
    const slowPoll = new Deferred<StampedBalances>();
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
    slowPoll.resolve({ balances: { toncoin: 100n, 'ton-fresh': 999n } });
    await jest.advanceTimersByTimeAsync(1);

    const balances = await stream.getBalances();
    // The fresher socket value for `toncoin` survives; the new slug from the poll still applies.
    expect(balances).toEqual({ toncoin: 555n, 'ton-fresh': 999n });

    stream.destroy();
  });

  it('applies a socket delta on a non-standard EVM chain once the stream has its own balances', async () => {
    jest.useFakeTimers();

    // A polygon stream (standard chain: ethereum) that has completed its own poll. The
    // cross-chain assets map is untouched, as for an account whose ethereum stream is inactive.
    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { pol: 100n } });
    const fetchBalances = jest.fn().mockReturnValueOnce(firstPoll.promise);

    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(
      fetchBalances, 'polygon', '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49',
    );
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    expect(updateEvents.at(-1)).toEqual({ balances: { pol: 100n }, source: 'poll' });

    await deliverNativeSocketBalance(555n);

    expect(updateEvents.at(-1)).toEqual({ balances: { pol: 555n }, source: 'socket' });

    stream.destroy();
  });

  it('does not let a snapshot observed before a delta overwrite the slug that delta refreshed', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-08-26T10:02:09.000Z'));

    // The measured production case: a delta lands, then a poll STARTS (so it wins on the client
    // clock) and returns a page the gateway observed a minute earlier, before the transaction.
    const observedBeforeTheDelta = Date.now() - 60_000;
    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { toncoin: 100n } });
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockResolvedValueOnce({ balances: { toncoin: 100n }, asOf: observedBeforeTheDelta });

    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances);
    stream.start();

    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(555n);
    expect(await stream.getBalances()).toEqual({ toncoin: 555n });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(await stream.getBalances()).toEqual({ toncoin: 555n });
    expect(updateEvents.at(-1)).toEqual({ balances: { toncoin: 555n }, source: 'socket' });

    stream.destroy();
  });

  it('ranks a slug an unstamped snapshot rewrote by the clock, not by the instant it used to carry',
    async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-08-26T10:02:09.000Z'));

      const observedByTheFirstPoll = Date.now() - 120_000;
      const firstPoll = Deferred.resolved<StampedBalances>({
        balances: { toncoin: 100n, 'ton-tok': 5n },
        asOf: observedByTheFirstPoll,
      });
      // The gateway degrades and answers without an instant, so `ton-tok` loses its provenance.
      const unstampedPoll = new Deferred<StampedBalances>();
      const laterPoll = Deferred.resolved<StampedBalances>({
        balances: { toncoin: 555n, 'ton-tok': 9n },
        asOf: observedByTheFirstPoll - 30_000,
      });
      const fetchBalances = jest.fn()
        .mockReturnValueOnce(firstPoll.promise)
        .mockReturnValueOnce(unstampedPoll.promise)
        .mockReturnValueOnce(laterPoll.promise);

      const { stream, deliverNativeSocketBalance } = createSocketScenario(fetchBalances);
      stream.start();

      await jest.advanceTimersByTimeAsync(1);
      expect(await stream.getBalances()).toEqual({ toncoin: 100n, 'ton-tok': 5n });

      stream.markWalletActiveAndForcePoll();
      await Promise.resolve();
      expect(fetchBalances).toHaveBeenCalledTimes(2);

      // A delta on `toncoin` lands while the unstamped poll is in flight, so the merge runs
      // per-slug and `ton-tok` is written by a source that states no instant.
      await deliverNativeSocketBalance(555n);
      unstampedPoll.resolve({ balances: { toncoin: 100n, 'ton-tok': 7n } });
      await jest.advanceTimersByTimeAsync(1);
      expect(await stream.getBalances()).toEqual({ toncoin: 555n, 'ton-tok': 7n });

      stream.markWalletActiveAndForcePoll();
      await jest.advanceTimersByTimeAsync(1);

      // `toncoin` still carries the delta's instant and holds against this older page, while
      // `ton-tok`, whose stored value has no instant, is ranked by the clock and updates.
      expect(await stream.getBalances()).toEqual({ toncoin: 555n, 'ton-tok': 9n });

      stream.destroy();
    });

  it('lets a poll that started after a socket delta overwrite that slug', async () => {
    jest.useFakeTimers();

    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { toncoin: 100n } });
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockResolvedValueOnce({ balances: { toncoin: 777n } });

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

    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { toncoin: 100n } });
    const slowPoll = new Deferred<StampedBalances>();
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
    slowPoll.resolve({ balances: { 'ton-other': 42n } });
    await jest.advanceTimersByTimeAsync(1);

    const balances = await stream.getBalances();
    // The stale poll must not remove the slug refreshed by the newer socket delta.
    expect(balances).toEqual({ toncoin: 555n, 'ton-other': 42n });

    stream.destroy();
  });

  it('lets a fresh poll drop a slug that is absent from its snapshot', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { toncoin: 100n, 'ton-gone': 5n } })
      .mockResolvedValueOnce({ balances: { toncoin: 100n } });

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
      .mockResolvedValueOnce({ balances: { toncoin: 1n, 'ton-aaa': 2n } })
      .mockResolvedValueOnce({ balances: { toncoin: 3n, 'ton-bbb': 4n } });

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
      .mockResolvedValueOnce({ balances: { toncoin: 1n, 'ton-aaa': 2n } })
      .mockResolvedValueOnce({ balances: { toncoin: 1n, 'ton-aaa': 2n } });

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

    const firstPoll = Deferred.resolved<StampedBalances>({ balances: { toncoin: 100n } });
    // The second poll is slow: it captures its freshness version, then a no-op socket delta arrives
    // (the same value already stored), and only afterwards does the poll resolve with a fresher value.
    const slowPoll = new Deferred<StampedBalances>();
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
    slowPoll.resolve({ balances: { toncoin: 200n } });
    await jest.advanceTimersByTimeAsync(1);

    expect(await stream.getBalances()).toEqual({ toncoin: 200n });
    expect(updateEvents.at(-1)).toEqual({ balances: { toncoin: 200n }, source: 'poll' });

    stream.destroy();
  });
});
