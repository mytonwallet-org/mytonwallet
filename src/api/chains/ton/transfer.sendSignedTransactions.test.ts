import { beginCell } from '@ton/core';

import { ApiTransactionError } from '../../types';

import { sendExternal } from './util/sendExternal';
import { getTonClient } from './util/tonCore';
import { fetchStoredWallet } from '../../common/accounts';
import { withoutTransferConcurrency } from '../../common/preventTransferConcurrency';
import { ApiServerError } from '../../errors';
import { sendSignedTransactions } from './transfer';
import { getTonWallet, getWalletInfo } from './wallet';

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(),
}));

jest.mock('./util/sendExternal', () => ({
  sendExternal: jest.fn(),
}));

jest.mock('./util/tonCore', () => ({
  getTonClient: jest.fn(),
  isSeqnoMismatchError: jest.fn((message: string) => message.includes('seqno')),
}));

jest.mock('./wallet', () => ({
  getTonWallet: jest.fn(),
  getWalletInfo: jest.fn(),
}));

describe('sendSignedTransactions', () => {
  let walletSeqno: number;
  let walletAddress: string;

  beforeEach(() => {
    jest.useFakeTimers();
    walletSeqno = 5;
    walletAddress = `wallet-address-${Math.random()}`;
    jest.mocked(fetchStoredWallet).mockImplementation(() => Promise.resolve({
      address: walletAddress,
      isInitialized: true,
    } as Awaited<ReturnType<typeof fetchStoredWallet>>));
    jest.mocked(getTonClient).mockReturnValue({} as ReturnType<typeof getTonClient>);
    jest.mocked(getTonWallet).mockReturnValue({} as ReturnType<typeof getTonWallet>);
    jest.mocked(getWalletInfo).mockImplementation(() => Promise.resolve({
      seqno: walletSeqno,
    } as Awaited<ReturnType<typeof getWalletInfo>>));
    jest.mocked(sendExternal).mockResolvedValue({
      boc: 'first-boc',
      msgHash: 'first-hash',
      msgHashNormalized: 'first-normalized-hash',
    } as Awaited<ReturnType<typeof sendExternal>>);
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it('does not send the next pre-signed BOC when the previous seqno does not advance before timeout', async () => {
    const base64 = beginCell().endCell().toBoc().toString('base64');
    const resultPromise = sendSignedTransactions('1-mainnet', [
      { chain: 'ton', payload: { base64, seqno: 5 } },
      { chain: 'ton', payload: { base64, seqno: 6 } },
    ]);

    await jest.advanceTimersByTimeAsync(60_000);

    await expect(resultPromise).resolves.toEqual([{ boc: 'first-boc', msgHashNormalized: 'first-normalized-hash' }]);
    expect(sendExternal).toHaveBeenCalledTimes(1);
  });

  it('keeps the queue occupied after a final accepted BOC until wallet seqno advances', async () => {
    const base64 = beginCell().endCell().toBoc().toString('base64');
    const sentPromise = sendSignedTransactions('1-mainnet', [
      { chain: 'ton', payload: { base64, seqno: 5 } },
    ]);

    await expect(sentPromise).resolves.toEqual([{ boc: 'first-boc', msgHashNormalized: 'first-normalized-hash' }]);

    const order: string[] = [];
    const queuedAfterTonConnect = withoutTransferConcurrency('mainnet', walletAddress, () => {
      order.push('next');
    });

    await jest.advanceTimersByTimeAsync(999);
    expect(order).toEqual([]);

    walletSeqno = 6;
    await jest.advanceTimersByTimeAsync(1);
    await queuedAfterTonConnect;

    expect(order).toEqual(['next']);
    expect(sendExternal).toHaveBeenCalledTimes(1);
  });

  it('still maps immediate seqno mismatch errors to ConcurrentTransaction', async () => {
    jest.mocked(sendExternal).mockRejectedValueOnce(new ApiServerError('seqno mismatch'));
    const base64 = beginCell().endCell().toBoc().toString('base64');

    await expect(sendSignedTransactions('1-mainnet', [
      { chain: 'ton', payload: { base64, seqno: 5 } },
    ])).resolves.toEqual({ error: ApiTransactionError.ConcurrentTransaction });
  });
});
