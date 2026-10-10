/* eslint-disable no-null/no-null -- Query fixtures exercise the nullable detail result. */
import type { ApiActivity } from '../types';
import type { AgentApiChain, AgentToolCall, AgentWalletDataQueryArgs } from './protocol/types';
import type { AgentV2HostContextSnapshot, AgentV2HostPosition } from './types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';

import { getSupportedChains } from '../../util/chain';
import * as cache from '../common/cache';
import contractManifest from './generated/manifest.json';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { materializeWalletQuery } from './walletQueryMaterializer';
import { resolveWalletQueryScope } from './walletQueryScope';
import { AgentV2WalletSession } from './walletSession';

const NOW = '2026-08-10T12:00:00.000Z';
const MESSAGE_ID = '11111111-1111-4111-8111-111111111111';
const CHAIN_CASES = [
  { name: 'runtime catalog', chains: [...getSupportedChains()] },
  { name: '65 future chains', chains: Array.from({ length: 65 }, (_, index) => `future-chain-${index}`) },
];

describe('wallet query materializer', () => {
  it('rejects token search on the client', async () => {
    await expect(runQuery(sessionWithHost(), assetsArgs('TON'))).rejects.toMatchObject({
      code: 'invalid_arguments',
    });
  });

  it('requires only the requested position sources before confirming an empty result', async () => {
    const source = host();
    source.accounts[0].holdings = [];
    source.accounts[0].positions = [];
    source.accounts[0].nftLoadedChains = [];
    source.accounts[0].domainStates = {
      fungible: { state: 'fresh' },
      staking: { state: 'notLoaded' },
      vesting: { state: 'notLoaded' },
      vault: { state: 'unavailable' },
    };
    const session = new AgentV2WalletSession();
    session.update(source);
    const query = positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: false });
    const refreshWalletHoldings = jest.fn().mockResolvedValue(new Map());

    for (const kind of ['nft', 'staking', 'vesting'] as const) {
      const result = await runQuery(session, { ...query, positionKinds: [kind] }, { refreshWalletHoldings });
      expect(result).toMatchObject({
        positions: [],
        coverage: {
          status: 'unavailable', accountsIncluded: 0,
          sourceOutcomes: [{ status: 'not_loaded', reason: 'unknown' }],
        },
      });
      expect(result.coverage).not.toHaveProperty('emptyReason');
    }
    expect(refreshWalletHoldings).not.toHaveBeenCalled();
    expect(await runQuery(session, { ...query, positionKinds: ['fungible'] })).toMatchObject({
      positions: [],
      coverage: { status: 'complete', emptyReason: 'no_matching_rows' },
    });
    const mixed = await runQuery(session, { ...query, positionKinds: ['fungible', 'nft'] });
    expect(mixed).toMatchObject({
      positions: [],
      coverage: { status: 'partial', sourceOutcomes: [{ status: 'not_loaded' }] },
    });
    expect(mixed.coverage).not.toHaveProperty('emptyReason');

    source.accounts[0].nftLoadedChains = ['ton'];
    session.update(source);
    expect(await runQuery(session, { ...query, positionKinds: ['nft'] })).toMatchObject({
      positions: [],
      coverage: {
        status: 'complete', emptyReason: 'no_matching_rows',
        sourceOutcomes: [{ status: 'complete_empty' }],
      },
    });
  });

  it('needs the NFTs of the networks read alone to be read in full', async () => {
    const source = host();
    source.accounts[0].chains = ['ton', 'solana'];
    source.accounts[0].addresses = { ton: 'EQ-main-private-address', solana: 'solana-main-private-address' };
    source.accounts[0].nftLoadedChains = ['ton'];
    const session = new AgentV2WalletSession();
    session.update(source);
    const readNfts = (chains: AgentApiChain[]) => runQuery(session, {
      ...positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: false }), positionKinds: ['nft'], chains,
    });

    expect(await readNfts(['ton'])).toMatchObject({ coverage: { status: 'complete' } });
    for (const chains of [['solana'], []]) {
      expect(await readNfts(chains)).toMatchObject({ coverage: { sourceOutcomes: [{ status: 'not_loaded' }] } });
    }
  });

  it('reads no vesting as complete while the backend keeps vesting off', async () => {
    const source = host();
    // The web host waits for a TON account's vesting, and the native hosts read none
    source.accounts[0].domainStates = { ...source.accounts[0].domainStates, vesting: { state: 'notLoaded' } };
    const session = new AgentV2WalletSession();
    session.update(source);
    const query = { ...positionsArgs({ riskMode: 'exclude', visibilityMode: 'all', includeZero: false }),
      positionKinds: ['fungible' as const, 'staking' as const, 'vesting' as const] };
    expect((await runQuery(session, query)).coverage.limitations).toContain('source_partial');

    // The production config has no `isVestingEnabled`
    jest.spyOn(cache, 'getBackendConfigCacheSync')
      .mockReturnValue({} as ReturnType<typeof cache.getBackendConfigCacheSync>);
    try {
      const { coverage } = await runQuery(session, query);
      expect(coverage.limitations).not.toContain('source_partial');
      expect(coverage.sourceOutcomes).toEqual([expect.objectContaining({ status: 'complete' })]);
    } finally {
      jest.restoreAllMocks();
    }
  });

  it('keeps streamed NFT rows partial and preserves missing sources after refreshing balances', async () => {
    const source = host();
    source.accounts[0].nftLoadedChains = [];
    source.accounts[0].domainStates = {
      fungible: { state: 'notLoaded' },
      staking: { state: 'notLoaded' },
      vesting: { state: 'notLoaded' },
      vault: { state: 'unavailable' },
    };
    source.accounts[0].positions = [{
      id: 'streamed-nft', kind: 'nft', chain: 'ton', label: 'Collectible', valuationStatus: 'not_applicable',
    }];
    const session = new AgentV2WalletSession();
    session.update(source);
    const query = positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: false });
    const refreshWalletHoldings = jest.fn().mockResolvedValue(new Map([['main', {
      byChain: { ton: { toncoin: 2_000_000_000n } }, failedChains: [],
    }]]));
    const nfts = await runQuery(session, { ...query, positionKinds: ['nft'] }, { refreshWalletHoldings });
    expect(nfts).toMatchObject({
      positions: [{ positionKind: 'nft' }],
      coverage: { status: 'partial', sourceOutcomes: [{ status: 'not_loaded' }] },
    });
    expect(refreshWalletHoldings).not.toHaveBeenCalled();

    const all = await runQuery(session, query, { refreshWalletHoldings });
    expect(all).toMatchObject({
      coverage: { status: 'partial', limitations: expect.arrayContaining(['source_partial']) },
      positions: expect.arrayContaining([expect.objectContaining({ positionKind: 'fungible', quantity: '2' })]),
    });
    expect(all.coverage).not.toHaveProperty('emptyReason');
    expect(refreshWalletHoldings).toHaveBeenCalledTimes(1);

    const inventory = await runQuery(session, {
      operation: 'account.inventory', accountSelector: { kind: 'current' },
      chains: [], includePortfolioTotals: true,
    }, { refreshWalletHoldings });
    expect(inventory).toMatchObject({
      accounts: [{ portfolioTotalStatus: 'partial' }], coverage: { status: 'partial' },
    });
  });

  it('returns safe inventory metadata for every account with reason-bound addresses', async () => {
    const session = sessionWithHost();
    const result = await runQuery(session, {
      operation: 'account.inventory',
      accountSelector: { kind: 'explicitAll' },
      chains: [],
      includePublicAddressReason: 'receive',
    });

    expect(result.operation).toBe('account.inventory');
    if (result.operation !== 'account.inventory') return;
    expect(result.accounts).toEqual([
      expect.objectContaining({ accountLabel: 'Main', isCurrent: true, state: 'active' }),
      expect.objectContaining({ accountLabel: 'Savings', isCurrent: false, state: 'active' }),
      expect.objectContaining({ accountLabel: 'Old', isCurrent: false, state: 'stale' }),
      expect.objectContaining({ accountLabel: 'Deleted', isCurrent: false, state: 'deleted' }),
    ]);
    expect(result.accounts[0].publicAddresses).toEqual([{
      chain: 'ton', address: 'EQ-main-private-address', disclosureReason: 'receive',
    }]);
    expect(result.accounts.slice(2).every((account) => account.publicAddresses === undefined)).toBe(true);
    expect(result.coverage).toMatchObject({ status: 'complete', accountsRequested: 4, accountsIncluded: 4 });
  });

  it('returns one fiat overview row for each active regular or view-only wallet', async () => {
    const source = host();
    source.accounts[0].positions = [{
      id: 'staking-1', kind: 'staking', chain: 'ton', label: 'Staking',
      asset: source.assetCatalog![0], quantity: '2', valuationStatus: 'valued', fiatValue: '10',
    }, {
      id: 'nft-1', kind: 'nft', chain: 'ton', label: 'NFT',
      asset: { slug: 'nft-1', chain: 'ton', symbol: 'NFT', decimals: 0 },
      quantity: '1', valuationStatus: 'valued', fiatValue: '2', visibility: 'hidden',
    }, {
      id: 'vesting-1', kind: 'vesting', chain: 'ton', label: 'Vesting',
      asset: source.assetCatalog![0], quantity: '3', valuationStatus: 'unpriced',
    }, {
      id: 'vault-1', kind: 'vault', chain: 'ton', label: 'Vault',
      asset: source.assetCatalog![0], quantity: '1', valuationStatus: 'valued', fiatValue: '3',
    }, {
      id: 'spam-stake', kind: 'staking', chain: 'ton', label: 'Spam',
      asset: source.assetCatalog![0], quantity: '1', valuationStatus: 'valued', fiatValue: '999',
      riskVerdict: 'spam',
    }];
    source.accounts[1].accountType = 'viewOnly';
    source.accounts[1].isViewOnly = true;
    const session = new AgentV2WalletSession();
    session.update(source);

    const result = await runQuery(session, {
      operation: 'account.inventory',
      accountSelector: { kind: 'explicitAll' },
      chains: [],
      includePortfolioTotals: true,
    });

    expect(result.operation).toBe('account.inventory');
    if (result.operation !== 'account.inventory') return;
    expect(result.accounts).toEqual([
      expect.objectContaining({
        accountLabel: 'Main', state: 'active', isViewOnly: false,
        portfolioTotalStatus: 'partial',
        portfolioTotal: { value: '40.5', baseCurrency: 'USD', unpricedCount: 3 },
      }),
      expect.objectContaining({
        accountLabel: 'Savings', state: 'active', isViewOnly: true,
        portfolioTotalStatus: 'complete',
        portfolioTotal: { value: '50', baseCurrency: 'USD', unpricedCount: 0 },
      }),
    ]);
    expect(result.accounts.map(({ accountLabel }) => accountLabel)).not.toEqual(
      expect.arrayContaining(['Old', 'Deleted']),
    );
    expect(result.coverage).toMatchObject({
      status: 'partial', accountsRequested: 2, accountsIncluded: 2,
      limitations: ['unpriced_positions'],
    });
  });

  it.each(CHAIN_CASES)('preserves every $name chain and reason-bound inventory address', async ({ chains }) => {
    const source = buildMultiChainHost(chains);
    const session = new AgentV2WalletSession();
    session.update(source);
    const result = await runQuery(session, {
      operation: 'account.inventory', accountSelector: { kind: 'current' },
      chains: [...chains], includePublicAddressReason: 'receive',
    });

    expect(result.operation).toBe('account.inventory');
    if (result.operation !== 'account.inventory') throw new Error('Expected inventory');
    expect(result.accounts).toHaveLength(1);
    expect(result.accounts[0].chains).toEqual(chains);
    expect(result.accounts[0].publicAddresses).toEqual(chains.map((chain) => ({
      chain, address: source.accounts[0].addresses[chain], disclosureReason: 'receive',
    })));
    expect(result.resolvedScope).toEqual({
      kind: 'current', accounts: [{ accountRef: session.snapshot().accountRefs.get('main')!, accountLabel: 'Main' }],
    });
    expect(result.coverage).toMatchObject({
      status: 'complete', accountsRequested: 1, accountsIncluded: 1, rowsOmitted: 0, limitations: [],
    });
  });

  it('retains wallet metadata when portfolio totals are stale or unavailable', async () => {
    const source = host();
    source.accounts[0].nftLoadedChains = [];
    source.accounts[0].domainStates = {
      ...source.accounts[0].domainStates,
      fungible: { state: 'unavailable' },
      staking: { state: 'unavailable' },
      vesting: { state: 'unavailable' },
      vault: { state: 'unavailable' },
    };
    source.accounts[1].domainStates = {
      ...source.accounts[1].domainStates,
      fungible: { state: 'stale' },
      staking: { state: 'stale' },
      vesting: { state: 'stale' },
      vault: { state: 'stale' },
    };
    const session = new AgentV2WalletSession();
    session.update(source);

    const result = await runQuery(session, {
      operation: 'account.inventory',
      accountSelector: { kind: 'explicitAll' },
      chains: [],
      includePortfolioTotals: true,
    });

    expect(result.operation).toBe('account.inventory');
    if (result.operation !== 'account.inventory') return;
    expect(result.accounts).toEqual([
      expect.objectContaining({
        accountLabel: 'Main', portfolioTotalStatus: 'unavailable',
      }),
      expect.objectContaining({
        accountLabel: 'Savings', portfolioTotalStatus: 'partial',
        portfolioTotal: { value: '50', baseCurrency: 'USD', unpricedCount: 0 },
      }),
    ]);
    expect(result.accounts[0]).not.toHaveProperty('portfolioTotal');
    expect(result.coverage).toMatchObject({
      status: 'partial', accountsRequested: 2, accountsIncluded: 1,
      limitations: expect.arrayContaining(['source_unavailable', 'stale_data', 'source_partial']),
    });
  });

  it('projects available balances and applies risk, visibility, and zero-balance policy', async () => {
    const session = sessionWithHost();
    const all = await runQuery(session, positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: true }));
    const safeVisible = await runQuery(session, positionsArgs({
      riskMode: 'exclude', visibilityMode: 'visible', includeZero: false,
    }));

    expect(all.operation).toBe('positions.list');
    expect(safeVisible.operation).toBe('positions.list');
    if (all.operation !== 'positions.list' || safeVisible.operation !== 'positions.list') return;
    expect(all.positions).toEqual(expect.arrayContaining([
      expect.objectContaining({
        asset: expect.objectContaining({ slug: 'toncoin' }), quantity: '5', availableQuantity: '4.5',
      }),
      expect.objectContaining({ asset: expect.objectContaining({ slug: 'zero' }), quantity: '0' }),
      expect.objectContaining({
        asset: expect.objectContaining({ slug: 'spam' }), riskVerdict: 'spam', assetRef: expect.any(String),
      }),
    ]));
    expect(all.positions.find(({ asset }) => asset.slug === 'mystery')).not.toHaveProperty('availableQuantity');
    expect(safeVisible.positions.map(({ asset }) => asset.slug)).toEqual(['toncoin', 'mystery']);
    expect(safeVisible.policySummary).toEqual({
      riskMode: 'exclude',
      visibilityMode: 'visible',
      spamMatches: { count: 1, accuracy: 'exact' },
      hiddenMatches: { count: 1, accuracy: 'exact' },
    });
  });

  it('scrubs identifier-shaped asset and position display metadata', async () => {
    const source = host();
    const sensitiveSymbol = 'A'.repeat(32);
    const sensitiveName = `Asset ${'b'.repeat(64)}`;
    const positionAddress = `0x${'12'.repeat(20)}`;
    const collectionHash = 'c'.repeat(64);
    source.accounts[0].holdings.push({
      asset: {
        slug: 'unsafe-held', chain: 'ton', symbol: sensitiveSymbol, name: sensitiveName, decimals: 9,
      },
      balance: '3',
      fiatValue: '3',
      valuationStatus: 'valued',
    });
    source.accounts[0].positions = [{
      id: 'unsafe-nft',
      kind: 'nft',
      chain: 'ton',
      label: positionAddress,
      asset: {
        slug: 'unsafe-nft', chain: 'ton', symbol: 'SAFE', name: 'Normal NFT', decimals: 0,
      },
      quantity: '1',
      valuationStatus: 'not_applicable',
      collection: collectionHash,
    }];
    const session = new AgentV2WalletSession();
    session.update(source);
    const positions = await runQuery(session, positionsArgs({
      riskMode: 'all', visibilityMode: 'all', includeZero: true,
    }));
    const portfolio = await runQuery(session, {
      operation: 'portfolio.aggregate',
      accountSelector: { kind: 'current' },
      chains: ['ton'],
      range: '3m',
      groupBy: ['asset'],
      riskMode: 'all',
      visibilityMode: 'all',
    });
    const valueSeries = await runQuery(session, {
      operation: 'value.series',
      accountSelector: { kind: 'current' },
      chains: [],
      metric: 'position_value',
      assetSelectors: [{ slug: 'unsafe-held' }],
      range: '3m',
      maxPoints: 64,
    });

    expect(positions.operation).toBe('positions.list');
    expect(portfolio.operation).toBe('portfolio.aggregate');
    expect(valueSeries.operation).toBe('value.series');
    if (
      positions.operation !== 'positions.list'
      || portfolio.operation !== 'portfolio.aggregate'
      || valueSeries.operation !== 'value.series'
    ) return;
    const fungible = positions.positions.find(({ asset }) => asset.slug === 'unsafe-held')!;
    const nft = positions.positions.find(({ asset }) => asset.slug === 'unsafe-nft')!;
    expect(fungible).toMatchObject({ label: 'Asset', asset: { symbol: 'Asset', name: 'Asset' } });
    expect(nft).toMatchObject({ label: 'Position', collection: 'Collection' });
    expect(positions.positions.find(({ asset }) => asset.slug === 'zero')).toMatchObject({
      label: 'ZERO', asset: { symbol: 'ZERO' },
    });
    expect(portfolio.aggregates.find(({ label }) => label === 'Asset')).toBeDefined();
    expect(valueSeries.historyAccounts).toEqual([expect.objectContaining({
      asset: expect.objectContaining({ slug: 'unsafe-held', symbol: 'Asset', name: 'Asset' }),
    })]);
    expect(JSON.stringify({ positions, portfolio, valueSeries })).not.toMatch(
      new RegExp(`${sensitiveSymbol}|${sensitiveName}|${positionAddress}|${collectionHash}`, 'u'),
    );
  });

  it('does not synthesize spendable quantity from a refreshed total balance', async () => {
    const source = host();
    source.accounts[0] = {
      ...source.accounts[0],
      domainStates: { ...source.accounts[0].domainStates, fungible: { state: 'stale' } },
    };
    const session = new AgentV2WalletSession();
    session.update(source);
    const result = await runQuery(session, positionsArgs({
      riskMode: 'exclude', visibilityMode: 'visible', includeZero: false,
    }), {
      refreshWalletHoldings: () => Promise.resolve(new Map([['main', {
        byChain: { ton: { toncoin: 5_000_000_000n } },
        failedChains: [],
      }]])),
    });

    expect(result.operation).toBe('positions.list');
    if (result.operation !== 'positions.list') return;
    expect(result.positions.find(({ asset }) => asset.slug === 'toncoin')).toMatchObject({ quantity: '5' });
    expect(result.positions.find(({ asset }) => asset.slug === 'toncoin')).not.toHaveProperty('availableQuantity');
  });

  it('projects vesting under its own asset and never substitutes the native token for a missing asset', async () => {
    const source = host();
    const mycoin = {
      slug: 'ton-eqcfvnlrbn', chain: 'ton', symbol: 'MY', name: 'My Wallet Coin',
      tokenAddress: 'EQ-mycoin-minter', decimals: 9,
    };
    source.accounts[0].positions = [{
      id: 'vesting-1', kind: 'vesting', chain: 'ton', label: 'Vesting',
      asset: mycoin, quantity: '12.5', valuationStatus: 'unpriced', status: 'frozen',
    }, {
      // Native hosts send untyped JSON, so the SDK still meets positions that lack a required asset
      id: 'vesting-2', kind: 'vesting', chain: 'ton', label: 'Vesting', quantity: '3', valuationStatus: 'unpriced',
    } as AgentV2HostPosition, {
      id: 'staking-1', kind: 'staking', chain: 'ton', label: 'Staking', quantity: '4', valuationStatus: 'unpriced',
    } as AgentV2HostPosition];
    const session = new AgentV2WalletSession();
    session.update(source);
    const args: Extract<AgentWalletDataQueryArgs, { operation: 'positions.list' }> = {
      ...positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: true }),
      positionKinds: ['staking', 'vesting'],
    };
    const all = await runQuery(session, args);
    const byMycoin = await runQuery(session, { ...args, assetSelectors: [{ slug: mycoin.slug }] });

    expect(all.operation).toBe('positions.list');
    expect(byMycoin.operation).toBe('positions.list');
    if (all.operation !== 'positions.list' || byMycoin.operation !== 'positions.list') return;
    expect(all.positions).toEqual([expect.objectContaining({
      positionKind: 'vesting', asset: mycoin, quantity: '12.5', decimals: 9,
      valuationStatus: 'unpriced', status: 'frozen',
    })]);
    expect(all.coverage).toMatchObject({ status: 'partial', rowsOmitted: 2 });
    expect(byMycoin.positions.map(({ positionKind }) => positionKind)).toEqual(['vesting']);
  });

  it('never reads stale or deleted accounts and reports explicit-all coverage honestly', async () => {
    const session = sessionWithHost();
    const result = await runQuery(session, {
      ...positionsArgs({ riskMode: 'exclude', visibilityMode: 'all', includeZero: false }),
      accountSelector: { kind: 'explicitAll' },
    });

    expect(result.operation).toBe('positions.list');
    if (result.operation !== 'positions.list') return;
    const accountLabels = result.positions.map(({ accountLabel }) => accountLabel);
    expect(accountLabels).toEqual(expect.arrayContaining(['Main', 'Savings']));
    expect(accountLabels).not.toEqual(expect.arrayContaining(['Old', 'Deleted']));
    expect(result.positions.map(({ quantity }) => quantity)).not.toContain('777');
    expect(result.coverage).toMatchObject({
      status: 'partial', accountsRequested: 4, accountsIncluded: 2,
      limitations: expect.arrayContaining(['source_partial']),
    });
  });

  it('hands only the current wallet sources to the backend', async () => {
    const source = host();
    source.accounts[1].portfolioWalletKeys = ['ton:EQ-savings-private-address'];
    const session = new AgentV2WalletSession();
    session.update(source);
    const result = await runQuery(session, {
      operation: 'portfolio.aggregate', accountSelector: { kind: 'current' },
      chains: [], range: '1m', groupBy: ['account'], riskMode: 'all', visibilityMode: 'all',
      historySource: 'backend',
    });
    expect(result.operation).toBe('portfolio.aggregate');
    if (result.operation !== 'portfolio.aggregate') throw new Error('Expected portfolio');
    expect(result.positions.length).toBeGreaterThan(0);
    expect(result.series).toEqual([]);
    expect(result.rangePnl).toBeUndefined();
    expect(result.historyAccounts?.map(({ accountRef }) => accountRef)).toEqual(
      result.resolvedScope.accounts.map(({ accountRef }) => accountRef),
    );
    expect(result.historyAccounts?.flatMap(({ wallets }) => wallets)).toEqual(['ton:EQ-main-private-address']);
  });

  it.each(CHAIN_CASES)('preserves every $name history wallet key within the current account', async ({ chains }) => {
    const source = buildMultiChainHost(chains);
    const session = new AgentV2WalletSession();
    session.update(source);
    const queries: AgentWalletDataQueryArgs[] = [{
      operation: 'value.series', accountSelector: { kind: 'current' },
      chains: [], metric: 'portfolio_value', assetSelectors: [], range: '1m', maxPoints: 64,
    }, {
      operation: 'portfolio.aggregate', accountSelector: { kind: 'current' },
      chains: [], range: '1m', groupBy: ['account'], riskMode: 'all', visibilityMode: 'all',
      historySource: 'backend',
    }];
    const accountRef = session.snapshot().accountRefs.get('main')!;
    const wallets = chains.map((chain) => `${chain}:${source.accounts[0].addresses[chain]}`);

    for (const query of queries) {
      const result = await runQuery(session, query);
      expect(result.operation).toBe(query.operation);
      if (result.operation !== 'value.series' && result.operation !== 'portfolio.aggregate') {
        throw new Error('Expected history result');
      }
      expect(result.historyAccounts).toEqual([{ accountRef, wallets }]);
      expect(result.resolvedScope).toEqual({ kind: 'current', accounts: [{ accountRef, accountLabel: 'Main' }] });
      expect(result.coverage).toMatchObject({
        status: 'complete', accountsRequested: 1, accountsIncluded: 1, rowsOmitted: 0, limitations: [],
      });
      expect(result.series).toEqual([]);
    }
  });

  it('returns current portfolio totals and allocations without reading history', async () => {
    const result = await runQuery(sessionWithHost(), {
      operation: 'portfolio.aggregate', accountSelector: { kind: 'current' },
      chains: [], range: '3m', groupBy: ['asset', 'network'], riskMode: 'exclude', visibilityMode: 'visible',
    });

    if (result.operation !== 'portfolio.aggregate') throw new Error('Expected portfolio');
    expect(result.total).toEqual({ value: '25.5', baseCurrency: 'USD', unpricedCount: 1 });
    expect(result.allocations).toEqual([
      expect.objectContaining({ asset: expect.objectContaining({ slug: 'toncoin' }), value: '25.5', percent: '100' }),
    ]);
    expect(result.aggregates).toEqual(expect.arrayContaining([
      expect.objectContaining({ groupKind: 'network', label: 'ton', value: '25.5', unpricedCount: 1 }),
    ]));
    expect(result.series).toEqual([]);
    expect(result).not.toHaveProperty('rangePnl');
    expect(result).not.toHaveProperty('historyAccounts');
  });

  it.each([
    ['include', ['Main', 'Savings', 'Old', 'Deleted'], ['main', 'savings'], [
      'ton:EQ-main-private-address', 'ton:EQ-savings-private-address',
    ]],
    ['exclude', ['Main', 'Old', 'Deleted'], ['main'], ['ton:EQ-main-private-address']],
    ['only', ['Savings'], ['savings'], ['ton:EQ-savings-private-address']],
  ] as const)(
    'applies the %s view-only portfolio filter before explicit-all materialization',
    async (viewOnly, expectedLabels, expectedAccountIds, expectedWalletKeys) => {
      const source = host();
      source.accounts[1].accountType = 'viewOnly';
      source.accounts[1].isViewOnly = true;
      source.accounts[1].portfolioWalletKeys = ['ton:EQ-savings-private-address'];
      const session = new AgentV2WalletSession();
      session.update(source);
      const args: Extract<AgentWalletDataQueryArgs, { operation: 'portfolio.aggregate' }> = {
        operation: 'portfolio.aggregate',
        historySource: 'backend',
        accountSelector: { kind: 'explicitAll' },
        accountFilter: { viewOnly },
        chains: [],
        range: '3m',
        groupBy: ['account', 'asset', 'network'],
        riskMode: 'all',
        visibilityMode: 'all',
      };
      const snapshot = session.snapshot();
      const active = snapshot.host!.accounts.find(({ accountId }) => (
        accountId === snapshot.host!.activeAccountId
      ))!;
      const authority = await session.walletAuthorityBinding();
      const resolution = resolveWalletQueryScope({
        args,
        authorityBinding: {
          ...authority,
          accountScope: 'explicitAll',
          activeAccountRef: snapshot.accountRefs.get(active.accountId)!,
        },
        call: queryCall(session, args, 'explicitAll'),
        session,
      });

      expect(resolution.kind).toBe('resolved');
      if (resolution.kind !== 'resolved') return;
      expect(resolution.resolvedScope.accounts.map(({ accountLabel }) => accountLabel)).toEqual(expectedLabels);
      expect(resolution.materializationScope.accountIds).toEqual(expectedAccountIds);
      expect(resolution.materializationScope.accountsRequested).toBe(expectedLabels.length);

      const result = await materializeWalletQuery({
        session,
        authorityBinding: {
          ...authority,
          accountScope: 'explicitAll',
          activeAccountRef: snapshot.accountRefs.get(active.accountId)!,
        },
        args,
        call: queryCall(session, args, 'explicitAll'),
        completedAt: NOW,
        signal: new AbortController().signal,
        scope: resolution.materializationScope,
        resolvedScope: resolution.resolvedScope,
      });
      expect(result.coverage.accountsRequested).toBe(expectedLabels.length);
      if (result.operation !== 'portfolio.aggregate') throw new Error('Expected a portfolio aggregate result');
      expect(result.resolvedScope.accounts.map(({ accountLabel }) => accountLabel)).toEqual(expectedLabels);
      expect(result.historyAccounts?.flatMap(({ wallets }) => wallets)).toEqual(expectedWalletKeys);
    },
  );

  it('accounts for position and allocation truncation', async () => {
    const source = host();
    const holdings = Array.from({ length: 101 }, (_, index) => ({
      asset: { slug: `asset-${index}`, chain: 'ton' as const, symbol: `A${index}`, decimals: 9 },
      balance: '1', fiatValue: '1', valuationStatus: 'valued' as const,
    }));
    source.accounts[0] = { ...source.accounts[0], holdings };
    const session = new AgentV2WalletSession();
    session.update(source);
    const result = await runQuery(session, {
      operation: 'portfolio.aggregate',
      accountSelector: { kind: 'current' },
      chains: [],
      range: '3m',
      groupBy: ['asset'],
      riskMode: 'exclude',
      visibilityMode: 'visible',
    });

    expect(result.operation).toBe('portfolio.aggregate');
    if (result.operation !== 'portfolio.aggregate') return;
    expect(result.positions).toHaveLength(100);
    expect(result.allocations).toHaveLength(100);
    expect(result.series).toEqual([]);
    expect(result.coverage).toMatchObject({
      status: 'partial', rowsOmitted: 3, limitations: expect.arrayContaining(['row_limit']),
    });
  });

  it.each([
    ['week', 'rolling_weeks', '2026-08-03T12:00:00.000Z'],
    ['month', 'rolling_months', '2026-07-10T12:00:00.000Z'],
    ['six months', 'rolling_months', '2026-02-10T12:00:00.000Z'],
  ] as const)('filters transaction rows for %s using inclusive start and exclusive end', async (
    _period, rangeKind, fromInclusive,
  ) => {
    const from = Date.parse(fromInclusive);
    const to = Date.parse(NOW);
    const times = [to, to - 1, from + 1, from, from - 1];
    const fetchPastActivities = jest.fn(() => Promise.resolve({
      activities: times.map((time, index) => transaction(String(index + 1).repeat(64), time, 1_000_000_000n)),
      hasMore: false,
    }));
    const result = await runQuery(sessionWithHost(), {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
      filters: { schemaVersion: 1, catalogDigest: contractManifest.walletFilterCatalogSha256, clauses: [{
        field: 'transaction.timestamp', operator: 'timestamp_range',
        range: { rangeKind, fromInclusive, toExclusive: NOW, timeZone: 'UTC', resolvedAt: NOW },
      }] },
    }, { fetchPastActivities });
    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') throw new Error('Expected transaction list');
    expect(result.transactions.map(({ timestamp }) => timestamp)).toEqual(
      [to - 1, from + 1, from].map((time) => new Date(time).toISOString()),
    );
    expect(result.coverage.status).toBe('complete');
  });

  it('builds globally ordered self-contained transaction rows without raw hashes or addresses', async () => {
    const session = sessionWithHost();
    const mainHash = 'a'.repeat(64);
    const savingsHash = 'b'.repeat(64);
    const zeroHash = 'c'.repeat(64);
    const fetchPastActivities = jest.fn((accountId: string) => Promise.resolve({
      activities: accountId === 'main'
        ? [transaction(mainHash, Date.parse('2026-08-10T10:00:00.000Z'), 1_000_000_000n),
          transaction(zeroHash, Date.parse('2026-08-10T08:00:00.000Z'), 0n)]
        : [transaction(savingsHash, Date.parse('2026-08-10T11:00:00.000Z'), 2_000_000n, true)],
      hasMore: false,
    }));
    const result = await runQuery(session, transactionsArgs('list'), { fetchPastActivities });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    expect(result.transactions.map(({ timestamp }) => timestamp)).toEqual([
      '2026-08-10T11:00:00.000Z', '2026-08-10T10:00:00.000Z', '2026-08-10T08:00:00.000Z',
    ]);
    expect(result.transactions[2]).not.toHaveProperty('quantity');
    expect(new Set(result.transactions.map(({ rowId }) => rowId)).size).toBe(3);
    expect(result.transactions.every(({ displayHash }) => displayHash.length < 64)).toBe(true);
    const serialized = JSON.stringify(result);
    expect(serialized).not.toContain(mainHash);
    expect(serialized).not.toContain(savingsHash);
    expect(serialized).not.toContain('EQ-external-counterparty-address');
    expect(fetchPastActivities.mock.calls.map(([accountId]) => accountId).sort()).toEqual(['main', 'savings']);
  });

  it('projects approvals without treating the allowance as transferred value', async () => {
    const session = sessionWithHost();
    const approval = transaction('d'.repeat(64), Date.parse(NOW), 2n ** 256n - 1n);
    if (approval.kind !== 'transaction') throw new Error('Expected transaction fixture');
    approval.type = 'approval';
    const result = await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, {
      fetchPastActivities: () => Promise.resolve({ activities: [approval], hasMore: false }),
    });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    expect(result.transactions).toEqual([
      expect.objectContaining({
        transactionType: 'callContract',
        safeDescription: 'Token approval',
      }),
    ]);
    expect(result.transactions[0]).not.toHaveProperty('quantity');
  });

  it('applies the top-level transaction chain constraint', async () => {
    const session = sessionWithHost();
    const result = await runQuery(session, {
      ...transactionsArgs('list'),
      accountSelector: { kind: 'current' },
      chains: ['ethereum'],
    }, {
      fetchPastActivities: () => Promise.resolve({
        activities: [transaction('a'.repeat(64), Date.parse(NOW), 1n)],
        hasMore: false,
      }),
    });

    expect(result).toMatchObject({ operation: 'transactions.list', transactions: [] });
  });

  it('does not identify stale account addresses as wallet counterparties', async () => {
    const session = sessionWithHost();
    const activity = transaction('b'.repeat(64), Date.parse(NOW), 1n, true);
    if (activity.kind !== 'transaction') throw new Error('Expected transaction fixture');
    activity.fromAddress = 'EQ-old-private-address';
    const result = await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, {
      fetchPastActivities: () => Promise.resolve({ activities: [activity], hasMore: false }),
    });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    expect(result.transactions[0].counterparty).toMatchObject({ kind: 'external' });
    expect(JSON.stringify(result.transactions[0])).not.toContain('Old');
  });

  it('does not trust address- or hash-shaped provider names for transaction displays', async () => {
    const session = sessionWithHost();
    const rawAddress = `0x${'ab'.repeat(20)}`;
    const fullHashName = 'd'.repeat(64);
    const prefixedHashName = `tx:${'c'.repeat(64)}`;
    const addressNamed = transaction('e'.repeat(64), Date.parse(NOW), 1n);
    const hashNamed = transaction('f'.repeat(64), Date.parse(NOW) - 1, 1n);
    const prefixedHashNamed = transaction('a'.repeat(64), Date.parse(NOW) - 2, 1n);
    if (
      addressNamed.kind !== 'transaction'
      || hashNamed.kind !== 'transaction'
      || prefixedHashNamed.kind !== 'transaction'
    ) {
      throw new Error('Expected transaction fixtures');
    }
    addressNamed.type = 'callContract';
    addressNamed.toAddress = rawAddress;
    addressNamed.metadata = { name: `Router ${rawAddress}` };
    hashNamed.type = 'callContract';
    hashNamed.metadata = { name: `${fullHashName}…` };
    prefixedHashNamed.type = 'callContract';
    prefixedHashNamed.metadata = { name: prefixedHashName };
    const result = await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, {
      fetchPastActivities: () => Promise.resolve({
        activities: [addressNamed, hashNamed, prefixedHashNamed],
        hasMore: false,
      }),
    });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    const serialized = JSON.stringify(result.transactions);
    expect(serialized).not.toContain(rawAddress);
    expect(serialized).not.toContain(fullHashName);
    expect(serialized).not.toContain(prefixedHashName);
    expect(result.transactions).toEqual(expect.arrayContaining([
      expect.objectContaining({
        counterparty: expect.objectContaining({ display: expect.stringMatching(/[·…]/u) }),
        contractDetails: expect.objectContaining({ contractDisplay: expect.stringMatching(/[·…]/u) }),
      }),
    ]));
  });

  it('scrubs identifier-shaped NFT metadata and transaction account labels', async () => {
    const source = host();
    const rawAddress = `0x${'34'.repeat(20)}`;
    const secondAddress = `0x${'56'.repeat(20)}`;
    const nftHash = '7'.repeat(64);
    source.accounts[0].label = rawAddress;
    source.accounts[0].addresses.ethereum = rawAddress;
    source.accounts[1].label = `Savings ${secondAddress}`;
    source.accounts[1].addresses.ethereum = secondAddress;
    const session = new AgentV2WalletSession();
    session.update(source);
    const nftActivity = transaction('8'.repeat(64), Date.parse(NOW), 0n);
    if (nftActivity.kind !== 'transaction') throw new Error('Expected transaction fixture');
    nftActivity.nft = {
      chain: 'ton',
      index: 1,
      address: 'EQ-nft-address',
      name: `Collectible tx:${nftHash}`,
      collectionName: `${rawAddress}… collection`,
      isOnSale: false,
      metadata: {},
      interface: 'default',
    };
    const walletCounterpartyActivity = transaction('5'.repeat(64), Date.parse(NOW) - 1, 1n);
    if (walletCounterpartyActivity.kind !== 'transaction') throw new Error('Expected transaction fixture');
    walletCounterpartyActivity.toAddress = source.accounts[1].addresses.ton!;
    const result = await runQuery(session, transactionsArgs('list'), {
      fetchPastActivities: (accountId) => Promise.resolve({
        activities: accountId === 'main'
          ? [nftActivity, walletCounterpartyActivity]
          : [transaction('6'.repeat(64), Date.parse(NOW) - 2, 1n)],
        hasMore: false,
      }),
    });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    expect(result.transactions).toHaveLength(3);
    expect(new Set(result.transactions.map(({ accountLabel }) => accountLabel))).toEqual(new Set(['Wallet']));
    expect(result.transactions[0]).toMatchObject({
      nftDetails: { displayName: 'NFT', collectionName: 'NFT collection' },
      safeDescription: 'NFT transaction',
    });
    expect(result.transactions[1].counterparty).toEqual({ kind: 'wallet', display: 'Wallet' });
    expect(JSON.stringify(result.transactions)).not.toMatch(
      new RegExp(`${rawAddress}|${secondAddress}|${nftHash}`, 'u'),
    );

    const inventory = await runQuery(session, {
      operation: 'account.inventory',
      accountSelector: { kind: 'explicitAll' },
      chains: [],
    });
    const positions = await runQuery(session, {
      ...positionsArgs({ riskMode: 'all', visibilityMode: 'all', includeZero: true }),
      accountSelector: { kind: 'explicitAll' },
    });
    const valueSeries = await runQuery(session, {
      operation: 'value.series',
      accountSelector: { kind: 'explicitAll' },
      chains: [],
      metric: 'portfolio_value',
      assetSelectors: [],
      range: '3m',
      maxPoints: 64,
    });

    expect(inventory.operation).toBe('account.inventory');
    expect(positions.operation).toBe('positions.list');
    expect(valueSeries.operation).toBe('value.series');
    if (
      inventory.operation !== 'account.inventory'
      || positions.operation !== 'positions.list'
      || valueSeries.operation !== 'value.series'
    ) return;
    expect(inventory.accounts.slice(0, 2).map(({ accountLabel }) => accountLabel)).toEqual(['Wallet', 'Wallet']);
    expect(new Set(positions.positions.map(({ accountLabel }) => accountLabel))).toEqual(new Set(['Wallet']));
    expect(valueSeries.historyAccounts).not.toHaveLength(0);
    expect(valueSeries.series).toEqual([]);
  });

  it('expands a bounded activity window before advancing so equal-timestamp peers are not lost', async () => {
    const session = sessionWithHost();
    const activities = Array.from({ length: 60 }, (_, index) => transaction(
      index.toString(16).padStart(64, '0'),
      Date.parse('2026-08-10T10:00:00.000Z'),
      1_000_000_000n,
    ));
    const fetchPastActivities = jest.fn((_accountId: string, limit: number) => Promise.resolve({
      activities: activities.slice(0, limit),
      hasMore: activities.length > limit,
    }));
    const result = await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' }, pageSize: 50,
    }, { fetchPastActivities });

    expect(result.operation).toBe('transactions.list');
    if (result.operation !== 'transactions.list') return;
    expect(result.transactions).toHaveLength(50);
    expect(fetchPastActivities.mock.calls.map(([, limit]) => limit)).toEqual([50, 100]);
    expect(result.coverage).toMatchObject({ status: 'partial', rowsOmitted: 10 });
  });

  it('fails closed when enriched detail no longer matches the requested full hash', async () => {
    const session = sessionWithHost();
    const hash = 'd'.repeat(64);
    const result = await runQuery(session, {
      operation: 'transactions.detail', accountSelector: { kind: 'current' }, hash,
    }, {
      fetchPastActivities: () => Promise.resolve({
        activities: [transaction(hash, Date.parse(NOW), 1n)], hasMore: false,
      }),
      fetchActivityDetails: () => Promise.resolve(transaction('e'.repeat(64), Date.parse(NOW), 1n)),
    });

    expect(result).toMatchObject({
      operation: 'transactions.detail',
      transaction: null,
      coverage: { status: 'partial', limitations: expect.arrayContaining(['source_partial']) },
    });
  });

  it('matches canonical-equivalent EVM detail hashes through scan and enrichment', async () => {
    const session = sessionWithHost();
    const bareHash = 'a'.repeat(64);
    const requestedHash = `0x${bareHash.toUpperCase()}`;
    const fetchActivityDetails = jest.fn(() => Promise.resolve(transaction(bareHash, Date.parse(NOW), 1n)));
    const result = await runQuery(session, {
      operation: 'transactions.detail',
      accountSelector: { kind: 'current' },
      hash: requestedHash,
    }, {
      fetchPastActivities: () => Promise.resolve({
        activities: [transaction(bareHash, Date.parse(NOW), 1n)], hasMore: false,
      }),
      fetchActivityDetails,
    });

    expect(result.operation).toBe('transactions.detail');
    if (result.operation !== 'transactions.detail') return;
    expect(result.transaction).not.toBeNull();
    expect(fetchActivityDetails).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(result)).not.toContain(bareHash);
    expect(JSON.stringify(result)).not.toContain(requestedHash);
  });

  it('does not case-fold non-hex transaction hashes', async () => {
    const session = sessionWithHost();
    const sourceHash = `A${'b'.repeat(42)}`;
    const result = await runQuery(session, {
      operation: 'transactions.detail',
      accountSelector: { kind: 'current' },
      hash: sourceHash.toLocaleLowerCase('en-US'),
    }, {
      fetchPastActivities: () => Promise.resolve({
        activities: [transaction(sourceHash, Date.parse(NOW), 1n)], hasMore: false,
      }),
    });

    expect(result).toMatchObject({ operation: 'transactions.detail', transaction: null });
  });

  it('returns opaque per-account contact bindings and a masked display address', async () => {
    const session = sessionWithHost();
    const args = {
      operation: 'contacts.list' as const,
      accountSelector: { kind: 'explicitAll' },
      query: 'treasury',
      chains: ['ton'],
      ownWalletChains: ['ton'],
      pageSize: 10,
    } satisfies AgentWalletDataQueryArgs;
    const result = await runQuery(session, args);
    const secondSessionResult = await runQuery(sessionWithHost(), args);

    expect(result.operation).toBe('contacts.list');
    if (result.operation !== 'contacts.list') return;
    expect(result.contacts).toEqual([expect.objectContaining({
      name: 'Treasury', contactRef: expect.any(String), addressRef: expect.any(String),
      addressDisplay: expect.not.stringContaining('EQ-treasury-private-address'),
    })]);
    expect(JSON.stringify(result)).not.toContain('EQ-treasury-private-address');
    expect(secondSessionResult.operation).toBe('contacts.list');
    if (secondSessionResult.operation !== 'contacts.list') return;
    expect(secondSessionResult.contacts[0].rowId).not.toBe(result.contacts[0].rowId);
  });

  it('returns another own wallet as an opaque recipient candidate', async () => {
    const result = await runQuery(sessionWithHost(), {
      operation: 'contacts.list',
      accountSelector: { kind: 'current' },
      query: 'savings',
      chains: ['ton'],
      ownWalletChains: ['ton'],
      pageSize: 10,
    });

    expect(result.operation).toBe('contacts.list');
    if (result.operation !== 'contacts.list') return;
    expect(result.coverage).toMatchObject({ status: 'complete', rowsOmitted: 0 });
    expect(result.contacts).toEqual([expect.objectContaining({
      kind: 'contact',
      name: 'Savings',
      chain: 'ton',
      contactRef: expect.stringMatching(/^contact_/u),
      addressRef: expect.stringMatching(/^address_/u),
      addressDisplay: expect.stringMatching(/[·…]/u),
    })]);
    expect(JSON.stringify(result)).not.toContain('EQ-savings-private-address');
  });

  it('builds Send recipient context from all profile wallets and address books on every chain', async () => {
    const source = host();
    source.accounts[1].savedAddresses!.push({
      id: 'secondary-sol', name: 'Workshop', chain: 'solana', address: 'solana-workshop-private',
    });
    source.accounts[1].chains = ['tron'];
    source.accounts[1].addresses = { tron: 'tron-vault-private' };
    source.accounts[1].isViewOnly = true;
    source.savedAddresses = [
      { id: 'profile-only', name: 'Partner', chain: 'ethereum', address: '0x-partner-private' },
      { id: 'duplicate', name: 'Workshop', chain: 'solana', address: 'solana-workshop-private' },
    ];
    const session = new AgentV2WalletSession();
    session.update(source);
    const result = await runQuery(session, {
      operation: 'contacts.list', accountSelector: { kind: 'current' },
      purpose: 'send_recipient_resolution', query: null, chains: [], ownWalletChains: ['ton', 'tron'], pageSize: 100,
    });
    expect(result.operation).toBe('contacts.list');
    if (result.operation !== 'contacts.list') throw new Error('Expected contacts');
    expect(result.coverage).toMatchObject({ status: 'complete', rowsOmitted: 0 });
    expect(result.contacts).toEqual(expect.arrayContaining([
      expect.objectContaining({ name: 'Workshop', chain: 'solana' }),
      expect.objectContaining({ name: 'Savings', chain: 'tron' }),
      expect.objectContaining({ name: 'Main', chain: 'ton' }),
      expect.objectContaining({ name: 'Treasury', chain: 'ton' }),
      expect.objectContaining({ name: 'Partner', chain: 'ethereum' }),
    ]));
    expect(result.contacts.filter(({ name }) => name === 'Workshop')).toHaveLength(1);
    expect(JSON.stringify(result)).not.toContain('solana-workshop-private');
    expect(JSON.stringify(result)).not.toContain('tron-vault-private');
    // A transfer on TON lists the own wallets on TON alone, Savings has none, and every saved address still
    const onTon = await runQuery(session, {
      operation: 'contacts.list', accountSelector: { kind: 'current' },
      purpose: 'send_recipient_resolution', query: null, chains: [], ownWalletChains: ['ton'], pageSize: 100,
    });
    if (onTon.operation !== 'contacts.list') throw new Error('Expected contacts');
    expect(onTon.coverage).toMatchObject({ status: 'complete', rowsOmitted: 0 });
    expect(onTon.contacts.map(({ name, chain }) => `${name}:${chain}`)).toEqual(expect.arrayContaining([
      'Workshop:solana', 'Partner:ethereum', 'Main:ton',
    ]));
    expect(onTon.contacts.some(({ name }) => name === 'Savings')).toBe(false);
    // An address book read without networks for own wallets lists the saved addresses alone
    const savedOnly = await runQuery(session, {
      operation: 'contacts.list', accountSelector: { kind: 'current' },
      purpose: 'send_recipient_resolution', query: null, chains: [], ownWalletChains: [], pageSize: 100,
    });
    if (savedOnly.operation !== 'contacts.list') throw new Error('Expected contacts');
    expect(savedOnly.contacts.map(({ name }) => name)).toEqual(expect.arrayContaining(['Workshop', 'Partner']));
    expect(savedOnly.contacts.some(({ name }) => name === 'Main' || name === 'Savings')).toBe(false);
    const scoped = await runQuery(session, {
      operation: 'contacts.list', accountSelector: { kind: 'current' },
      query: 'Workshop', chains: [], ownWalletChains: [], pageSize: 100,
    });
    expect(scoped).toMatchObject({ contacts: [] });
  });

  it('masks contact names that equal or contain their raw address', async () => {
    const source = host();
    const rawAddress = `0x${'12'.repeat(20)}`;
    source.accounts[0].savedAddresses = [{
      id: 'raw-name', name: rawAddress, chain: 'ethereum', address: rawAddress,
    }, {
      id: 'embedded-name', name: `Treasury ${rawAddress}`, chain: 'ethereum', address: rawAddress,
    }];
    const session = new AgentV2WalletSession();
    session.update(source);
    const contacts = await runQuery(session, {
      operation: 'contacts.list',
      accountSelector: { kind: 'current' },
      query: null,
      chains: ['ethereum'],
      ownWalletChains: ['ethereum'],
      pageSize: 10,
    });
    const activity = transaction('9'.repeat(64), Date.parse(NOW), 1n);
    if (activity.kind !== 'transaction') throw new Error('Expected transaction fixture');
    activity.toAddress = rawAddress;
    const transactions = await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, {
      fetchPastActivities: () => Promise.resolve({ activities: [activity], hasMore: false }),
    });

    expect(contacts.operation).toBe('contacts.list');
    expect(transactions.operation).toBe('transactions.list');
    if (contacts.operation !== 'contacts.list' || transactions.operation !== 'transactions.list') return;
    expect(JSON.stringify({ contacts, transactions })).not.toContain(rawAddress);
    expect(contacts.contacts.map(({ name }) => name)).toEqual([
      expect.stringMatching(/[·…]/u),
      expect.stringMatching(/[·…]/u),
    ]);
    expect(transactions.transactions[0].counterparty).toMatchObject({
      kind: 'contact', display: expect.stringMatching(/[·…]/u),
    });
  });

  it('revalidates wallet authority immediately after a network read', async () => {
    const source = host();
    const session = new AgentV2WalletSession();
    session.update(source);
    await expect(runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, {
      fetchPastActivities: () => {
        session.update({ ...source, accounts: source.accounts.map((account) => (
          account.accountId === 'savings' ? { ...account, label: 'Changed Savings' } : account
        )) });
        return Promise.resolve({ activities: [], hasMore: false });
      },
    })).rejects.toMatchObject({ code: 'wallet_context_changed' });
  });

  it('retries one transport failure and forwards the query signal to activity I/O', async () => {
    const session = sessionWithHost();
    const fetchPastActivities = jest.fn()
      .mockRejectedValueOnce(new TypeError('fetch failed'))
      .mockResolvedValueOnce({ activities: [], hasMore: false });

    await runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, { fetchPastActivities });

    expect(fetchPastActivities).toHaveBeenCalledTimes(2);
    expect(fetchPastActivities).toHaveBeenLastCalledWith(
      'main', 50, undefined, undefined, {
        signal: expect.any(AbortSignal),
        shouldThrowOnError: true,
      },
    );
  });

  it('does not retry or mask decoder and programming failures', async () => {
    const session = sessionWithHost();
    const error = new Error('invalid provider payload');
    const fetchPastActivities = jest.fn().mockRejectedValue(error);

    await expect(runQuery(session, {
      ...transactionsArgs('list'), accountSelector: { kind: 'current' },
    }, { fetchPastActivities })).rejects.toBe(error);
    expect(fetchPastActivities).toHaveBeenCalledTimes(1);
  });
});

