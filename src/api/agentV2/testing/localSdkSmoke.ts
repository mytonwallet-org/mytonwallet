import type { Storage } from '../../storages/types';
import type {
  AgentEntryPoint,
  AgentRunRequestV2,
  AgentToolResultRequestV2,
  AgentWalletSnapshotV1,
} from '../protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2HostContextSnapshot,
  AgentV2RunCommandInput,
} from '../types';

import { getSupportedChains } from '../../../util/chain';
import { AgentV2Runtime } from '../runtime';
import { AgentV2WalletSession } from '../walletSession';
import { AgentV2WalletToolDispatcher } from '../walletTools';
import { hostUiCapabilities } from './hostUiCapabilities';

const originA = process.env.AGENT_V2_LOCAL_BASE_URL_A ?? 'http://127.0.0.1:3001';
const originB = process.env.AGENT_V2_LOCAL_BASE_URL_B ?? 'http://127.0.0.1:3002';
const baseUrl = `${originA}/api/v2`;
const smokeNonce = process.env.AGENT_V2_LOCAL_SMOKE_NONCE ?? 'default';
const PRIVATE_ADDRESS = `EQ-sdk-private-owner-address-${smokeNonce}`;
const PRIVATE_WATCH_ADDRESS = `EQ-sdk-private-watch-address-${smokeNonce}`;
const PRIVATE_CONTACT = 'EQ-sdk-private-contact-address';
const PRIVATE_CURRENT_BALANCE = '10.000000001';
const PRIVATE_WATCH_BALANCE = '0.125000009';
const PRIVATE_CURRENT_LABEL = 'SDK Wallet';
const PRIVATE_WATCH_LABEL = 'Watch Wallet';
const SNAPSHOT_UPLOAD_TIMEOUT_MS = 10_000;
const SNAPSHOT_ACK_SETTLE_MS = 50;

