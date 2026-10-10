import type { ApiActivity } from '../types';
import type {
  AgentFeatureCapabilitiesResponseV2,
  AgentPersistedActionV2,
  AgentToolCall,
  AgentV2LiveAction,
  AgentWalletDataQueryArgs,
} from './protocol/types';
import type { AgentV2HostContextSnapshot } from './types';
import type { AgentV2WalletToolDispatcherDependencies } from './walletTools';

import { getSupportedChains } from '../../util/chain';
import contractManifest from './generated/manifest.json';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { AgentV2ActionResolver } from './actionResolver';
import { AgentV2WalletSession } from './walletSession';
import { AgentV2WalletToolDispatcher } from './walletTools';

const RUN_ID = '11111111-1111-4111-8111-111111111111';
const THREAD_ID = '22222222-2222-4222-8222-222222222222';
const MESSAGE_ID = '33333333-3333-4333-8333-333333333333';
const TOOL_CALL_ID = '44444444-4444-4444-8444-444444444444';
const ACTION_ID = '55555555-5555-4555-8555-555555555555';
const RESULT_ID = '66666666-6666-4666-8666-666666666666';
const SECOND_RESULT_ID = '77777777-7777-4777-8777-777777777777';
const SEND_ACTION_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const NOW = '2026-08-10T12:00:00.000Z';
const NOW_MS = Date.parse(NOW);
const FULL_TRANSACTION_HASH = 'b'.repeat(64);
const MAX_RESULT_BYTES = 98_304;
const CHAIN_LISTS = [
  { name: 'runtime catalog', chains: [...getSupportedChains()] },
  { name: 'future networks', chains: ['ton', ...Array.from({ length: 64 }, (_, index) => `future-chain-${index}`)] },
];

interface SetupOptions extends Partial<Omit<AgentV2WalletToolDispatcherDependencies, 'session'>> {
  host?: AgentV2HostContextSnapshot;
}

interface QueryVariant {
  args: AgentWalletDataQueryArgs;
  expected: Record<string, unknown>;
  operation: AgentWalletDataQueryArgs['operation'];
}

