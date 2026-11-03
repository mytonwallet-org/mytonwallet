import { FallbackPollingScheduler } from '../../../common/polling/fallbackPollingScheduler';
import { activeNftTiming, inactiveNftTiming, periodToMs } from '../../../common/polling/utils';
import { streamAllAccountNfts } from '../nfts';
import { inactiveWallets } from './inactiveWallets';
import { NftStream } from './nftStream';

const mockSocketHandlers: { onConnect?: NoneToVoidFunction } = {};

jest.mock('../nfts', () => ({
  fetchNftByAddress: jest.fn(),
  streamAllAccountNfts: jest.fn(),
}));

jest.mock('./socket', () => ({
  getAlchemySocket: jest.fn(() => ({
    watchWallets: jest.fn((_wallets, handlers) => {
      Object.assign(mockSocketHandlers, handlers);
      return { isConnected: true, destroy: jest.fn() };
    }),
  })),
}));

jest.mock('../../../common/polling/fallbackPollingScheduler', () => ({
  FallbackPollingScheduler: jest.fn().mockImplementation(() => ({
    forceImmediatePoll: jest.fn(),
    onSocketConnect: jest.fn(),
    onSocketDisconnect: jest.fn(),
    onSocketMessage: jest.fn(),
    destroy: jest.fn(),
  })),
}));

const mockedStreamAllAccountNfts = jest.mocked(streamAllAccountNfts);
const MockedFallbackPollingScheduler = jest.mocked(FallbackPollingScheduler);
const [, INACTIVE_RECHECK_MS] = periodToMs(inactiveNftTiming.forcedPollingPeriod);

let now = 0;
let dateNowSpy: jest.SpyInstance;

function createStream() {
  const stream = new NftStream('base', 'mainnet', '0xa1', '0-mainnet', activeNftTiming);
  const poll = MockedFallbackPollingScheduler.mock.calls[0][0] as () => Promise<void>;
  const scheduler = MockedFallbackPollingScheduler.mock.results[0].value as jest.Mocked<FallbackPollingScheduler>;

  return { stream, poll, scheduler };
}

describe('NftStream', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    inactiveWallets.reset();
    now = Date.parse('2026-10-31T00:00:00Z');
    dateNowSpy = jest.spyOn(Date, 'now').mockImplementation(() => now);
    mockedStreamAllAccountNfts.mockReset();
    mockedStreamAllAccountNfts.mockImplementation((_chain, _accountId, options) => {
      if (!options.ignorePreCheck) options.onPreCheckResult?.(false);
      return Promise.resolve();
    });
  });

  afterEach(() => {
    dateNowSpy.mockRestore();
  });

  it('leaves an empty wallet to events and rechecks it only at the pace of an inactive NFT stream', async () => {
    const { poll } = createStream();

    await poll();
    await poll();
    now += INACTIVE_RECHECK_MS - 1;
    await poll();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);

    now += 1;
    await poll();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
  });

  // A first NFT that lands before the first subscription or during an outage leaves no event behind,
  // and a verdict cached before that gap must not answer the recheck.
  it('rechecks an empty wallet on the next poll after the socket connects, past the inactive TTL', async () => {
    const { poll } = createStream();
    await poll();
    inactiveWallets.mark('mainnet', 'base', '0xa1');

    mockSocketHandlers.onConnect!();

    await poll();
    expect(inactiveWallets.has('mainnet', 'base', '0xa1')).toBe(false);
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    expect(mockedStreamAllAccountNfts.mock.calls[1][2].ignorePreCheck).toBe(false);
  });

  // The clock stands still throughout, so the order of the read and the connect is all that decides
  it('keeps the recheck due when a precheck in flight at the connect comes back empty', async () => {
    const { poll } = createStream();
    let wasCachedOnRecheck: boolean | undefined;
    mockedStreamAllAccountNfts
      .mockImplementationOnce((_chain, _accountId, options) => {
        mockSocketHandlers.onConnect!();
        // The read began before the connect and caches its verdict only after it
        inactiveWallets.mark('mainnet', 'base', '0xa1');
        options.onPreCheckResult?.(false);
        return Promise.resolve();
      })
      .mockImplementationOnce((_chain, _accountId, options) => {
        wasCachedOnRecheck = inactiveWallets.has('mainnet', 'base', '0xa1');
        options.onPreCheckResult?.(false);
        return Promise.resolve();
      });

    await poll();
    await poll();
    await poll();

    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    expect(wasCachedOnRecheck).toBe(false);
  });

  it('keeps a failed recheck due until it succeeds', async () => {
    const { poll } = createStream();
    await poll();
    mockSocketHandlers.onConnect!();

    mockedStreamAllAccountNfts.mockRejectedValueOnce(new Error('upstream'));
    await expect(poll()).rejects.toThrow('upstream');

    await poll();
    await poll();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(3);
  });

  it('loads the NFTs of an empty wallet once activity wakes it, without another precheck', async () => {
    const { stream, poll, scheduler } = createStream();
    await poll();

    stream.activate();
    stream.activate();
    expect(scheduler.forceImmediatePoll).toHaveBeenCalledTimes(1);

    await poll();
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(2);
    expect(mockedStreamAllAccountNfts.mock.calls[1][2].ignorePreCheck).toBe(true);
  });
});
