import type { AbstractWebsocketClient, WalletWatcher } from './abstractWsClient';

import { BalanceStream } from './balanceStream';

const POLLING_OPTIONS = {
  pollOnStart: true,
  minPollDelay: 60_000,
  pollingStartDelay: 60_000,
  pollingPeriod: 60_000,
  forcedPollingPeriod: 60_000,
};

describe('BalanceStream', () => {
  afterEach(() => {
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
