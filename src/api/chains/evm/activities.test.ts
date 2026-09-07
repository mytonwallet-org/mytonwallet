import type { ApiAccountAny, ApiBackendConfig } from '../../types';

import { fetchJson } from '../../../util/fetch';
import { untrackableRegistry } from './util/untrackable';
import { fetchStoredAccount } from '../../common/accounts';
import { setBackendConfigCache } from '../../common/cache';
import { ApiServerError } from '../../errors';
import { fetchActivitySlice, fetchEvmTxs } from './activities';

// Mock only the network call; keep isNegativeCacheableStatus real so the adapter's classification
// is exercised end to end.
jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

const fetchJsonMock = jest.mocked(fetchJson);
const fetchStoredAccountMock = jest.mocked(fetchStoredAccount);

function setNegVerdictCacheFlag(enabled: boolean) {
  setBackendConfigCache({ isNegVerdictCacheEnabled: enabled } as unknown as ApiBackendConfig);
}

const BASE = { chain: 'ethereum', network: 'mainnet', limit: 50 } as const;

describe('fetchEvmTxs untrackable handling', () => {
  beforeEach(() => {
    untrackableRegistry.reset();
    fetchJsonMock.mockReset();
    setNegVerdictCacheFlag(false);
  });

  it('flag off: a deterministic 400 rethrows unchanged and marks nothing (dark-ship guard)', async () => {
    fetchJsonMock.mockRejectedValue(new ApiServerError('untrackable wallet address', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xdead')).toBe(false);
  });

  it('flag on: a plain-history 400 marks the address, returns empty, and short-circuits the next call', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('untrackable wallet address', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).resolves.toEqual([]);
    expect(untrackableRegistry.has('mainnet', '0xdead')).toBe(true);

    fetchJsonMock.mockClear();
    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).resolves.toEqual([]);
    expect(fetchJsonMock).not.toHaveBeenCalled();
  });

  it('flag on: a hash-scoped 400 does NOT mark the address (a user fetches their own tx by hash)', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('bad search_query', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xuser', hash: '0xabc' })).rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xuser')).toBe(false);
  });

  it('flag on: a token-scoped 422 does NOT mark the address (the token filter may be at fault)', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('bad fungible filter', 422));

    await expect(fetchEvmTxs({ ...BASE, address: '0xuser', slug: 'ethereum-0xtoken' }))
      .rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xuser')).toBe(false);
  });
});

// Robinhood rides the Ethereum wallet, so an account created before the chain existed has no
// Robinhood entry of its own. The per-token activity path still asks for that chain by name.
describe('fetchActivitySlice on a chain sharing another chain\'s wallet', () => {
  const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

  beforeEach(() => {
    untrackableRegistry.reset();
    fetchJsonMock.mockReset();
    fetchJsonMock.mockResolvedValue({ data: [] });
    setNegVerdictCacheFlag(false);
    fetchStoredAccountMock.mockResolvedValue({
      type: 'bip39',
      byChain: { ethereum: { address: ADDRESS, index: 0 } },
    } as ApiAccountAny);
  });

  it('asks Zerion for that chain using the address of the wallet it shares', async () => {
    await expect(fetchActivitySlice('robinhood', { accountId: '0-mainnet', limit: 50 })).resolves.toEqual([]);

    const [url, params] = fetchJsonMock.mock.calls[0];
    expect(url).toContain(`/wallets/${ADDRESS}/transactions/`);
    expect(params).toMatchObject({ 'filter[chain_ids]': 'robinhood' });
  });
});
