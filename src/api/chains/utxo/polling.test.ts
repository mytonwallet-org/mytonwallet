import type { ApiBackendActivitiesUpdate } from '../../common/backendSocket';
import type { ApiAccountWithChain, OnApiUpdate } from '../../types';
import type { UtxoTransaction } from './types';

import { fetchJson } from '../../../util/fetch';
import { fetchStoredWallet } from '../../common/accounts';
import { getUtxoBackendSocket } from '../../common/backendSocket';
import { setupActivePolling, setupUtxoBackendActivityTracking } from './polling';

jest.mock('../../../util/fetch', () => ({ fetchJson: jest.fn() }));
jest.mock('../../common/accounts', () => ({ fetchStoredWallet: jest.fn() }));
jest.mock('../../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId, activities) => Promise.resolve(activities)),
}));
jest.mock('../../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../../common/txCallbacks', () => ({ txCallbacks: { runCallbacks: jest.fn() } }));
jest.mock('../../common/websocket/balanceStream', () => ({
  BalanceStream: jest.fn().mockImplementation(() => ({
    onUpdate: jest.fn(),
    onLoadingChange: jest.fn(),
    start: jest.fn(),
    destroy: jest.fn(),
  })),
}));
jest.mock('./util/socket', () => ({ getUtxoSocket: jest.fn() }));
jest.mock('./wallet', () => ({ fetchAccountAssets: jest.fn().mockResolvedValue({ btc: 1000n }) }));

jest.mock('../../common/backendSocket', () => ({
  getUtxoBackendSocket: jest.fn(),
}));

const SENDER_ADDRESS = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';
const RECIPIENT_ADDRESS = 'bc1qvmw9dmensxtuxu5vw7mxtxqurad2u99pdj9wwa';
const TX_ID = 'a'.repeat(64);

function rawTransaction(confirmations = 1): UtxoTransaction {
  return {
    txid: TX_ID,
    confirmations,
    blockTime: 1_700_000_000,
    fees: '100',
    vin: [{ addresses: [SENDER_ADDRESS], value: '1000' }],
    vout: [{ addresses: [RECIPIENT_ADDRESS], value: '900', n: 0 }],
  };
}

function mockBackendWatcher() {
  let callback: ((update: ApiBackendActivitiesUpdate) => void) | undefined;
  let onConnect: NoneToVoidFunction | undefined;
  const destroy = jest.fn();
  const watchWallets = jest.fn((_wallets, options) => {
    callback = options.onNewActivities;
    onConnect = options.onConnect;
    return { destroy };
  });

  (getUtxoBackendSocket as jest.Mock).mockReturnValue({ watchWallets });

  return {
    watchWallets,
    destroy,
    connect() {
      onConnect?.();
    },
    emit(update: ApiBackendActivitiesUpdate) {
      callback?.(update);
    },
  };
}

describe('setupUtxoBackendActivityTracking', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('parses backend raw UTXO transactions and emits partial newActivities without pendingActivities', () => {
    const watcher = mockBackendWatcher();
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    const activityUpdate = jest.fn();

    setupUtxoBackendActivityTracking('bitcoin', '0-mainnet', RECIPIENT_ADDRESS, activityUpdate, onUpdate);

    watcher.emit({
      address: RECIPIENT_ADDRESS,
      utxoActivityUpdate: {
        type: 'utxoActivityUpdate',
        chain: 'bitcoin',
        address: RECIPIENT_ADDRESS,
        txId: TX_ID,
        confirmations: 1,
        maxConfirmations: 2,
        etaSeconds: 600,
        status: 'pending',
        blockHeight: 966489,
        blockHash: 'block-1',
        rawTransaction: rawTransaction(),
      },
    });

    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newActivities',
      accountId: '0-mainnet',
      chain: 'bitcoin',
      activities: [expect.objectContaining({
        id: TX_ID,
        isIncoming: true,
        confirmations: 1,
        maxConfirmations: 2,
        etaSeconds: 600,
        status: 'pending',
      })],
    }));
    expect(onUpdate.mock.calls[0][0]).not.toHaveProperty('pendingActivities');
    expect(activityUpdate).not.toHaveBeenCalled();
  });

  it('parses the same raw transaction relative to each subscribed wallet address', () => {
    const recipientWatcher = mockBackendWatcher();
    const recipientUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    setupUtxoBackendActivityTracking('bitcoin', '0-mainnet', RECIPIENT_ADDRESS, jest.fn(), recipientUpdate);

    const senderWatcher = mockBackendWatcher();
    const senderUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    setupUtxoBackendActivityTracking('bitcoin', '1-mainnet', SENDER_ADDRESS, jest.fn(), senderUpdate);

    const update = {
      type: 'utxoActivityUpdate' as const,
      chain: 'bitcoin' as const,
      address: RECIPIENT_ADDRESS,
      txId: TX_ID,
      confirmations: 1 as const,
      maxConfirmations: 2,
      status: 'pending' as const,
      blockHeight: 966489,
      blockHash: 'block-1',
      rawTransaction: rawTransaction(),
    };

    recipientWatcher.emit({ address: RECIPIENT_ADDRESS, utxoActivityUpdate: update });
    senderWatcher.emit({ address: SENDER_ADDRESS, utxoActivityUpdate: { ...update, address: SENDER_ADDRESS } });

    expect((recipientUpdate.mock.calls[0][0] as any).activities[0]).toEqual(expect.objectContaining({
      isIncoming: true,
      fromAddress: SENDER_ADDRESS,
      toAddress: RECIPIENT_ADDRESS,
      amount: 900n,
    }));
    expect((senderUpdate.mock.calls[0][0] as any).activities[0]).toEqual(expect.objectContaining({
      isIncoming: false,
      fromAddress: SENDER_ADDRESS,
      toAddress: RECIPIENT_ADDRESS,
      amount: -900n,
    }));
  });

  it('normalizes legacy Bitcoin Cash addresses before backend subscription', () => {
    const watcher = mockBackendWatcher();
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    const activityUpdate = jest.fn();
    const legacyAddress = '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu';
    const cashAddr = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';

    setupUtxoBackendActivityTracking('bitcoincash', '0-mainnet', legacyAddress, activityUpdate, onUpdate);

    expect(watcher.watchWallets).toHaveBeenCalledWith([
      { chain: 'bitcoincash', address: cashAddr, events: ['activity'] },
    ], expect.anything());

    watcher.emit({
      address: cashAddr,
      utxoActivityUpdate: {
        type: 'utxoActivityUpdate',
        chain: 'bitcoincash',
        address: cashAddr,
        txId: TX_ID,
        confirmations: 1,
        maxConfirmations: 2,
        status: 'pending',
        blockHeight: 966489,
        blockHash: 'block-1',
        rawTransaction: rawTransaction(1),
      },
    });

    expect((onUpdate.mock.calls[0][0] as any).activities[0]).toEqual(expect.objectContaining({
      normalizedAddress: cashAddr,
    }));
  });
});

