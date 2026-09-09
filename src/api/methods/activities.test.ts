import {
  activitiesFromActionsPage,
  activitiesFromBackendRows,
  activitiesFromSocketMessage,
  backendRowsOf,
  fixtures,
  localSwapRowOf,
  meta,
  socketMessage,
  wallet2,
} from '../../../tests/helpers/swapReconcilerFixtures';
import { fetchPastActivities, reconcileActivityUpdate } from './activities';

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

jest.mock('./swap', () => ({
  fetchSwaps: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../common/swap', () => ({
  ...jest.requireActual('../common/swap'),
  swapReplaceActivities: jest.fn((_accountId: string, activities: unknown[]) => activities),
  swapGetHistory: jest.fn().mockResolvedValue([]),
  swapGetHistoryByAddresses: jest.fn().mockResolvedValue([]),
}));

// Proxy returns a stable stub per chain key, so the mock survives additions and removals
// of chains in `CHAIN_CONFIG` without a manual list, and `expect(stub).toHaveBeenCalled()`
// keeps working across multiple accesses to the same chain.
jest.mock('../chains', () => {
  const stubsByChain = new Map<string, unknown>();
  return {
    __esModule: true,
    default: new Proxy({}, {
      get: (_target, chain: string) => {
        if (!stubsByChain.has(chain)) {
          stubsByChain.set(chain, {
            fetchActivitySlice: jest.fn().mockResolvedValue([]),
            crosschain: {
              fetchCrossChainActivitySlice: jest.fn().mockResolvedValue([]),
            },
          });
        }
        return stubsByChain.get(chain);
      },
    }),
  };
});

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredAccount } = require('../common/accounts') as {
  fetchStoredAccount: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as Record<string, {
  fetchActivitySlice: jest.Mock;
  crosschain: { fetchCrossChainActivitySlice: jest.Mock };
}>;

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchSwaps } = require('./swap') as { fetchSwaps: jest.Mock };

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { swapReplaceActivities, swapGetHistory, swapGetHistoryByAddresses } = require('../common/swap') as {
  swapReplaceActivities: jest.Mock;
  swapGetHistory: jest.Mock;
  swapGetHistoryByAddresses: jest.Mock;
};

describe('fetchPastActivities', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // Persisted `account.byChain` may outlive a chain being removed from CHAIN_CONFIG.
  // The slice fetcher must skip such stored keys; otherwise the whole slice rejects and
  // the past-activity loader silently returns undefined, leaving the UI on a skeleton.
  it('survives a stale chain key in account.byChain', async () => {
    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: {
        ton: { address: 'EQ-test', publicKey: '00' },
        polygon: { address: '0x-test', publicKey: '00' },
      },
    });

    const result = await fetchPastActivities('0-mainnet', 50);

    expect(result).toBeDefined();
    expect(result!.activities).toEqual([]);
    expect(result!.hasMore).toBe(false);
  });

  it('trims the trace cut by the page limit so the next page loads it whole', async () => {
    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: { ton: { address: 'EQ-test', publicKey: '00' } },
    });
    const page = activitiesFromActionsPage(fixtures.initialActions);
    chains.ton.fetchActivitySlice.mockResolvedValue(page);
    const boundaryTraceId = page.at(-1)!.id.split(':')[0];
    const boundaryCount = page.filter(({ id }) => id.startsWith(boundaryTraceId)).length;
    expect(boundaryCount).toBeGreaterThan(1);

    const result = await fetchPastActivities('0-mainnet', page.length);

    expect(result?.hasMore).toBe(true);
    expect(result?.activities).toHaveLength(page.length - boundaryCount);
    expect(result?.activities.some(({ id }) => id.startsWith(boundaryTraceId))).toBe(false);
  });

  it('passes the caller signal through chain and swap-history I/O', async () => {
    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: { ton: { address: 'EQ-test', publicKey: '00' } },
    });
    chains.ton.fetchActivitySlice.mockResolvedValue([]);
    const controller = new AbortController();

    await fetchPastActivities('0-mainnet', 50, undefined, undefined, { signal: controller.signal });

    expect(chains.ton.fetchActivitySlice).toHaveBeenCalledWith(expect.objectContaining({
      signal: controller.signal,
    }));
    expect(swapReplaceActivities).toHaveBeenCalledWith('0-mainnet', [], undefined, undefined, controller.signal);
  });

  it('uses the cross-chain activity source for account-wide EVM history', async () => {
    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: { ethereum: { address: '0x-test', publicKey: '00' } },
    });

    await fetchPastActivities('0-mainnet', 50);

    expect(chains.ethereum.crosschain.fetchCrossChainActivitySlice).toHaveBeenCalledWith({
      accountId: '0-mainnet',
      limit: 50,
      toTimestamp: undefined,
    });
    expect(chains.ethereum.fetchActivitySlice).not.toHaveBeenCalled();
  });

  it('uses the chain-specific activity source for token history', async () => {
    await fetchPastActivities('0-mainnet', 50, 'toncoin');

    expect(chains.ton.fetchActivitySlice).toHaveBeenCalledWith({
      accountId: '0-mainnet',
      limit: 50,
      tokenSlug: 'toncoin',
      toTimestamp: undefined,
    });
    expect(chains.ton.crosschain.fetchCrossChainActivitySlice).not.toHaveBeenCalled();
  });

  it('suppresses source failures for signalled callers unless requested', async () => {
    const error = new TypeError('fetch failed');
    fetchStoredAccount.mockRejectedValue(error);

    await expect(fetchPastActivities('0-mainnet', 50, undefined, undefined, {
      signal: new AbortController().signal,
    })).resolves.toBeUndefined();
  });

  it('surfaces source failures when requested', async () => {
    const error = new TypeError('fetch failed');
    fetchStoredAccount.mockRejectedValue(error);

    await expect(fetchPastActivities('0-mainnet', 50, undefined, undefined, {
      signal: new AbortController().signal,
      shouldThrowOnError: true,
    })).rejects.toBe(error);
  });
});