async function runQuery(
  session: AgentV2WalletSession,
  args: AgentWalletDataQueryArgs,
  overrides: Partial<WalletQueryMaterializationDependencies> = {},
) {
  const snapshot = session.snapshot();
  const active = snapshot.host!.accounts.find(({ accountId }) => accountId === snapshot.host!.activeAccountId)!;
  const accountScope = args.operation === 'assets.search' || args.accountSelector.kind === 'current'
    ? 'current' as const
    : args.accountSelector.kind === 'explicitAll' ? 'explicitAll' as const : 'selected' as const;
  const inventoryAccounts = snapshot.host!.accounts.slice(0, 100);
  const metadataOnlyInventory = args.operation === 'account.inventory' && !args.includePortfolioTotals;
  const materializedAccounts = metadataOnlyInventory
    ? inventoryAccounts
    : inventoryAccounts.filter(({ state }) => state === 'active');
  const selectedAccounts = args.operation === 'assets.search' ? []
    : args.accountSelector.kind === 'current' ? [active]
      : args.accountSelector.kind === 'explicitAll' ? materializedAccounts
        : materializedAccounts.filter(({ label }) => label === ('label' in args.accountSelector
          ? args.accountSelector.label : undefined));
  const resolvedAccounts = args.operation === 'assets.search' ? []
    : args.accountSelector.kind === 'explicitAll' && metadataOnlyInventory
      ? inventoryAccounts : selectedAccounts;
  const authority = await session.walletAuthorityBinding();
  const authorityBinding = {
    ...authority,
    accountScope,
    activeAccountRef: snapshot.accountRefs.get(active.accountId)!,
  };
  const call = queryCall(session, args, accountScope);
  const dependencies: WalletQueryMaterializationDependencies = {
    session,
    authorityBinding,
    args,
    call,
    completedAt: NOW,
    signal: new AbortController().signal,
    ...(args.operation === 'assets.search' ? {} : {
      scope: {
        accountScope,
        accountIds: selectedAccounts.map(({ accountId }) => accountId),
        accountsRequested: args.accountSelector.kind === 'explicitAll'
          ? args.operation === 'account.inventory' && args.includePortfolioTotals
            ? materializedAccounts.length
            : inventoryAccounts.length
          : 1,
      },
      resolvedScope: {
        kind: args.accountSelector.kind === 'explicitAll' ? 'explicitAll' as const
          : args.accountSelector.kind === 'current' ? 'current' as const : 'named' as const,
        accounts: resolvedAccounts.map((account) => ({
          accountRef: snapshot.accountRefs.get(account.accountId)!,
          accountLabel: account.label!,
        })),
      },
    }),
    ...(args.operation === 'transactions.list' ? { filterDigest: 'f'.repeat(64) } : {}),
    ...overrides,
  };
  return materializeWalletQuery(dependencies);
}

