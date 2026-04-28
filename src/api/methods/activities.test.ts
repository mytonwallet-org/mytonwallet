import { fetchPastActivities } from './activities';

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

jest.mock('../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId: string, activities: unknown[]) => activities),
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
            fetchCrossChainActivitySlice: jest.fn().mockResolvedValue([]),
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
});