export async function run() {
  const updates: AgentV2ClientUpdate[] = [];
  const storage = memoryStorage();
  const session = new AgentV2WalletSession();
  let toolResultPosts = 0;
  let snapshotUploads = 0;
  let runsWithSnapshot = 0;
  const toolResultNames: string[] = [];
  const supportedChains = [...getSupportedChains()];
  let resolveSnapshotUpload: () => void;
  const snapshotUploaded = new Promise<void>((resolve) => {
    resolveSnapshotUpload = resolve;
  });
  const routedFetch: typeof fetch = async (input, init) => {
    const source = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const url = new URL(source);
    if (url.pathname.endsWith('/tool-results') || url.pathname.includes('/threads/')) {
      url.host = new URL(originB).host;
      url.protocol = new URL(originB).protocol;
    }
    if (url.pathname.endsWith('/tool-results')) {
      toolResultPosts += 1;
      if (typeof init?.body === 'string') {
        const body = JSON.parse(init.body) as AgentToolResultRequestV2;
        toolResultNames.push(body.toolName ?? 'unknown');
        if (body.status === 'success' && body.toolName === 'wallet.directory.query') {
          body.result.result.accounts.forEach(({ chains }) => {
            assertChains(chains, supportedChains, 'Directory');
          });
        }
      }
    }
    if (url.pathname.endsWith('/runs') && typeof init?.body === 'string') {
      const body = JSON.parse(init.body) as AgentRunRequestV2;
      assertChains(body.context.activeWalletChains!, supportedChains, 'Run context');
      assert(body.walletContext.mode === 'wallet', 'Run lost wallet context');
      assertChains(body.walletContext.activeAccount.chains, supportedChains, 'Run wallet authority');
      if (body.walletSnapshotRef) runsWithSnapshot += 1;
    }
    const isSnapshotUpload = url.pathname.endsWith('/wallet-snapshots') && init?.method === 'PUT';
    if (isSnapshotUpload && typeof init.body === 'string') {
      const body = JSON.parse(init.body) as AgentWalletSnapshotV1;
      body.accounts.forEach(({ chains }) => assertChains(chains, supportedChains, 'Snapshot'));
    }
    const response = await fetch(url, init);
    if (isSnapshotUpload) {
      assert(response.ok, `Full-catalog snapshot was rejected with HTTP ${response.status}`);
      const acknowledgement = await response.clone().json() as { snapshotRef?: unknown };
      assert(acknowledgement.snapshotRef, 'Snapshot acknowledgement is missing its reference');
      snapshotUploads += 1;
      resolveSnapshotUpload!();
    }
    return response;
  };
  const runtime = new AgentV2Runtime({
    storage,
    baseUrl,
    fetch: routedFetch,
    onUpdate: (update) => updates.push(update),
    walletSession: session,
  });
  const dispatcher = new AgentV2WalletToolDispatcher({
    session,
    getConsent: () => runtime.getConsent(),
  });
  runtime.setToolExecutor({
    execute: async (call, context) => {
      try {
        return await dispatcher.execute(call, context);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'unknown tool execution error';
        process.stderr.write(`Agent V2 SDK tool execution failed: ${message}\n`);
        throw error;
      }
    },
  });

  await runtime.acceptConsent();
  await runtime.updateHostContext(hostContext());
  const hints = await runtime.getHints('en');
  assert(hints.items.length === 5, 'Starter hints were not hydrated');

  await append(runtime, updates, 'Local SDK smoke question', { kind: 'agentTab' }, 'general');
  const beforeWalletReadPosts = toolResultPosts;
  await append(runtime, updates, 'How much TON do I hold?', { kind: 'globalSearch', query: 'TON' }, 'wallet-read');
  assertToolResults(toolResultNames, beforeWalletReadPosts, ['wallet.data.query'], 'Wallet read');

  const receiveHint = hints.items.find(({ id }) => id === 'receive.tokens');
  assert(receiveHint, 'Receive starter hint is missing');
  const beforeReceivePosts = toolResultPosts;
  await append(runtime, updates, 'Show me how to receive tokens.', {
    kind: 'emptyState',
    surface: 'agentTab',
    hintId: receiveHint.id,
    catalogVersion: hints.catalogVersion,
  }, 'receive');
  assert(toolResultPosts === beforeReceivePosts, 'Receive incorrectly used tool lifecycle');
  const receive = findLatestAction(updates, 'receive');
  assert(receive && runtime.resolveAction(receive.messageId, receive.action.id).kind === 'openReceive',
    'Receive action did not resolve on user gesture');

  await runtime.updateHostContext({
    ...hostContext(), platform: 'classic', uiCapabilities: hostUiCapabilities('classic'), client: 'web',
  });
  const beforeSendPosts = toolResultPosts;
  await append(runtime, updates, 'Send 1.5 TON to Mom', { kind: 'agentTab' }, 'send');
  const send = findLatestAction(updates, 'send');
  assert(send, 'Send action was not emitted');
  const sendPresentation = runtime.getActionPresentation(send.messageId, send.action.id);
  assert(sendPresentation.kind === 'send' && sendPresentation.status === 'active',
    'Classic Send action did not expose an active presentation');
  const sendResolution = runtime.resolveAction(send.messageId, send.action.id);
  assert(sendResolution.kind === 'sendForm' && sendResolution.url.startsWith('mtw://send/'),
    'Classic Send action did not resolve to wallet navigation');
  assertToolResults(toolResultNames, beforeSendPosts, [
    'wallet.directory.query',
    'wallet.data.query',
    'wallet.data.query',
  ], 'Send');
  await runtime.updateHostContext(hostContext());

  const beforePortfolioPosts = toolResultPosts;
  const beforePortfolioUpdates = updates.length;
  await append(runtime, updates, 'Analyze this portfolio', {
    kind: 'portfolioChart',
    chartId: 'sdk-local-portfolio',
    range: '3m',
    accountScope: 'current',
    source: 'analyzeIt',
  }, 'portfolio');
  const portfolioUpdates = updates.slice(beforePortfolioUpdates);
  const portfolioAnswer = portfolioUpdates
    .filter((update): update is Extract<AgentV2ClientUpdate, { kind: 'textDelta' }> => update.kind === 'textDelta')
    .map(({ delta }) => delta)
    .join('');
  assert(
    portfolioAnswer === 'Local Agent response.',
    `Portfolio chart response differs: ${summarizeUpdates(portfolioUpdates)}`,
  );
  assertToolResults(toolResultNames, beforePortfolioPosts, [], 'Portfolio');

  await runtime.updateHostContext({
    ...hostContext(), platform: 'classic', uiCapabilities: hostUiCapabilities('classic'), client: 'web',
  });
  const hydration = await currentHydration(runtime);
  const firstUser = hydration.messages.find(({ role }) => role === 'user');
  assert(firstUser, 'Hydration is missing the first user message');
  await runAgainstCurrentThread(runtime, updates, {
    input: { kind: 'edit', targetUserMessageId: firstUser.id, text: 'Edited local SDK smoke question' },
  }, 'edit');
  reportStage('edit passed');

  const defaultThread = await runtime.getDefaultThread();
  const repeatedHydration = await runtime.getMessages(defaultThread.thread.id);
  assert(repeatedHydration.thread.id === defaultThread.thread.id,
    'Repeated hydration changed the default thread binding');
  reportStage('default thread hydration passed');

  await runtime.setChatActive(true);
  await waitForSnapshotUpload(snapshotUploaded);
  await new Promise((resolve) => {
    setTimeout(resolve, SNAPSHOT_ACK_SETTLE_MS);
  });
  await append(runtime, updates, 'Full catalog snapshot question', { kind: 'agentTab' }, 'full-catalog-snapshot');
  assert(snapshotUploads > 0 && runsWithSnapshot > 0, 'Run did not reuse the acknowledged full-catalog snapshot');
  await runtime.setChatActive(false);
  reportStage('full catalog snapshot and run admission passed');

  const serializedUpdates = JSON.stringify(updates);
  assert(!serializedUpdates.includes(PRIVATE_ADDRESS), 'Raw wallet address escaped into UI updates');
  assert(!serializedUpdates.includes(PRIVATE_WATCH_ADDRESS), 'Raw watch address escaped into UI updates');
  assert(!serializedUpdates.includes(PRIVATE_CONTACT), 'Raw contact address escaped into UI updates');
  assert(!serializedUpdates.includes('adt_v2.'), 'Bearer token escaped into UI updates');

  const current = await runtime.getDefaultThread();
  await runtime.clearThread(current.thread.id, current.thread.revision);
  const cleared = await runtime.getMessages(current.thread.id);
  assert(cleared.messages.length === 0, 'Thread clear did not remove hydrated history');
  await runtime.destroy({ shouldClearPersistentIdentity: true });

  process.stdout.write(`${JSON.stringify({
    ok: true,
    replicaA: originA,
    replicaB: originB,
    toolResultPosts,
    toolResultNames,
    updateCount: updates.length,
    walletReadChecked: true,
    receiveResolved: true,
    sendDraftResolved: true,
    portfolioAnswered: true,
    classicEditChecked: true,
    defaultThreadChecked: true,
    privacyChecked: true,
    chainCount: supportedChains.length,
    fullCatalogSnapshotChecked: true,
  }, undefined, 2)}\n`);
}

