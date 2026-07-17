import type { ApiBackendConfig } from '../../types';

import { fetchJson } from '../../../util/fetch';
import { untrackableRegistry } from './util/untrackable';
import { setBackendConfigCache } from '../../common/cache';
import { ApiServerError } from '../../errors';
import { fetchEvmTxs } from './activities';

// Mock only the network call; keep isNegativeCacheableStatus real so the adapter's classification
// is exercised end to end.
jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));

const fetchJsonMock = jest.mocked(fetchJson);

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
