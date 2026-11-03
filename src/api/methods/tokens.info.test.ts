import type { ApiTokenWithPrice } from '../types';

import { callBackendPost } from '../common/backend';
import { tokensPreload, updateTokens } from '../common/tokens';
import { fetchTokenInfo } from './tokens';

jest.mock('../chains', () => ({}));
jest.mock('../db', () => ({
  tokenRepository: { bulkPut: jest.fn().mockResolvedValue(undefined) },
}));
jest.mock('../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn(),
}));
jest.mock('../storages', () => ({
  storage: { getItem: jest.fn().mockResolvedValue('en') },
}));

// The catalog token holds `ethereum-0x00000000`, the backend slug of every address that starts with eight zeros, so
// the spam token gets the full slug of its address
const CATALOG_TOKEN = makeToken('ethereum-0x00000000', '0x00000000efe302beaa2b3e6e1b18d08d69a9012a');
const SPAM_ADDRESS = '0x00000000f9fd50c832d79facfe6f4e8ce90a5efb';
const SPAM_TOKEN = makeToken(`ethereum-${SPAM_ADDRESS}`, SPAM_ADDRESS);
const OTHER_TOKEN = makeToken('ethereum-0x11111111', '0x11111111d0c5e1b2f3a4958677a8b9c0d1e2f3a4');

describe('fetchTokenInfo', () => {
  beforeAll(async () => {
    tokensPreload.resolve();
    await updateTokens([CATALOG_TOKEN, SPAM_TOKEN, OTHER_TOKEN]);
  });

  beforeEach(() => {
    jest.mocked(callBackendPost).mockClear();
  });

  it('requests the tokens in one batch and gives each its own details', async () => {
    jest.mocked(callBackendPost).mockResolvedValue([
      { slug: CATALOG_TOKEN.slug, tokenInfo: { description: 'Catalog token' } },
      { slug: OTHER_TOKEN.slug, tokenInfo: { description: 'Other token' } },
    ]);

    const result = await fetchTokenInfo([CATALOG_TOKEN.slug, OTHER_TOKEN.slug]);

    expect(callBackendPost).toHaveBeenCalledWith(expect.any(String), {
      assets: [CATALOG_TOKEN.tokenAddress, OTHER_TOKEN.tokenAddress],
    });
    expect(result).toEqual({
      detailsBySlug: {
        [CATALOG_TOKEN.slug]: expect.objectContaining({ description: 'Catalog token' }),
        [OTHER_TOKEN.slug]: expect.objectContaining({ description: 'Other token' }),
      },
    });
  });

  it('leaves out a token with a full slug, as its details come back under the slug of another token', async () => {
    jest.mocked(callBackendPost).mockResolvedValue([
      { slug: CATALOG_TOKEN.slug, tokenInfo: { description: 'Catalog token' } },
    ]);

    const result = await fetchTokenInfo([CATALOG_TOKEN.slug, SPAM_TOKEN.slug]);

    expect(callBackendPost).toHaveBeenCalledWith(expect.any(String), { assets: [CATALOG_TOKEN.tokenAddress] });
    expect(result).toEqual({
      detailsBySlug: { [CATALOG_TOKEN.slug]: expect.objectContaining({ description: 'Catalog token' }) },
    });
  });
});

function makeToken(slug: string, tokenAddress: string): ApiTokenWithPrice {
  return {
    slug, chain: 'ethereum', tokenAddress, name: slug, symbol: slug, decimals: 18, priceUsd: 0, percentChange24h: 0,
  };
}
