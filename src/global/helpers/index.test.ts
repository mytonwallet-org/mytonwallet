import type { ApiTokenWithPrice } from '../../api/types';

import { TON_USDT_MAINNET } from '../../config';
import { makeMockTransactionActivity } from '../../../tests/mocks';
import { getIsTinyOrScamTransaction } from '.';

// Six decimals and a price of exactly 1 make the cost of a sub-cent transfer easy to express.
const USDT: ApiTokenWithPrice = { ...TON_USDT_MAINNET, percentChange24h: 0 };

/** $0.0001, two orders of magnitude below TINY_TRANSFER_MAX_COST. */
const SUB_CENT_AMOUNT = 100n;
/** $10 */
const NORMAL_AMOUNT = 10_000_000n;

describe('getIsTinyOrScamTransaction', () => {
  it('hides an incoming sub-cent transfer', () => {
    const activity = makeMockTransactionActivity({ isIncoming: true, amount: SUB_CENT_AMOUNT });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(true);
  });

  it('keeps an outgoing sub-cent transfer, because the user authored it', () => {
    const activity = makeMockTransactionActivity({ isIncoming: false, amount: -SUB_CENT_AMOUNT });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(false);
  });

  it('keeps an outgoing transfer above the threshold', () => {
    const activity = makeMockTransactionActivity({ isIncoming: false, amount: -NORMAL_AMOUNT });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(false);
  });

  it('hides an outgoing sub-cent bounce, which is the tail of incoming spam rather than a user transfer', () => {
    const activity = makeMockTransactionActivity({
      isIncoming: false,
      amount: -SUB_CENT_AMOUNT,
      type: 'bounced',
    });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(true);
  });

  it('hides a sub-cent mint', () => {
    const activity = makeMockTransactionActivity({ isIncoming: true, amount: SUB_CENT_AMOUNT, type: 'mint' });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(true);
  });

  it('keeps a sub-cent transfer of an unknown token', () => {
    const activity = makeMockTransactionActivity({ isIncoming: true, amount: SUB_CENT_AMOUNT });
    expect(getIsTinyOrScamTransaction(activity, undefined)).toBe(false);
  });

  it('hides a scam transfer regardless of direction', () => {
    const activity = makeMockTransactionActivity({
      isIncoming: false,
      amount: -NORMAL_AMOUNT,
      metadata: { isScam: true },
    });
    expect(getIsTinyOrScamTransaction(activity, USDT)).toBe(true);
  });
});
