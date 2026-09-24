import { recordTonConnectEvent } from './analytics';

// Covers two throttled flush cycles, so the batch is sent and the throttle becomes idle for the next test
const FLUSH_WAIT_MS = 5000;

const mockFetch = jest.fn();

jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  TON_CONNECT_ANALYTICS_URL: 'https://analytics.example',
}));

jest.mock('../../../common/accounts', () => ({
  getCurrentNetwork: () => Promise.resolve('mainnet'),
}));

jest.mock('../../../common/cache', () => ({
  getBackendConfigCacheSync: () => ({ isTonConnectAnalyticsEnabled: true }),
  getBackendConfigCache: () => Promise.resolve({ isTonConnectAnalyticsEnabled: true }),
}));

// The dapp modals cancel their request after the close animation even when the request has already succeeded,
// so a decline recorded after an acceptance must not reach the collector
describe('recordTonConnectEvent decision events', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    mockFetch.mockReset().mockResolvedValue(undefined);
    global.fetch = mockFetch;
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('drops a transaction decline that follows the acceptance', async () => {
    await recordTonConnectEvent({ event_name: 'wallet-transaction-accepted', promiseId: 'accepted-transaction' });
    await recordTonConnectEvent({ event_name: 'wallet-transaction-declined', promiseId: 'accepted-transaction' });

    expect(await flushSentEventNames()).toEqual(['wallet-transaction-accepted']);
  });

  it('drops a sign data decline that follows the acceptance', async () => {
    await recordTonConnectEvent({ event_name: 'wallet-sign-data-accepted', promiseId: 'accepted-sign-data' });
    await recordTonConnectEvent({ event_name: 'wallet-sign-data-declined', promiseId: 'accepted-sign-data' });

    expect(await flushSentEventNames()).toEqual(['wallet-sign-data-accepted']);
  });

  it('sends a decline for a request that was not accepted', async () => {
    await recordTonConnectEvent({ event_name: 'wallet-transaction-declined', promiseId: 'declined-transaction' });

    expect(await flushSentEventNames()).toEqual(['wallet-transaction-declined']);
  });
});

async function flushSentEventNames() {
  await jest.advanceTimersByTimeAsync(FLUSH_WAIT_MS);

  return mockFetch.mock.calls
    .flatMap(([, init]: [string, RequestInit]) => JSON.parse(init.body as string) as { event_name: string }[])
    .map((event) => event.event_name);
}