describe('AgentV2 wallet tools and actions', () => {
  it('rejects wallet reads when the server filter catalog differs from the client build', async () => {
    const { dispatcher, session } = setup();
    session.updateFeatureCapabilities(featureCapabilities('0'.repeat(64)));

    await expect(dispatcher.execute(queryCall(session, positionsListArgs()), execution())).resolves.toMatchObject({
      status: 'rejected', error: { code: 'capability_unsupported', retryable: false },
    });
  });

  it('rejects a legacy frontend price call even when local prices are available', async () => {
    const { dispatcher, session } = setup();
    const call = { ...queryCall(session, positionsListArgs()), name: 'market.asset.quote', version: 1,
      scopes: ['market.data.read'], timeoutMs: 15_000, maxResultBytes: 16_384,
      arguments: { schemaVersion: 1, selector: { kind: 'asset', asset: {
        slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9,
      } }, quoteCurrency: 'USD' } } as unknown as AgentToolCall;
    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected', error: { code: 'tool_unsupported' },
    });
  });

  it('rejects retired Send preparation calls', async () => {
    const { dispatcher, session } = setup();
    const call = {
      ...queryCall(session, positionsListArgs()), name: 'action.send.prepare', version: 1,
      scopes: ['action.send.prepare'],
      arguments: { asset: { slug: 'toncoin', chain: 'ton' },
        amount: { value: '1', valueType: 'decimal' },
        recipient: { kind: 'address', chain: 'ton', address: 'EQ-user-recipient' } },
    } as unknown as AgentToolCall;
    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected', error: { code: 'tool_unsupported' },
    });
  });

  it('returns every non-deleted wallet through the purpose-bound directory tool', async () => {
    const { dispatcher, session } = setup();

    const response = await dispatcher.execute(directoryCall(session), execution());

    expect(response).toMatchObject({
      toolName: 'wallet.directory.query',
      status: 'success',
      directorySession: {
        sessionId: session.snapshot().sessionId,
        revision: session.snapshot().revision,
      },
      result: {
        freshness: { asOf: NOW, source: 'store', isStale: false },
        redaction: { level: 'scoped', omittedFields: [], maxResultBytes: 32_768 },
        result: {
          status: 'complete',
          coverage: { accountsRequested: 2, accountsIncluded: 2, rowsOmitted: 0 },
          accounts: [
            { label: 'Main', isCurrent: true, state: 'active', chains: ['ton'] },
            { label: 'Savings', isCurrent: false, state: 'active', chains: ['ton'] },
          ],
        },
      },
    });
    expect(response).not.toHaveProperty('walletContextSession');
  });

  it('rejects a wallet directory grant that is not bound to the current message', async () => {
    const { dispatcher, session } = setup();
    const call = directoryCall(session);
    call.directoryGrant.messageId = RUN_ID;

    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      toolName: 'wallet.directory.query',
      status: 'rejected',
      error: { code: 'tool_scope_mismatch', retryable: false },
    });
  });

  it('rejects the retired client Swap preparation tool', async () => {
    const { dispatcher, session } = setup({ host: swapHostContext() });
    const call = {
      ...directoryCall(session),
      name: 'action.swap.prepare',
      scopes: ['action.swap.prepare'],
      arguments: { schemaVersion: 1 },
    } as unknown as AgentToolCall;
    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected', error: { code: 'tool_unsupported' },
    });
  });

  it('revalidates live and persisted Swap actions against current wallet authority', () => {
    const { actions, session } = setup({ host: swapHostContext() });
    const action = swapAction(session);
    const persisted = { ...persistedSwapAction(action), id: 'persisted-swap' };
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, persisted);
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);

    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toMatchObject({
      kind: 'openSwap', url: action.url,
    });
    const host = session.snapshot().host!;
    const refreshedPrices = {
      ...host,
      swapAssetCatalog: host.swapAssetCatalog!.map((asset) => ({ ...asset, priceUsd: '4' })),
    };
    expect(session.update(refreshedPrices)).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toMatchObject({
      kind: 'openSwap', url: action.url,
    });
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toMatchObject({
      kind: 'openSwap', url: action.url,
    });
    const expandedCatalog = {
      ...refreshedPrices,
      swapAssetCatalog: [...refreshedPrices.swapAssetCatalog, {
        slug: 'gram', chain: 'ton', symbol: 'GRAM', decimals: 9, priceUsd: '1',
      }],
    };
    expect(session.update(expandedCatalog)).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toMatchObject({
      kind: 'openSwap', url: action.url,
    });
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toMatchObject({
      kind: 'openSwap', url: action.url,
    });
    session.update({ ...expandedCatalog, swapAssetCatalog: [], assetCatalog: [] });
    const openSwap = {
      kind: 'openSwap',
      url: action.url,
      tokenInSlug: 'toncoin',
      tokenOutSlug: 'usdton',
      amount: '10',
      amountSide: 'source',
    };
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual(openSwap);
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toEqual(openSwap);
    session.update({ ...expandedCatalog, isTestnet: true });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toEqual({ kind: 'inactive' });
  });

  it('keeps an unsupported exact-buy Swap inactive in live and restored history', () => {
    const { actions, session } = setup({ host: swapHostContext() });
    const action = {
      ...swapAction(session),
      destinationAsset: { slug: 'sol', chain: 'solana', symbol: 'SOL', decimals: 9 },
      amount: { value: '1', valueType: 'decimal' as const, side: 'destination' as const },
    };
    const persisted = { ...persistedSwapAction(action), id: 'persisted-swap' };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, persisted);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toEqual({ kind: 'inactive' });

    const supported = { ...action, destinationAsset: swapAction(session).destinationAsset };
    actions.registerAction(THREAD_ID, MESSAGE_ID, supported);
    expect(actions.resolveAction(MESSAGE_ID, supported.id)).toMatchObject({
      kind: 'openSwap', amount: '1', amountSide: 'destination',
    });
  });

  it('opens a partial Swap in live and restored history', () => {
    const host = swapHostContext();
    const { actions, session } = setup({ host });
    const action = {
      ...swapAction(session),
      sourceAsset: undefined,
      destinationAsset: { slug: 'trx', chain: 'tron', symbol: 'TRX', decimals: 6 },
      amount: undefined,
      url: 'https://my.tt/swap?out=trx',
    };
    const persisted = { ...persistedSwapAction(action), id: 'persisted-partial-swap' };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, persisted);

    const resolved = { kind: 'openSwap', url: action.url, tokenOutSlug: 'trx' };
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual(resolved);
    expect(actions.resolveAction(MESSAGE_ID, persisted.id)).toEqual(resolved);
  });

  it.each(getQueryVariants())('executes the exact $operation variant', async ({ args, expected, operation }) => {
    const { dispatcher, session } = setup();
    const call = queryCall(session, args);

    const response = await dispatcher.execute(call, execution());

    expect(response).toMatchObject({
      protocolVersion: 3,
      runId: RUN_ID,
      threadId: THREAD_ID,
      toolCallId: TOOL_CALL_ID,
      toolName: 'wallet.data.query',
      status: 'success',
      result: {
        schemaVersion: 1,
        freshness: { asOf: NOW, source: 'store', isStale: false },
        redaction: {
          level: 'scoped',
          omittedFields: ['rawAccountId', 'fullTransactionHash'],
          maxResultBytes: MAX_RESULT_BYTES,
        },
        result: {
          operation,
          status: 'resolved',
          ...expected,
        },
      },
    });
    if (operation === 'transactions.detail') {
      expect(JSON.stringify(response)).not.toContain(FULL_TRANSACTION_HASH);
    }
  });

  it.each(CHAIN_LISTS)('queries the final $name chain within the byte budget', async ({ chains }) => {
    const host = hostContext();
    const lastChain = chains[chains.length - 1];
    host.accounts[0].chains = [...chains];
    host.accounts[0].addresses = Object.fromEntries(chains.map((chain) => [chain, `${chain}-public-address`]));
    host.accounts[0].holdings = [{
      asset: { slug: 'final-chain-asset', chain: lastChain, symbol: 'LAST', decimals: 9 },
      balance: '5', availableBalance: '4', fiatValue: '10', valuationStatus: 'valued',
    }];
    const { dispatcher, session } = setup({ host });
    const call = queryCall(session, { ...positionsListArgs(), chains: [...chains] });

    const response = await dispatcher.execute(call, execution());

    expect(response).toMatchObject({
      status: 'success',
      result: { result: {
        operation: 'positions.list', status: 'resolved',
        positions: [{ chain: lastChain, asset: { slug: 'final-chain-asset' }, quantity: '5' }],
        coverage: { status: 'complete', accountsRequested: 1, accountsIncluded: 1, rowsOmitted: 0 },
      } },
    });
    expect(serializedByteLength(response)).toBeLessThanOrEqual(MAX_RESULT_BYTES);
  });

  it.each(CHAIN_LISTS)('keeps the complete $name in directory and history tool results', async ({ chains }) => {
    const host = hostContext();
    const walletKeys = chains.map((chain) => `${chain}:${chain}-public-address`);
    host.accounts[0].chains = [...chains];
    host.accounts[0].portfolioWalletKeys = walletKeys;
    const { dispatcher, session } = setup({ host });
    const directory = directoryCall(session);

    const directoryResponse = await dispatcher.execute(directory, execution());
    expect(directoryResponse).toMatchObject({
      status: 'success',
      result: { result: {
        status: 'complete',
        accounts: [{ chains }, { chains: ['ton'] }],
        coverage: { accountsRequested: 2, accountsIncluded: 2, rowsOmitted: 0 },
      } },
    });
    expect(serializedByteLength(directoryResponse)).toBeLessThanOrEqual(directory.maxResultBytes);

    const history = queryCall(session, {
      operation: 'value.series', accountSelector: { kind: 'current' }, chains: [],
      metric: 'portfolio_value', assetSelectors: [], range: '3m', maxPoints: 64,
    });
    const historyResponse = await dispatcher.execute(history, execution());
    expect(historyResponse).toMatchObject({
      status: 'success',
      result: { result: {
        operation: 'value.series', status: 'resolved',
        historyAccounts: [{ wallets: walletKeys }],
        coverage: { status: 'complete', accountsRequested: 1, accountsIncluded: 1, rowsOmitted: 0 },
      } },
    });
    expect(serializedByteLength(historyResponse)).toBeLessThanOrEqual(MAX_RESULT_BYTES);

    history.maxResultBytes = 512;
    const rejectedHistory = await dispatcher.execute(history, execution());
    expect(rejectedHistory).toMatchObject({
      status: 'rejected', error: { code: 'result_too_large', retryable: false },
    });
    expect(rejectedHistory).not.toHaveProperty('result');
  });

  it('rejects a directory exceeding its byte budget without shortening chain lists', async () => {
    const host = hostContext();
    const chains = CHAIN_LISTS[1].chains;
    host.accounts = Array.from({ length: 100 }, (_, index) => ({
      ...host.accounts[0], accountId: `wallet-${index}`, label: `Wallet ${index}`, chains: [...chains],
    }));
    host.activeAccountId = host.accounts[0].accountId;
    const { dispatcher, session } = setup({ host });
    expect(session.buildContext().capabilities.features).toContain('walletDirectory');

    const response = await dispatcher.execute(directoryCall(session), execution());

    expect(response).toMatchObject({ status: 'rejected', error: { code: 'result_too_large', retryable: false } });
    expect(response).not.toHaveProperty('result');
    for (const account of session.buildWalletDirectory(NOW).accounts) {
      expect(account.chains).toEqual(chains);
    }
  });

  it('does not resolve token names on the client', async () => {
    const { dispatcher, session } = setup();
    await expect(dispatcher.execute(queryCall(session, assetsSearchArgs('TON')), execution()))
      .resolves.toMatchObject({ status: 'rejected', error: { code: 'invalid_arguments' } });
  });

  it('checks consent on every direct execution', async () => {
    let isConsentAccepted = true;
    const getConsent = jest.fn(() => Promise.resolve(isConsentAccepted));
    const { dispatcher, session } = setup({ getConsent });
    const call = queryCall(session, positionsListArgs());

    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({ status: 'success' });
    isConsentAccepted = false;
    const denied = await dispatcher.execute(call, execution());

    expect(denied).toMatchObject({
      status: 'rejected',
      error: { code: 'consent_required', retryable: false },
    });
    expect(denied).not.toHaveProperty('result');
  });

  it('executes repeated direct calls independently because runtime owns replay', async () => {
    const ids = [RESULT_ID, SECOND_RESULT_ID];
    const randomUuid = jest.fn(() => ids.shift()!);
    const { dispatcher, session } = setup({ randomUuid });
    const call = queryCall(session, positionsListArgs());

    const first = await dispatcher.execute(call, execution());
    const second = await dispatcher.execute(call, execution());

    expect(first).toMatchObject({ status: 'success', clientToolResultId: RESULT_ID });
    expect(second).toMatchObject({ status: 'success', clientToolResultId: SECOND_RESULT_ID });
    expect(randomUuid).toHaveBeenCalledTimes(2);
  });

  it.each([
    'asset.search',
    'wallet.accounts.list',
    'wallet.balances.list',
    'wallet.transactions.list',
    'portfolio.snapshot',
    'addressBook.resolve',
  ])('rejects the removed %s tool name', async (name) => {
    const { dispatcher, session } = setup();
    const call = {
      ...queryCall(session, positionsListArgs()),
      name,
    } as unknown as AgentToolCall;

    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected',
      error: { code: 'tool_unsupported', retryable: false },
    });
  });

  it.each([
    {},
    { schemaVersion: 4, operation: 'assets.search', query: 'TON', chains: [], pageSize: 10 },
    {
      semanticFrame: { operation: 'transactions.list' },
      accountSelector: { kind: 'current' },
      reads: [],
    },
  ])('rejects malformed or legacy arguments before materialization', async (argumentsValue) => {
    const fetchPastActivities = jest.fn(defaultFetchPastActivities);
    const { dispatcher, session } = setup({ fetchPastActivities });
    const call = {
      ...queryCall(session, positionsListArgs()),
      arguments: argumentsValue,
    } as unknown as AgentToolCall;

    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected',
      error: { code: 'validation_failed', retryable: false },
    });
    expect(fetchPastActivities).not.toHaveBeenCalled();
  });

  it.each([
    'b'.repeat(16),
    `${'b'.repeat(12)}…${'b'.repeat(12)}`,
  ])('rejects a shortened or ellipsized transaction detail hash', async (hash) => {
    const fetchPastActivities = jest.fn(defaultFetchPastActivities);
    const { dispatcher, session } = setup({ fetchPastActivities });
    const call = queryCall(session, transactionDetailArgs(hash));

    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({
      status: 'rejected',
      error: { code: 'validation_failed', retryable: false },
    });
    expect(fetchPastActivities).not.toHaveBeenCalled();
  });

  it('returns reason-only clarification for an ambiguous wallet name', async () => {
    const host = hostContext();
    host.accounts[1].label = 'Duplicate';
    host.accounts.push(secondaryAccount('account-three', 'Duplicate'));
    const { dispatcher, session } = setup({ host });
    const call = queryCall(session, {
      ...positionsListArgs(),
      accountSelector: { kind: 'named', label: 'Duplicate' },
    });

    const result = await dispatcher.execute(call, execution());

    expect(result).toMatchObject({
      status: 'success',
      toolName: 'wallet.data.query',
      result: {
        result: {
          operation: 'positions.list',
          status: 'scope_resolution_required',
          reason: 'ambiguous',
        },
      },
    });
    if (result.status !== 'success' || result.toolName !== 'wallet.data.query') {
      throw new Error('Expected a wallet query result');
    }
  });

  it('resolves a saved-recipient Send form', () => {
    const { actions, session } = setup({ host: hostContext() });
    const snapshot = session.snapshot();
    const addressRef = session.resolveWalletAddressRefs('account-savings', 'ton')!.addressRef;
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID,
      kind: 'send',
      labelCode: 'open_send',
      title: 'Review prepared action',
      effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId,
        revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!,
        activeNetwork: 'ton',
      },
      asset: { slug: 'toncoin', chain: 'ton' },
      recipient: { kind: 'savedAddress', addressRef },
      localDraftRequired: false,
      requiresConfirmation: false,
    };

    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-account-savings-private-address?token=toncoin',
    });
    expect(JSON.stringify(action)).not.toContain('EQ-account-savings-private-address');
  });

  it('asks the host for the most it can send only of a named asset', () => {
    const { actions, session } = setup({ host: hostContext() });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: { sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton' },
      asset: { slug: 'toncoin', chain: 'ton' },
      isMaxAmount: true,
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:?token=toncoin', isMaxAmount: true,
    });
    actions.registerAction(THREAD_ID, MESSAGE_ID, { ...action, asset: undefined });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
  });

  it('opens a Send form with the recipient and comment when the wallet lacks the requested asset', () => {
    const host = hostContext();
    host.accounts[0].holdings = [];
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const addressRef = session.resolveWalletAddressRefs('account-savings', 'ton')!.addressRef;
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: { sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton' },
      recipient: { kind: 'savedAddress', addressRef },
      comment: 'Coffee',
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-account-savings-private-address?text=Coffee',
    });
    actions.registerAction(THREAD_ID, MESSAGE_ID, { ...action, comment: undefined });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-account-savings-private-address',
    });
    actions.registerAction(THREAD_ID, MESSAGE_ID, { ...action, recipient: undefined, comment: 'Coffee for mom+dad' });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:?text=Coffee%20for%20mom%2Bdad',
    });
    actions.registerAction(THREAD_ID, MESSAGE_ID, {
      ...action, recipient: { kind: 'savedAddress', addressRef: 'unknown-ref' },
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
  });

  it('opens an unfilled Send form without holdings', () => {
    const host = hostContext();
    host.accounts[0].holdings = [];
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: { sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton' },
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'sendForm', url: 'mtw://send' });
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({ status: 'active' });
    actions.registerAction(THREAD_ID, MESSAGE_ID, { ...action, amount: '3' });
    expect(actions.resolveAction(MESSAGE_ID, action.id))
      .toEqual({ kind: 'inactive' });
    host.activeAccountId = 'account-savings';
    session.update(host);
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'sendForm', url: 'mtw://send' });
  });

  it.each([
    [false, false],
    [false, true],
    [true, false],
    [true, true],
  ])('resolves Android Send forms with view-only=%s, asset=%s', (isViewOnly, hasAsset) => {
    const host = hostContext();
    host.platform = 'android';
    host.uiCapabilities = hostUiCapabilities('android');
    host.client = 'native';
    host.accounts[0].isViewOnly = isViewOnly;
    host.accounts[0].accountType = isViewOnly ? 'viewOnly' : 'regular';
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton',
      },
      ...(hasAsset ? { asset: { slug: 'toncoin', chain: 'ton' } } : {}),
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    if (isViewOnly) {
      expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
      expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    } else {
      expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
        kind: 'sendForm', url: hasAsset ? 'mtw://send/ton:?token=toncoin' : 'mtw://send',
      });
      expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({ status: 'active' });
    }
  });

  it('keeps Send inactive on a view-only wallet and opens it after a switch to one that can send', () => {
    const host = hostContext();
    host.accounts[0].isViewOnly = true;
    host.accounts[0].accountType = 'viewOnly';
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton',
      },
      asset: { slug: 'toncoin', chain: 'ton' }, amount: '5',
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });

    host.activeAccountId = 'account-savings';
    session.update(host);

    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:?token=toncoin&amount=5000000000',
    });
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({ status: 'active' });
  });

  it('opens Send using a contact saved in a different profile wallet', () => {
    const host = hostContext();
    host.accounts[1].savedAddresses = [{
      id: 'secondary-recipient', name: 'Studio', chain: 'ton', address: 'EQ-studio-private-address',
    }];
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const addressRef = session.resolveSavedAddressRefs(host.accounts[1].accountId, 'secondary-recipient')!.addressRef;
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton',
      },
      asset: { slug: 'toncoin', chain: 'ton' }, recipient: { kind: 'savedAddress', addressRef },
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-studio-private-address?token=toncoin',
    });
    host.accounts[1].savedAddresses = [];
    session.update(host);
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
  });

  it.each([
    [{ kind: 'address', chain: 'ton', address: 'EQ-user-authored-address' }, 'EQ-user-authored-address'],
    [{ kind: 'domain', chain: 'ton', domain: 'mother.ton' }, 'mother.ton'],
    [{ kind: 'address', chain: 'ton', address: `0:${'ab'.repeat(32)}` }, `0:${'ab'.repeat(32)}`],
  ] as const)('resolves a live Send-form action with a direct recipient', (recipient, toAddress) => {
    const { actions, session } = setup();
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID,
      kind: 'send',
      labelCode: 'open_send',
      title: 'Review prepared action',
      effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId,
        revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!,
        activeNetwork: 'ton',
      },
      asset: { slug: 'toncoin', chain: 'ton' },
      recipient,
      localDraftRequired: false,
      requiresConfirmation: false,
    };

    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm',
      url: `mtw://send/ton:${toAddress}?token=toncoin`,
    });
  });

  it('resolves a zero-balance Send-form asset on another supported account chain without a recipient', () => {
    const host = hostContext();
    host.accounts[0].chains.push('ethereum');
    host.accounts[0].addresses.ethereum = '0x-account-main-private-address';
    host.accounts[0].holdings.push({
      asset: { slug: 'ethereum', chain: 'ethereum', symbol: 'ETH', name: 'Ethereum', decimals: 18 },
      balance: '0',
      availableBalance: '0',
      valuationStatus: 'unpriced',
    });
    host.assetCatalog!.push({
      slug: 'ethereum', chain: 'ethereum', symbol: 'ETH', name: 'Ethereum', decimals: 18,
    });
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID,
      kind: 'send',
      labelCode: 'open_send',
      title: 'Review prepared action',
      effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId,
        revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!,
        activeNetwork: 'ton',
      },
      asset: { slug: 'ethereum', chain: 'ethereum' },
      localDraftRequired: false,
      requiresConfirmation: false,
    };

    action.amount = '7.25';
    action.comment = 'Invoice & delivery';
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm',
      url: 'mtw://send/ethereum:?token=ethereum&amount=7250000000000000000&text=Invoice%20%26%20delivery',
    });
  });

  it('resolves a cross-network Send-form action from the selected asset', () => {
    const host = hostContext();
    const ethereumAsset = {
      slug: 'ethereum', chain: 'ethereum' as const, symbol: 'ETH', name: 'Ethereum', decimals: 18,
    };
    host.assetCatalog!.push(ethereumAsset);
    host.accounts[0].chains.push('ethereum');
    host.accounts[0].addresses.ethereum = '0x1234567890123456789012345678901234567890';
    host.accounts[0].holdings.push({
      asset: ethereumAsset,
      balance: '0',
      availableBalance: '0',
      valuationStatus: 'unpriced',
    });
    const { actions, session } = setup({ host });
    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID,
      kind: 'send',
      labelCode: 'open_send',
      title: 'Review prepared action',
      effect: 'open_send',
      contextBinding: {
        sessionId: snapshot.sessionId,
        revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!,
        activeNetwork: 'tron',
      },
      asset: { slug: 'ethereum', chain: 'ethereum' },
      recipient: {
        kind: 'address',
        chain: 'ethereum',
        address: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      },
      localDraftRequired: false,
      requiresConfirmation: false,
    };

    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({
      kind: 'send',
      status: 'active',
      network: 'ethereum',
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm',
      url: 'mtw://send/ethereum:0xabcdefabcdefabcdefabcdefabcdefabcdefabcd?token=ethereum',
    });
    actions.registerAction(THREAD_ID, MESSAGE_ID, {
      ...action,
      recipient: { kind: 'address', chain: 'ton', address: 'EQ-user-recipient' },
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    actions.registerAction(THREAD_ID, MESSAGE_ID, {
      ...action,
      asset: { slug: 'unknown-ethereum-token', chain: 'ethereum' },
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toEqual({ kind: 'inactive' });
  });

  it('opens Send for an asset whether or not the host has loaded the balances that hold it', async () => {
    const host = hostContext();
    host.accounts[0].holdings = [];
    host.accounts[0].domainStates = { ...freshDomainStates(), fungible: { state: 'notLoaded' } };
    const refreshWalletHoldings = jest.fn().mockResolvedValue(new Map([['account-main', {
      byChain: { ton: { toncoin: 0n } }, failedChains: [],
    }]]));
    const { actions, dispatcher, session } = setup({ host, refreshWalletHoldings });
    const result = await dispatcher.execute(queryCall(session, {
      ...positionsListArgs(), chains: ['ton'], positionKinds: ['fungible'],
      riskMode: 'all', visibilityMode: 'all', includeZero: true,
    }), execution());
    if (result.status !== 'success' || result.toolName !== 'wallet.data.query'
      || result.result.result.operation !== 'positions.list' || result.result.result.status !== 'resolved') {
      throw new Error('Expected resolved positions');
    }
    const found = result.result.result.positions.find(({ asset }) => asset?.slug === 'toncoin')?.asset;
    expect(refreshWalletHoldings).toHaveBeenCalledTimes(1);
    expect(found).toMatchObject({ slug: 'toncoin', chain: 'ton' });

    const snapshot = session.snapshot();
    const action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> = {
      id: SEND_ACTION_ID, kind: 'send', labelCode: 'open_send', title: 'Open Send', effect: 'open_send',
      contextBinding: { sessionId: snapshot.sessionId, revision: snapshot.revision,
        activeAccountRef: snapshot.accountRefs.get('account-main')!, activeNetwork: 'ton' },
      asset: { slug: found!.slug, chain: found!.chain },
      recipient: {
        kind: 'savedAddress', addressRef: session.resolveSavedAddressRefs('account-main', 'alice')!.addressRef,
      },
      localDraftRequired: false, requiresConfirmation: false,
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, action);
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({
      kind: 'send', status: 'active', network: 'ton', recipient: { kind: 'savedAddress', label: 'Alice' },
    });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-alice-private-address?token=toncoin',
    });

    const usdtAction = {
      ...action, id: ACTION_ID, asset: { slug: 'usdton', chain: 'ton' as const }, amount: '1.5',
    };
    actions.registerAction(THREAD_ID, MESSAGE_ID, usdtAction);
    expect(actions.getActionPresentation(MESSAGE_ID, usdtAction.id)).toMatchObject({
      status: 'active', amount: { value: '1.5', symbol: 'USDT' },
    });
    for (const amount of [undefined, '5']) {
      actions.registerAction(THREAD_ID, MESSAGE_ID, {
        ...usdtAction, asset: { ...usdtAction.asset, tokenAddress: 'EQ-other-jetton' }, amount,
      });
      expect(actions.getActionPresentation(MESSAGE_ID, usdtAction.id)).toEqual({ kind: 'inactive' });
    }
    actions.registerAction(THREAD_ID, MESSAGE_ID, usdtAction);

    session.update({ ...host, accounts: [{
      ...host.accounts[0],
      holdings: hostContext().accounts[0].holdings,
      nftLoadedChains: [...getSupportedChains()],
      domainStates: freshDomainStates(),
    }, host.accounts[1]] });
    expect(session.snapshot().revision).toBe(snapshot.revision);
    expect(actions.getActionPresentation(MESSAGE_ID, action.id)).toMatchObject({ status: 'active' });
    actions.registerAction(THREAD_ID, MESSAGE_ID, { ...action, amount: '2' });
    expect(actions.resolveAction(MESSAGE_ID, action.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-alice-private-address?token=toncoin&amount=2000000000',
    });
    expect(actions.resolveAction(MESSAGE_ID, usdtAction.id)).toEqual({
      kind: 'sendForm', url: 'mtw://send/ton:EQ-alice-private-address?token=usdton&amount=1500000',
    });
  });

  it('fits a large query response to the exact 98,304-byte contract budget', async () => {
    const { dispatcher, session } = setup({ host: largeHostContext() });
    const call = queryCall(session, {
      ...positionsListArgs(),
      positionKinds: ['nft'],
      riskMode: 'all',
    });

    const result = await dispatcher.execute(call, execution());

    expect(result.status).toBe('success');
    expect(serializedByteLength(result)).toBeLessThanOrEqual(MAX_RESULT_BYTES);
    if (result.status !== 'success' || result.toolName !== 'wallet.data.query') {
      throw new Error('Expected a fitted wallet query result');
    }
    const queryResult = result.result.result;
    if (queryResult.operation !== 'positions.list' || queryResult.status !== 'resolved') {
      throw new Error('Expected resolved positions');
    }
    expect(result.result.redaction.maxResultBytes).toBe(MAX_RESULT_BYTES);
    expect(queryResult.positions.length).toBeLessThan(100);
    expect(queryResult.coverage).toMatchObject({
      status: 'partial',
      rowsOmitted: expect.any(Number),
      limitations: expect.arrayContaining(['row_limit']),
    });
  });

  it('returns result_too_large without a payload when even the minimal result exceeds a small budget', async () => {
    const { dispatcher, session } = setup();
    const call = queryCall(session, positionsListArgs());
    call.maxResultBytes = 512;

    const result = await dispatcher.execute(call, execution());

    expect(result).toMatchObject({
      status: 'rejected',
      error: { code: 'result_too_large', retryable: false },
    });
    expect(result).not.toHaveProperty('result');
    expect(JSON.stringify(result)).not.toContain('EQ-main-private-address');
  });

  it('returns a contract-valid tool failure when a history source throws an unexpected error', async () => {
    const { dispatcher, session } = setup({
      fetchPastActivities: () => Promise.reject(new Error('Source unavailable')),
    });

    await expect(dispatcher.execute(queryCall(session, transactionsListArgs()), execution())).resolves.toMatchObject({
      status: 'error',
      error: { code: 'tool_failed', retryable: true },
    });
  });

  it('propagates the runtime signal through wallet query and returns abort as cancelled', async () => {
    let markStarted!: () => void;
    let sourceSignal: AbortSignal | undefined;
    let isFirstCall = true;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    const fetchPastActivities = jest.fn((
      _accountId: string,
      _limit: number,
      _tokenSlug?: string,
      _toTimestamp?: number,
      options?: { signal?: AbortSignal; shouldThrowOnError?: boolean },
    ): Promise<{ activities: ApiActivity[]; hasMore: boolean } | undefined> => {
      sourceSignal = options?.signal;
      if (isFirstCall) {
        isFirstCall = false;
        markStarted();
        return new Promise(() => undefined);
      }
      return Promise.resolve({ activities: [], hasMore: false });
    });
    const { dispatcher, session } = setup({ fetchPastActivities });
    const call = queryCall(session, transactionsListArgs());
    const controller = new AbortController();
    const context = { ...execution(), signal: controller.signal };
    const first = dispatcher.execute(call, context);
    await started;

    expect(sourceSignal).toBe(controller.signal);
    controller.abort(new Error('parent stopped'));

    await expect(first).resolves.toMatchObject({
      status: 'cancelled',
      error: { code: 'tool_failed', retryable: true },
    });
    await expect(dispatcher.execute(call, execution())).resolves.toMatchObject({ status: 'success' });
    expect(fetchPastActivities).toHaveBeenCalledTimes(2);
  });
});

