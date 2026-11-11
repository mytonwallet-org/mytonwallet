import type { ApiActivity, ApiSwapActivity, ApiTransactionActivity } from '../../api/types';
import type { AccountState } from '../types';

import { getIsCrossChainBackendSwap, selectCexSwapRefreshContextActivities } from './cexSwapRefresh';

function makeTransaction(id: string): ApiTransactionActivity {
  return {
    kind: 'transaction',
    id,
    timestamp: 1,
    amount: 1n,
    fromAddress: 'from',
    toAddress: 'to',
    normalizedAddress: 'to',
    fee: 0n,
    slug: 'toncoin',
    isIncoming: true,
    status: 'completed',
  };
}

function makePendingCexSwap(id: string): ApiSwapActivity {
  return {
    kind: 'swap',
    id,
    timestamp: 1,
    from: 'toncoin',
    fromAmount: '1',
    fromAddress: 'from',
    to: 'tron-usdt',
    toAmount: '1',
    networkFee: '0',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    transactionIds: {},
    cex: { payinAddress: 'payin', payoutAddress: 'payout', status: 'waiting', transactionId: 'cex-id' },
  };
}

describe('CEX refresh context', () => {
  it('keeps active CEX, local and pending context ahead of a 250-item incoming batch', () => {
    const activeCex = makePendingCexSwap('active-cex');
    const local = makeTransaction('local');
    const pending = makeTransaction('pending');
    const incoming = Array.from({ length: 250 }, (_, index) => makeTransaction(`incoming-${index}`));
    const byId = Object.fromEntries([activeCex, local, pending].map((activity) => [activity.id, activity]));
    const activities: NonNullable<AccountState['activities']> = {
      byId,
      localActivityIds: [local.id],
      pendingActivityIds: { ton: [pending.id] },
      idsMain: ['older-raw'],
    };

    const context = selectCexSwapRefreshContextActivities(activities, [], incoming);

    expect(context).toHaveLength(250);
    expect(context.slice(0, 3).map(({ id }) => id)).toEqual([activeCex.id, local.id, pending.id]);
    expect(context.map(({ id }) => id)).toContain('incoming-0');
  });

  it('retains recent main and token-history rows after priority context when capacity remains', () => {
    const activeCex = makePendingCexSwap('active-cex');
    const olderRaw = makeTransaction('older-raw');
    const activities: NonNullable<AccountState['activities']> = {
      byId: { [activeCex.id]: activeCex, [olderRaw.id]: olderRaw },
      idsMain: [olderRaw.id],
      idsBySlug: { toncoin: [olderRaw.id] },
    };

    const context: ApiActivity[] = selectCexSwapRefreshContextActivities(activities, [activeCex]);

    expect(context.map(({ id }) => id)).toEqual([activeCex.id, olderRaw.id]);
  });

  it('retains a hidden CEX-owned source even when presentation indexes no longer contain it', () => {
    const activeCex = makePendingCexSwap('active-cex');
    const hiddenSource: ApiTransactionActivity = {
      ...makeTransaction('hidden-source'),
      shouldHide: true,
      extra: {
        reconciliation: {
          operationId: 'swap:active-cex',
          sourceActionIds: ['active-cex', 'hidden-source'],
          hiddenSourceActionIds: ['hidden-source'],
          reason: 'cex-swap',
        },
      },
    };
    const activities: NonNullable<AccountState['activities']> = {
      byId: { [activeCex.id]: activeCex, [hiddenSource.id]: hiddenSource },
      idsMain: [activeCex.id],
      idsBySlug: {},
    };

    const context = selectCexSwapRefreshContextActivities(activities, [activeCex]);

    expect(context.map(({ id }) => id)).toEqual([activeCex.id, hiddenSource.id]);
  });
});

describe('pending swap polling', () => {
  const crossChain: ApiSwapActivity = {
    ...makePendingCexSwap('vt-id:backend-swap'),
    cex: undefined,
    from: 'base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',
    to: 'arbitrum-0xaf88d065e77c8cc2239327c5edb3a432268e5831',
  };

  it('polls backend cross-chain swaps besides CEX ones', () => {
    expect(getIsCrossChainBackendSwap(crossChain)).toBe(true);
  });

  it('skips same-chain and local swaps', () => {
    const sameChain = { ...crossChain, to: 'base-0xfde4c96c8593536e31f229ea8f37b2ada2699bb2' };
    expect(getIsCrossChainBackendSwap(sameChain)).toBe(false);
    expect(getIsCrossChainBackendSwap({ ...crossChain, id: 'vt-id:local' })).toBe(false);
  });
});
