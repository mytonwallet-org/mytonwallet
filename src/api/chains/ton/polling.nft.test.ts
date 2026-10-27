import type { WalletWatcher } from '../../common/websocket/abstractWsClient';
import type { ApiNft, ApiNftUpdate } from '../../types';
import type { ToncenterSocket } from './toncenter/socket';

import Deferred from '../../../util/Deferred';
import { setIsAppFocused } from '../../../util/focusAwareDelay';
import { logDebugError } from '../../../util/logs';
import * as randomModule from '../../../util/random';
import { MINUTE, SEC } from '../../constants';
import { getToncenterSocket } from './toncenter/socket';
import { getNftUpdates, streamAllAccountNfts } from './nfts';
import { setupNftPolling } from './polling';

jest.mock('../../../util/logs', () => ({
  logDebug: jest.fn(),
  logDebugError: jest.fn(),
}));

jest.mock('./nfts', () => ({
  getNftUpdates: jest.fn(),
  streamAllAccountNfts: jest.fn(),
}));

jest.mock('./toncenter/socket', () => ({
  getToncenterSocket: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const ADDRESS = 'UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e';
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

  it('loads once on start and resolves the first-load promise after the stream finishes', async () => {
    const fullLoad = new Deferred<void>();
    mockedStreamAllAccountNfts.mockReturnValueOnce(fullLoad.promise);
    const { firstFullLoadPromise, onUpdate, poll } = startPolling();
    const onFirstFullLoad = jest.fn();
    void firstFullLoadPromise.then(onFirstFullLoad);
    connectSocket();

    expect(getToncenterSocket).toHaveBeenCalledWith('mainnet');
    expect(watchWallets).toHaveBeenCalledWith([{ address: ADDRESS, chain: 'ton' }], expect.any(Object));
    expect(mockedStreamAllAccountNfts).toHaveBeenCalledTimes(1);
    const [accountId, options] = mockedStreamAllAccountNfts.mock.calls[0];
    expect(accountId).toBe(ACCOUNT_ID);
    expect(options.signal?.aborted).toBe(false);
    options.onBatch(BATCH_NFTS);

    await jest.advanceTimersByTimeAsync(2 * SEC);
    expect(onFirstFullLoad).not.toHaveBeenCalled();
    expect(onUpdate.mock.calls).toEqual([[{
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
    expect(onUpdate).toHaveBeenLastCalledWith({
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
    expect(onUpdate).not.toHaveBeenCalled();
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
    expect(onUpdate.mock.calls.map(([update]) => update)).toContainEqual(NFT_UPDATE);

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
    expect(onUpdate).not.toHaveBeenCalled();
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