function setup(options: SetupOptions = {}) {
  const session = new AgentV2WalletSession();
  const host = options.host ?? hostContext();
  session.update(host);
  session.updateFeatureCapabilities(featureCapabilities());
  const dispatcher = new AgentV2WalletToolDispatcher({
    session,
    getConsent: options.getConsent ?? (() => Promise.resolve(true)),
    randomUuid: options.randomUuid ?? (() => RESULT_ID),
    now: options.now ?? (() => NOW_MS),
    fetchPastActivities: options.fetchPastActivities ?? defaultFetchPastActivities,
    fetchActivityDetails: options.fetchActivityDetails ?? defaultFetchActivityDetails,
    getTokenBySlug: options.getTokenBySlug,
    refreshWalletHoldings: options.refreshWalletHoldings,
  });
  const actions = new AgentV2ActionResolver(session, options.now ?? (() => NOW_MS));
  return { actions, dispatcher, host, session };
}

function directoryCall(
  session: AgentV2WalletSession,
): Extract<AgentToolCall, { name: 'wallet.directory.query' }> {
  const snapshot = session.snapshot();
  const active = snapshot.host!.accounts.find(({ accountId }) => accountId === snapshot.host!.activeAccountId)!;
  const activeAccountRef = snapshot.accountRefs.get(active.accountId)!;
  return {
    id: TOOL_CALL_ID,
    name: 'wallet.directory.query',
    arguments: { schemaVersion: 1, purpose: 'send_wallet_resolution' },
    scopes: ['wallet.directory.read'],
    timeoutMs: 30_000,
    maxResultBytes: 32_768,
    directorySession: {
      sessionId: snapshot.sessionId,
      revision: snapshot.revision,
      activeAccountRef,
    },
    directoryGrant: {
      schemaVersion: 1,
      kind: 'send_wallet_resolution',
      sourceCapabilityId: 'wallet.send-prepare',
      messageId: MESSAGE_ID,
      sessionId: snapshot.sessionId,
      revision: snapshot.revision,
    },
    intentSource: { kind: 'userMessage', messageId: MESSAGE_ID },
  };
}

