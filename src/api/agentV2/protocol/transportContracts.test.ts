import type { AgentToolCall, AgentWalletDataQueryArgs, AgentWalletTransactionsListArgs } from './types';

import { getSupportedChains } from '../../../util/chain';
import compatibilityFixture from '../../../../tests/fixtures/agentV2/client-wire-compatibility.v1.json';
import navigationFixture from '../../../../tests/fixtures/agentV2/navigation-action-projection.v1.json';
import contractManifest from '../generated/manifest.json';
import { decodeAgentV2WalletSnapshotAck } from './decoders/coreRun';
import {
  AgentV2CompatibilityError,
  AgentV2ContractError,
  decodeAgentV2FeatureCapabilities,
  decodeAgentV2Hints,
  decodeAgentV2Messages,
  decodeAgentV2PersistedAction,
  decodeAgentV2StreamEvent,
  decodeAgentV2StreamFrame,
  decodeAgentV2ToolArguments,
} from './transportContracts';
import { object as readWireObject } from './wireReader';

const RUN_ID = '11111111-1111-4111-8111-111111111111';
const MESSAGE_ID = '22222222-2222-4222-8222-222222222222';
const THREAD_ID = '33333333-3333-4333-8333-333333333333';
const TOOL_CALL_ID = '44444444-4444-4444-8444-444444444444';
const WALLET_SESSION_ID = '55555555-5555-4555-8555-555555555555';
const WALLET_CHAIN_LISTS = [
  { name: 'runtime catalog', chains: [...getSupportedChains()] },
  { name: 'future catalog', chains: Array.from({ length: 65 }, (_, index) => `future-chain-${index}`) },
];
const INVALID_WALLET_CHAIN_LISTS = [
  { name: 'duplicate identifiers', chains: ['ton', 'ton'] },
  { name: 'empty identifiers', chains: [''] },
  { name: 'oversized identifiers', chains: ['x'.repeat(33)] },
];
const WALLET_TRANSACTIONS_QUERY_ARGUMENTS: AgentWalletTransactionsListArgs = {
  operation: 'transactions.list', accountSelector: { kind: 'current' }, chains: [],
  filters: { schemaVersion: 1, catalogDigest: contractManifest.walletFilterCatalogSha256, clauses: [] },
  riskMode: 'all', pageSize: 50,
};
const WALLET_QUERY_CHAIN_ARGUMENTS: Exclude<AgentWalletDataQueryArgs, { operation: 'transactions.detail' }>[] = [
  { operation: 'account.inventory', accountSelector: { kind: 'current' }, chains: [] },
  { operation: 'assets.search', query: 'TON', chains: [], pageSize: 10 },
  {
    operation: 'positions.list', accountSelector: { kind: 'current' }, chains: [], assetSelectors: [],
    positionKinds: ['fungible'], riskMode: 'all', visibilityMode: 'all', includeZero: true,
    sort: 'wallet_order', pageSize: 100,
  },
  {
    operation: 'portfolio.aggregate', accountSelector: { kind: 'current' }, chains: [], range: '1m',
    groupBy: ['network'], riskMode: 'all', visibilityMode: 'all',
  },
  WALLET_TRANSACTIONS_QUERY_ARGUMENTS,
  {
    operation: 'contacts.list', accountSelector: { kind: 'current' }, query: 'Mom', chains: [], ownWalletChains: [],
    pageSize: 100,
  },
  {
    operation: 'value.series', accountSelector: { kind: 'current' }, chains: [], metric: 'portfolio_value',
    assetSelectors: [], range: '1m', maxPoints: 2,
  },
];

interface CompatibilityFixtureGroup {
  schema: string;
  values: unknown[];
}

describe('Agent V2 client wire compatibility contract', () => {
  it('rejects retired frontend market quote calls', () => {
    const toolCall = {
      id: TOOL_CALL_ID, name: 'market.asset.quote', version: 1,
      maxResultBytes: 16_384, scopes: ['market.data.read'], timeoutMs: 15_000,
      arguments: {
        schemaVersion: 1, quoteCurrency: 'USD',
        selector: { kind: 'asset', asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON' } },
      },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID, revision: 1, activeAccountRef: 'wallet-1',
        accountScope: 'current', activeNetwork: 'ton',
      },
    };
    expect(() => decodeAgentV2StreamEvent(event({ type: 'tool_call', sequence: 3, toolCall })))
      .toThrow(AgentV2ContractError);
  });

  it('keeps history text and cursor when optional metadata is malformed', () => {
    const message = { ...persistedMessage(MESSAGE_ID, 'assistant', { kind: 'markdown', text: 'Saved answer' }),
      chains: [123] };
    const page = decodeAgentV2Messages({ protocolVersion: 3, thread: threadSummary(),
      messages: [message], nextCursor: 'next-page' });
    expect(page.messages).toHaveLength(1);
    expect(page.messages[0]).toMatchObject({ id: MESSAGE_ID, content: { kind: 'markdown', text: 'Saved answer' } });
    expect(page.nextCursor).toBe('next-page');
  });

  it('drops a malformed answer link without failing its message', () => {
    const link = { textOffset: 0, textLength: 4, url: 'https://help.mywallet.io/' };
    const malformed = [
      { messageId: 'not-a-uuid', link },
      { messageId: MESSAGE_ID, link: { ...link, url: 'http://a.io' } },
    ];
    for (const value of malformed) {
      const frame = decodeAgentV2StreamFrame(event({ type: 'text_link', sequence: 3, ...value }));
      expect(frame).toMatchObject({ disposition: 'ignore', wireType: 'text_link' });
      expect(frame).not.toHaveProperty('incompleteMessageId');
    }
  });

  it('keeps a stored answer whole while dropping links it cannot place', () => {
    const link = { textOffset: 4, textLength: 4, url: 'https://help.mywallet.io/' };
    const page = decodeAgentV2Messages({ protocolVersion: 3, thread: threadSummary(), messages: [
      persistedMessage(MESSAGE_ID, 'assistant', { kind: 'markdown', text: 'See Help', links: [
        link, { ...link, textOffset: 6 }, { ...link, textOffset: 0, url: 'http://help.mywallet.io/' },
      ] }),
      persistedMessage(RUN_ID, 'assistant', { kind: 'markdown', text: 'Saved', links: 'broken' }),
    ] });

    expect(page.messages.map(({ content }) => content)).toEqual([
      { kind: 'markdown', text: 'See Help', links: [link] },
      { kind: 'markdown', text: 'Saved' },
    ]);
    expect(page.messages.map(({ error }) => error)).toEqual([undefined, undefined]);
    expect(page.incompatibleMessages).toBeUndefined();
  });

  it('decodes every fixture group with its live transport reader', () => {
    expect(compatibilityFixture.schemaVersion).toBe(1);
    compatibilityFixture.fixtures.forEach(decodeCompatibilityFixtureGroup);
  });

  it.each([
    { query: 'Studio' },
    { chains: ['ton'] },
    { accountSelector: { kind: 'explicitAll' } },
    { purpose: 'untrusted-purpose' },
  ])('rejects filtered or unbound Send recipient context: %j', (change) => {
    const groups: CompatibilityFixtureGroup[] = compatibilityFixture.fixtures;
    const value = groups.flatMap(({ values }) => values).find((value) => {
      const candidate = readWireObject(value, '$');
      return candidate.type === 'tool_call'
        && readWireObject(readWireObject(candidate.toolCall, '$.toolCall').arguments, '$.arguments').purpose
        === 'send_recipient_resolution';
    });
    const candidate = readWireObject(value, '$');
    const call = readWireObject(candidate.toolCall, '$.toolCall');
    const decoded = decodeAgentV2StreamEvent({ ...candidate, toolCall: {
      ...call, arguments: { ...readWireObject(call.arguments, '$.arguments'), ...change },
    } });
    if (decoded.type !== 'tool_call') throw new Error('Expected recipient tool call');
    expect(() => decodeCompatibilityFixtureGroup({
      schema: 'AgentStreamEventV2', values: [decoded],
    })).toThrow(AgentV2ContractError);
  });

  it('rejects a fixture tool call with an incompatible wallet filter catalog', () => {
    const toolCall = decodeWalletQueryArguments(WALLET_TRANSACTIONS_QUERY_ARGUMENTS);
    const value = event({ type: 'tool_call', sequence: 3, toolCall: {
      ...toolCall,
      arguments: {
        ...WALLET_TRANSACTIONS_QUERY_ARGUMENTS,
        filters: { ...WALLET_TRANSACTIONS_QUERY_ARGUMENTS.filters, catalogDigest: 'a'.repeat(64) },
      },
    } });
    expect(decodeAgentV2StreamEvent(value)).toMatchObject({ type: 'tool_call' });
    expect(() => decodeCompatibilityFixtureGroup({
      schema: 'AgentStreamEventV2', values: [value],
    })).toThrow(AgentV2ContractError);
  });

  it('rejects unsupported fixture schemas', () => {
    expect(() => decodeCompatibilityFixtureGroup({
      schema: 'AgentUnknownV2',
      values: [],
    })).toThrow('Unsupported Agent V2 compatibility fixture: AgentUnknownV2');
  });
});