async function append(
  runtime: AgentV2Runtime,
  updates: AgentV2ClientUpdate[],
  text: string,
  entryPoint: AgentEntryPoint,
  label: string,
) {
  return runAgainstCurrentThread(runtime, updates, { input: { kind: 'append', text }, entryPoint }, label);
}

async function runAgainstCurrentThread(
  runtime: AgentV2Runtime,
  updates: AgentV2ClientUpdate[],
  command: AgentV2RunCommandInput,
  label: string,
) {
  const updateOffset = updates.length;
  const current = await runtime.getDefaultThread();
  const result = await runtime.startRun({
    ...command,
    threadId: current.thread.id,
    expectedThreadRevision: current.thread.revision,
  });
  if (result.state !== 'completed') {
    const failure = [...updates.slice(updateOffset)].reverse().find((update) => update.kind === 'runFailed');
    const detail = failure?.kind === 'runFailed' ? ` (${failure.code})` : '';
    throw new Error(`${label} run ended as ${result.state}${detail}`);
  }
  return result;
}

async function currentHydration(runtime: AgentV2Runtime) {
  const current = await runtime.getDefaultThread();
  return runtime.getMessages(current.thread.id);
}

function findLatestAction(updates: AgentV2ClientUpdate[], kind: 'send' | 'receive') {
  return [...updates].reverse().find((update): update is Extract<AgentV2ClientUpdate, { kind: 'actionAvailable' }> => (
    update.kind === 'actionAvailable' && update.action.kind === kind
  ));
}

