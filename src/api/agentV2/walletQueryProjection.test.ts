import type {
  AgentToolCall,
  AgentToolResultRequestV2,
  AgentWalletDataPositionRowV3,
  AgentWalletDataQueryArgs,
} from './protocol/types';
import type { AgentV2HostContextSnapshot } from './types';

import { getSupportedChains } from '../../util/chain';
import contractManifest from './generated/manifest.json';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { WalletQueryProjectionError } from './walletQueryErrors';
import {
  buildWalletQueryProjection,
  fitWalletQueryV5Request,
} from './walletQueryProjection';
import { AgentV2WalletSession } from './walletSession';

const NOW = '2026-08-10T12:00:00.000Z';
const MESSAGE_ID = '11111111-1111-4111-8111-111111111111';

describe('wallet query projection', () => {
  it('canonicalizes transaction filters and produces an order-independent applied digest', async () => {
    const session = sessionWithHost();
    const timestamp = {
      field: 'transaction.timestamp' as const,
      operator: 'timestamp_range' as const,
      range: {
        rangeKind: 'absolute' as const,
        fromInclusive: '2026-08-01T00:00:00.000Z',
        toExclusive: '2026-08-11T00:00:00.000Z',
        timeZone: 'UTC',
        resolvedAt: NOW,
      },
    };
    const status = {
      field: 'transaction.status' as const,
      operator: 'in' as const,
      values: ['failed' as const, 'completed' as const],
    };
    const first = await project(session, transactionsArgs([timestamp, status]));
    const second = await project(session, transactionsArgs([status, timestamp]));
    const empty = await project(session, transactionsArgs([]));

    expect(first).toMatchObject({
      operation: 'transactions.list', status: 'resolved', appliedFilterDigest: expect.any(String),
    });
    if (
      first.status !== 'resolved'
      || first.operation !== 'transactions.list'
      || second.status !== 'resolved'
      || second.operation !== 'transactions.list'
    ) throw new Error('Expected resolved transaction lists');
    expect(first.appliedFilterDigest).toBe(second.appliedFilterDigest);
    expect(empty).toMatchObject({
      appliedFilterDigest: '72b7ec92664b92147cf0ecfa2958b5908518ffd700ca534c9e9561a01e4c32fa',
    });
  });

  it('rejects an unknown or internally duplicated filter catalog request', async () => {
    const session = sessionWithHost();
    const invalidDigest = transactionsArgs([]);
    invalidDigest.filters.catalogDigest = '0'.repeat(64);
    await expect(project(session, invalidDigest)).rejects.toBeInstanceOf(WalletQueryProjectionError);

    const duplicate = transactionsArgs([{
      field: 'transaction.status', operator: 'in', values: ['completed'],
    }, {
      field: 'transaction.status', operator: 'in', values: ['failed'],
    }]);
    await expect(project(session, duplicate)).rejects.toBeInstanceOf(WalletQueryProjectionError);
  });

  it.each([
    ['current', { kind: 'current' }, 'current', ['Main']],
    ['unique named', { kind: 'named', label: 'Savings' }, 'named', ['Savings']],
    ['valid ordinal', { kind: 'ordinal', index: 2 }, 'ordinal', ['Savings']],
    ['explicit all', { kind: 'explicitAll' }, 'explicitAll', ['Main', 'Savings']],
  ] as const)('resolves the %s wallet selector without retained scope state', async (
    _name,
    accountSelector,
    resolvedKind,
    accountLabels,
  ) => {
    const session = sessionWithHost();
    const outcome = await project(session, {
      operation: 'account.inventory',
      accountSelector,
      chains: [],
    });

    expect(outcome).toMatchObject({
      operation: 'account.inventory',
      status: 'resolved',
      resolvedScope: {
        kind: resolvedKind,
        accounts: accountLabels.map((accountLabel) => ({ accountLabel })),
      },
    });
  });

  it('returns reason-only clarification for an ambiguous wallet name', async () => {
    const source = host();
    source.accounts[1].label = 'Duplicate';
    source.accounts.push({ ...source.accounts[1], accountId: 'duplicate-two' });
    const session = new AgentV2WalletSession();
    session.update(source);
    const outcome = await project(session, {
      operation: 'positions.list',
      accountSelector: { kind: 'named', label: 'Duplicate' },
      chains: [],
      assetSelectors: [],
      positionKinds: ['fungible'],
      riskMode: 'exclude',
      visibilityMode: 'visible',
      includeZero: false,
      sort: 'wallet_order',
      pageSize: 100,
    });

    expect(outcome).toMatchObject({
      operation: 'positions.list',
      status: 'scope_resolution_required',
      reason: 'ambiguous',
    });
  });

  it.each([
    ['missing name', { kind: 'named', label: 'Missing' }],
    ['missing ordinal', { kind: 'ordinal', index: 3 }],
  ] as const)('returns reason-only clarification for a %s', async (_name, accountSelector) => {
    const session = sessionWithHost();
    const outcome = await project(session, {
      operation: 'account.inventory',
      accountSelector,
      chains: [],
    });

    expect(outcome).toEqual({
      operation: 'account.inventory',
      status: 'scope_resolution_required',
      reason: 'not_found',
    });
  });

  it('scrubs account identifiers from resolved scopes and clarification output', async () => {
    const source = host();
    const activeAddress = `0x${'12'.repeat(20)}`;
    const selectedAddress = `0x${'34'.repeat(20)}`;
    source.accounts[0].label = activeAddress;
    source.accounts[0].addresses.ethereum = activeAddress;
    source.accounts[1].label = `Vault ${selectedAddress}`;
    source.accounts[1].addresses.ethereum = selectedAddress;
    source.accounts.push({
      ...source.accounts[1],
      accountId: 'savings-two',
      addresses: { ton: 'EQ-savings-two', ethereum: `0x${'56'.repeat(20)}` },
    });
    const session = new AgentV2WalletSession();
    session.update(source);
    const resolved = await project(session, {
      operation: 'account.inventory',
      accountSelector: { kind: 'current' },
      chains: [],
    });
    const ambiguous = await project(session, {
      operation: 'positions.list',
      accountSelector: { kind: 'named', label: `Vault ${selectedAddress}` },
      chains: [],
      assetSelectors: [],
      positionKinds: ['fungible'],
      riskMode: 'exclude',
      visibilityMode: 'visible',
      includeZero: false,
      sort: 'wallet_order',
      pageSize: 100,
    });

    expect(resolved).toMatchObject({
      status: 'resolved',
      resolvedScope: { accounts: [{ accountLabel: 'Wallet' }] },
      accounts: [{ accountLabel: 'Wallet' }],
    });
    expect(ambiguous).toMatchObject({
      status: 'scope_resolution_required',
    });
    expect(JSON.stringify(ambiguous)).not.toContain(activeAddress);
    expect(JSON.stringify(ambiguous)).not.toContain(selectedAddress);
  });

  it('fits a maximal portfolio envelope to the exact 98,304-byte transport cap', () => {
    const request = oversizedPortfolioRequest();
    const before = byteLength(request);

    fitWalletQueryV5Request(request, 98_304);

    expect(before).toBeGreaterThan(98_304);
    expect(byteLength(request)).toBeLessThanOrEqual(98_304);
    expect(request.status).toBe('success');
    if (request.status !== 'success' || request.toolName !== 'wallet.data.query') return;
    const result = request.result.result;
    expect(result).toMatchObject({
      operation: 'portfolio.aggregate',
      coverage: { status: 'partial', rowsOmitted: expect.any(Number) },
    });
    if (result.status !== 'resolved' || result.operation !== 'portfolio.aggregate') return;
    expect(result.coverage.limitations).toContain('row_limit');
  });
});