describe.each(WALLET_CHAIN_LISTS)('Agent V2 wallet query chain lists: $name', ({ chains }) => {
  it.each(WALLET_QUERY_CHAIN_ARGUMENTS)('preserves every chain in $operation', (args) => {
    const decoded = decodeWalletQueryArguments({ ...args, chains: [...chains] });

    expect(decoded.arguments).toEqual({ ...args, chains });
  });

  it('preserves every transaction chain filter value', () => {
    const decoded = decodeWalletQueryArguments(createWalletChainFilterArguments([...chains]));

    expect(decoded.arguments).toEqual(createWalletChainFilterArguments(chains));
  });
});

describe.each(INVALID_WALLET_CHAIN_LISTS)('Agent V2 wallet query invalid chain lists: $name', ({ chains }) => {
  it.each(WALLET_QUERY_CHAIN_ARGUMENTS)('rejects invalid chain identifiers in $operation', (args) => {
    expect(() => decodeWalletQueryArguments({ ...args, chains })).toThrow(AgentV2ContractError);
  });

  it('rejects invalid transaction chain filter values', () => {
    expect(() => decodeWalletQueryArguments(createWalletChainFilterArguments(chains))).toThrow(AgentV2ContractError);
  });
});

describe('Agent V2 wallet query bounds of a host that lists every network', () => {
  it('reads a 300-row contact page and a 600 KiB result budget, and nothing larger', () => {
    const contacts = (pageSize: number): AgentWalletDataQueryArgs => ({
      operation: 'contacts.list', accountSelector: { kind: 'current' }, query: 'Mom', chains: [], ownWalletChains: [],
      pageSize,
    });
    expect(decodeWalletQueryArguments(contacts(300), 614_400).arguments).toMatchObject({ pageSize: 300 });
    expect(() => decodeWalletQueryArguments(contacts(301))).toThrow(AgentV2ContractError);
    expect(() => decodeWalletQueryArguments(WALLET_TRANSACTIONS_QUERY_ARGUMENTS, 614_401))
      .toThrow(AgentV2ContractError);
  });

  it('reads the networks of own wallets on every contacts read', () => {
    const recipients = {
      // eslint-disable-next-line no-null/no-null -- The query contract uses null for no filter.
      operation: 'contacts.list', accountSelector: { kind: 'current' }, query: null, chains: [], pageSize: 300,
      purpose: 'send_recipient_resolution', ownWalletChains: ['ton'],
    } satisfies AgentWalletDataQueryArgs;
    expect(decodeWalletQueryArguments(recipients).arguments).toMatchObject({ ownWalletChains: ['ton'] });
    const { ownWalletChains, ...withoutNetworks } = recipients;
    expect(() => decodeWalletQueryArguments(withoutNetworks as unknown as AgentWalletDataQueryArgs))
      .toThrow(AgentV2ContractError);
    expect(() => decodeWalletQueryArguments({ ...recipients, ownWalletChains: ['ton', 'ton'] }))
      .toThrow(AgentV2ContractError);
  });
});

describe('writer-authored presentation', () => {
  const action = { id: TOOL_CALL_ID, schemaVersion: 1, kind: 'openDapp', labelCode: 'open_external_link',
    title: 'Открыть приложение', url: 'https://app.ston.fi/', requiresConfirmation: true };
  const event = { type: 'action', protocolVersion: 3, runId: RUN_ID, messageId: MESSAGE_ID,
    sequence: 2, action };

  it('preserves titles on live and persisted actions without changing their destination', () => {
    expect(decodeAgentV2StreamEvent(event)).toMatchObject({ action });
    expect(decodeAgentV2PersistedAction({ ...action, schemaVersion: 3 }))
      .toMatchObject({ title: action.title, url: action.url, requiresConfirmation: true });
  });

  it('ignores additive action presentation fields while keeping the validated destination', () => {
    expect(decodeAgentV2StreamEvent({ ...event, action: { ...action, futureCaption: 'New label' } }))
      .toEqual(event);
    expect(decodeAgentV2PersistedAction({ ...action, schemaVersion: 3, futureCaption: 'New label' }))
      .toEqual({ ...action, schemaVersion: 3 });
  });

  it.each([undefined, '', ' ', ' Open', 'Open ', 'x'.repeat(81), 'Open\nnow', 123])(
    'rejects invalid title %j on both live and persisted actions', (title) => {
      expect(() => decodeAgentV2StreamEvent({ ...event, action: { ...action, title } }))
        .toThrow(AgentV2ContractError);
      expect(() => decodeAgentV2PersistedAction({ ...action, schemaVersion: 3, title })).toThrow(AgentV2ContractError);
    },
  );

  const table = { id: 't1', content: { kind: 'display', headers: ['Актив', 'Количество'],
    rows: [['[Token](https://example.com)', '12.500000001 TON']], notes: ['Данные неполные'] } };
  const tableEvent = { type: 'table_data', protocolVersion: 3, runId: RUN_ID, messageId: MESSAGE_ID,
    sequence: 2, table };

  it.each(['contacts', 'valueSeries', 'walletQuery'])('rejects retired table kind %s', (kind) => {
    expect(() => decodeAgentV2StreamEvent({ ...tableEvent,
      table: { id: 't1', content: { kind, outcome: 'complete', rows: [] } },
    })).toThrow(AgentV2ContractError);
  });

  it('reads ready strings literally and tolerates unknown optional table fields', () => {
    expect(decodeAgentV2StreamEvent({ ...tableEvent,
      table: { ...table, content: { ...table.content, futureProperty: true } } }))
      .toMatchObject({ table });
  });

  it.each([[[]], [['one']], [['one', 'two', 'three']], [['one', 123]]])(
    'rejects a malformed ready row %j', (row) => {
      expect(() => decodeAgentV2StreamEvent({ ...tableEvent,
        table: { ...table, content: { ...table.content, rows: [row] } } })).toThrow(AgentV2ContractError);
    },
  );
});

