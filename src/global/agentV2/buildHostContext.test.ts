import type { GlobalState } from '../../global/types';

import { DEFAULT_STAKING_STATE, MYCOIN_MAINNET, MYCOIN_TESTNET } from '../../config';
import { buildAgentV2HostContext, createAgentV2HostContextSelector } from './buildHostContext';

describe('buildAgentV2HostContext', () => {
  it.each([
    ['TON when the account has it', ['bitcoin', 'ethereum', 'ton'], 'ton', ['bitcoin', 'ethereum', 'ton']],
    ['the first network in the app\'s order without TON', ['tron', 'solana', 'ethereum'], 'ethereum',
      ['ethereum', 'solana', 'tron']],
  ])('takes %s as the active network', (_case, accountChains, activeNetwork, chains) => {
    const global = {
      currentAccountId: 'mainnet-account',
      accounts: {
        byId: {
          'mainnet-account': {
            type: 'view',
            title: 'Watch',
            byChain: Object.fromEntries(accountChains.map((chain) => [chain, { address: `${chain}-address` }])),
          },
        },
      },
      byAccountId: {
        'mainnet-account': { balances: { bySlug: {} } },
      },
      tokenInfo: { bySlug: {} },
      settings: {
        langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {},
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    const host = buildAgentV2HostContext(global);
    expect(host.activeNetwork).toBe(activeNetwork);
    expect(host.accounts[0].chains).toEqual(chains);
  });

  it('projects staking restrictions without publishing a client product catalog', () => {
    const global = stakingGlobal();
    const host = buildAgentV2HostContext(global);
    expect(host.isStakingDisabled).toBe(false);
    expect(host).not.toHaveProperty('stakingOffers');
    expect(buildAgentV2HostContext({ ...global, settings: { ...global.settings, isTestnet: true } })
      .isStakingDisabled).toBe(true);
  });

  it('projects wallet data without credentials or unbound portfolio history', () => {
    const netWorthHistory = {
      status: 'ok',
      base: 'usd',
      density: '1d',
      datasets: [{
        assetId: 1,
        symbol: 'GRAM',
        contractAddress: '',
        points: [[1_752_364_800, 2.5] as [number, number]],
      }],
    };
    const global = {
      currentAccountId: 'mainnet-account',
      accounts: {
        byId: {
          'mainnet-account': {
            type: 'view',
            title: 'Watch',
            byChain: {
              ton: { address: 'EQ-raw-address' },
              base: { address: '0x-base-address' },
              bnb: { address: '0x-bnb-address' },
              robinhood: { address: '0x-robinhood-address' },
              retired: { address: 'retired-address' },
            },
          },
        },
      },
      byAccountId: {
        'mainnet-account': {
          balances: { bySlug: { toncoin: 1_250_000_000n, trx: 2_000_000n } },
          nfts: {
            byAddress: {
              'nft-address': {
                address: 'nft-address', chain: 'ton', name: 'Unsafe NFT', collectionName: 'Collection',
                isOnSale: false, isHidden: true, isScam: true,
              },
              'retired-nft': { address: 'retired-nft', chain: 'retired', name: 'Retired NFT', isOnSale: false },
            },
          },
          savedAddresses: [{ name: 'Alice', chain: 'ton', address: 'EQ-alice' }],
        },
      },
      tokenInfo: {
        bySlug: {
          toncoin: {
            slug: 'toncoin', chain: 'ton', symbol: 'GRAM', name: 'Gram', decimals: 9, priceUsd: 2,
          },
          trx: {
            slug: 'trx', chain: 'tron', symbol: 'TRX', name: 'TRON', decimals: 6, priceUsd: 1,
          },
        },
      },
      settings: {
        langCode: 'en',
        baseCurrency: 'USD',
        theme: 'light',
        byAccountId: { 'mainnet-account': { alwaysHiddenSlugs: ['toncoin'] } },
      },
      portfolio: {
        activeRange: '3M',
        historyByAccountId: {
          'mainnet-account': { USD: { '3M': { netWorth: netWorthHistory, fetchedAtSlot: 20_257 } } },
        },
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    const result = buildAgentV2HostContext(global);

    expect(result.activeNetwork).toBe('ton');
    expect(result.accounts[0]).toMatchObject({
      accountType: 'viewOnly',
      isViewOnly: true,
      chains: ['ton', 'bnb', 'base', 'robinhood'],
      addresses: {
        ton: 'EQ-raw-address', base: '0x-base-address', bnb: '0x-bnb-address', robinhood: '0x-robinhood-address',
      },
      portfolioWalletKeys: expect.arrayContaining([
        'ton:EQ-raw-address',
        'base:0x-base-address',
        'bnb:0x-bnb-address',
        'robinhood:0x-robinhood-address',
      ]),
      holdings: [{ balance: '1.25', visibility: 'hidden' }],
      positions: [{
        kind: 'nft', visibility: 'hidden', riskVerdict: 'spam', label: 'Unsafe NFT',
      }],
    });
    expect(result.accounts[0].portfolioWalletKeys).toHaveLength(4);
    expect(result.accounts[0].addresses).not.toHaveProperty('retired');
    expect(result.assetCatalog).toEqual([{
      slug: 'toncoin',
      chain: 'ton',
      symbol: 'GRAM',
      name: 'Gram',
      decimals: 9,
      priceUsd: '2',
    }, {
      slug: 'trx', chain: 'tron', symbol: 'TRX', name: 'TRON', decimals: 6, priceUsd: '1',
    }]);
    expect(result.currencyRate).toBe('1');
    expect(JSON.stringify(result)).not.toContain('mnemonic');
  });

  it('does not expose active or inactive testnet wallets to the mainnet-only Portfolio API', () => {
    const global = {
      currentAccountId: '1-mainnet',
      accounts: {
        byId: {
          '1-mainnet': {
            type: 'view',
            byChain: { ton: { address: 'EQ-mainnet-address' } },
          },
          '1-testnet': {
            type: 'view',
            byChain: { ton: { address: 'kQ-testnet-address' } },
          },
        },
      },
      byAccountId: {
        '1-mainnet': { balances: { bySlug: {} } },
        '1-testnet': { balances: { bySlug: {} } },
      },
      tokenInfo: { bySlug: {} },
      settings: {
        langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {},
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    const accounts = buildAgentV2HostContext(global).accounts;
    expect(accounts.find(({ accountId }) => accountId === '1-mainnet')).toMatchObject({
      portfolioWalletKeys: ['ton:EQ-mainnet-address'],
      domainStates: { value_series: { state: 'stale' } },
    });
    expect(accounts.find(({ accountId }) => accountId === '1-testnet')).toMatchObject({
      portfolioWalletKeys: [],
      domainStates: { value_series: { state: 'unavailable' } },
    });
  });

  it('treats an absent saved-address property as an authoritative empty address book', () => {
    const global = {
      currentAccountId: 'mainnet-account',
      accounts: {
        byId: {
          'mainnet-account': {
            type: 'mnemonic',
            title: 'Main',
            byChain: { ton: { address: 'EQ-address' } },
          },
        },
      },
      byAccountId: {
        'mainnet-account': { balances: { bySlug: {} } },
      },
      tokenInfo: { bySlug: {} },
      settings: {
        langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {},
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    expect(buildAgentV2HostContext(global).accounts[0]).toMatchObject({
      savedAddresses: [],
      domainStates: { contacts: { state: 'fresh' } },
    });
  });

  it('tracks source readiness independently of balances and distinguishes completed empty NFT scans', () => {
    const global = {
      currentAccountId: '0-ton-mainnet',
      accounts: { byId: { '0-ton-mainnet': {
        type: 'view', byChain: { ton: { address: 'EQ-address' } },
      } } },
      byAccountId: { '0-ton-mainnet': { balances: { bySlug: {} } } },
      tokenInfo: { bySlug: {} },
      settings: { langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {} },
      restrictions: {}, currencyRates: { USD: 1 },
    } as unknown as GlobalState;
    const account = global.byAccountId['0-ton-mainnet'];
    expect(buildAgentV2HostContext(global).accounts[0]).toMatchObject({
      nftLoadedChains: [],
      domainStates: { fungible: { state: 'fresh' }, staking: { state: 'notLoaded' }, vesting: { state: 'notLoaded' } },
    });

    account.nfts = { byAddress: {}, isFullLoadingByChain: { ton: false } };
    expect(buildAgentV2HostContext(global).accounts[0].nftLoadedChains).toEqual([]);
    account.nfts.isFullLoadCompleteByChain = { ton: true };
    account.staking = { stateById: {} };
    account.vesting = { info: [] };
    expect(buildAgentV2HostContext(global).accounts[0]).toMatchObject({
      nftLoadedChains: ['ton'],
      domainStates: { staking: { state: 'fresh' }, vesting: { state: 'fresh' } },
    });
  });

  it('projects remaining vesting as a human-unit amount of the account network MY token record', () => {
    const part = (id: number, amount: number, status: string) => ({ id, time: '', timeEnd: '', amount, status });
    const vesting = {
      info: [{
        id: 1,
        title: 'Investor',
        startsAt: new Date(0),
        initialAmount: 12.3,
        parts: [part(1, 0.1, 'ready'), part(2, 0.2, 'frozen'), part(3, 5, 'unfrozen'), part(4, 7, 'missed')],
      }, {
        id: 2,
        title: 'Claimed',
        startsAt: new Date(0),
        initialAmount: 3,
        parts: [part(5, 3, 'unfrozen')],
      }, {
        id: 3,
        title: 'Malformed',
        startsAt: new Date(0),
        initialAmount: 4,
        parts: [part(6, 1, 'frozen'), part(7, Number.NaN, 'ready')],
      }],
    };
    const mainnetToken = {
      slug: MYCOIN_MAINNET.slug, chain: 'ton', symbol: 'MY', name: 'Backend MY', decimals: 9,
    };
    const global = {
      currentAccountId: '0-mainnet',
      accounts: {
        byId: {
          '0-mainnet': { type: 'mnemonic', byChain: { ton: { address: 'EQ-mainnet-address' } } },
          '0-testnet': { type: 'mnemonic', byChain: { ton: { address: 'kQ-testnet-address' } } },
        },
      },
      byAccountId: {
        '0-mainnet': { balances: { bySlug: {} }, vesting },
        '0-testnet': { balances: { bySlug: {} }, vesting },
      },
      tokenInfo: { bySlug: { [MYCOIN_MAINNET.slug]: mainnetToken } },
      settings: { langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {} },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    const [mainnet, testnet] = buildAgentV2HostContext(global).accounts;

    expect(mainnet.positions).toEqual([{
      id: 'vesting-1',
      kind: 'vesting',
      chain: 'ton',
      label: 'Investor',
      asset: mainnetToken,
      quantity: '0.3',
      valuationStatus: 'unpriced',
      visibility: 'visible',
      status: 'ready',
    }, {
      id: 'vesting-3',
      kind: 'vesting',
      chain: 'ton',
      label: 'Malformed',
      asset: mainnetToken,
      valuationStatus: 'unpriced',
      visibility: 'visible',
      status: 'ready',
    }]);
    expect(testnet.positions?.[0]).toMatchObject({
      asset: {
        slug: MYCOIN_TESTNET.slug,
        symbol: 'MY',
        name: MYCOIN_TESTNET.name,
        tokenAddress: MYCOIN_TESTNET.minterAddress,
        decimals: 9,
      },
      quantity: '0.3',
    });
  });

  it('keeps saved-address identities stable when the address book order changes', () => {
    const savedAddresses = [
      { name: 'Mom', chain: 'ton' as const, address: 'EQ-mom' },
      { name: 'Alice', chain: 'ethereum' as const, address: '0x-alice' },
    ];
    const global = {
      currentAccountId: 'mainnet-account',
      accounts: {
        byId: {
          'mainnet-account': {
            type: 'mnemonic',
            title: 'Main',
            byChain: { ton: { address: 'EQ-address' } },
          },
        },
      },
      byAccountId: {
        'mainnet-account': { balances: { bySlug: {} }, savedAddresses },
      },
      tokenInfo: { bySlug: {} },
      settings: {
        langCode: 'en', baseCurrency: 'USD', theme: 'light', byAccountId: {},
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;

    const first = buildAgentV2HostContext(global).accounts[0].savedAddresses!;
    const reordered = buildAgentV2HostContext({
      ...global,
      byAccountId: {
        'mainnet-account': { balances: { bySlug: {} }, savedAddresses: [...savedAddresses].reverse() },
      },
    } as unknown as GlobalState).accounts[0].savedAddresses!;

    expect(Object.fromEntries(first.map(({ address, id }) => [address, id]))).toEqual(
      Object.fromEntries(reordered.map(({ address, id }) => [address, id])),
    );
  });

  it('projects a minimal swap catalog only after local swap metadata is loaded', () => {
    const global = {
      ...stakingGlobal(),
      swapTokenInfo: {
        isLoaded: true,
        bySlug: {
          toncoin: {
            slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: 2.5,
          },
          usdton: {
            slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6, priceUsd: 1,
            tokenAddress: 'EQ-usdt',
          },
          invalidPrice: {
            slug: 'invalid-price', chain: 'ton', symbol: 'BAD', name: 'Bad Price', decimals: 9, priceUsd: 0,
          },
          baseToken: {
            slug: 'base-token', chain: 'base', symbol: 'BASE', name: 'Base Token', decimals: 18, priceUsd: 1,
          },
          retiredChain: {
            slug: 'retired-token', chain: 'retired', symbol: 'OLD', name: 'Retired Token', decimals: 9, priceUsd: 1,
          },
        },
      },
    } as unknown as GlobalState;

    expect(buildAgentV2HostContext(global).swapAssetCatalog).toEqual([
      { slug: 'base-token', chain: 'base', symbol: 'BASE', name: 'Base Token', decimals: 18, priceUsd: '1' },
      { slug: 'invalid-price', chain: 'ton', symbol: 'BAD', name: 'Bad Price', decimals: 9 },
      { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: '2.5' },
      {
        slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6,
        tokenAddress: 'EQ-usdt', priceUsd: '1',
      },
    ]);
    expect(buildAgentV2HostContext({
      ...global,
      swapTokenInfo: { ...global.swapTokenInfo, isLoaded: false },
    } as unknown as GlobalState).swapAssetCatalog).toBeUndefined();
  });

  it('keeps the first assets by slug when the catalog is over its limit', () => {
    const global = stakingGlobal();
    const slugs = Array.from({ length: 10_001 }, (_, index) => `token-${String(index).padStart(5, '0')}`);
    // Inserted last first, so the kept assets do not depend on the store's order
    global.tokenInfo.bySlug = Object.fromEntries([...slugs].reverse().map((slug) => [slug, {
      slug, chain: 'ton', symbol: 'TKN', name: 'Token', decimals: 9,
    }])) as GlobalState['tokenInfo']['bySlug'];

    const catalog = buildAgentV2HostContext(global).assetCatalog!;
    expect(catalog).toHaveLength(10_000);
    expect(catalog[0].slug).toBe('token-00000');
    expect(catalog.at(-1)!.slug).toBe('token-09999');
  });

  it('omits malformed assets without discarding valid catalog entries', () => {
    const global = stakingGlobal();
    global.byAccountId['mainnet-account'].balances!.bySlug = {
      toncoin: 1_000_000_000n,
      invalid: 1_000_000_000n,
    };
    global.tokenInfo.bySlug.invalid = {
      slug: 'invalid', chain: 'ton', symbol: '', name: 'Invalid', decimals: 9,
      priceUsd: 0, percentChange24h: 0,
    };
    global.swapTokenInfo = {
      isLoaded: true,
      bySlug: {
        valid: {
          slug: 'valid', chain: 'ton', symbol: 'VALID', name: 'Valid', decimals: 9,
          isPopular: false, priceUsd: 0,
        },
        invalid: {
          slug: 'invalid', chain: 'ton', symbol: '', name: 'Invalid', decimals: 9,
          isPopular: false, priceUsd: 0,
        },
      },
    } as GlobalState['swapTokenInfo'];

    const result = buildAgentV2HostContext(global);

    expect(result.assetCatalog?.map(({ slug }) => slug)).toEqual(['toncoin']);
    expect(result.swapAssetCatalog?.map(({ slug }) => slug)).toEqual(['valid']);
    expect(result.accounts[0].holdings.map(({ asset }) => asset.slug)).toEqual(['toncoin']);
    expect(result.activeAccountId).toBe('mainnet-account');
  });

  it('reuses the projection when only unrelated global and token-info wrapper fields change', () => {
    const global = {
      currentAccountId: 'mainnet-account',
      accounts: {
        byId: {
          'mainnet-account': {
            type: 'view',
            byChain: { ton: { address: 'EQ-address' } },
          },
        },
      },
      byAccountId: {
        'mainnet-account': { balances: { bySlug: { toncoin: 1_000_000_000n } } },
      },
      tokenInfo: {
        bySlug: {
          toncoin: {
            slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: 1,
          },
        },
      },
      settings: {
        langCode: 'en',
        baseCurrency: 'USD',
        theme: 'light',
        areTokensWithNoCostHidden: false,
        byAccountId: {},
      },
      restrictions: {},
      currencyRates: { USD: 1 },
    } as unknown as GlobalState;
    const buildHostContext = jest.fn(buildAgentV2HostContext);
    const selectHostContext = createAgentV2HostContextSelector(buildHostContext);

    const first = selectHostContext(global);
    const unrelatedUpdate = {
      ...global,
      DEBUG_randomId: 2,
      tokenInfo: {
        ...global.tokenInfo,
        irrelevantStatus: 'loaded',
      },
    } as unknown as GlobalState;
    const second = selectHostContext(unrelatedUpdate);

    expect(second).toBe(first);
    expect(buildHostContext).toHaveBeenCalledTimes(1);

    selectHostContext({
      ...unrelatedUpdate,
      tokenInfo: {
        ...unrelatedUpdate.tokenInfo,
        bySlug: { ...unrelatedUpdate.tokenInfo.bySlug },
      },
    });
    expect(buildHostContext).toHaveBeenCalledTimes(2);
  });

  it('invalidates the memoized host context when swap metadata changes', () => {
    const global = {
      ...stakingGlobal(),
      swapTokenInfo: {
        isLoaded: true,
        bySlug: {
          toncoin: {
            slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: 2.5,
          },
        },
      },
    } as unknown as GlobalState;
    const buildHostContext = jest.fn(buildAgentV2HostContext);
    const selectHostContext = createAgentV2HostContextSelector(buildHostContext);
    const first = selectHostContext(global);

    const second = selectHostContext({
      ...global,
      swapTokenInfo: {
        ...global.swapTokenInfo,
        bySlug: {
          ...global.swapTokenInfo.bySlug,
          toncoin: { ...global.swapTokenInfo.bySlug.toncoin, priceUsd: 3 },
        },
      },
    } as GlobalState);

    expect(second).not.toBe(first);
    expect(buildHostContext).toHaveBeenCalledTimes(2);
  });
});

function stakingGlobal(): GlobalState {
  return {
    currentAccountId: 'mainnet-account',
    accounts: {
      byId: {
        'mainnet-account': {
          type: 'mnemonic',
          title: 'Main',
          byChain: { ton: { address: 'EQ-address' } },
        },
      },
    },
    byAccountId: {
      'mainnet-account': { balances: { bySlug: {} } },
    },
    tokenInfo: {
      bySlug: {
        toncoin: {
          slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9,
        },
      },
    },
    settings: {
      langCode: 'en', baseCurrency: 'USD', theme: 'light', isTestnet: false, byAccountId: {},
    },
    stakingDefault: DEFAULT_STAKING_STATE,
    restrictions: {},
    currencyRates: { USD: 1 },
  } as unknown as GlobalState;
}