describe('UTXO history after reopening', () => {
  const cachedBlockTime = 1_700_000_000;
  const account = {
    type: 'view',
    byChain: { bitcoin: { address: RECIPIENT_ADDRESS, index: 0 } },
  } as ApiAccountWithChain<'bitcoin'>;

  async function flushPromises() {
    for (let i = 0; i < 20; i++) {
      await Promise.resolve();
    }
  }

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    jest.mocked(fetchStoredWallet).mockResolvedValue({ address: RECIPIENT_ADDRESS, index: 0 });
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
  });

  it.each([
    { confirmations: 0, blockTime: cachedBlockTime + 60 },
    { confirmations: 1, blockTime: cachedBlockTime + 60 },
    { confirmations: 0, blockTime: undefined },
    { confirmations: 1, blockTime: cachedBlockTime },
  ])('restores $confirmations confirmations at blockTime=$blockTime', async ({ confirmations, blockTime }) => {
    const watcher = mockBackendWatcher();
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    jest.mocked(fetchJson).mockResolvedValue({
      page: 1,
      totalPages: 1,
      transactions: [
        { ...rawTransaction(confirmations), blockTime },
        { ...rawTransaction(10), txid: 'b'.repeat(64), blockTime: cachedBlockTime },
      ],
    });

    const stop = setupActivePolling('bitcoin', '0-mainnet', account, onUpdate, jest.fn(), {
      btc: cachedBlockTime * 1000,
    });
    watcher.connect();
    await flushPromises();

    const update = onUpdate.mock.calls.map(([value]) => value).find((value) => value.type === 'newActivities');
    expect(update).toMatchObject({
      chain: 'bitcoin',
      activities: [expect.objectContaining({ id: TX_ID, status: 'pending', confirmations })],
    });
    // A partial history slice cannot clear other pending transactions.
    expect(update).not.toHaveProperty('pendingActivities');
    stop();
  });

  it('keeps the confirmed history cursor behind pending transactions after an uncached launch', async () => {
    const watcher = mockBackendWatcher();
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    const pending = { ...rawTransaction(0), blockTime: cachedBlockTime + 120 };
    const confirmed = { ...rawTransaction(10), txid: 'b'.repeat(64), blockTime: cachedBlockTime };
    jest.mocked(fetchJson).mockResolvedValue({ page: 1, totalPages: 1, transactions: [pending, confirmed] });

    const stop = setupActivePolling('bitcoin', '0-mainnet', account, onUpdate, jest.fn(), {});
    await flushPromises();
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'initialActivities',
      mainActivities: [expect.objectContaining({ id: TX_ID }), expect.objectContaining({ id: confirmed.txid })],
    }));

    const newlyConfirmed = { ...rawTransaction(2), txid: 'c'.repeat(64), blockTime: cachedBlockTime + 60 };
    jest.mocked(fetchJson).mockResolvedValue({
      page: 1, totalPages: 1, transactions: [pending, newlyConfirmed, confirmed],
    });
    onUpdate.mockClear();
    watcher.connect();
    await jest.advanceTimersByTimeAsync(1000);

    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'newActivities',
      activities: expect.arrayContaining([expect.objectContaining({ id: newlyConfirmed.txid, status: 'completed' })]),
    }));
    stop();
  });
});