describe('Agent V2 feature capabilities', () => {
  const walletQuery = {
    status: 'available',
    filterCatalog: { version: 1, digest: 'a'.repeat(64), requiresClientTimeZone: true },
  };

  const problemReport = { status: 'available' };

  it('decodes the nested capabilities and ignores additive fields', () => {
    const value = { protocolVersion: 3, walletQuery, problemReport };
    expect(decodeAgentV2FeatureCapabilities({ ...value, portfolioPositions: 'available' })).toEqual(value);
    const disabled = {
      protocolVersion: 3, walletQuery: { status: 'disabled' }, problemReport: { status: 'disabled' },
    };
    expect(decodeAgentV2FeatureCapabilities(disabled)).toEqual(disabled);
    expect(decodeAgentV2FeatureCapabilities({ protocolVersion: 3, walletQuery }))
      .toEqual({ protocolVersion: 3, walletQuery, problemReport: { status: 'disabled' } });
    expect(decodeAgentV2FeatureCapabilities({ protocolVersion: 3, walletQuery, problemReport: { status: 'on' } }))
      .toEqual({ protocolVersion: 3, walletQuery, problemReport: { status: 'disabled' } });
  });

  it.each([
    { status: 'available' },
    { status: 'disabled', filterCatalog: walletQuery.filterCatalog },
    { ...walletQuery, filterCatalog: { ...walletQuery.filterCatalog, digest: 'A'.repeat(64) } },
  ])('rejects an inconsistent wallet-query capability %j', (value) => {
    expect(() => decodeAgentV2FeatureCapabilities({
      protocolVersion: 3, walletQuery: value, problemReport,
    })).toThrow(AgentV2ContractError);
  });
});

describe('Agent V2 staking offer tool contract', () => {
  const toolCall = {
    id: TOOL_CALL_ID,
    name: 'staking.offer.read',
    version: 1,
    arguments: {
      schemaVersion: 1,
      productId: 'liquid',
      asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
    },
    scopes: ['staking.data.read'],
    timeoutMs: 15_000,
    maxResultBytes: 16_384,
    walletContextSession: {
      sessionId: WALLET_SESSION_ID,
      revision: 1,
      accountScope: 'current',
      activeAccountRef: 'account-current',
      activeNetwork: 'ton',
    },
  } as const;

  it('rejects the retired client staking read tool', () => {
    expect(() => decodeAgentV2StreamEvent(event({ type: 'tool_call', sequence: 3, toolCall })))
      .toThrow(AgentV2ContractError);
  });

  it('rejects unsafe staking offer arguments before execution', () => {
    expect(() => decodeAgentV2ToolArguments({
      ...toolCall,
      arguments: { ...toolCall.arguments, productId: 'unsafe product' },
    } as unknown as AgentToolCall)).toThrow(AgentV2ContractError);
  });
});