async function project(
  session: AgentV2WalletSession,
  args: AgentWalletDataQueryArgs,
) {
  const snapshot = session.snapshot();
  const active = snapshot.host!.accounts.find(({ accountId }) => accountId === snapshot.host!.activeAccountId)!;
  const accountScope = args.operation === 'assets.search' || args.accountSelector.kind === 'current'
    ? 'current' as const
    : args.accountSelector.kind === 'explicitAll' ? 'explicitAll' as const : 'selected' as const;
  const authority = await session.walletAuthorityBinding();
  return buildWalletQueryProjection({
    session,
    args,
    call: queryCall(session, args, accountScope),
    completedAt: NOW,
    signal: new AbortController().signal,
    authorityBinding: {
      ...authority,
      accountScope,
      activeAccountRef: snapshot.accountRefs.get(active.accountId)!,
    },
    fetchPastActivities: () => Promise.resolve({ activities: [], hasMore: false }),
  });
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

function transactionsArgs(
  clauses: Extract<AgentWalletDataQueryArgs, { operation: 'transactions.list' }>['filters']['clauses'],
): Extract<AgentWalletDataQueryArgs, { operation: 'transactions.list' }> {
  return {
    operation: 'transactions.list',
    accountSelector: { kind: 'current' },
    chains: [],
    filters: { schemaVersion: 1, catalogDigest: contractManifest.walletFilterCatalogSha256, clauses },
    riskMode: 'exclude',
    pageSize: 50,
  };
}

function oversizedPortfolioRequest(): AgentToolResultRequestV2 {
  const positions = Array.from({ length: 100 }, (_, index): AgentWalletDataPositionRowV3 => ({
    rowId: `position_${index}`,
    kind: 'position',
    accountRef: 'account_ref',
    accountLabel: `Account ${index} ${'A'.repeat(60)}`,
    positionKind: 'fungible',
    chain: 'ton',
    label: `Token ${index} ${'L'.repeat(120)}`,
    asset: {
      slug: `token-${index}`,
      chain: 'ton',
      symbol: `T${index}`,
      name: `Token ${index} ${'N'.repeat(120)}`,
      tokenAddress: `EQ${index.toString().padStart(60, '0')}`,
      decimals: 9,
    },
    quantity: '123456789.123456789',
    decimals: 9,
    availableQuantity: '123456789.123456789',
    valuationStatus: 'valued',
    fiatValue: '999999999.999999999',
    baseCurrency: 'USD',
  }));
  const coverage = {
    status: 'complete' as const,
    accountsRequested: 1,
    accountsIncluded: 1,
    rowsOmitted: 0,
    limitations: [],
    sourceOutcomes: [{ domain: 'portfolio' as const, status: 'complete' as const, attempts: 1 }],
  };
  return {
    protocolVersion: 3,
    runId: '33333333-3333-4333-8333-333333333333',
    threadId: '44444444-4444-4444-8444-444444444444',
    toolCallId: '22222222-2222-4222-8222-222222222222',
    clientToolResultId: '55555555-5555-4555-8555-555555555555',
    completedAt: NOW,
    walletContextSession: {
      sessionId: '66666666-6666-4666-8666-666666666666', revision: 1, accountScope: 'current',
      activeAccountRef: 'account_ref', activeNetwork: 'ton',
    },
    toolName: 'wallet.data.query',
    status: 'success',
    result: {
      schemaVersion: 1,
      freshness: { asOf: NOW, source: 'store', isStale: false },
      redaction: { level: 'scoped', maxResultBytes: 98_304 },
      result: {
        operation: 'portfolio.aggregate',
        status: 'resolved',
        resolvedScope: { kind: 'current', accounts: [{ accountRef: 'account_ref', accountLabel: 'Main' }] },
        generatedAt: NOW,
        freshness: { asOf: NOW, source: 'cache', isStale: false },
        coverage,
        policySummary: {
          riskMode: 'exclude', visibilityMode: 'visible',
          spamMatches: { count: 0, accuracy: 'exact' }, hiddenMatches: { count: 0, accuracy: 'exact' },
        },
        total: { value: '99999999999', baseCurrency: 'USD', unpricedCount: 0 },
        allocations: positions.map(({ asset }, index) => ({
          asset, value: '999999999.999999999', baseCurrency: 'USD', percent: `${index}.123456789`,
        })),
        positions,
        aggregates: positions.map(({ rowId }, index) => ({
          rowId: `aggregate_${rowId}`,
          kind: 'aggregate',
          groupKind: 'asset',
          label: `${'G'.repeat(150)}${index}`,
          value: '999999999.999999999',
          baseCurrency: 'USD',
          unpricedCount: 0,
        })),
        series: Array.from({ length: 5 }, (_, seriesIndex) => ({
          seriesId: `series_${seriesIndex}`,
          metric: 'portfolio_value' as const,
          label: 'S'.repeat(160),
          baseCurrency: 'USD',
          points: Array.from({ length: 64 }, (_, pointIndex) => ({
            timestamp: new Date(Date.parse(NOW) - pointIndex * 60_000).toISOString(),
            value: '999999999.999999999',
          })),
        })),
      },
    },
  };
}

function byteLength(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function sessionWithHost() {
  const session = new AgentV2WalletSession();
  session.update(host());
  return session;
}

function host(): AgentV2HostContextSnapshot {
  const domainStates = {
    accounts: { state: 'fresh' as const },
    fungible: { state: 'fresh' as const },
    staking: { state: 'fresh' as const },
    vesting: { state: 'fresh' as const },
    vault: { state: 'fresh' as const },
    transactions: { state: 'fresh' as const },
    contacts: { state: 'fresh' as const },
    value_series: { state: 'unavailable' as const },
  };
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: 'main',
    activeNetwork: 'ton',
    assetCatalog: [{ slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 }],
    accounts: [{
      accountId: 'main',
      label: 'Main',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-main' },
      holdings: [],
      savedAddresses: [],
      nftLoadedChains: [...getSupportedChains()],
      domainStates,
    }, {
      accountId: 'savings',
      label: 'Savings',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-savings' },
      holdings: [],
      savedAddresses: [],
      nftLoadedChains: [...getSupportedChains()],
      domainStates,
    }],
    savedAddresses: [],
  };
}