function queryCall(
  session: AgentV2WalletSession,
  args: AgentWalletDataQueryArgs,
  accountScope: 'current' | 'selected' | 'explicitAll',
): AgentToolCall {
  const snapshot = session.snapshot();
  const active = snapshot.host!.accounts.find(({ accountId }) => accountId === snapshot.host!.activeAccountId)!;
  return {
    id: '22222222-2222-4222-8222-222222222222',
    name: 'wallet.data.query',
    arguments: args,
    scopes: ['wallet.data.read'],
    timeoutMs: 15_000,
    maxResultBytes: 98_304,
    walletContextSession: {
      sessionId: snapshot.sessionId,
      revision: snapshot.revision,
      accountScope,
      activeAccountRef: snapshot.accountRefs.get(active.accountId)!,
      activeNetwork: snapshot.host!.activeNetwork,
    },
    intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
    ...(accountScope === 'current' ? {} : {
      scopeIntent: {
        messageId: MESSAGE_ID,
        reason: accountScope === 'explicitAll'
          ? 'explicit_all_wallet_query' as const
          : 'selected_wallet_query' as const,
      },
    }),
  };
}

function assetsArgs(query: string): AgentWalletDataQueryArgs {
  return { operation: 'assets.search', query, chains: [], pageSize: 10 };
}