describe('Agent V2 semantic public contract', () => {
  it.each(['agent_unavailable', 'content_over_budget', 'web_search_no_results'])(
    'keeps the code-only notice %s on live and persisted notices', (code) => {
      const content = { kind: 'notice', schemaVersion: 1, code };
      const extended = { ...content, clarificationText: 'Do not replace the localized notice', futureProperty: true };
      expect(decodeAgentV2StreamEvent(event({
        type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID, content: extended,
      }))).toMatchObject({ content });
      const page = decodeAgentV2Messages({
        protocolVersion: 3, thread: threadSummary(),
        messages: [persistedMessage(MESSAGE_ID, 'assistant', { kind: 'semantic', content: extended })],
      });
      expect(page.messages[0].content).toEqual({ kind: 'semantic', content });
    },
  );

  it.each(['empty_result', 'clarification_required', 'wallet_data_unavailable', 'action_description_unavailable'])(
    'does not synthesize an agent answer for retired notice %s', (code) => {
      expect(decodeAgentV2StreamEvent(event({
        type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID,
        content: { kind: 'notice', schemaVersion: 1, code },
      }))).toMatchObject({ content: { kind: 'clientUnsupported', schemaVersion: 1 } });
    },
  );

  it.each([undefined, 42, {}])('rejects malformed operational notice code %j', (code) => {
    expect(() => decodeAgentV2StreamEvent(event({
      type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID,
      content: { kind: 'notice', schemaVersion: 1, code },
    }))).toThrow(AgentV2ContractError);
  });

  it('accepts contentKind and ignores an obsolete optional display marker', () => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant',
      contentKind: 'semantic', responseLanguage: 'ru', textFormat: 'agentMarkdownV2',
    }))).toMatchObject({ contentKind: 'semantic', responseLanguage: 'ru' });
  });

  it('keeps an unfamiliar well-formed response language and drops a malformed one', () => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant',
      contentKind: 'markdown', responseLanguage: 'it',
    }))).toMatchObject({ responseLanguage: 'it' });
    expect(decodeAgentV2StreamEvent(event({
      type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant',
      contentKind: 'markdown', responseLanguage: 'not a language',
    }))).not.toHaveProperty('responseLanguage');
  });

  it('decodes persisted targeted Receive V3 without wallet authority fields', () => {
    const action = {
      id: TOOL_CALL_ID,
      schemaVersion: 3,
      kind: 'receive',
      labelCode: 'open_receive',
      title: 'Review prepared action',
      effect: 'open_receive',
      targetNetwork: 'tron',
      localDraftRequired: false,
      requiresConfirmation: false,
    } as const;

    expect(decodeAgentV2PersistedAction(action)).toEqual(action);
    expect(() => decodeAgentV2PersistedAction({
      ...action,
      contextBinding: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        activeAccountRef: 'account-current',
        activeNetwork: 'ton',
      },
    })).toThrow();
  });

  it('rejects retired live and persisted Stake V1 actions', () => {
    const liveAction = {
      id: TOOL_CALL_ID,
      kind: 'stake',
      labelCode: 'open_staking',
      title: 'Review prepared action',
      effect: 'open_staking',
      contextBinding: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        activeAccountRef: 'account-current',
      },
      localDraftRequired: false,
      requiresConfirmation: false,
    } as const;

    expect(() => decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: liveAction,
    }))).toThrow(AgentV2ContractError);

    const { contextBinding: _contextBinding, ...persistedAction } = liveAction;
    expect(() => decodeAgentV2PersistedAction(persistedAction)).toThrow(AgentV2ContractError);
  });

  it('decodes exact Stake V2 targets and closes their executable fields', () => {
    const liveAction = {
      id: TOOL_CALL_ID,
      schemaVersion: 2,
      kind: 'stake',
      labelCode: 'open_staking',
      title: 'Review prepared action',
      effect: 'open_staking',
      contextBinding: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        activeAccountRef: 'account-current',
      },
      productId: 'ethena',
      asset: {
        slug: 'ton-eqaib6kmdf', chain: 'ton', symbol: 'USDe', decimals: 6,
      },
      amount: { kind: 'exact', value: '125.5' },
      localDraftRequired: false,
      requiresConfirmation: false,
    } as const;
    expect(decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: liveAction,
    }))).toMatchObject({ type: 'action', action: liveAction });

    const { contextBinding: _contextBinding, ...persistedAction } = liveAction;
    expect(decodeAgentV2PersistedAction({
      ...persistedAction,
      amount: { kind: 'all' },
    })).toMatchObject({ productId: 'ethena', amount: { kind: 'all' } });

    expect(() => decodeAgentV2PersistedAction({
      ...persistedAction,
      amount: { kind: 'exact', value: '01' },
    })).toThrow(AgentV2ContractError);
  });

  it.each([
    { prefill: { amount: '2' }, isValid: false },
    { prefill: { recipient: { kind: 'address', chain: 'ton', address: 'EQ-recipient' } }, isValid: true },
    { prefill: { comment: 'Payment' }, isValid: true },
  ])('decodes only asset-independent Send prefills without an asset: %j', ({ prefill, isValid }) => {
    const groups: CompatibilityFixtureGroup[] = compatibilityFixture.fixtures;
    const value = groups.filter(({ schema }) => schema === 'AgentStreamEventV2')
      .flatMap(({ values }) => values).find((value) => {
        const candidate = readWireObject(value, '$');
        if (candidate.type !== 'action') return false;
        const action = readWireObject(candidate.action, '$.action');
        return action.effect === 'open_send' && action.asset === undefined && action.recipient === undefined;
      });
    const candidate = readWireObject(value, '$');
    const decode = () => decodeAgentV2StreamEvent({ ...candidate,
      action: { ...readWireObject(candidate.action, '$.action'), ...prefill },
    });
    if (isValid) expect(decode()).toMatchObject({ action: prefill });
    else expect(decode).toThrow(AgentV2ContractError);
  });

  it.each([
    { kind: 'savedAddress', addressRef: 'address-mother' },
    { kind: 'address', chain: 'ton', address: 'EQ-user-authored-address' },
    { kind: 'domain', chain: 'ton', domain: 'mother.ton' },
  ] as const)('decodes a live Send-form action with recipient kind $kind', (recipient) => {
    const action = {
      id: TOOL_CALL_ID,
      kind: 'send',
      labelCode: 'open_send',
      title: 'Review prepared action',
      effect: 'open_send',
      contextBinding: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        activeAccountRef: 'account-current',
        activeNetwork: 'ton',
      },
      asset: { slug: 'gram', chain: 'ton' },
      recipient,
      localDraftRequired: false,
      requiresConfirmation: false,
    } as const;

    expect(decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action,
    }))).toMatchObject({ action });
  });

  it('decodes a live Send-form action without a recipient prefill', () => {
    const decoded = decodeAgentV2StreamEvent(event({
      type: 'action',
      sequence: 3,
      messageId: MESSAGE_ID,
      action: {
        id: TOOL_CALL_ID,
        kind: 'send',
        labelCode: 'open_send',
        title: 'Review prepared action',
        effect: 'open_send',
        contextBinding: {
          sessionId: WALLET_SESSION_ID,
          revision: 1,
          activeAccountRef: 'account-current',
          activeNetwork: 'ton',
        },
        asset: { slug: 'gram', chain: 'ton' },
        localDraftRequired: false,
        requiresConfirmation: false,
      },
    }));

    expect(decoded).toMatchObject({
      type: 'action',
      action: { kind: 'send', effect: 'open_send', asset: { slug: 'gram', chain: 'ton' } },
    });
    expect(decoded).not.toHaveProperty('action.recipient');
  });

  it('decodes Swap display extensions while keeping executable action fields closed', () => {
    const action = swapActionFixture();
    expect(decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID, action,
    }))).toMatchObject({ action });
    expect(() => decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID,
      action: { ...action, url: 'javascript:invalid' },
    }))).toThrow(AgentV2ContractError);
    const { contextBinding: _contextBinding, ...persisted } = action;
    expect(decodeAgentV2PersistedAction(persisted)).toEqual(persisted);
    expect(() => decodeAgentV2PersistedAction({ ...persisted, sourceToolCallId: TOOL_CALL_ID }))
      .toThrow(AgentV2ContractError);
  });

  it.each([...getSupportedChains(), 'future-chain'])('decodes live and persisted Swap assets on %s', (chain) => {
    const fixture = swapActionFixture();
    const action = {
      ...fixture,
      sourceAsset: { ...fixture.sourceAsset, chain },
      destinationAsset: { ...fixture.destinationAsset, chain },
    };
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID, action,
    }))).toMatchObject({ disposition: 'handle', event: { action } });
    const { contextBinding: _contextBinding, ...persisted } = action;
    expect(decodeAgentV2PersistedAction(persisted)).toEqual(persisted);
  });

  it.each(['', 'x'.repeat(33), undefined, 1])('rejects a malformed Swap chain %s', (chain) => {
    const fixture = swapActionFixture();
    const action = { ...fixture, destinationAsset: { ...fixture.destinationAsset, chain } };
    expect(() => decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID, action,
    }))).toThrow(AgentV2ContractError);
    const { contextBinding: _contextBinding, ...persisted } = action;
    expect(() => decodeAgentV2PersistedAction(persisted)).toThrow(AgentV2ContractError);
  });

  it('decodes a partial Swap without inventing a source asset or amount in live and persisted actions', () => {
    const { sourceAsset: _sourceAsset, amount: _amount, ...fixture } = swapActionFixture();
    const action = {
      ...fixture,
      destinationAsset: { slug: 'trx', chain: 'tron', symbol: 'TRX', decimals: 6 },
      url: 'https://my.tt/swap?out=trx',
    };
    expect(decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID, action,
    }))).toMatchObject({ action });
    const { contextBinding: _contextBinding, ...persisted } = action;
    expect(decodeAgentV2PersistedAction(persisted)).toEqual(persisted);
  });

  it.each([
    ['malformed provided asset', { sourceAsset: false, amount: undefined }],
    ['malformed provided amount', { amount: false }],
    ['source amount without source asset', { sourceAsset: undefined }],
    ['destination amount without destination asset', {
      destinationAsset: undefined, amount: { value: '10', valueType: 'decimal', side: 'destination' },
    }],
  ])('rejects a partial Swap with %s in live and persisted actions', (_name, change) => {
    const action = { ...swapActionFixture(), ...change };
    expect(() => decodeAgentV2StreamEvent(event({
      type: 'action', sequence: 4, messageId: MESSAGE_ID, action,
    }))).toThrow(AgentV2ContractError);
    const { contextBinding: _contextBinding, ...persisted } = action;
    expect(() => decodeAgentV2PersistedAction(persisted)).toThrow(AgentV2ContractError);
  });

  it.each([
    ['an unknown asset field', { asset: { slug: 'gram', chain: 'ton', network: 'mainnet' } }],
    ['an unknown recipient kind', { recipient: { kind: 'contact', contactId: 'contact-mother' } }],
    ['an unknown effect', { effect: 'sign_transfer' }],
  ])('drops a Send action with %s without failing its message', (_, change) => {
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { ...sendActionFixture(), ...change },
    }))).toEqual({
      disposition: 'ignore',
      envelope: { protocolVersion: 3, runId: RUN_ID, sequence: 3 },
      wireType: 'action',
      boundary: expect.any(String),
    });
  });

  it('keeps a well-formed Send action and fails the message of a malformed one', () => {
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: sendActionFixture(),
    }))).toMatchObject({ disposition: 'handle' });
    // Any network of the wallet: the resolver checks that the app supports it
    expect(decodeAgentV2StreamFrame(event({
      type: 'action',
      sequence: 3,
      messageId: MESSAGE_ID,
      action: { ...sendActionFixture(), asset: { slug: 'robinhood', chain: 'robinhood' } },
    }))).toMatchObject({ disposition: 'handle' });
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { ...sendActionFixture(), amount: '1e5' },
    }))).toMatchObject({ disposition: 'ignore', incompleteMessageId: MESSAGE_ID });
  });

  it('drops a persisted action with an unknown executable field without failing its message', () => {
    const { contextBinding: _contextBinding, ...persisted } = swapActionFixture();
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant'),
        actions: [persisted, { ...persisted, id: TOOL_CALL_ID, amount: { ...persisted.amount, unit: 'fiat' } }],
      }],
    });

    expect(decoded.messages[0].actions).toEqual([persisted]);
    expect(decoded.messages[0].error).toBeUndefined();
    expect(decoded.incompatibleMessages).toBeUndefined();
  });

  it('redacts unknown semantic variants and keeps the known-event decoder strict', () => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID,
      content: { kind: 'futureContent', schemaVersion: 8, raw: 'must-not-survive' },
    }))).toMatchObject({ content: { kind: 'clientUnsupported', schemaVersion: 1 } });
    expect(() => decodeAgentV2StreamEvent(event({
      type: 'widget', sequence: 3, messageId: MESSAGE_ID,
      widget: { kind: 'legacyWidget', version: 1, payload: {} },
    }))).toThrow(AgentV2CompatibilityError);
    expect(decodeAgentV2StreamFrame(event({
      type: 'widget', sequence: 3, messageId: MESSAGE_ID,
      widget: { kind: 'legacyWidget', version: 1, payload: {} },
    }))).toEqual({
      disposition: 'ignore',
      envelope: { protocolVersion: 3, runId: RUN_ID, sequence: 3 },
      wireType: 'widget',
    });
  });

  it.each([
    { type: '', sequence: 3 },
    { type: 'x'.repeat(65), sequence: 3 },
    { type: 'future_optional', sequence: 0 },
    { type: 'future_optional', sequence: 3, runId: 'invalid' },
    { type: 'future_optional', sequence: 3, createdAt: 'invalid' },
  ])('rejects an unknown event with a malformed V2 envelope', (wireEvent) => {
    expect(() => decodeAgentV2StreamFrame(event(wireEvent))).toThrow(AgentV2ContractError);
  });

  it('does not soften unknown protocol versions', () => {
    expect(() => decodeAgentV2StreamFrame({
      ...event({ type: 'future_optional', sequence: 3 }),
      protocolVersion: 4,
    })).toThrow(AgentV2CompatibilityError);
  });

  it('hands a tool call with an unknown name back for rejection and keeps a malformed one fatal', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'future.tool',
      version: 1,
      scopes: ['wallet.data.read'],
      timeoutMs: 1_000,
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
      },
      arguments: {},
    };
    expect(decodeAgentV2StreamFrame(event({ type: 'tool_call', sequence: 3, toolCall }))).toEqual({
      disposition: 'unsupportedTool',
      envelope: { protocolVersion: 3, runId: RUN_ID, sequence: 3 },
      toolCall: { id: TOOL_CALL_ID, name: 'future.tool' },
    });
    expect(() => decodeAgentV2StreamFrame(event({
      type: 'tool_call', sequence: 3, toolCall: { ...toolCall, id: 'invalid' },
    }))).toThrow(AgentV2ContractError);
  });

  it.each([
    { kind: 'notice', schemaVersion: 1, code: 'future_notice' },
    { kind: 'market', schemaVersion: 1, view: 'overview' },
    { kind: 'notice', schemaVersion: 1, code: 'market_quote' },
    { kind: 'walletQuery', schemaVersion: 1, queryKind: 'future', outcome: 'complete' },
    { kind: 'portfolio', schemaVersion: 1, view: 'future' },
    { kind: 'assetSearch', schemaVersion: 1, outcome: 'future' },
    { kind: 'webDigest', schemaVersion: 1, outcome: 'future' },
    { kind: 'notice', schemaVersion: 2, code: 'empty_result' },
  ])('maps an unknown semantic renderer extension to clientUnsupported', (content) => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID, content,
    }))).toMatchObject({
      content: { kind: 'clientUnsupported', schemaVersion: 1 },
    });
  });

  it('decodes markdown and semantic persisted content while ignoring optional extensions', () => {
    const { chains: _chains, ...userWithoutChains } = persistedMessage(
      '44444444-4444-4444-8444-444444444444',
      'user',
      { kind: 'markdown', text: 'Hello' },
    );
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [
        userWithoutChains,
        persistedMessage(MESSAGE_ID, 'assistant', {
          kind: 'semantic', content: semanticContents()[0],
        }),
      ],
    });
    expect(decoded.messages[0].content).toEqual({ kind: 'markdown', text: 'Hello' });
    expect(decoded.messages[1].content?.kind).toBe('semantic');
    expect(decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{ ...persistedMessage(MESSAGE_ID, 'assistant'), text: 'legacy' }],
    }).messages).toHaveLength(1);
  });

  it('keeps persisted semantic messages with unsupported renderer content', () => {
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [persistedMessage(MESSAGE_ID, 'assistant', {
        kind: 'semantic',
        content: { kind: 'notice', schemaVersion: 1, code: 'future_notice' },
      })],
    });

    expect(decoded.messages).toHaveLength(1);
    expect(decoded.messages[0].content).toEqual({
      kind: 'semantic',
      content: { kind: 'clientUnsupported', schemaVersion: 1 },
    });
  });

  it('keeps the response language on persisted assistant messages', () => {
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant', { kind: 'markdown', text: 'Ответ' }),
        responseLanguage: 'ru',
      }],
    });

    expect(decoded.messages[0].responseLanguage).toBe('ru');
  });

  it('keeps unfamiliar well-formed persisted languages without rejecting the message', () => {
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant', { kind: 'markdown', text: 'Ciao' }),
        responseLanguage: 'it',
      }],
    });

    expect(decoded.messages[0].responseLanguage).toBe('it');
  });

  it('keeps messages after dropping unknown persisted controls and reports malformed messages', () => {
    const contractMessageId = '77777777-7777-4777-8777-777777777777';
    const compatibilityMessageId = '88888888-8888-4888-8888-888888888888';
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [
        persistedMessage(contractMessageId, 'assistant', { kind: 'markdown', text: 42 }),
        {
          ...persistedMessage(compatibilityMessageId, 'assistant'),
          actions: [{ id: '99999999-9999-4999-8999-999999999999', kind: 'futureAction' }],
        },
        persistedMessage(MESSAGE_ID, 'assistant', { kind: 'markdown', text: 'Still readable' }),
      ],
    });

    expect(decoded.messages).toHaveLength(2);
    expect(decoded.messages[0]).toMatchObject({ id: compatibilityMessageId });
    expect(decoded.messages[0].actions).toBeUndefined();
    expect(decoded.messages[1].id).toBe(MESSAGE_ID);
    expect(decoded.incompatibleMessages).toEqual([
      {
        index: 0,
        category: 'contract',
        boundary: '$.messages[0].content.text',
        messageId: contractMessageId,
      },
    ]);
  });

  it('filters unknown live controls and normalizes unknown progress and terminal values', () => {
    const supportedFollowup = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'suggested_prompt',
      text: 'Help me open staking.',
    };
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { kind: 'futureAction' },
    }))).toMatchObject({ disposition: 'ignore', wireType: 'action' });
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID,
      action: { kind: 'receive', schemaVersion: 4 },
    }))).toMatchObject({ disposition: 'ignore', wireType: 'action' });
    expect(decodeAgentV2StreamFrame(event({
      type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { kind: 'openDapp' },
    }))).toMatchObject({ disposition: 'ignore', incompleteMessageId: MESSAGE_ID });
    expect(decodeAgentV2StreamFrame(event({
      type: 'followups', sequence: 3, messageId: MESSAGE_ID,
      items: [{ kind: 'futureFollowup' }, supportedFollowup],
    }))).toMatchObject({
      disposition: 'handle',
      event: { items: [supportedFollowup] },
    });
    expect(decodeAgentV2StreamFrame(event({
      type: 'tool_status', sequence: 3, toolCallId: TOOL_CALL_ID, status: 'future',
    }))).toMatchObject({ disposition: 'ignore', wireType: 'tool_status' });
    expect(decodeAgentV2StreamFrame(event({
      type: 'run_activity', sequence: 3, code: 'future.phase', status: 'active',
    }))).toMatchObject({ disposition: 'ignore', wireType: 'run_activity' });
    expect(decodeAgentV2StreamFrame(event({
      type: 'run_activity', sequence: 3, code: 'web.reading_sources', status: 'completed',
    }))).toMatchObject({
      disposition: 'handle',
      event: { type: 'run_activity', code: 'web.reading_sources', status: 'completed' },
    });
    const retryableError = decodeAgentV2StreamFrame(event({
      type: 'error', sequence: 3, code: 'future_retryable', retryable: true,
      retryAfterMs: 'not-applicable', resetAt: 'not-applicable',
    }));
    expect(retryableError).toMatchObject({
      disposition: 'handle',
      event: { code: 'internal_error', retryable: true },
    });
    if (retryableError.disposition !== 'handle') throw new Error('Expected handled error');
    expect(retryableError.event).not.toHaveProperty('retryAfterMs');
    expect(retryableError.event).not.toHaveProperty('resetAt');
    expect(decodeAgentV2StreamFrame(event({
      type: 'error', sequence: 3, code: 'future_terminal', retryable: false,
    }))).toMatchObject({
      disposition: 'handle',
      event: { code: 'invalid_event', retryable: false },
    });
    const messageEnd = decodeAgentV2StreamFrame(event({
      type: 'message_end', sequence: 3, messageId: MESSAGE_ID,
      finishReason: 'future_finish',
    }));
    expect(messageEnd).toMatchObject({
      disposition: 'handle',
      event: { finishReason: 'run_interrupted' },
    });
  });

  it('decodes a bounded model-owned follow-up', () => {
    const marketFollowup = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'suggested_prompt',
      text: 'Explain market analysis.',
    };

    expect(decodeAgentV2StreamFrame(event({
      type: 'followups', sequence: 3, messageId: MESSAGE_ID, items: [marketFollowup],
    }))).toMatchObject({ disposition: 'handle', event: { items: [marketFollowup] } });
  });

  it('decodes the visible-content boundary independently from the terminal event', () => {
    expect(decodeAgentV2StreamFrame(event({
      type: 'message_content_end', sequence: 3, messageId: MESSAGE_ID,
    }))).toMatchObject({
      disposition: 'handle',
      event: { type: 'message_content_end', messageId: MESSAGE_ID },
    });
  });

  it.each([
    '',
    ' Detailed analysis',
    'Detailed\nanalysis',
    '**Detailed analysis**',
    'x'.repeat(81),
  ])('filters an invalid model-owned follow-up item: %o', (text) => {
    expect(decodeAgentV2StreamFrame(event({
      type: 'followups',
      sequence: 3,
      messageId: MESSAGE_ID,
      items: [{
        id: 'adadadad-adad-4dad-8dad-adadadadadad',
        kind: 'suggested_prompt',
        text,
      }],
    }))).toMatchObject({ disposition: 'ignore', wireType: 'followups' });
  });

  it('keeps the first three unique valid follow-ups without failing the message', () => {
    const first = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'suggested_prompt',
      text: 'Explain staking risks.',
    };
    const second = {
      id: 'bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd',
      kind: 'suggested_prompt',
      text: 'How do staking rewards work?',
    };
    const third = {
      id: 'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
      kind: 'suggested_prompt',
      text: 'Compare staking options.',
    };
    const fourth = {
      id: 'dededede-dede-4ede-8ede-dededededede',
      kind: 'suggested_prompt',
      text: 'How do I unstake?',
    };

    expect(decodeAgentV2StreamFrame(event({
      type: 'followups',
      sequence: 3,
      messageId: MESSAGE_ID,
      items: [
        { kind: 'deterministic', code: 'prepare_stake' },
        first,
        { ...first, text: 'Duplicate id.' },
        second,
        third,
        fourth,
      ],
    }))).toMatchObject({
      disposition: 'handle',
      event: { items: [first, second, third] },
    });
  });

  it.each([
    'Explore staking risks.',
    'Риски стейкинга подробнее.',
  ] as const)('decodes server copy in the current request language', (text) => {
    const followup = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'suggested_prompt',
      text,
    };

    expect(decodeAgentV2StreamFrame(event({
      type: 'followups', sequence: 3, messageId: MESSAGE_ID, items: [followup],
    }))).toMatchObject({ disposition: 'handle', event: { items: [followup] } });
  });

  it('accepts server copy above the preferred display length', () => {
    const followup = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'suggested_prompt',
      text: 'x'.repeat(33),
    };

    expect(decodeAgentV2StreamFrame(event({
      type: 'followups', sequence: 3, messageId: MESSAGE_ID, items: [followup],
    }))).toMatchObject({ disposition: 'handle', event: { items: [followup] } });
  });

  it('filters controls with unknown behavioral selectors from live and persisted output', () => {
    const unsupportedFollowup = {
      id: 'adadadad-adad-4dad-8dad-adadadadadad',
      kind: 'deterministic',
      code: 'prepare_stake',
      intent: 'future_intent',
    };
    const unsupportedKindFollowup = {
      id: 'bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd',
      kind: 'futureFollowup',
      title: 'Future',
      prompt: 'Future prompt',
      intent: 'future_intent',
    };

    expect(decodeAgentV2StreamFrame(event({
      type: 'followups', sequence: 3, messageId: MESSAGE_ID,
      items: [unsupportedFollowup, unsupportedKindFollowup],
    }))).toMatchObject({ disposition: 'ignore', wireType: 'followups' });

    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant'),
        followups: [unsupportedFollowup, unsupportedKindFollowup],
      }],
    });
    expect(decoded.messages).toHaveLength(1);
    expect(decoded.messages[0].followups).toBeUndefined();
  });

  it('rejects malformed known control output before compatibility filtering', () => {
    const malformed = event({ type: 'followups', sequence: 3, items: [{ kind: 'futureFollowup' }] });
    expect(() => decodeAgentV2StreamFrame(malformed)).toThrow(AgentV2ContractError);
  });

  it('normalizes unknown persisted errors without preserving timing extensions', () => {
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant'),
        error: { code: 'future_error', retryable: true, retryAfterMs: 'future' },
      }],
    });

    expect(decoded.messages[0].error).toEqual({ code: 'internal_error', retryable: true });
  });

  it.each([
    'market-analysis-details',
    'adadadad-adad-5dad-8dad-adadadadadad',
    'adadadad-adad-7dad-8dad-adadadadadad',
  ])('filters malformed or unsupported follow-up id %s', (id) => {
    expect(decodeAgentV2StreamFrame(event({
      type: 'followups',
      sequence: 3,
      messageId: MESSAGE_ID,
      items: [{
        id,
        kind: 'suggested_prompt',
        text: 'Help me open staking.',
      }],
    }))).toMatchObject({ disposition: 'ignore', wireType: 'followups' });
  });

  it.each(navigationFixture.projectionCases)(
    'decodes executable live and persisted V3 navigation action $id',
    ({ live, expectedPersisted }) => {
      expect(decodeAgentV2StreamEvent(event({
        type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { ...live, title: 'Review prepared action' },
      }))).toMatchObject({ action: live });
      expect(decodeAgentV2Messages({
        protocolVersion: 3,
        thread: threadSummary(),
        messages: [{
          ...persistedMessage(MESSAGE_ID, 'assistant'),
          actions: [{ ...expectedPersisted, title: 'Review prepared action' }],
        }],
      }).messages[0].actions).toEqual([{ ...expectedPersisted, title: 'Review prepared action' }]);
    },
  );

  it('drops a persisted action with an unknown schema version without deleting its message', () => {
    const decoded = decodeAgentV2Messages({
      protocolVersion: 3,
      thread: threadSummary(),
      messages: [{
        ...persistedMessage(MESSAGE_ID, 'assistant'),
        actions: [navigationFixture.invalidV3[0]],
      }],
    });

    expect(decoded.messages).toHaveLength(1);
    expect(decoded.messages[0].actions).toBeUndefined();
  });

  it.each(navigationFixture.invalidV3.slice(1).map((action, index) => [index + 1, action] as const))(
    'preserves a message while rejecting malformed persisted V3 navigation action %s',
    (_index, action) => {
      const decoded = decodeAgentV2Messages({
        protocolVersion: 3,
        thread: threadSummary(),
        messages: [{ ...persistedMessage(MESSAGE_ID, 'assistant'), actions: [action] }],
      });
      expect(decoded.messages).toHaveLength(1);
      expect(decoded.messages[0].actions).toBeUndefined();
      expect(decoded.messages[0].error?.code).toBe('invalid_event');
      expect(decoded.incompatibleMessages).toEqual([
        expect.objectContaining({
          index: 0,
          category: 'contract',
          messageId: MESSAGE_ID,
        }),
      ]);
    },
  );

  it('accepts code-only hints and ignores optional server-authored fields', () => {
    expect(decodeAgentV2Hints({
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [{ id: 'receive.tokens', requiredCapabilities: ['receive_action'] }, { id: 'future.hint' }],
    }).items).toHaveLength(1);
    expect(decodeAgentV2Hints({
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [{
        id: 'receive.tokens', requiredCapabilities: ['receive_action'],
        title: 'Receive', prompt: 'Receive tokens',
      }],
    }).items).toHaveLength(1);
  });

  it('accepts the flat backend wallet-query transaction frame', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      maxResultBytes: 98_304,
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
        activeNetwork: 'ton',
      },
      arguments: {
        operation: 'transactions.list',
        accountSelector: { kind: 'current' },
        chains: [],
        filters: {
          schemaVersion: 1,
          catalogDigest: contractManifest.walletFilterCatalogSha256,
          clauses: [],
        },
        riskMode: 'only',
        pageSize: 10,
      },
    };

    expect(decodeAgentV2StreamEvent(event({
      type: 'tool_call', sequence: 3, toolCall,
    }))).toMatchObject({ type: 'tool_call', toolCall });
    const decoded = decodeAgentV2StreamEvent(event({
      type: 'tool_call',
      sequence: 3,
      toolCall: {
        ...toolCall,
        arguments: {
          ...toolCall.arguments,
          riskMode: 'future',
        },
      },
    }));
    if (decoded.type !== 'tool_call') throw new Error('Expected tool_call');
    expect(() => decodeAgentV2ToolArguments(decoded.toolCall)).toThrow(AgentV2ContractError);
  });

  it('accepts an explicit-all portfolio view-only filter and rejects it for current scope', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      maxResultBytes: 98_304,
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
      scopeIntent: { messageId: MESSAGE_ID, reason: 'explicit_all_wallet_query' },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'explicitAll',
        activeAccountRef: 'account_current',
        activeNetwork: 'ton',
      },
      arguments: {
        operation: 'portfolio.aggregate',
        historySource: 'backend',
        accountSelector: { kind: 'explicitAll' },
        accountFilter: { viewOnly: 'exclude' },
        chains: [],
        range: '3m',
        groupBy: ['account', 'asset', 'network'],
        riskMode: 'all',
        visibilityMode: 'all',
      },
    };

    const decoded = decodeAgentV2StreamEvent(event({
      type: 'tool_call', sequence: 3, toolCall,
    }));
    if (decoded.type !== 'tool_call') throw new Error('Expected tool_call');
    expect(decodeAgentV2ToolArguments(decoded.toolCall)).toMatchObject({
      arguments: toolCall.arguments,
    });
    const invalid = decodeAgentV2StreamEvent(event({
      type: 'tool_call',
      sequence: 3,
      toolCall: {
        ...toolCall,
        arguments: {
          ...toolCall.arguments,
          accountSelector: { kind: 'current' },
        },
      },
    }));
    if (invalid.type !== 'tool_call') throw new Error('Expected tool_call');
    expect(() => decodeAgentV2ToolArguments(invalid.toolCall)).toThrow(AgentV2ContractError);
  });

  it('accepts a current-wallet transaction list query without filters', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      maxResultBytes: 98_304,
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
        activeNetwork: 'ton',
      },
      arguments: {
        operation: 'transactions.list',
        accountSelector: { kind: 'current' },
        chains: [],
        filters: {
          schemaVersion: 1,
          catalogDigest: contractManifest.walletFilterCatalogSha256,
          clauses: [],
        },
        riskMode: 'exclude',
        pageSize: 50,
      },
    };

    const decoded = decodeAgentV2StreamEvent(event({
      type: 'tool_call', sequence: 3, toolCall,
    }));
    if (decoded.type !== 'tool_call') throw new Error('Expected tool_call');
    expect(decodeAgentV2ToolArguments(decoded.toolCall)).toMatchObject({
      arguments: toolCall.arguments,
    });
  });

  it('accepts the backend wallet-query position policy fields', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      maxResultBytes: 98_304,
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
        activeNetwork: 'ton',
      },
      arguments: {
        operation: 'positions.list',
        accountSelector: { kind: 'current' },
        assetSelectors: [],
        chains: [],
        positionKinds: ['fungible'],
        riskMode: 'exclude',
        visibilityMode: 'visible',
        includeZero: false,
        sort: 'wallet_order',
        pageSize: 100,
      },
    };

    expect(decodeAgentV2StreamEvent(event({
      type: 'tool_call', sequence: 3, toolCall,
    }))).toMatchObject({ type: 'tool_call', toolCall });
    const decoded = decodeAgentV2StreamEvent(event({
      type: 'tool_call', sequence: 3,
      toolCall: {
        ...toolCall,
        arguments: {
          ...toolCall.arguments,
          riskMode: 'future',
        },
      },
    }));
    if (decoded.type !== 'tool_call') throw new Error('Expected tool_call');
    expect(() => decodeAgentV2ToolArguments(decoded.toolCall)).toThrow(AgentV2ContractError);
  });

  it.each([
    'a'.repeat(42),
    'aaaaaaaa…aaaaaaaa',
    `0x${'a'.repeat(40)}`,
  ])('rejects a shortened or masked transaction detail hash', (hash) => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      maxResultBytes: 98_304,
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
      },
      arguments: {
        operation: 'transactions.detail',
        accountSelector: { kind: 'current' },
        hash,
      },
    } as AgentToolCall;

    expect(() => decodeAgentV2ToolArguments(toolCall)).toThrow(AgentV2ContractError);
  });

  it('accepts a full EVM detail hash with an uppercase prefix', () => {
    const toolCall = {
      id: TOOL_CALL_ID,
      name: 'wallet.data.query',
      scopes: ['wallet.data.read'],
      timeoutMs: 30_000,
      walletContextSession: {
        sessionId: WALLET_SESSION_ID,
        revision: 1,
        accountScope: 'current',
        activeAccountRef: 'account_current',
      },
      arguments: {
        operation: 'transactions.detail',
        accountSelector: { kind: 'current' },
        hash: `0X${'A'.repeat(64)}`,
      },
    } as AgentToolCall;

    expect(decodeAgentV2ToolArguments(toolCall)).toBe(toolCall);
  });

  it.each([
    {
      kind: 'walletQuery',
      schemaVersion: 1,
      queryKind: 'transactions',
      outcome: 'complete',
      hasMore: false,
      omittedRows: { count: 3, accuracy: 'lower_bound' },
      policySummary: {
        presentation: 'quarantine',
        suspicious: { count: 1, accuracy: 'lower_bound' },
      },
      rows: [{
        chain: 'ton',
        transactionType: 'transfer',
        status: 'completed',
        timestamp: '2026-08-07T15:15:00.000Z',
        assetLabelStatus: 'redacted_unsafe',
      }],
    },
    {
      kind: 'walletQuery',
      schemaVersion: 1,
      queryKind: 'positions',
      outcome: 'partial',
      hasMore: false,
      policySummary: {
        presentation: 'standard',
        omittedSpam: { count: 2, accuracy: 'exact' },
        omittedHidden: { count: 1, accuracy: 'exact' },
      },
      rows: [{
        chain: 'ton',
        positionKind: 'fungible',
        assetLabelStatus: 'redacted_unsafe',
      }],
    },
    {
      kind: 'walletQuery',
      schemaVersion: 1,
      queryKind: 'positions',
      outcome: 'complete',
      hasMore: false,
      policySummary: {
        presentation: 'hidden_review',
        suspicious: { count: 1, accuracy: 'exact' },
      },
      rows: [{
        chain: 'ton',
        positionKind: 'fungible',
        assetName: 'Gram Event',
        assetSymbol: 'GRAM AT GRAMEVENT.ORG',
        assetLabelStatus: 'untrusted_plaintext',
        quantity: '100',
      }],
    },
  ])('rejects retired wallet-query presentation for $queryKind', (content) => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'semantic_content', sequence: 3, messageId: MESSAGE_ID, content,
    }))).toMatchObject({ type: 'semantic_content', content: { kind: 'clientUnsupported', schemaVersion: 1 } });
  });

  it('accepts code-only terminal errors and ignores optional server extensions', () => {
    expect(decodeAgentV2StreamEvent(event({
      type: 'error', sequence: 4, code: 'tool_failed', retryable: true, messageId: MESSAGE_ID,
    }))).toMatchObject({ code: 'tool_failed' });
    expect(decodeAgentV2StreamEvent(event({
      type: 'error', sequence: 4, code: 'tool_failed', retryable: true,
      userMessage: 'Server-authored copy',
    }))).toMatchObject({ code: 'tool_failed' });
  });
});

