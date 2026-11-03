import type { ApiBalanceBySlug, ApiChain, OnApiUpdate } from '../types';

import { ARBITRUM, ETH, ETH_USDT_MAINNET, SOLANA, TONCOIN } from '../../config';
import { MINUTE } from '../constants';
import {
  applyPendingBalances, capturePendingTransferBalances, clearPendingBalances, registerPendingTransfer,
} from './pendingBalances';

const ACCOUNT_ID = 'pending-mainnet';
const OTHER_ACCOUNT_ID = 'other-mainnet';

describe('pending balances', () => {
  const onUpdate = jest.fn<void, Parameters<OnApiUpdate>>();

  beforeEach(() => {
    jest.useFakeTimers();
    onUpdate.mockClear();
  });

  afterEach(() => {
    clearPendingBalances(ACCOUNT_ID);
    clearPendingBalances(OTHER_ACCOUNT_ID);
    jest.useRealTimers();
  });

  function observe(balances: ApiBalanceBySlug, chain: ApiChain = 'ethereum', accountId = ACCOUNT_ID) {
    return applyPendingBalances({ type: 'updateBalances', accountId, chain, balances }).balances;
  }

  function send(
    amount: bigint,
    fee: bigint,
    slug: string = ETH.slug,
    chain: ApiChain = 'ethereum',
    accountId = ACCOUNT_ID,
  ) {
    const balancesBeforeTransfer = capturePendingTransferBalances(accountId, chain, slug);
    registerPendingTransfer(accountId, chain, { slug, amount, fee }, balancesBeforeTransfer, onUpdate);
  }

  it('adds native transfers to the latest observed baseline and clamps the result at zero', () => {
    observe({ [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n });
    observe({ [ETH.slug]: 1100n, [ETH_USDT_MAINNET.slug]: 600n });

    send(100n, 10n);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum',
      balances: { [ETH.slug]: 990n, [ETH_USDT_MAINNET.slug]: 600n },
    });

    send(200n, 20n);
    expect(observe({ [ETH.slug]: 1100n, [ETH_USDT_MAINNET.slug]: 600n })).toEqual({
      [ETH.slug]: 770n, [ETH_USDT_MAINNET.slug]: 600n,
    });

    send(1000n, 10n);
    expect(observe({ [ETH.slug]: 1100n, [ETH_USDT_MAINNET.slug]: 600n })).toEqual({
      [ETH.slug]: 0n, [ETH_USDT_MAINNET.slug]: 600n,
    });
  });

  it('keeps stale ERC-20 balances reduced and clears changed slugs independently', () => {
    observe({ [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n });

    send(100n, 10n, ETH_USDT_MAINNET.slug);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum',
      balances: { [ETH.slug]: 990n, [ETH_USDT_MAINNET.slug]: 400n },
    });
    expect(observe({ [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n })).toEqual({
      [ETH.slug]: 990n, [ETH_USDT_MAINNET.slug]: 400n,
    });
    expect(jest.getTimerCount()).toBe(2);

    expect(observe({ [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 500n })).toEqual({
      [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 400n,
    });
    expect(jest.getTimerCount()).toBe(1);
    expect(observe({ [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 500n })).toEqual({
      [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 400n,
    });
    expect(observe({ [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 450n })).toEqual({
      [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 450n,
    });
    expect(jest.getTimerCount()).toBe(0);
    expect(observe({ [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 450n })).toEqual({
      [ETH.slug]: 980n, [ETH_USDT_MAINNET.slug]: 450n,
    });

    send(450n, 10n, ETH_USDT_MAINNET.slug);
    expect(observe({ [ETH.slug]: 980n })).toEqual({ [ETH.slug]: 970n });
    expect(jest.getTimerCount()).toBe(1);
    onUpdate.mockClear();
    jest.advanceTimersByTime(15 * MINUTE);
    expect(onUpdate.mock.calls).toEqual([[{
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum', balances: { [ETH.slug]: 980n },
    }]]);
    send(100n, 10n);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum', balances: { [ETH.slug]: 870n },
    });
  });

  it('registers only slugs with an observed balance', () => {
    send(100n, 10n, ETH_USDT_MAINNET.slug);
    jest.advanceTimersByTime(15 * MINUTE);
    expect(onUpdate).not.toHaveBeenCalled();

    observe({ [ETH_USDT_MAINNET.slug]: 500n });
    send(100n, 10n, ETH_USDT_MAINNET.slug);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum',
      balances: { [ETH_USDT_MAINNET.slug]: 400n },
    });
    expect(observe({ [ETH.slug]: 1000n })).toEqual({ [ETH.slug]: 1000n });
  });

  it('does not deduct a balance updated after the transfer snapshot', () => {
    observe({ [ETH.slug]: 1000n });
    const balancesBeforeTransfer = capturePendingTransferBalances(ACCOUNT_ID, 'ethereum', ETH.slug);
    expect(observe({ [ETH.slug]: 875n })).toEqual({ [ETH.slug]: 875n });

    registerPendingTransfer(
      ACCOUNT_ID, 'ethereum', { slug: ETH.slug, amount: 100n, fee: 25n }, balancesBeforeTransfer, onUpdate,
    );
    jest.advanceTimersByTime(15 * MINUTE);

    expect(onUpdate).not.toHaveBeenCalled();
    expect(observe({ [ETH.slug]: 875n })).toEqual({ [ETH.slug]: 875n });
  });

  it('keeps accounts and chains independent', () => {
    observe({ [ETH.slug]: 1000n });
    observe({ [ETH.slug]: 2000n }, 'ethereum', OTHER_ACCOUNT_ID);
    observe({ [ARBITRUM.slug]: 3000n }, 'arbitrum');

    send(100n, 10n);
    send(200n, 20n, ETH.slug, 'ethereum', OTHER_ACCOUNT_ID);
    send(300n, 30n, ARBITRUM.slug, 'arbitrum');

    expect(observe({ [ETH.slug]: 1000n })).toEqual({ [ETH.slug]: 890n });
    expect(observe({ [ETH.slug]: 2000n }, 'ethereum', OTHER_ACCOUNT_ID)).toEqual({ [ETH.slug]: 1780n });
    expect(observe({ [ARBITRUM.slug]: 3000n }, 'arbitrum')).toEqual({ [ARBITRUM.slug]: 2670n });
  });

  it('expires each transfer after fifteen minutes and keeps later transfers pending', () => {
    observe({ [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n });
    send(100n, 10n);
    jest.advanceTimersByTime(MINUTE);
    send(200n, 20n);
    onUpdate.mockClear();

    jest.advanceTimersByTime(14 * MINUTE - 1);
    expect(onUpdate).not.toHaveBeenCalled();
    expect(observe({ [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n })).toEqual({
      [ETH.slug]: 670n, [ETH_USDT_MAINNET.slug]: 500n,
    });

    jest.advanceTimersByTime(1);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum',
      balances: { [ETH.slug]: 780n, [ETH_USDT_MAINNET.slug]: 500n },
    });
    onUpdate.mockClear();
    jest.advanceTimersByTime(MINUTE - 1);
    expect(onUpdate).not.toHaveBeenCalled();
    jest.advanceTimersByTime(1);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateBalances', accountId: ACCOUNT_ID, chain: 'ethereum',
      balances: { [ETH.slug]: 1000n, [ETH_USDT_MAINNET.slug]: 500n },
    });
  });

  it('clears an account baseline and timers while preserving other accounts', () => {
    observe({ [ETH.slug]: 1000n });
    observe({ [ARBITRUM.slug]: 3000n }, 'arbitrum');
    observe({ [ETH.slug]: 2000n }, 'ethereum', OTHER_ACCOUNT_ID);
    send(100n, 10n);
    send(300n, 30n, ARBITRUM.slug, 'arbitrum');
    send(200n, 20n, ETH.slug, 'ethereum', OTHER_ACCOUNT_ID);

    clearPendingBalances(ACCOUNT_ID);
    onUpdate.mockClear();
    send(100n, 10n);
    jest.advanceTimersByTime(15 * MINUTE);

    expect(onUpdate.mock.calls).toEqual([[{
      type: 'updateBalances', accountId: OTHER_ACCOUNT_ID, chain: 'ethereum', balances: { [ETH.slug]: 2000n },
    }]]);
    expect(jest.getTimerCount()).toBe(0);
    expect(observe({ [ETH.slug]: 1000n })).toEqual({ [ETH.slug]: 1000n });
    expect(observe({ [ARBITRUM.slug]: 3000n }, 'arbitrum')).toEqual({ [ARBITRUM.slug]: 3000n });
  });

  it.each([
    ['ton', TONCOIN.slug],
    ['solana', SOLANA.slug],
  ] as const)('passes %s balances through without pending debits', (chain, slug) => {
    const update = { type: 'updateBalances', accountId: ACCOUNT_ID, chain, balances: { [slug]: 1000n } } as const;
    expect(applyPendingBalances(update)).toBe(update);

    send(100n, 10n, slug, chain);
    jest.advanceTimersByTime(15 * MINUTE);

    expect(applyPendingBalances(update)).toBe(update);
    expect(onUpdate).not.toHaveBeenCalled();
  });
});
