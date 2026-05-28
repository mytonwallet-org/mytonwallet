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
});