function decodeWalletQueryArguments(args: AgentWalletDataQueryArgs, maxResultBytes = 98_304) {
  const decoded = decodeAgentV2StreamEvent(event({
    type: 'tool_call', sequence: 3,
    toolCall: {
      id: TOOL_CALL_ID, name: 'wallet.data.query', arguments: args,
      scopes: ['wallet.data.read'], timeoutMs: 30_000, maxResultBytes,
      intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
      walletContextSession: {
        sessionId: WALLET_SESSION_ID, revision: 1, accountScope: 'current',
        activeAccountRef: 'account_current', activeNetwork: 'ton',
      },
    },
  }));
  if (decoded.type !== 'tool_call') throw new Error('Expected tool_call');
  return decodeAgentV2ToolArguments(decoded.toolCall);
}

function createWalletChainFilterArguments(values: string[]): AgentWalletTransactionsListArgs {
  return {
    ...WALLET_TRANSACTIONS_QUERY_ARGUMENTS,
    filters: {
      ...WALLET_TRANSACTIONS_QUERY_ARGUMENTS.filters,
      clauses: [{ field: 'transaction.chain', operator: 'in', values }],
    },
  };
}

function sendActionFixture() {
  return {
    id: TOOL_CALL_ID,
    kind: 'send' as const,
    labelCode: 'open_send' as const,
    title: 'Review prepared action',
    effect: 'open_send' as const,
    contextBinding: {
      sessionId: WALLET_SESSION_ID,
      revision: 1,
      activeAccountRef: 'account-current',
      activeNetwork: 'ton',
    },
    asset: { slug: 'gram', chain: 'ton' as const },
    recipient: { kind: 'savedAddress' as const, addressRef: 'address-mother' },
    amount: '1.5',
    localDraftRequired: false as const,
    requiresConfirmation: false as const,
  };
}