function positionsArgs(options: {
  riskMode: 'exclude' | 'only' | 'all';
  visibilityMode: 'visible' | 'hidden' | 'all';
  includeZero: boolean;
}): Extract<AgentWalletDataQueryArgs, { operation: 'positions.list' }> {
  return {
    operation: 'positions.list',
    accountSelector: { kind: 'current' },
    chains: [],
    assetSelectors: [],
    positionKinds: ['fungible', 'nft', 'staking', 'vesting', 'vault'],
    ...options,
    sort: 'value_desc',
    pageSize: 100,
  };
}

function transactionsArgs(
  _mode: 'list',
): Extract<AgentWalletDataQueryArgs, { operation: 'transactions.list' }> {
  return {
    operation: 'transactions.list',
    accountSelector: { kind: 'explicitAll' },
    chains: [],
    filters: { schemaVersion: 1, catalogDigest: contractManifest.walletFilterCatalogSha256, clauses: [] },
    riskMode: 'exclude',
    pageSize: 50,
  };
}

function transaction(hash: string, timestamp: number, amount: bigint, incoming = false): ApiActivity {
  return {
    kind: 'transaction',
    id: `${hash}:0`,
    externalMsgHashNorm: hash,
    timestamp,
    amount,
    fee: 1_000n,
    fromAddress: incoming ? 'EQ-external-counterparty-address' : 'EQ-main-private-address',
    toAddress: incoming ? 'EQ-main-private-address' : 'EQ-external-counterparty-address',
    normalizedAddress: 'EQ-main-private-address',
    slug: incoming ? 'usdton' : 'toncoin',
    isIncoming: incoming,
    status: 'completed',
  };
}

