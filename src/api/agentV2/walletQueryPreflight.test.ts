import type {
  AgentToolCall,
  AgentToolResultRequestV2,
  AgentWalletDataQueryToolCall,
  AgentWalletDataTransactionRowV3,
  AgentWalletFilterClauseV1,
  AgentWalletTransactionsDetailArgs,
  AgentWalletTransactionsListArgs,
} from './protocol/types';

import { getWalletQueryPreflightFailure } from './walletQueryPreflight';

const HASH = 'a'.repeat(64);
const NOW = '2026-08-10T10:00:00.000Z';

describe('wallet query preflight', () => {
  it('accepts unique newest-first transaction rows inside the requested range', () => {
    expect(preflight([
      transaction('tx_one', '2026-08-10T09:00:00.000Z'),
      transaction('tx_two', '2026-08-10T08:00:00.000Z'),
    ], [timestampClause()])).toBeUndefined();
  });

  it.each([
    {
      reason: 'duplicate_transaction_row_id',
      rows: [transaction('tx_one', '2026-08-10T09:00:00.000Z'), transaction('tx_one', '2026-08-10T08:00:00.000Z')],
    },
    {
      reason: 'invalid_transaction_quantity',
      rows: [transaction('tx_one', '2026-08-10T09:00:00.000Z', '0.000')],
    },
    {
      reason: 'non_monotonic_transaction_order',
      rows: [transaction('tx_one', '2026-08-10T08:00:00.000Z'), transaction('tx_two', '2026-08-10T09:00:00.000Z')],
    },
    {
      reason: 'transaction_timestamp_out_of_bounds',
      rows: [transaction('tx_one', '2026-08-09T23:59:59.000Z')],
    },
  ])('rejects $reason', ({ reason, rows }) => {
    expect(preflight(rows, [timestampClause()])).toMatchObject({ reason });
  });

  it('rejects a transaction detail result that reproduces the requested full hash', () => {
    const request = successRequest({
      ...resolvedBase(),
      operation: 'transactions.detail',
      transaction: { ...transaction('tx_detail', NOW), safeDescription: `Transaction ${HASH}` },
    });

    expect(getWalletQueryPreflightFailure(detailCall(), request)).toEqual({
      reason: 'transaction_detail_hash_leaked',
    });
    expect(getWalletQueryPreflightFailure(detailCall(), successRequest({
      ...resolvedBase(), operation: 'transactions.detail', transaction: transaction('tx_detail', NOW),
    }))).toBeUndefined();
  });

  it('detects an unprefixed lowercase leak for a prefixed mixed-case EVM request', () => {
    const requestedHash = `0x${HASH.toUpperCase()}`;
    const request = successRequest({
      ...resolvedBase(),
      operation: 'transactions.detail',
      transaction: { ...transaction('tx_detail', NOW), safeDescription: `Transaction ${HASH}` },
    });

    expect(getWalletQueryPreflightFailure(detailCall(requestedHash), request)).toEqual({
      reason: 'transaction_detail_hash_leaked',
    });
  });

  it('preserves case when checking non-hex transaction hashes', () => {
    const hash = `A${'b'.repeat(42)}`;
    const lowerCaseOnly = successRequest({
      ...resolvedBase(),
      operation: 'transactions.detail',
      transaction: { ...transaction('tx_detail', NOW), safeDescription: hash.toLocaleLowerCase('en-US') },
    });
    const exact = successRequest({
      ...resolvedBase(),
      operation: 'transactions.detail',
      transaction: { ...transaction('tx_detail', NOW), safeDescription: hash },
    });

    expect(getWalletQueryPreflightFailure(detailCall(hash), lowerCaseOnly)).toBeUndefined();
    expect(getWalletQueryPreflightFailure(detailCall(hash), exact)).toEqual({
      reason: 'transaction_detail_hash_leaked',
    });
  });

  it('ignores non-query and non-success requests', () => {
    const request = successRequest({
      ...resolvedBase(), operation: 'transactions.list', policySummary: policySummary(),
      appliedFilterDigest: 'a'.repeat(64), transactions: [],
    });
    expect(getWalletQueryPreflightFailure({
      ...listCall([]), name: 'wallet.directory.query',
    } as unknown as AgentToolCall, request)).toBeUndefined();
    expect(getWalletQueryPreflightFailure(listCall([]), {
      ...request, status: 'rejected', error: { code: 'validation_failed', retryable: false },
    } as AgentToolResultRequestV2)).toBeUndefined();
  });
});

