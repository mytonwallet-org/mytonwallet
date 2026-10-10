jest.mock('../../db', () => ({
  tokenRepository: {
    all: jest.fn().mockResolvedValue([]),
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));
jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));
jest.mock('./toncenter/other', () => ({
  callToncenterV3: jest.fn(),
  fetchMetadata: jest.fn(),
}));
jest.mock('./priceless', () => ({
  updateTokenHashes: jest.fn().mockResolvedValue(undefined),
}));

// The two jetton masters agree in the first 44 bits of the hash, so their friendly addresses share 10 characters
const JETTON_ADDRESS = `0:${'ab'.repeat(5)}1${'0'.repeat(53)}`;
const OTHER_JETTON_ADDRESS = `0:${'ab'.repeat(5)}1${'f'.repeat(53)}`;
const OWNER_ADDRESS = `0:${'1'.repeat(64)}`;
const OTHER_OWNER_ADDRESS = `0:${'2'.repeat(64)}`;

describe('TON jetton slugs', () => {
  beforeEach(() => jest.resetModules());

  it('gives jettons that share a backend slug their own slugs when two wallets load them together', async () => {
    const { callToncenterV3 } = await import('./toncenter/other');
    const tokens = await import('../../common/tokens');
    const { toBase64Address } = await import('./util/tonCore');
    const { loadTokenBalances } = await import('./tokens');
    const jettonByOwner = { [OWNER_ADDRESS]: JETTON_ADDRESS, [OTHER_OWNER_ADDRESS]: OTHER_JETTON_ADDRESS };
    jest.mocked(callToncenterV3).mockImplementation((_network, _path, data) => {
      const jettonAddress = jettonByOwner[(data as { owner_address: string }).owner_address];
      return Promise.resolve({
        jetton_wallets: [{ address: OWNER_ADDRESS, jetton: jettonAddress, balance: '1000' }],
        metadata: {
          [jettonAddress]: {
            is_indexed: true,
            token_info: [{ type: 'jetton_masters', name: 'Jetton', symbol: 'JET', extra: { decimals: '9' } }],
          },
        },
      });
    });
    expect(tokens.buildTokenSlug('ton', toBase64Address(JETTON_ADDRESS, true)))
      .toBe(tokens.buildTokenSlug('ton', toBase64Address(OTHER_JETTON_ADDRESS, true)));

    void tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    const balancesPromise = Promise.all([
      loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn()),
      loadTokenBalances('mainnet', OTHER_OWNER_ADDRESS, jest.fn()),
    ]);
    await tokens.updateTokensFromBackend(jest.fn());
    tokens.resumeTokenUpdates();
    const [balances, otherBalances] = await balancesPromise;

    const [slug] = Object.keys(balances);
    const [otherSlug] = Object.keys(otherBalances);
    expect(slug).not.toBe(otherSlug);
    expect(tokens.getTokenBySlug(slug)?.tokenAddress).toBe(toBase64Address(JETTON_ADDRESS, true, 'mainnet'));
    expect(tokens.getTokenBySlug(otherSlug)?.tokenAddress).toBe(toBase64Address(OTHER_JETTON_ADDRESS, true, 'mainnet'));
  });

  it('resolves both jettons by address after a failed catalog request recovers', async () => {
    const { callBackendGet } = await import('../../common/backend');
    const { callToncenterV3 } = await import('./toncenter/other');
    const tokens = await import('../../common/tokens');
    const { toBase64Address } = await import('./util/tonCore');
    const { loadTokenBalances } = await import('./tokens');
    const jettonAddress = toBase64Address(JETTON_ADDRESS, true, 'mainnet');
    const otherJettonAddress = toBase64Address(OTHER_JETTON_ADDRESS, true, 'mainnet');
    const catalogSlug = tokens.buildTokenSlug('ton', jettonAddress);
    const onUpdate = jest.fn();

    jest.mocked(callToncenterV3).mockResolvedValue({
      jetton_wallets: [OTHER_JETTON_ADDRESS, JETTON_ADDRESS].map((jetton) => ({
        address: OWNER_ADDRESS, jetton, balance: '1000',
      })),
      metadata: Object.fromEntries([JETTON_ADDRESS, OTHER_JETTON_ADDRESS].map((jetton) => [jetton, {
        is_indexed: true,
        token_info: [{ type: 'jetton_masters', name: 'Jetton', symbol: 'JET', extra: { decimals: '9' } }],
      }])),
    });
    await tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    jest.mocked(callBackendGet).mockRejectedValueOnce(new Error('offline'));
    await expect(tokens.updateTokensFromBackend(onUpdate)).rejects.toThrow('offline');
    tokens.resumeTokenUpdates();

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    // The jetton with the smaller address key keeps the backend slug, and the catalog then lists the other one
    const [holderAddress, listedAddress] = tokens.buildTokenSlug('ton', jettonAddress) === catalogSlug
      ? [jettonAddress, otherJettonAddress]
      : [otherJettonAddress, jettonAddress];
    const discoveredSlug = tokens.buildTokenSlug('ton', listedAddress);
    expect(discoveredSlug).not.toBe(catalogSlug);
    expect(balances[discoveredSlug]).toBe(1000n);

    jest.mocked(callBackendGet).mockResolvedValueOnce([{
      slug: catalogSlug, chain: 'ton', tokenAddress: listedAddress,
      name: 'Catalog Jetton', symbol: 'CAT', decimals: 9, priceUsd: 2, percentChange24h: 0,
    }]);
    await tokens.updateTokensFromBackend(onUpdate);

    expect(tokens.getTokenByAddress(listedAddress)).toBe(tokens.getTokenBySlug(catalogSlug));
    expect(tokens.getTokenByAddress(listedAddress)).toMatchObject({ name: 'Catalog Jetton', priceUsd: 2 });
    expect(tokens.getTokenByAddress(holderAddress))
      .toBe(tokens.getTokenBySlug(tokens.buildTokenSlug('ton', holderAddress)));
    expect(tokens.getTokenBySlug(discoveredSlug)?.tokenAddress).toBe(listedAddress);
  });
});