function featureCapabilities(
  digest = contractManifest.walletFilterCatalogSha256,
): AgentFeatureCapabilitiesResponseV2 {
  return {
    protocolVersion: 3,
    walletQuery: {
      status: 'available',
      filterCatalog: { version: 1, digest, requiresClientTimeZone: true },
    },
    problemReport: { status: 'available' },
  };
}

function execution(threadId = THREAD_ID) {
  return {
    messageId: MESSAGE_ID,
    runId: RUN_ID,
    threadId,
    signal: new AbortController().signal,
  };
}

function queryCall(
  session: AgentV2WalletSession,
  args: AgentWalletDataQueryArgs,
): Extract<AgentToolCall, { name: 'wallet.data.query' }> {
  const snapshot = session.snapshot();
  const activeAccount = snapshot.host!.accounts.find(({ accountId }) => (
    accountId === snapshot.host!.activeAccountId
  ))!;
  const accountScope = getQueryAccountScope(args);
  return {
    id: TOOL_CALL_ID,
    name: 'wallet.data.query',
    arguments: args,
    scopes: ['wallet.data.read'],
    timeoutMs: 30_000,
    maxResultBytes: MAX_RESULT_BYTES,
    walletContextSession: {
      sessionId: snapshot.sessionId,
      revision: snapshot.revision,
      accountScope,
      activeAccountRef: snapshot.accountRefs.get(activeAccount.accountId)!,
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

function swapAction(
  session: AgentV2WalletSession,
): Extract<AgentV2LiveAction, { kind: 'swap' }> {
  const snapshot = session.snapshot();
  return {
    id: ACTION_ID,
    schemaVersion: 2,
    kind: 'swap',
    labelCode: 'open_swap',
    title: 'Review prepared action',
    effect: 'open_swap',
    url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
    contextBinding: {
      sessionId: snapshot.sessionId,
      revision: snapshot.revision,
      activeAccountRef: snapshot.accountRefs.get(snapshot.host!.activeAccountId!)!,
    },
    sourceAsset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
    destinationAsset: { slug: 'usdton', chain: 'ton', symbol: 'USDT', decimals: 6 },
    amount: { value: '10', valueType: 'decimal', side: 'source' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function persistedSwapAction(
  action: Extract<AgentV2LiveAction, { kind: 'swap' }>,
): Extract<AgentPersistedActionV2, { kind: 'swap' }> {
  return {
    id: action.id,
    schemaVersion: 2,
    kind: 'swap',
    labelCode: 'open_swap',
    title: 'Review prepared action',
    effect: 'open_swap',
    url: action.url,
    sourceAsset: action.sourceAsset,
    destinationAsset: action.destinationAsset,
    amount: action.amount,
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function getQueryAccountScope(args: AgentWalletDataQueryArgs) {
  if (args.operation === 'assets.search' || args.accountSelector.kind === 'current') return 'current' as const;
  if (args.accountSelector.kind === 'explicitAll') return 'explicitAll' as const;
  return 'selected' as const;
}

function getQueryVariants(): QueryVariant[] {
  return [
    {
      operation: 'account.inventory',
      args: {
        operation: 'account.inventory',
        accountSelector: { kind: 'explicitAll' },
        chains: [],
      },
      expected: {
        resolvedScope: { kind: 'explicitAll' },
        accounts: [
          expect.objectContaining({ kind: 'account', accountLabel: 'Main', isCurrent: true }),
          expect.objectContaining({ kind: 'account', accountLabel: 'Savings', isCurrent: false }),
        ],
      },
    },
    {
      operation: 'positions.list',
      args: positionsListArgs(),
      expected: {
        resolvedScope: { kind: 'current' },
        policySummary: {
          riskMode: 'exclude',
          visibilityMode: 'visible',
          spamMatches: { count: 1, accuracy: 'exact' },
          hiddenMatches: { count: 0, accuracy: 'exact' },
        },
        positions: [expect.objectContaining({
          kind: 'position',
          asset: expect.objectContaining({ slug: 'toncoin' }),
          quantity: '5',
          availableQuantity: '4.5',
          valuationStatus: 'valued',
          fiatValue: '25.5',
          baseCurrency: 'USD',
        })],
      },
    },
    {
      operation: 'portfolio.aggregate',
      args: {
        operation: 'portfolio.aggregate',
        accountSelector: { kind: 'current' },
        chains: [],
        range: '3m',
        groupBy: ['asset'],
        riskMode: 'exclude',
        visibilityMode: 'visible',
      },
      expected: {
        total: { value: '25.5', baseCurrency: 'USD', unpricedCount: 0 },
        allocations: [expect.objectContaining({ value: '25.5', percent: '100' })],
        aggregates: [expect.objectContaining({ groupKind: 'asset', value: '25.5' })],
        series: [],
      },
    },
    {
      operation: 'transactions.list',
      args: transactionsListArgs(),
      expected: {
        appliedFilterDigest: expect.stringMatching(/^[0-9a-f]{64}$/u),
        transactions: [expect.objectContaining({
          kind: 'transaction',
          direction: 'incoming',
          status: 'completed',
          asset: expect.objectContaining({ slug: 'toncoin' }),
          quantity: '1.25',
          safeDescription: 'Received 1.25 TON',
        })],
      },
    },
    {
      operation: 'transactions.detail',
      args: transactionDetailArgs(FULL_TRANSACTION_HASH),
      expected: {
        transaction: expect.objectContaining({
          kind: 'transaction',
          direction: 'incoming',
          status: 'completed',
          asset: expect.objectContaining({ slug: 'toncoin' }),
          quantity: '1.25',
        }),
      },
    },
    {
      operation: 'contacts.list',
      args: {
        operation: 'contacts.list',
        accountSelector: { kind: 'current' },
        query: 'Alice',
        chains: ['ton'],
        ownWalletChains: ['ton'],
        pageSize: 100,
      },
      expected: {
        contacts: [expect.objectContaining({
          kind: 'contact',
          name: 'Alice',
          contactRef: expect.any(String),
          addressRef: expect.any(String),
          addressDisplay: expect.not.stringContaining('EQ-alice-private-address'),
        })],
      },
    },
    {
      operation: 'value.series',
      args: {
        operation: 'value.series',
        accountSelector: { kind: 'current' },
        chains: [],
        metric: 'portfolio_value',
        assetSelectors: [],
        range: '3m',
        maxPoints: 64,
      },
      expected: {
        baseCurrency: 'USD',
        historyAccounts: [expect.objectContaining({ wallets: ['ton:EQ-main-private-address'] })],
        series: [],
      },
    },
  ];
}

function assetsSearchArgs(query: string): AgentWalletDataQueryArgs {
  return {
    operation: 'assets.search',
    query,
    chains: [],
    pageSize: 10,
  };
}

function positionsListArgs(): Extract<AgentWalletDataQueryArgs, { operation: 'positions.list' }> {
  return {
    operation: 'positions.list',
    accountSelector: { kind: 'current' },
    chains: [],
    assetSelectors: [],
    positionKinds: ['fungible', 'nft', 'staking', 'vesting', 'vault'],
    riskMode: 'exclude',
    visibilityMode: 'visible',
    includeZero: false,
    sort: 'wallet_order',
    pageSize: 100,
  };
}

function transactionsListArgs(): Extract<AgentWalletDataQueryArgs, { operation: 'transactions.list' }> {
  return {
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
  };
}

function transactionDetailArgs(
  hash: string,
): Extract<AgentWalletDataQueryArgs, { operation: 'transactions.detail' }> {
  return {
    operation: 'transactions.detail',
    accountSelector: { kind: 'current' },
    hash,
  };
}

function defaultFetchPastActivities() {
  return Promise.resolve({ activities: [transactionActivity()], hasMore: false });
}

function defaultFetchActivityDetails(_accountId: string, activity: ApiActivity) {
  return Promise.resolve(activity);
}

function transactionActivity(): Extract<ApiActivity, { kind: 'transaction' }> {
  return {
    kind: 'transaction',
    id: `${FULL_TRANSACTION_HASH}:0`,
    externalMsgHashNorm: FULL_TRANSACTION_HASH,
    timestamp: Date.parse('2026-08-10T10:00:00.000Z'),
    status: 'completed',
    amount: 1_250_000_000n,
    fee: 1_000n,
    fromAddress: 'EQ-external-private-address',
    toAddress: 'EQ-main-private-address',
    normalizedAddress: 'EQ-main-private-address',
    slug: 'toncoin',
    isIncoming: true,
  };
}

function hostContext(): AgentV2HostContextSnapshot {
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    currencyRate: '1',
    timeZone: 'Europe/Moscow',
    activeAccountId: 'account-main',
    activeNetwork: 'ton',
    isTestnet: false,
    assetCatalog: [
      {
        slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9,
        priceUsd: '2.5', percentChange24h: '-1.25',
      },
      { slug: 'spam-token', chain: 'ton', symbol: 'SPAM', name: 'Spam Token', decimals: 9 },
      { slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6 },
    ],
    accounts: [
      {
        accountId: 'account-main',
        label: 'Main',
        state: 'active',
        accountType: 'regular',
        isViewOnly: false,
        chains: ['ton'],
        addresses: { ton: 'EQ-main-private-address' },
        portfolioWalletKeys: ['ton:EQ-main-private-address'],
        holdings: [
          {
            asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9 },
            balance: '5',
            availableBalance: '4.5',
            fiatValue: '25.5',
            valuationStatus: 'valued',
          },
          {
            asset: { slug: 'spam-token', chain: 'ton', symbol: 'SPAM', name: 'Spam Token', decimals: 9 },
            balance: '1000000',
            fiatValue: '999999',
            valuationStatus: 'valued',
            riskVerdict: 'spam',
          },
        ],
        savedAddresses: [
          { id: 'alice', name: 'Alice', chain: 'ton', address: 'EQ-alice-private-address' },
        ],
        nftLoadedChains: [...getSupportedChains()],
        domainStates: freshDomainStates(),
      },
      secondaryAccount('account-savings', 'Savings'),
    ],
    savedAddresses: [],
  };
}

function swapHostContext(): AgentV2HostContextSnapshot {
  return {
    ...hostContext(),
    isTestnet: false,
    swapAssetCatalog: [
      {
        slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: '2.5',
      },
      {
        slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6, priceUsd: '1',
      },
    ],
  };
}

function secondaryAccount(accountId: string, label: string) {
  return {
    accountId,
    label,
    state: 'active' as const,
    accountType: 'regular' as const,
    isViewOnly: false,
    chains: ['ton'],
    addresses: { ton: `EQ-${accountId}-private-address` },
    portfolioWalletKeys: [`ton:EQ-${accountId}-private-address`],
    holdings: [{
      asset: { slug: 'usdton', chain: 'ton' as const, symbol: 'USDT', name: 'Tether USD', decimals: 6 },
      balance: '50',
      fiatValue: '50',
      valuationStatus: 'valued' as const,
    }],
    savedAddresses: [{
      id: `${accountId}-contact`,
      name: `${label} Contact`,
      chain: 'ton' as const,
      address: `EQ-${accountId}-contact-private-address`,
    }],
    nftLoadedChains: [...getSupportedChains()],
    domainStates: freshDomainStates(),
  };
}

function freshDomainStates() {
  return {
    accounts: { state: 'fresh' as const },
    fungible: { state: 'fresh' as const },
    staking: { state: 'fresh' as const },
    vesting: { state: 'fresh' as const },
    vault: { state: 'fresh' as const },
    transactions: { state: 'fresh' as const },
    contacts: { state: 'fresh' as const },
    value_series: { state: 'fresh' as const },
  };
}

function largeHostContext(): AgentV2HostContextSnapshot {
  const host = hostContext();
  host.accounts[0].label = 'M'.repeat(80);
  host.accounts[0].holdings = [];
  host.accounts[0].positions = Array.from({ length: 100 }, (_, index) => ({
    id: `nft-${index}-${'i'.repeat(120)}`,
    kind: 'nft' as const,
    chain: 'ton',
    label: `Collectible ${index} ${'Ж'.repeat(140)}`,
    asset: {
      slug: `asset-${index}-${'s'.repeat(110)}`,
      chain: 'ton',
      symbol: `NFT${index}${'x'.repeat(24)}`.slice(0, 32),
      name: `Asset ${index} ${'名'.repeat(145)}`.slice(0, 160),
      tokenAddress: `EQ${index}${'a'.repeat(250)}`.slice(0, 256),
      decimals: 0,
    },
    quantity: '1',
    valuationStatus: 'valued' as const,
    fiatValue: '1',
    status: 'active',
    collection: `Collection ${index} ${'界'.repeat(145)}`.slice(0, 160),
    isOnSale: true,
    riskVerdict: 'spam' as const,
  }));
  return host;
}

function serializedByteLength(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}
