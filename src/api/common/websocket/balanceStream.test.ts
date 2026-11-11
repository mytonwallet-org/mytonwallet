import type { ApiBalanceBySlug, ApiNetwork } from '../../types';
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
import { notifyTokenSlugsMove } from '../../common/tokenSlugMoves';
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

  it('drops at once and refetches the balance under a slug that passes to another token', async () => {
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const refetch = new Deferred();
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { 'ethereum-0x00000000': 400n } })
      .mockImplementationOnce(() => {
        refetch.resolve();
        return Promise.resolve({ balances: { 'ethereum-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n } });
      });
    const updateEvents: ApiBalanceBySlug[] = [];

    const stream = new BalanceStream({
      chain: 'ethereum',
      wsClient,
      network: 'mainnet',
      address: '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb: fetchBalances,
    });
    const firstLoad = new Promise<void>((resolve) => {
      stream.onLoadingChange((isLoading) => {
        if (!isLoading) resolve();
      });
    });
    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();
    await firstLoad;

    notifyTokenSlugsMove(['base-0x42000000']);
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(fetchBalances).toHaveBeenCalledTimes(1);

    notifyTokenSlugsMove(['ethereum-0x00000000']);
    expect(updateEvents.at(-1)).toEqual({});
    await refetch.promise;
    await new Promise((resolve) => setTimeout(resolve, 0));
    stream.destroy();

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(updateEvents.at(-1)).toEqual({ 'ethereum-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n });
  });

  it('polls again when a slug moves while its first poll, which assigned the old slug, is running', async () => {
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const firstPoll = new Deferred<StampedBalances>();
    const refetch = new Deferred();
    const fetchBalances = jest.fn()
      .mockReturnValueOnce(firstPoll.promise)
      .mockImplementationOnce(() => {
        refetch.resolve();
        return Promise.resolve({ balances: { 'ethereum-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n } });
      });
    const updateEvents: ApiBalanceBySlug[] = [];

    const stream = new BalanceStream({
      chain: 'ethereum',
      wsClient,
      network: 'mainnet',
      address: '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb: fetchBalances,
    });
    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(fetchBalances).toHaveBeenCalledTimes(1);

    notifyTokenSlugsMove(['ethereum-0x00000000']);
    firstPoll.resolve({ balances: { 'ethereum-0x00000000': 400n } });
    await refetch.promise;
    await new Promise((resolve) => setTimeout(resolve, 0));
    stream.destroy();

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(updateEvents.some((balances) => 'ethereum-0x00000000' in balances)).toBe(false);
    expect(updateEvents.at(-1)).toEqual({ 'ethereum-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n });
  });

  it('fetches every chain again when a moved slug of another chain was fetched with them', async () => {
    const watcher: WalletWatcher = {
      isConnected: false,
      destroy: jest.fn(),
    };
    const wsClient = {
      watchWallets: jest.fn(() => watcher),
    } as unknown as AbstractWebsocketClient<any, any, any, any, any>;
    const fetchBalances = jest.fn();
    const refetch = new Deferred();
    const fetchCrosschainBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { ethereum: 1n, 'base-0x00000000': 400n } })
      .mockImplementationOnce(() => {
        refetch.resolve();
        return Promise.resolve({ balances: { ethereum: 1n, 'base-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n } });
      });
    const updateEvents: ApiBalanceBySlug[] = [];

    const stream = new BalanceStream({
      chain: 'ethereum',
      wsClient,
      network: 'mainnet',
      address: '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb: fetchBalances,
      fetchCrosschainBalancesCb: fetchCrosschainBalances,
    });
    const firstLoad = new Promise<void>((resolve) => {
      stream.onLoadingChange((isLoading) => {
        if (!isLoading) resolve();
      });
    });
    stream.onUpdate((balances) => updateEvents.push(balances));
    stream.start();
    await firstLoad;

    notifyTokenSlugsMove(['base-0x00000000']);
    expect(updateEvents.at(-1)).toEqual({ ethereum: 1n });
    // A regular request queued after the move must not replace the cross-chain poll it asked for
    stream.markWalletActiveAndForcePoll();
    await refetch.promise;
    await new Promise((resolve) => setTimeout(resolve, 0));
    stream.destroy();

    expect(fetchBalances).not.toHaveBeenCalled();
    expect(updateEvents.at(-1)).toEqual({ ethereum: 1n, 'base-0x00000000f9fd50c832d79facfe6f4e8ce90a5efb': 400n });
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
    /** Fires a native-token socket delta and applies it (advances the 100ms throttle) */
    deliverNativeSocketBalance: (balance: bigint, blockNumber?: number) => Promise<void>;
    onBalanceUpdate: BalanceUpdateCallback;
    updateEvents: Array<{ balances: ApiBalanceBySlug; source: string }>;
  }

  /**
   * Builds a BalanceStream on the given chain, wired so the test can drive the socket path. The socket
   * `onBalanceUpdate` callback registered in the constructor is captured from the `watchWallets`
   * mock so the test can simulate live deltas arriving out of order with HTTP polls.
   */
  function createSocketScenario(
    fetchBalancesCb: jest.Mock,
    chain: 'ton' | 'polygon' | 'ethereum' | 'base' = 'ton',
    address = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
    fetchCrosschainBalancesCb?: jest.Mock,
    network: ApiNetwork = 'mainnet',
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
      network,
      address,
      sendUpdateTokens: jest.fn(),
      fallbackPollingOptions: FAST_POLLING_OPTIONS,
      fetchBalancesCb,
      fetchCrosschainBalancesCb,
    });

    stream.onUpdate((balances, source) => updateEvents.push({ balances: { ...balances }, source }));

    const deliverNativeSocketBalance = async (balance: bigint, blockNumber?: number) => {
      // `tokenAddress: undefined` denotes the chain native token.
      onBalanceUpdate!({ address, balance, blockNumber, finality: 'confirmed' });
      // The socket handler is throttled by 100ms, then awaits token preload before committing.
      await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
    };

    return { stream, deliverNativeSocketBalance, onBalanceUpdate: onBalanceUpdate!, updateEvents };
  }

  it('inherits cross-chain blocks until thirty minutes after publication', async () => {
    jest.useFakeTimers();

    const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
    const fetchBalances = jest.fn();
    let publishedAt = 0;
    const fetchCrosschainBalances = jest.fn(() => {
      publishedAt = Date.now();
      return Promise.resolve({ balances: { eth: 100n, base: 7n }, blockBySlug: { eth: 100, base: 110 } });
    });
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    const lateBase = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();
    lateBase.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(1);
      expect(fetchBalances).not.toHaveBeenCalled();
      expect(await publisher.stream.getBalances()).toEqual({ eth: 100n, base: 7n });

      jest.setSystemTime(publishedAt + 29 * 60_000);
      await base.deliverNativeSocketBalance(2n, 105);
      expect(base.updateEvents.at(-1)).toBeUndefined();

      await base.deliverNativeSocketBalance(3n, 111);
      expect(base.updateEvents.at(-1)).toEqual({ balances: { base: 3n }, source: 'socket' });

      jest.setSystemTime(publishedAt + 30 * 60_000);
      await lateBase.deliverNativeSocketBalance(2n, 105);
      expect(lateBase.updateEvents.at(-1)).toEqual({ balances: { base: 2n }, source: 'socket' });
      expect(fetchBalances).not.toHaveBeenCalled();
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
      lateBase.stream.destroy();
    }
  });

  it('removes a cross-chain block when the next publication does not provide one', async () => {
    jest.useFakeTimers();

    const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n, base: 7n }, blockBySlug: { base: 110 } })
      .mockResolvedValueOnce({ balances: { eth: 100n, base: 9n }, blockBySlug: {} });
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    const nextPublisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const nextBase = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(2n, 105);
      expect(base.updateEvents.at(-1)).toBeUndefined();

      publisher.stream.destroy();
      base.stream.destroy();
      nextPublisher.stream.start();
      nextBase.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(2);
      expect(await nextPublisher.stream.getBalances()).toEqual({ eth: 100n, base: 9n });

      await nextBase.deliverNativeSocketBalance(2n, 105);
      expect(nextBase.updateEvents.at(-1)).toEqual({ balances: { base: 2n }, source: 'socket' });
      expect(fetchBalances).not.toHaveBeenCalled();
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
      nextPublisher.stream.destroy();
      nextBase.stream.destroy();
    }
  });

  it('waits for a cross-chain snapshot before applying a socket delta', async () => {
    jest.useFakeTimers();

    const address = '0x0000000000000000000000000000000000000055';
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn();
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(2n, 105);

      expect(base.updateEvents).toEqual([]);
      expect(fetchBalances).not.toHaveBeenCalled();
      expect(fetchCrosschainBalances).not.toHaveBeenCalled();
    } finally {
      base.stream.destroy();
    }
  });

  it('inherits a pending cross-chain snapshot before applying later socket deltas', async () => {
    jest.useFakeTimers();

    const address = '0x0000000000000000000000000000000000000066';
    const tokenSlug = 'base-0x12345678';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn().mockReturnValue(pendingPoll.promise);
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(1);
      await base.deliverNativeSocketBalance(2n, 105);
      expect(base.updateEvents).toEqual([]);

      pendingPoll.resolve({
        balances: { eth: 100n, base: 7n, [tokenSlug]: 5n },
        blockBySlug: { base: 110, [tokenSlug]: 110 },
      });
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(2n, 105);
      expect(base.updateEvents).toEqual([]);

      await base.deliverNativeSocketBalance(8n, 111);
      expect(base.updateEvents.at(-1)).toEqual({
        balances: { base: 8n, [tokenSlug]: 5n }, source: 'socket',
      });
      expect(fetchBalances).not.toHaveBeenCalled();
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
    }
  });

  it.each([
    { scope: 'wallet', network: 'mainnet' as const, block: 115, foreignBlock: 120 },
    { scope: 'network', network: 'testnet' as const, block: 500, foreignBlock: 1000 },
  ])('scopes cross-chain stamps to each $scope', async ({ scope, network, block, foreignBlock }) => {
    jest.useFakeTimers();

    const address = '0x0000000000000000000000000000000000000011';
    const foreignAddress = scope === 'wallet' ? '0x0000000000000000000000000000000000000022' : address;
    const fetchBalances = jest.fn();
    const fetchTarget = jest.fn().mockResolvedValue({ balances: { base: 7n }, blockBySlug: { base: 110 } });
    const fetchForeign = jest.fn().mockResolvedValue({
      balances: { base: 9n }, blockBySlug: { base: foreignBlock },
    });
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchTarget, network);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchTarget, network);
    const foreignPublisher = createSocketScenario(fetchBalances, 'ethereum', foreignAddress, fetchForeign);
    const foreignBase = createSocketScenario(fetchBalances, 'base', foreignAddress, fetchForeign);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      foreignPublisher.stream.start();
      foreignBase.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchForeign).toHaveBeenCalledTimes(1);
      expect(fetchTarget).toHaveBeenCalledTimes(1);
      foreignPublisher.stream.destroy();
      foreignBase.stream.destroy();

      await base.deliverNativeSocketBalance(2n, block);
      expect(base.updateEvents.at(-1)).toEqual({ balances: { base: 2n }, source: 'socket' });
      expect(fetchBalances).not.toHaveBeenCalled();
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
      foreignPublisher.stream.destroy();
      foreignBase.stream.destroy();
    }
  });

  it('retains inherited token balances when its own snapshot has an older block', async () => {
    jest.useFakeTimers();

    const address = '0x0000000000000000000000000000000000000033';
    const tokenSlug = 'base-0x12345678';
    const otherTokenSlug = 'base-0x98765432';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn().mockReturnValue(pendingPoll.promise);
    const fetchCrosschainBalances = jest.fn().mockResolvedValue({
      balances: { base: 7n, [tokenSlug]: 5n, [otherTokenSlug]: 0n },
      blockBySlug: { base: 110, [tokenSlug]: 110 },
    });
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(8n, 111);
      base.stream.markWalletActiveAndForcePoll();
      await Promise.resolve();
      expect(fetchBalances).toHaveBeenCalledTimes(1);

      pendingPoll.resolve({
        balances: { base: 8n, [tokenSlug]: 4n, [otherTokenSlug]: 0n },
        blockBySlug: { base: 111, [tokenSlug]: 100, [otherTokenSlug]: 112 },
      });
      await jest.advanceTimersByTimeAsync(1);

      expect(base.updateEvents.at(-1)?.balances).toEqual({ base: 8n, [tokenSlug]: 5n, [otherTokenSlug]: 0n });
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
    }
  });

  it('does not inherit the token balances of the previous polling cycle', async () => {
    jest.useFakeTimers();

    const address = '0x00000000000000000000000000000000000000a1';
    const tokenSlug = 'base-0x12345678';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { base: 7n, [tokenSlug]: 5n } })
      .mockReturnValueOnce(pendingPoll.promise);
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    const nextPublisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const nextBase = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      expect(await publisher.stream.getBalances()).toEqual({ base: 7n, [tokenSlug]: 5n });

      publisher.stream.destroy();
      base.stream.destroy();
      nextPublisher.stream.start();
      nextBase.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(2);

      await nextBase.deliverNativeSocketBalance(8n, 111);
      expect(nextBase.updateEvents).toEqual([]);

      pendingPoll.resolve({ balances: { base: 7n, [tokenSlug]: 1n } });
      await jest.advanceTimersByTimeAsync(1);
      await nextBase.deliverNativeSocketBalance(9n, 112);
      expect(nextBase.updateEvents.at(-1)).toEqual({ balances: { base: 9n, [tokenSlug]: 1n }, source: 'socket' });
      expect(fetchBalances).not.toHaveBeenCalled();
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
      nextPublisher.stream.destroy();
      nextBase.stream.destroy();
    }
  });

  it('does not let a stream without its own balances inherit a moved slug', async () => {
    jest.useFakeTimers();

    const address = '0x00000000000000000000000000000000000000a2';
    const tokenSlug = 'base-0x12345678';
    const fetchBalances = jest.fn().mockReturnValue(new Deferred<StampedBalances>().promise);
    const fetchCrosschainBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { base: 7n, [tokenSlug]: 5n } })
      .mockReturnValue(new Deferred<StampedBalances>().promise);
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      notifyTokenSlugsMove([tokenSlug]);

      await base.deliverNativeSocketBalance(8n, 111);
      expect(base.updateEvents.at(-1)).toEqual({ balances: { base: 8n }, source: 'socket' });
      expect(fetchBalances).toHaveBeenCalledTimes(1);
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
    }
  });

  it('does not publish the cross-chain balances a destroyed stream fetched', async () => {
    jest.useFakeTimers();

    const address = '0x00000000000000000000000000000000000000a3';
    const tokenSlug = 'base-0x12345678';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn().mockReturnValue(pendingPoll.promise);
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(1);
      publisher.stream.destroy();
      pendingPoll.resolve({ balances: { base: 7n, [tokenSlug]: 5n } });
      await jest.advanceTimersByTimeAsync(1);

      base.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(8n, 111);
      expect(base.updateEvents).toEqual([]);
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
    }
  });

  it('keeps the cross-chain entry of a live stream when another stream of the address is destroyed', async () => {
    jest.useFakeTimers();

    const address = '0x00000000000000000000000000000000000000a4';
    const tokenSlug = 'base-0x12345678';
    const fetchBalances = jest.fn();
    const fetchFirst = jest.fn().mockResolvedValue({ balances: { base: 7n, [tokenSlug]: 5n } });
    const fetchSecond = jest.fn().mockResolvedValue({ balances: { base: 6n } });
    const first = createSocketScenario(fetchBalances, 'ethereum', address, fetchFirst);
    const second = createSocketScenario(fetchBalances, 'ethereum', address, fetchSecond);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchSecond);
    first.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      second.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      first.stream.destroy();

      base.stream.start();
      await jest.advanceTimersByTimeAsync(1);
      await base.deliverNativeSocketBalance(8n, 111);
      expect(base.updateEvents.at(-1)).toEqual({ balances: { base: 8n }, source: 'socket' });
    } finally {
      first.stream.destroy();
      second.stream.destroy();
      base.stream.destroy();
    }
  });

  it('does not publish a slug that moved while the cross-chain request was running', async () => {
    jest.useFakeTimers();

    const address = '0x00000000000000000000000000000000000000a5';
    const tokenSlug = 'base-0x12345678';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn();
    const fetchCrosschainBalances = jest.fn()
      .mockReturnValueOnce(pendingPoll.promise)
      .mockReturnValue(new Deferred<StampedBalances>().promise);
    const publisher = createSocketScenario(fetchBalances, 'ethereum', address, fetchCrosschainBalances);
    const base = createSocketScenario(fetchBalances, 'base', address, fetchCrosschainBalances);
    publisher.stream.start();
    base.stream.start();

    try {
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(1);
      notifyTokenSlugsMove([tokenSlug]);
      pendingPoll.resolve({ balances: { base: 7n, [tokenSlug]: 5n } });
      await jest.advanceTimersByTimeAsync(1);
      expect(fetchCrosschainBalances).toHaveBeenCalledTimes(2);

      await base.deliverNativeSocketBalance(8n, 111);
      expect(base.updateEvents.at(-1)).toEqual({ balances: { base: 8n }, source: 'socket' });
    } finally {
      publisher.stream.destroy();
      base.stream.destroy();
    }
  });

  it('keeps the socket balance until the positions snapshot reaches its block', async () => {
    jest.useFakeTimers();

    const oldBalance = 24_120_000_000_000_000_000n;
    const socketBalance = 2_000_000_000_000_000n;
    const receivedBalance = 500_000_000_000_000_000n;
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: oldBalance }, blockBySlug: { eth: 100 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: oldBalance }, blockBySlug: { eth: 100 }, asOf: Date.now(),
      }))
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: oldBalance }, blockBySlug: { eth: 100 }, asOf: Date.now(),
      }))
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: receivedBalance }, blockBySlug: { eth: 105 }, asOf: Date.now(),
      }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    await deliverNativeSocketBalance(socketBalance, 105);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: socketBalance });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: socketBalance }, source: 'socket' });

    jest.setSystemTime(Date.now() + 10 * 60_000);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: socketBalance });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(4);
    expect(await stream.getBalances()).toEqual({ eth: receivedBalance });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: receivedBalance }, source: 'poll' });
    stream.destroy();
  });

  it.each([
    { isSocketDuringPoll: false },
    { isSocketDuringPoll: true },
  ])('keeps a confirmed balance against an older fallback block: %j', async ({ isSocketDuringPoll }) => {
    jest.useFakeTimers();

    const cachedPositionsAt = Date.now();
    const confirmingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      // The RPC read at block 106 confirms the socket balance next to cached positions
      .mockReturnValueOnce(confirmingPoll.promise)
      // The RPC read fails and the same cached positions page supplies the balance before the transfer
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 100n }, blockBySlug: { eth: 100 }, asOf: cachedPositionsAt,
      }));
    const { stream, deliverNativeSocketBalance } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    if (!isSocketDuringPoll) await deliverNativeSocketBalance(2n, 105);
    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    if (isSocketDuringPoll) await deliverNativeSocketBalance(2n, 105);
    confirmingPoll.resolve({ balances: { eth: 2n }, blockBySlug: { eth: 106 }, asOf: cachedPositionsAt });
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 2n });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: 2n });
    stream.destroy();
  });

  it.each([
    { block: 110, expectedBalance: 7n },
    { block: 104, expectedBalance: 2n },
  ])('ranks snapshot block $block before an older observation time', async ({ block, expectedBalance }) => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 7n }, blockBySlug: { eth: block }, asOf: Date.now() - 60_000,
      }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(2n, 105);

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: expectedBalance });
    expect(updateEvents.at(-1)).toEqual({
      balances: { eth: expectedBalance }, source: block >= 105 ? 'poll' : 'socket',
    });
    stream.destroy();
  });

  it.each([
    { block: 105, expectedBalance: 7n },
    { block: 104, expectedBalance: 2n },
  ])('ranks an in-flight snapshot block $block per slug', async ({ block, expectedBalance }) => {
    jest.useFakeTimers();

    const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
    const tokenAddress = '0x1234567890123456789012345678901234567890';
    const tokenSlug = 'ethereum-0x12345678';
    const slowPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n, [tokenSlug]: 100n }, blockBySlug: { eth: 100 } })
      .mockReturnValueOnce(slowPoll.promise);
    const { stream, deliverNativeSocketBalance, onBalanceUpdate, updateEvents } = createSocketScenario(
      fetchBalances, 'ethereum', address,
    );
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    expect(fetchBalances).toHaveBeenCalledTimes(2);

    await deliverNativeSocketBalance(2n, 105);
    onBalanceUpdate({ address, tokenAddress, balance: 3n, finality: 'confirmed' });
    await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);

    slowPoll.resolve({
      balances: { eth: 7n, [tokenSlug]: 50n }, blockBySlug: { eth: block }, asOf: Date.now() - 60_000,
    });
    await jest.advanceTimersByTimeAsync(1);

    expect(await stream.getBalances()).toEqual({ eth: expectedBalance, [tokenSlug]: 3n });
    expect(updateEvents.at(-1)).toEqual({
      balances: { eth: expectedBalance, [tokenSlug]: 3n }, source: block >= 105 ? 'poll' : 'socket',
    });
    stream.destroy();
  });

  it('allows a lower-block snapshot exactly thirty minutes after the socket observation', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementation(() => Promise.resolve({
        balances: { eth: 50n }, blockBySlug: { eth: 100 }, asOf: Date.now(),
      }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(2n, 105);
    const observedAt = Date.now();

    jest.setSystemTime(observedAt + 30 * 60_000 - 1);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(0);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 2n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 2n }, source: 'socket' });

    await jest.advanceTimersByTimeAsync(1);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(0);

    expect(Date.now()).toBe(observedAt + 30 * 60_000);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: 50n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 50n }, source: 'poll' });
    stream.destroy();
  });

  it.each([
    {
      name: 'refreshes the block stamp on a no-op socket re-emit',
      firstBalance: 2n, firstBlock: 105, secondBlock: 106, expectedBalance: 2n,
    },
    {
      name: 'keeps the largest block across separate socket batches',
      firstBalance: 3n, firstBlock: 106, secondBlock: 105, expectedBalance: 3n,
    },
  ])('$name', async ({ firstBalance, firstBlock, secondBlock, expectedBalance }) => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 50n }, blockBySlug: { eth: 105 }, asOf: Date.now(),
      }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    await deliverNativeSocketBalance(firstBalance, firstBlock);
    await deliverNativeSocketBalance(2n, secondBlock);

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: expectedBalance });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: expectedBalance }, source: 'socket' });
    stream.destroy();
  });

  it('ignores an older socket block until the thirty-minute stamp expires', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn().mockResolvedValue({ balances: { eth: 100n }, blockBySlug: { eth: 100 } });
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(3n, 106);
    const observedAt = Date.now();

    jest.setSystemTime(observedAt + 29 * 60_000);
    await deliverNativeSocketBalance(2n, 105);

    expect(await stream.getBalances()).toEqual({ eth: 3n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 3n }, source: 'socket' });

    jest.setSystemTime(observedAt + 30 * 60_000);
    await deliverNativeSocketBalance(2n, 105);

    expect(await stream.getBalances()).toEqual({ eth: 2n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 2n }, source: 'socket' });
    stream.destroy();
  });

  it.each([
    { path: 'fast', isSocketDuringPoll: false },
    { path: 'slow', isSocketDuringPoll: true },
  ])('ranks delayed socket blocks against a poll-only stamp in the $path path', async ({ isSocketDuringPoll }) => {
    jest.useFakeTimers();

    const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
    const tokenAddress = '0x1234567890123456789012345678901234567890';
    const tokenSlug = 'ethereum-0x12345678';
    const pendingPoll = new Deferred<StampedBalances>();
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n, [tokenSlug]: 100n } })
      .mockReturnValueOnce(pendingPoll.promise);
    const { stream, deliverNativeSocketBalance, onBalanceUpdate, updateEvents } = createSocketScenario(
      fetchBalances, 'ethereum', address,
    );
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    stream.markWalletActiveAndForcePoll();
    await Promise.resolve();
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    if (isSocketDuringPoll) {
      onBalanceUpdate({ address, tokenAddress, balance: 3n, finality: 'confirmed' });
      await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
    }
    pendingPoll.resolve({ balances: { eth: 7n, [tokenSlug]: 100n }, blockBySlug: { eth: 110 } });
    await jest.advanceTimersByTimeAsync(1);
    const observedAt = Date.now();
    const expectedBalances = { eth: 7n, [tokenSlug]: isSocketDuringPoll ? 3n : 100n };
    expect(await stream.getBalances()).toEqual(expectedBalances);

    jest.setSystemTime(observedAt + 29 * 60_000);
    await deliverNativeSocketBalance(2n, 105);
    expect(await stream.getBalances()).toEqual(expectedBalances);
    expect(updateEvents.at(-1)).toEqual({ balances: expectedBalances, source: 'poll' });

    jest.setSystemTime(observedAt + 30 * 60_000);
    await deliverNativeSocketBalance(2n, 105);
    expect(await stream.getBalances()).toEqual({ ...expectedBalances, eth: 2n });
    expect(updateEvents.at(-1)).toEqual({ balances: { ...expectedBalances, eth: 2n }, source: 'socket' });
    stream.destroy();
  });

  it('keeps a poll-only block against fallback positions and removes an absent position immediately', async () => {
    jest.useFakeTimers();

    const tokenSlug = 'ethereum-0x12345678';
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n, [tokenSlug]: 7n }, blockBySlug: { [tokenSlug]: 110 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 100n, [tokenSlug]: 50n }, blockBySlug: { [tokenSlug]: 100 }, asOf: Date.now(),
      }))
      .mockImplementationOnce(() => Promise.resolve({ balances: { eth: 100n }, blockBySlug: {}, asOf: Date.now() }));
    const { stream, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 100n, [tokenSlug]: 7n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 100n, [tokenSlug]: 7n }, source: 'poll' });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: 100n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 100n }, source: 'poll' });
    stream.destroy();
  });

  it('replaces a poll-only block stamp with a newer socket block', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 7n }, blockBySlug: { eth: 110 } })
      .mockResolvedValueOnce({ balances: { eth: 8n }, blockBySlug: { eth: 120 } })
      .mockImplementationOnce(() => Promise.resolve({ balances: {}, blockBySlug: {}, asOf: Date.now() }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    await deliverNativeSocketBalance(2n, 105);
    expect(await stream.getBalances()).toEqual({ eth: 7n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 7n }, source: 'poll' });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 8n });

    await deliverNativeSocketBalance(2n, 115);
    expect(await stream.getBalances()).toEqual({ eth: 8n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 8n }, source: 'poll' });

    await deliverNativeSocketBalance(3n, 121);
    expect(await stream.getBalances()).toEqual({ eth: 3n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 3n }, source: 'socket' });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: 3n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 3n }, source: 'socket' });
    stream.destroy();
  });

  it('ignores a socket block older than the stamp carried from a snapshot', async () => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 7n }, blockBySlug: { eth: 110 }, asOf: Date.now(),
      }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(2n, 105);
    const observedAt = Date.now();

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 7n });

    jest.setSystemTime(observedAt + 29 * 60_000);
    await deliverNativeSocketBalance(3n, 109);

    expect(await stream.getBalances()).toEqual({ eth: 7n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 7n }, source: 'poll' });

    jest.setSystemTime(observedAt + 30 * 60_000);
    await deliverNativeSocketBalance(3n, 109);

    expect(await stream.getBalances()).toEqual({ eth: 3n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 3n }, source: 'socket' });
    stream.destroy();
  });

  it.each([false, true])('clears a batched block at an unstamped delta, then accepts a known block: %s',
    async (hasLaterKnownBlock) => {
      jest.useFakeTimers();

      const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
      const fetchBalances = jest.fn()
        .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
        .mockImplementationOnce(() => Promise.resolve({
          balances: { eth: 7n }, blockBySlug: { eth: 105 }, asOf: Date.now(),
        }));
      const { stream, onBalanceUpdate } = createSocketScenario(fetchBalances, 'ethereum', address);
      stream.start();
      await jest.advanceTimersByTimeAsync(1);

      onBalanceUpdate({ address, balance: 3n, blockNumber: 110, finality: 'confirmed' });
      onBalanceUpdate({ address, balance: 2n, finality: 'confirmed' });
      if (hasLaterKnownBlock) {
        onBalanceUpdate({ address, balance: 1n, blockNumber: 105, finality: 'confirmed' });
      }
      await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);
      expect(await stream.getBalances()).toEqual({ eth: hasLaterKnownBlock ? 1n : 2n });

      stream.markWalletActiveAndForcePoll();
      await jest.advanceTimersByTimeAsync(1);

      expect(fetchBalances).toHaveBeenCalledTimes(2);
      expect(await stream.getBalances()).toEqual({ eth: 7n });
      stream.destroy();
    });

  it.each([
    { balances: { eth: 0n } },
    { balances: {} },
  ])('protects a missing position block for ten minutes: $balances', async ({ balances }) => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementation(() => Promise.resolve({ balances, blockBySlug: {}, asOf: Date.now() }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(2n, 105);

    jest.setSystemTime(Date.now() + 10 * 60_000 - 2);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 2n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 2n }, source: 'socket' });

    jest.setSystemTime(Date.now() + 2);
    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual(balances);
    expect(updateEvents.at(-1)).toEqual({ balances, source: 'poll' });
    stream.destroy();
  });

  it.each([
    { blockNumber: 105, blockBySlug: undefined },
    { blockNumber: undefined, blockBySlug: { eth: 100 } },
  ])('uses existing ordering without blocks on both sources: %j', async ({ blockNumber, blockBySlug }) => {
    jest.useFakeTimers();

    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n }, blockBySlug: { eth: 100 } })
      .mockImplementationOnce(() => Promise.resolve({ balances: { eth: 500n }, blockBySlug, asOf: Date.now() }));
    const { stream, deliverNativeSocketBalance, updateEvents } = createSocketScenario(fetchBalances, 'ethereum');
    stream.start();
    await jest.advanceTimersByTimeAsync(1);
    await deliverNativeSocketBalance(2n, blockNumber);

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);

    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 500n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 500n }, source: 'poll' });
    stream.destroy();
  });

  it('carries the maximum block per token through a throttled socket batch', async () => {
    jest.useFakeTimers();

    const address = '0x41835810168DEaf5B36c2F38c0fE24a87675Ae49';
    const tokenAddress = '0x1234567890123456789012345678901234567890';
    const tokenSlug = 'ethereum-0x12345678';
    const fetchBalances = jest.fn()
      .mockResolvedValueOnce({ balances: { eth: 100n, [tokenSlug]: 100n }, blockBySlug: { [tokenSlug]: 100 } })
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 100n, [tokenSlug]: 500n }, blockBySlug: { [tokenSlug]: 107 }, asOf: Date.now(),
      }))
      .mockImplementationOnce(() => Promise.resolve({
        balances: { eth: 100n, [tokenSlug]: 500n }, blockBySlug: { [tokenSlug]: 110 }, asOf: Date.now(),
      }));
    const { stream, onBalanceUpdate, updateEvents } = createSocketScenario(fetchBalances, 'ethereum', address);
    stream.start();
    await jest.advanceTimersByTimeAsync(1);

    onBalanceUpdate({ address, tokenAddress, balance: 3n, blockNumber: 110, finality: 'confirmed' });
    onBalanceUpdate({ address, tokenAddress, balance: 2n, blockNumber: 105, finality: 'confirmed' });
    onBalanceUpdate({ address, balance: 100n, blockNumber: 999, finality: 'confirmed' });
    await jest.advanceTimersByTimeAsync(SOCKET_THROTTLE_DELAY);

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(2);
    expect(await stream.getBalances()).toEqual({ eth: 100n, [tokenSlug]: 3n });
    expect(updateEvents.at(-1)).toEqual({ balances: { eth: 100n, [tokenSlug]: 3n }, source: 'socket' });

    stream.markWalletActiveAndForcePoll();
    await jest.advanceTimersByTimeAsync(1);
    expect(fetchBalances).toHaveBeenCalledTimes(3);
    expect(await stream.getBalances()).toEqual({ eth: 100n, [tokenSlug]: 500n });
    stream.destroy();
  });

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