function sessionWithHost() {
  const session = new AgentV2WalletSession();
  session.update(host());
  return session;
}

function buildMultiChainHost(chains: string[]): AgentV2HostContextSnapshot {
  const source = host();
  source.activeNetwork = chains[0];
  source.accounts[0].chains = [...chains];
  source.accounts[0].addresses = Object.fromEntries(chains.map((chain) => [chain, `address-main-${chain}`]));
  source.accounts[0].portfolioWalletKeys = chains.map((chain) => `${chain}:${source.accounts[0].addresses[chain]}`);
  source.accounts[0].holdings = [];
  source.accounts[1].portfolioWalletKeys = ['ton:EQ-savings-private-address'];
  return source;
}

function host(): AgentV2HostContextSnapshot {
  const fresh = {
    accounts: { state: 'fresh' as const },
    fungible: { state: 'fresh' as const },
    staking: { state: 'fresh' as const },
    vesting: { state: 'fresh' as const },
    vault: { state: 'fresh' as const },
    transactions: { state: 'fresh' as const },
    contacts: { state: 'fresh' as const },
    value_series: { state: 'stale' as const },
  };
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: 'main',
    activeNetwork: 'ton',
    assetCatalog: [
      { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9 },
      { slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6 },
      {
        slug: 'usdt-ethereum', chain: 'ethereum', symbol: 'USDT', name: 'Tether USD', decimals: 6,
        tokenAddress: '0x2222222222222222222222222222222222222222',
      },
      { slug: 'mystery', chain: 'ton', symbol: 'MYSTERY', decimals: 9 },
      { slug: 'spam', chain: 'ton', symbol: 'SPAM', decimals: 9 },
      { slug: 'zero', chain: 'ton', symbol: 'ZERO', decimals: 9 },
    ],
    accounts: [{
      accountId: 'main',
      label: 'Main',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-main-private-address' },
      portfolioWalletKeys: ['ton:EQ-main-private-address'],
      holdings: [{
        asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '5', availableBalance: '4.5', fiatValue: '25.5', valuationStatus: 'valued',
      }, {
        asset: { slug: 'mystery', chain: 'ton', symbol: 'MYSTERY', decimals: 9 },
        balance: '2', valuationStatus: 'unpriced',
      }, {
        asset: { slug: 'spam', chain: 'ton', symbol: 'SPAM', decimals: 9 },
        balance: '1000000', fiatValue: '999999', valuationStatus: 'valued', riskVerdict: 'spam',
      }, {
        asset: { slug: 'zero', chain: 'ton', symbol: 'ZERO', decimals: 9 },
        balance: '0', valuationStatus: 'unpriced',
      }, {
        asset: { slug: 'private-only', chain: 'ton', symbol: 'PRIVATE', decimals: 9 },
        balance: '1', valuationStatus: 'unpriced', visibility: 'hidden',
      }],
      savedAddresses: [],
      nftLoadedChains: [...getSupportedChains()],
      domainStates: fresh,
    }, {
      accountId: 'savings',
      label: 'Savings',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-savings-private-address' },
      holdings: [{
        asset: { slug: 'usdton', chain: 'ton', symbol: 'USDT', decimals: 6 },
        balance: '50', fiatValue: '50', valuationStatus: 'valued',
      }],
      savedAddresses: [{
        id: 'treasury', name: 'Treasury', chain: 'ton', address: 'EQ-treasury-private-address',
      }],
      nftLoadedChains: [...getSupportedChains()],
      domainStates: fresh,
    }, {
      accountId: 'old',
      label: 'Old',
      state: 'stale',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-old-private-address' },
      holdings: [{
        asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '777', fiatValue: '777', valuationStatus: 'valued',
      }],
      savedAddresses: [],
      nftLoadedChains: [...getSupportedChains()],
      domainStates: fresh,
    }, {
      accountId: 'deleted',
      label: 'Deleted',
      state: 'deleted',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-deleted-private-address' },
      holdings: [],
      savedAddresses: [],
      nftLoadedChains: [...getSupportedChains()],
      domainStates: fresh,
    }],
    savedAddresses: [],
  };
}
