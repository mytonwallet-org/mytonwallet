import type { ApiSwapActivity } from '../../../types';

import {
  expireActiveCexSwaps,
  getActiveCexSwapStates,
  rememberActiveCexSwap,
  rememberActiveCexSwaps,
  rememberActiveCexSwapSubmittedHashes,
} from './activeCexSwapState';

const mockStorageState: Record<string, any> = {};

jest.mock('../../../storages', () => ({
  storage: {
    getItem: jest.fn((key: string) => Promise.resolve(mockStorageState[key])),
    mutateItem: jest.fn((key: string, mutate: AnyFunction) => {
      const nextValue = mutate(mockStorageState[key]);
      if (nextValue === undefined) {
        delete mockStorageState[key];
      } else {
        mockStorageState[key] = nextValue;
      }
      return nextValue;
    }),
  },
}));

beforeEach(() => {
  Object.keys(mockStorageState).forEach((key) => delete mockStorageState[key]);
});

function makeCexSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'backend-id::backend-swap',
    timestamp: 1_700_000_000_000,
    from: 'trx',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'toncoin',
    toAmount: '5',
    networkFee: '0.1',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: ['0xABCDEF', '0xabcdef'],
    cexLabel: 'changelly',
    cex: {
      payinAddress: 'payin-address',
      payoutAddress: 'payout-address',
      status: 'waiting',
      transactionId: 'cex-transaction-id',
    },
    ...overrides,
  } as ApiSwapActivity;
}

describe('active CEX swap reconciliation state', () => {
  it('stores active CEX metadata with normalized unique hashes', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap());

    await expect(getActiveCexSwapStates('account-1')).resolves.toEqual([
      expect.objectContaining({
        accountId: 'account-1',
        backendSwapId: 'backend-id',
        cexTransactionId: 'cex-transaction-id',
        provider: 'changelly',
        status: 'pendingTrusted',
        knownHashes: ['0xabcdef'],
        from: 'trx',
        to: 'toncoin',
      }),
    ]);
  });

  it('merges submitted hashes into existing active CEX state', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap({ hashes: ['backend-hash'] }));
    await rememberActiveCexSwapSubmittedHashes('account-1', 'backend-id::backend-swap', [
      '0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      '0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD',
    ]);

    const [state] = await getActiveCexSwapStates('account-1');
    expect(state.knownHashes).toEqual(['backend-hash']);
    expect(state.submittedHashes).toEqual(['0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd']);
  });

  it('updates active CEX status and provider hashes from later backend history', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap({
      cexLabel: 'changelly',
      hashes: ['payin-hash'],
      status: 'pending',
    }));
    await rememberActiveCexSwap('account-1', makeCexSwap({
      cexLabel: 'near-intents',
      hashes: ['payout-hash'],
      status: 'pendingTrusted',
    }));

    const [state] = await getActiveCexSwapStates('account-1');
    expect(state).toEqual(expect.objectContaining({
      provider: 'near-intents',
      status: 'pendingTrusted',
      knownHashes: ['payin-hash', 'payout-hash'],
    }));
  });

  it('does not reactivate a terminal CEX state when a concurrent stale pending response arrives', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap({ status: 'completed', hashes: ['completed-hash'] }));
    await rememberActiveCexSwap('account-1', makeCexSwap({ status: 'pending', hashes: ['late-pending-hash'] }));

    await expect(getActiveCexSwapStates('account-1')).resolves.toEqual([]);
  });

  it('does not return completed failed or expired swaps as active', async () => {
    await rememberActiveCexSwaps('account-1', [
      makeCexSwap({ id: 'completed::backend-swap', status: 'completed' }),
      makeCexSwap({ id: 'failed::backend-swap', status: 'failed' }),
      makeCexSwap({ id: 'expired::backend-swap', status: 'expired' }),
    ]);

    await expect(getActiveCexSwapStates('account-1')).resolves.toEqual([]);
  });

  it('terminalizes a canceled provider response before storing active state', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap({
      status: 'pendingTrusted',
      isCanceled: true,
    }));

    await expect(getActiveCexSwapStates('account-1')).resolves.toEqual([]);
  });

  it('expires a pending backend id returned as non-existent by swap history lookup', async () => {
    await rememberActiveCexSwap('account-1', makeCexSwap({ id: 'backend-id::backend-swap' }));
    await expireActiveCexSwaps('account-1', ['backend-id']);

    await expect(getActiveCexSwapStates('account-1')).resolves.toEqual([]);
  });

  it('prunes active CEX state per account', async () => {
    await rememberActiveCexSwaps('account-1', Array.from({ length: 101 }, (_, index) => makeCexSwap({
      id: `backend-${index}::backend-swap`,
      timestamp: 1_700_000_000_000 + index,
    })));

    const states = await getActiveCexSwapStates('account-1');
    expect(states).toHaveLength(100);
  });
});