describe('reconcileActivityUpdate', () => {
  const [case2Row] = backendRowsOf(fixtures.case2Backend.history);
  const pendingRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'pending'));

  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredAccount.mockResolvedValue({ type: 'mnemonic', byChain: { ton: { address: meta.wallet } } });
    swapGetHistory.mockResolvedValue([]);
    swapGetHistoryByAddresses.mockResolvedValue([]);
  });

  it('shows the swap row of a pending trace submitted elsewhere by looking its hash up in the backend', async () => {
    swapGetHistory.mockResolvedValue([case2Row]);

    const result = await reconcileActivityUpdate('0-mainnet', [], [], pendingRows);

    expect(swapGetHistory).toHaveBeenCalledWith(meta.wallet, expect.objectContaining({
      hashes: expect.arrayContaining([meta.case2ExternalMsgHashNorm]),
      isCex: false,
    }));
    expect(result.confirmedActivities.map(({ id, status }) => [id, status]))
      .toEqual([[`${meta.case2SwapId}::backend-swap`, 'pendingTrusted']]);
    expect(result.pendingActivities?.map(({ shouldHide }) => shouldHide)).toEqual([true, true]);
  });

  it('does not ask the backend when the local swap row already represents the pending trace', async () => {
    const result = await reconcileActivityUpdate('0-mainnet', [localSwapRowOf(case2Row)], [], pendingRows);

    expect(swapGetHistory).not.toHaveBeenCalled();
    expect(swapGetHistoryByAddresses).not.toHaveBeenCalled();
    expect(result.pendingActivities?.map(({ shouldHide }) => shouldHide)).toEqual([true, true]);
  });

  it('refreshes a pending CEX swap by its backend id when a raw transaction arrives', async () => {
    const [pendingRow] = activitiesFromBackendRows([fixtures.nearIntentsBackend.swapRowVersions[0]]);
    const [deposit] = activitiesFromSocketMessage(socketMessage(fixtures.nearIntentsWsActions, 'finalized'), wallet2);

    await reconcileActivityUpdate('0-mainnet', [], [deposit], undefined, { contextActivities: [pendingRow] });

    expect(fetchSwaps).toHaveBeenCalledWith(
      '0-mainnet',
      [{ id: '2545651', chain: 'ton' }],
      expect.arrayContaining([pendingRow, deposit]),
      { forceProviderRefresh: true },
    );
  });
});
