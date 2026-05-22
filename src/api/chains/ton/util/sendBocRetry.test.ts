import { withoutTransferConcurrency } from '../../../common/preventTransferConcurrency';
import { waitUntilWalletSeqnoChanges } from './sendBocRetry';

describe('waitUntilWalletSeqnoChanges', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('keeps the transfer queue occupied until wallet seqno advances', async () => {
    const order: string[] = [];
    let walletSeqno = 10;
    const queueAddress = `test-address-${Date.now()}`;

    const first = withoutTransferConcurrency('mainnet', queueAddress, (finalizeInBackground) => {
      order.push('first');
      finalizeInBackground(() => waitUntilWalletSeqnoChanges({
        getWalletSeqno: () => Promise.resolve(walletSeqno),
        seqno: 10,
        waitMs: 60_000,
        pauseMs: 1_000,
      }).then(() => undefined));
    });

    await first;
    const second = withoutTransferConcurrency('mainnet', queueAddress, () => {
      order.push('second');
    });

    await jest.advanceTimersByTimeAsync(999);
    expect(order).toEqual(['first']);

    walletSeqno = 11;
    await jest.advanceTimersByTimeAsync(1);
    await second;

    expect(order).toEqual(['first', 'second']);
  });

  it('returns false when seqno does not advance before timeout', async () => {
    const resultPromise = waitUntilWalletSeqnoChanges({
      getWalletSeqno: () => Promise.resolve(20),
      seqno: 20,
      waitMs: 2_000,
      pauseMs: 1_000,
    });

    await jest.advanceTimersByTimeAsync(2_000);

    await expect(resultPromise).resolves.toBe(false);
  });
});