function hostContext(): AgentV2HostContextSnapshot {
  return {
    platform: 'ios', uiCapabilities: hostUiCapabilities('ios'),
    client: 'native',
    lang: 'en',
    baseCurrency: 'USD',
    isTestnet: false,
    activeAccountId: 'sdk-account-one',
    activeNetwork: 'ton',
    assetCatalog: [
      { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: '2.5' },
      { slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6, priceUsd: '1' },
    ],
    swapAssetCatalog: [
      { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: '2.5' },
      { slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6, priceUsd: '1' },
    ],
    accounts: [
      {
        accountId: 'sdk-account-one',
        label: PRIVATE_CURRENT_LABEL,
        state: 'active',
        accountType: 'regular',
        isViewOnly: false,
        chains: [...getSupportedChains()],
        addresses: Object.fromEntries(getSupportedChains().map((chain) => [chain, PRIVATE_ADDRESS])),
        savedAddresses: [{ id: 'mom', name: 'Mom', chain: 'ton', address: PRIVATE_CONTACT }],
        nftLoadedChains: [...getSupportedChains()],
        domainStates: {
          accounts: { state: 'fresh' },
          fungible: { state: 'fresh' },
          staking: { state: 'fresh' },
          vesting: { state: 'fresh' },
          vault: { state: 'fresh' },
          transactions: { state: 'stale' },
          value_series: { state: 'stale' },
          contacts: { state: 'fresh' },
        },
        holdings: [{
          asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9 },
          balance: PRIVATE_CURRENT_BALANCE,
          availableBalance: PRIVATE_CURRENT_BALANCE,
          fiatValue: '25',
          valuationStatus: 'valued',
        }],
      },
      {
        accountId: 'sdk-account-two',
        label: PRIVATE_WATCH_LABEL,
        state: 'active',
        accountType: 'viewOnly',
        isViewOnly: true,
        chains: [...getSupportedChains()],
        addresses: Object.fromEntries(getSupportedChains().map((chain) => [chain, PRIVATE_WATCH_ADDRESS])),
        nftLoadedChains: [...getSupportedChains()],
        domainStates: {
          accounts: { state: 'fresh' },
          fungible: { state: 'fresh' },
          staking: { state: 'fresh' },
          vesting: { state: 'fresh' },
          vault: { state: 'fresh' },
          transactions: { state: 'stale' },
          value_series: { state: 'unavailable' },
          contacts: { state: 'fresh' },
        },
        holdings: [{
          asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9 },
          balance: PRIVATE_WATCH_BALANCE,
          availableBalance: PRIVATE_WATCH_BALANCE,
          fiatValue: '0.3125',
          valuationStatus: 'valued',
        }],
      },
    ],
    savedAddresses: [{ id: 'mom', name: 'Mom', chain: 'ton', address: PRIVATE_CONTACT }],
  };
}

function memoryStorage(): Storage {
  const values = new Map<string, unknown>();
  return {
    getItem: (key) => Promise.resolve(values.get(key)),
    setItem(key, value) {
      values.set(key, value);
      return Promise.resolve();
    },
    removeItem(key) {
      values.delete(key);
      return Promise.resolve();
    },
    clear() {
      values.clear();
      return Promise.resolve();
    },
  };
}

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

function assertChains(actual: string[], expected: string[], stage: string) {
  assert(JSON.stringify(actual) === JSON.stringify(expected), `${stage} lost or reordered supported chains`);
}

async function waitForSnapshotUpload(uploaded: Promise<void>) {
  let timer: ReturnType<typeof setTimeout>;
  try {
    await Promise.race([uploaded, new Promise<never>((resolve, reject) => {
      timer = setTimeout(() => reject(new Error('Full-catalog snapshot upload did not finish')),
        SNAPSHOT_UPLOAD_TIMEOUT_MS);
    })]);
  } finally {
    clearTimeout(timer!);
  }
}

function assertToolResults(
  names: string[],
  offset: number,
  expected: string[],
  label: string,
) {
  const actual = names.slice(offset);
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${label} posted unexpected tool results: ${actual.join(', ') || 'none'}`,
  );
}

function summarizeUpdates(updates: AgentV2ClientUpdate[]) {
  return updates.map((update) => {
    if (update.kind === 'textDelta') return `text:${update.delta}`;
    if (update.kind === 'semanticContentAvailable') return `semantic:${update.content.kind}`;
    if (update.kind === 'runFailed') return `failed:${update.code}`;
    return update.kind;
  }).join('|').slice(0, 1_000);
}

function reportStage(message: string) {
  process.stdout.write(`Agent V2 SDK local smoke: ${message}\n`);
}