function preflight(rows: AgentWalletDataTransactionRowV3[], clauses: AgentWalletFilterClauseV1[]) {
  return getWalletQueryPreflightFailure(listCall(clauses), successRequest({
    ...resolvedBase(), operation: 'transactions.list', policySummary: policySummary(),
    appliedFilterDigest: 'a'.repeat(64), transactions: rows,
  }));
}

function listCall(clauses: AgentWalletFilterClauseV1[]): AgentToolCall {
  const arguments_: AgentWalletTransactionsListArgs = {
    operation: 'transactions.list',
    accountSelector: { kind: 'current' },
    chains: [],
    filters: { schemaVersion: 1, catalogDigest: 'a'.repeat(64), clauses },
    riskMode: 'exclude',
    pageSize: 50,
  };
  return {
    ...callBase(),
    arguments: arguments_,
  };
}

function detailCall(hash = HASH): AgentToolCall {
  const arguments_: AgentWalletTransactionsDetailArgs = {
    operation: 'transactions.detail',
    accountSelector: { kind: 'current' },
    hash,
  };
  return {
    ...callBase(),
    arguments: arguments_,
  };
}

function callBase(): Omit<AgentWalletDataQueryToolCall, 'arguments'> {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    name: 'wallet.data.query',
    scopes: ['wallet.data.read'],
    timeoutMs: 5_000,
    walletContextSession: {
      sessionId: '22222222-2222-4222-8222-222222222222',
      revision: 1,
      accountScope: 'current',
      activeAccountRef: 'account_ref',
      activeNetwork: 'ton',
    },
  };
}

function successRequest(
  result: Extract<AgentToolResultRequestV2, { status: 'success'; toolName: 'wallet.data.query' }>['result']['result'],
): AgentToolResultRequestV2 {
  return {
    protocolVersion: 3,
    runId: '33333333-3333-4333-8333-333333333333',
    threadId: '44444444-4444-4444-8444-444444444444',
    toolCallId: '11111111-1111-4111-8111-111111111111',
    clientToolResultId: '55555555-5555-4555-8555-555555555555',
    completedAt: NOW,
    walletContextSession: callBase().walletContextSession,
    toolName: 'wallet.data.query',
    status: 'success',
    result: {
      schemaVersion: 1,
      freshness: { asOf: NOW, source: 'store', isStale: false },
      redaction: { level: 'scoped', maxResultBytes: 98_304 },
      result,
    },
  };
}

function resolvedBase() {
  return {
    schemaVersion: 5 as const,
    status: 'resolved' as const,
    resolvedScope: { kind: 'current' as const, accounts: [{ accountRef: 'account_ref', accountLabel: 'Main' }] },
    generatedAt: NOW,
    freshness: { asOf: NOW, source: 'network' as const, isStale: false },
    coverage: {
      status: 'complete' as const,
      accountsRequested: 1,
      accountsIncluded: 1,
      rowsOmitted: 0,
      limitations: [],
      sourceOutcomes: [{ domain: 'transactions' as const, status: 'complete' as const, attempts: 1 }],
    },
  };
}

function policySummary() {
  return {
    riskMode: 'exclude' as const,
    spamMatches: { count: 0, accuracy: 'exact' as const },
    hiddenMatches: { count: 0, accuracy: 'exact' as const },
  };
}

function transaction(rowId: string, timestamp: string, quantity = '1'): AgentWalletDataTransactionRowV3 {
  return {
    rowId,
    kind: 'transaction',
    accountRef: 'account_ref',
    accountLabel: 'Main',
    chain: 'ton',
    displayHash: 'aaaa…aaaa',
    transactionType: 'transfer',
    direction: 'incoming',
    status: 'completed',
    timestamp,
    asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
    quantity,
    decimals: 9,
    safeDescription: 'Received TON',
  };
}

function timestampClause(): AgentWalletFilterClauseV1 {
  return {
    field: 'transaction.timestamp',
    operator: 'timestamp_range',
    range: {
      rangeKind: 'absolute',
      fromInclusive: '2026-08-10T00:00:00.000Z',
      toExclusive: '2026-08-11T00:00:00.000Z',
      timeZone: 'UTC',
      resolvedAt: NOW,
    },
  };
}