function swapActionFixture() {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    schemaVersion: 2 as const,
    kind: 'swap' as const,
    labelCode: 'open_swap' as const,
    title: 'Review prepared action',
    effect: 'open_swap' as const,
    url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
    contextBinding: {
      sessionId: WALLET_SESSION_ID,
      revision: 1,
      activeAccountRef: 'account-current',
    },
    sourceAsset: { slug: 'toncoin', chain: 'ton' as const, symbol: 'TON', decimals: 9 },
    destinationAsset: { slug: 'usdton', chain: 'ton' as const, symbol: 'USDT', decimals: 6 },
    amount: { value: '10', valueType: 'decimal' as const, side: 'source' as const },
    localDraftRequired: false as const,
    requiresConfirmation: false as const,
  };
}

function event(value: Record<string, unknown>) {
  return { protocolVersion: 3, runId: RUN_ID, ...value };
}

function decodeCompatibilityFixtureGroup(fixture: CompatibilityFixtureGroup) {
  switch (fixture.schema) {
    case 'AgentStreamEventV2':
      fixture.values.forEach((value) => {
        const decoded = decodeAgentV2StreamEvent(value);
        expect(decoded).toBeDefined();
        if (decoded.type === 'tool_call') {
          expect(decodeAgentV2ToolArguments(decoded.toolCall)).toBeDefined();
        }
      });
      break;
    case 'AgentHintsResponseV2':
      fixture.values.forEach((value) => expect(decodeAgentV2Hints(value)).toBeDefined());
      break;
    case 'AgentWalletSnapshotAckV1':
      fixture.values.forEach((value) => expect(decodeAgentV2WalletSnapshotAck(value)).toBeDefined());
      break;
    case 'AgentFeatureCapabilitiesResponseV2':
      fixture.values.forEach((value) => expect(decodeAgentV2FeatureCapabilities(value)).toBeDefined());
      break;
    case 'AgentThreadMessagesPageV2':
      fixture.values.forEach((value) => expect(decodeAgentV2Messages(value)).toBeDefined());
      break;
    default:
      throw new Error(`Unsupported Agent V2 compatibility fixture: ${fixture.schema}`);
  }
}

function threadSummary() {
  return {
    id: THREAD_ID,
    revision: 1,
    createdAt: '2026-08-06T12:00:00.000Z',
    updatedAt: '2026-08-06T12:00:00.000Z',
    lastActivityAt: '2026-08-06T12:00:00.000Z',
    messageCount: 1,
  };
}

function persistedMessage(id: string, role: 'user' | 'assistant', content?: unknown) {
  return {
    id,
    threadId: THREAD_ID,
    role,
    status: 'complete',
    ...(content ? { content } : {}),
    createdAt: '2026-08-06T12:00:00.000Z',
    chains: ['ton'],
  };
}

function semanticContents() {
  return ['agent_unavailable', 'content_over_budget', 'web_search_no_results'].map((code) => ({
    kind: 'notice', schemaVersion: 1, code,
  }));
}
