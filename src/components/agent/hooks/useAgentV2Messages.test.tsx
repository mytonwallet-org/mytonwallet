import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type {
  AgentNewsFeedDiscussionNamingV2,
  AgentPersistedActionV2,
  AgentThreadClearResponseV2,
  AgentThreadNewsCardV2,
  AgentThreadSummaryV2,
  AgentV2LiveAction,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2HostContextSnapshot,
  AgentV2HydratedMessage,
  AgentV2MutationResult,
  AgentV2ResolvedAction,
  AgentV2RunResult,
  AgentV2StarterHints,
} from '../../../api/agentV2/types';
import type { LangFn } from '../../../hooks/useLang';
import type { AgentV2StarterHintEntryPoint } from './agentV2RunController';

import { buildAgentV2HostContext } from '../../../global/agentV2/buildHostContext';
import { buildAgentBuiltinDapps } from '../../../global/agentV2/builtinDapps';
import {
  agentThreadListListeners,
  dropAgentV2BackgroundQueue,
  forgetAgentV2ThreadDeletion,
  getAgentV2LocalState,
  holdAgentV2BackgroundQueue,
  resetAgentV2LocalState,
} from '../../../util/agent/agentV2LocalState';
import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
} from '../../../util/agentV2Updates';
import { parseDeeplinkTransferParams, processDeeplink } from '../../../util/deeplink';
import { openUrl } from '../../../util/openUrl';
import { pause, waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { hostUiCapabilities } from '../../../api/agentV2/testing/hostUiCapabilities';
import { getCanRequestAgentV2SupportFromList, requestAgentV2Support } from '../../agentV2/useAgentSuggestions';
import { openSite } from '../../explore/helpers/utils';
import * as agentV2RunController from './agentV2RunController';
import useAgentV2Messages, { type AgentV2ChatTarget, type UseAgentV2MessagesResult } from './useAgentV2Messages';

import Transition from '../../ui/Transition';

const mockOpenReceiveModal = jest.fn();
const mockSetSwapAmountIn = jest.fn();
const mockSetSwapAmountOut = jest.fn();
const mockStartStaking = jest.fn();
const mockStartSwap = jest.fn();
const mockStartTransfer = jest.fn();
const mockShowError = jest.fn();
const mockSwitchToWallet = jest.fn();
const FRAGMENT_SITE = {
  url: 'https://fragment.com/',
  name: 'Fragment',
  canBeRestricted: true,
  isExternal: false,
};
let mockExploreSites = [FRAGMENT_SITE];
let mockIsLimitedRegion = false;
let mockAccountState: { balances?: { bySlug: Record<string, bigint> } } = {};
let mockHasTokenInfo = false;
let mockSwapTokensBySlug: Record<string, { slug: string }> = {};

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../../util/deeplink', () => ({
  ...jest.requireActual('../../../util/deeplink'), processDeeplink: jest.fn(), parseDeeplinkTransferParams: jest.fn(),
}));
jest.mock('../../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../explore/helpers/utils', () => ({
  ...jest.requireActual('../../explore/helpers/utils'),
  openSite: jest.fn(),
}));
jest.mock('../../../global/agentV2/builtinDapps', () => ({ buildAgentBuiltinDapps: jest.fn(() => []) }));
jest.mock('../../../global/agentV2/buildHostContext', () => {
  // The hook reads the snapshot through the memoized selector, which the tests stub as the builder
  const buildAgentV2HostContext = jest.fn();
  return { buildAgentV2HostContext, selectAgentV2HostContext: buildAgentV2HostContext };
});
jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getGlobal: () => ({
    // What the wallet's balance is counted from
    ...(mockHasTokenInfo && (({
      tokenInfo, settings, currencyRates, stakingDefault,
    }) => ({ tokenInfo, settings, currencyRates, stakingDefault }))(
      jest.requireActual<typeof import('../../../global/initialState')>('../../../global/initialState').INITIAL_STATE,
    )),
    exploreData: { sites: mockExploreSites },
    restrictions: { isLimitedRegion: mockIsLimitedRegion },
    currentAccountId: '0-mainnet',
    byAccountId: { '0-mainnet': mockAccountState },
    swapTokenInfo: { bySlug: mockSwapTokensBySlug },
    // `Transition` reads the animation level
    ...(!mockHasTokenInfo && { settings: { animationLevel: 0 } }),
  }),
  getActions: () => ({
    openReceiveModal: mockOpenReceiveModal,
    setSwapAmountIn: mockSetSwapAmountIn,
    setSwapAmountOut: mockSetSwapAmountOut,
    startStaking: mockStartStaking,
    startSwap: mockStartSwap,
    showError: mockShowError,
    startTransfer: mockStartTransfer,
    switchToWallet: mockSwitchToWallet,
  }),
}));

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const REPLACEMENT_THREAD_ID = '11111111-1111-4111-8111-111111111112';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const NEXT_CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222223';
const MESSAGE_ID = '33333333-3333-4333-8333-333333333333';
const ASSISTANT_MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const RUN_ID = '55555555-5555-4555-8555-555555555555';
const INPUT_MESSAGE_ID = '99999999-9999-4999-8999-999999999991';
const OLDER_MESSAGE_ID = '99999999-9999-4999-8999-999999999992';
const SECOND_USER_MESSAGE_ID = '99999999-9999-4999-8999-999999999993';
const SECOND_ASSISTANT_MESSAGE_ID = '99999999-9999-4999-8999-999999999994';
const NEWS_TARGET: Extract<AgentV2ChatTarget, { kind: 'news' }> = {
  kind: 'news',
  news: { eventId: 7, locale: 'en' },
  preview: { eventId: 7, headline: 'Feed headline', publishedAt: '2026-10-21T10:00:00.000Z' },
};
const DIGEST = {
  id: 'digest-1', windowEnd: '2026-10-21T21:00:00.000Z', total: 2,
  top: [{ eventId: 7, headline: 'News headline' }],
};
const DIGEST_TARGET: Extract<AgentV2ChatTarget, { kind: 'digest' }> = {
  kind: 'digest', digest: { id: DIGEST.id }, digestPreview: DIGEST,
};
const DISCUSSIONS = ['news', 'digest'] as const;
const DISCUSSION_CREATION = { news: { news: NEWS_TARGET.news }, digest: { digest: DIGEST_TARGET.digest } };
const NEWS_FOLLOWUP = {
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  kind: 'suggested_prompt' as const,
  text: 'What does this mean?',
};
const STAKING_STARTER_HINTS: AgentV2StarterHints = {
  catalogVersion: 'agent-starter-hints-v2',
  items: [{ id: 'staking.yield', group: 'wallet' }],
};
const callApiMock = jest.mocked(callApi);
const buildAgentV2HostContextMock = jest.mocked(buildAgentV2HostContext);
const processDeeplinkMock = jest.mocked(processDeeplink);
const openUrlMock = jest.mocked(openUrl);
const openSiteMock = jest.mocked(openSite);
const lang = Object.assign(
  (key: string) => key === '$agent_error_conversation_updated'
    ? 'The conversation was updated. Please try the request again.'
    : key,
  { code: 'en' as const },
) as LangFn;

describe('useAgentV2Messages', () => {
  let root: HTMLDivElement;
  let result: UseAgentV2MessagesResult | undefined;
  let resolvedAction: unknown;
  let resolvedActionPromise: Promise<unknown> | undefined;
  let actionPresentationPromise: Promise<AgentV2ActionPresentation | undefined>;
  let clearThreadResponse:
    | AgentV2MutationResult<AgentThreadClearResponseV2>
    | Promise<AgentV2MutationResult<AgentThreadClearResponseV2> | undefined>
    | undefined;
  let starterHints: AgentV2StarterHints | undefined;
  let hydratedMessages: AgentV2HydratedMessage[];
  let hydrationNextCursor: string | undefined;
  let olderHydratedMessages: AgentV2HydratedMessage[];
  let olderNextCursor: string | undefined;
  let shouldFailOlderMessages: boolean;
  let hasAuthorityChanged: boolean | undefined;
  let isConsentAccepted: boolean;
  let isProblemReportAvailable: boolean;
  let problemReportAvailabilityPromise: Promise<boolean> | undefined;
  let retryRunResponse: AgentV2RunResult | Promise<AgentV2RunResult | undefined> | undefined;
  let startRunResponses: Array<AgentV2RunResult | Promise<AgentV2RunResult | undefined>>;
  let defaultThreadId: string;
  let threadRevision: number;
  let threadSupport: AgentThreadSummaryV2['support'];
  let createdThreadNews: AgentThreadNewsCardV2 | undefined;
  let createdThreadDigest: AgentThreadSummaryV2['digest'];
  let createThreadPromise: Promise<void> | undefined;

  beforeEach(() => {
    jest.mocked(buildAgentBuiltinDapps).mockReturnValue([]);
    root = document.createElement('div');
    document.body.appendChild(root);
    result = undefined;
    resolvedAction = undefined;
    resolvedActionPromise = undefined;
    actionPresentationPromise = Promise.resolve(undefined);
    clearThreadResponse = undefined;
    hydratedMessages = [persistedUserMessage()];
    hydrationNextCursor = undefined;
    olderHydratedMessages = [];
    olderNextCursor = undefined;
    shouldFailOlderMessages = false;
    hasAuthorityChanged = false;
    isConsentAccepted = true;
    isProblemReportAvailable = false;
    problemReportAvailabilityPromise = undefined;
    retryRunResponse = undefined;
    startRunResponses = [];
    defaultThreadId = THREAD_ID;
    threadRevision = 5;
    threadSupport = undefined;
    createdThreadNews = undefined;
    createdThreadDigest = undefined;
    createThreadPromise = undefined;
    mockOpenReceiveModal.mockReset();
    mockSetSwapAmountIn.mockReset();
    mockSetSwapAmountOut.mockReset();
    mockStartStaking.mockReset();
    mockStartSwap.mockReset();
    mockStartTransfer.mockReset();
    mockShowError.mockReset();
    mockSwitchToWallet.mockReset();
    mockAccountState = { balances: { bySlug: {} } };
    mockHasTokenInfo = false;
    mockSwapTokensBySlug = Object.fromEntries(['toncoin', 'usdton', 'trx'].map((slug) => [slug, { slug }]));
    mockExploreSites = [FRAGMENT_SITE];
    mockIsLimitedRegion = false;
    jest.mocked(parseDeeplinkTransferParams).mockReset();
    jest.mocked(parseDeeplinkTransferParams).mockReturnValue({ tokenSlug: 'toncoin', amount: 500000000n });
    processDeeplinkMock.mockReset();
    processDeeplinkMock.mockResolvedValue(true);
    openUrlMock.mockReset();
    openSiteMock.mockReset();
    buildAgentV2HostContextMock.mockReset();
    buildAgentV2HostContextMock.mockReturnValue(hostContext());
    callApiMock.mockReset();
    starterHints = undefined;
    callApiMock.mockImplementation((...args) => {
      const method = args[0];
      switch (method) {
        case 'getAgentV2Consent':
          return Promise.resolve(isConsentAccepted);
        case 'getAgentV2DefaultThread':
          return Promise.resolve({ ok: true, value: {
            protocolVersion: 3,
            thread: { ...threadSummary(threadRevision), id: defaultThreadId },
            created: false,
          } });
        case 'createAgentV2Thread':
          return (createThreadPromise ?? Promise.resolve()).then(() => ({ ok: true, value: {
            protocolVersion: 3,
            thread: {
              ...threadSummary(threadRevision),
              id: defaultThreadId,
              messageCount: hydratedMessages.length,
              ...(createdThreadNews && { news: createdThreadNews }),
              ...(createdThreadDigest && { digest: createdThreadDigest }),
            },
            created: true,
          } })) as never;
        case 'getAgentV2Messages':
          if (args[2]) {
            if (shouldFailOlderMessages) {
              return Promise.resolve({
                ok: false,
                error: { code: 'network_error', retryable: true },
              });
            }
            return Promise.resolve({
              ok: true,
              value: {
                thread: {
                  ...threadSummary(threadRevision), id: defaultThreadId,
                  news: createdThreadNews, digest: createdThreadDigest, support: threadSupport,
                },
                messages: olderHydratedMessages,
                nextCursor: olderNextCursor,
              },
            });
          }
          return Promise.resolve({
            ok: true,
            value: {
              thread: {
                ...threadSummary(threadRevision), id: defaultThreadId,
                news: createdThreadNews, digest: createdThreadDigest, support: threadSupport,
              },
              messages: hydratedMessages,
              nextCursor: hydrationNextCursor,
            },
          });
        case 'getAgentV2StarterHints':
          return Promise.resolve(starterHints);
        case 'getAgentV2Availability':
        case 'getAgentV2UserQuota':
          return Promise.resolve(undefined);
        case 'getAgentV2ProblemReportAvailability':
          return problemReportAvailabilityPromise ?? Promise.resolve(isProblemReportAvailable);
        case 'reportAgentV2Problem':
          return Promise.resolve({ ok: true, value: undefined }) as never;
        case 'startAgentV2Run':
          return Promise.resolve(startRunResponses.shift() ?? {
            clientRunId: CLIENT_RUN_ID,
            state: 'failed',
          }) as never;
        case 'retryAgentV2Run':
          return Promise.resolve(retryRunResponse) as never;
        case 'clearAgentV2Thread':
          return Promise.resolve(clearThreadResponse) as never;
        case 'getAgentV2ActionPresentation':
          return actionPresentationPromise as never;
        case 'updateAgentV2HostContext':
          return Promise.resolve({
            ok: true,
            value: { authorityChanged: Boolean(hasAuthorityChanged), generation: 1 },
          }) as never;
        case 'resolveAgentV2Action':
          return (resolvedActionPromise ?? Promise.resolve(resolvedAction)) as never;
        default:
          return Promise.resolve(undefined);
      }
    });
    cancelAgentV2ActiveRunReplays();
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    cancelAgentV2ActiveRunReplays();
    // A chat left in one test does not open with its history in the next
    resetAgentV2LocalState();
    jest.useRealTimers();
  });

  it('restores snapshot synchronization after runtime recovery and stops on unmount', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => (
      callApiMock.mock.calls.some(([method, active]) => method === 'setAgentV2ChatActive' && active === true)
    ), 10, 20)).toBe(true);
    callApiMock.mockClear();

    publishAgentV2Update({ kind: 'runtimeReady', generation: 104 });
    expect(await waitFor(() => (
      callApiMock.mock.calls.some(([method, active]) => method === 'setAgentV2ChatActive' && active === true)
    ), 10, 20)).toBe(true);

    TeactDOM.render(undefined, root);
    expect(callApiMock).toHaveBeenLastCalledWith('setAgentV2ChatActive', false);
    callApiMock.mockClear();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 105 });
    expect(callApiMock).not.toHaveBeenCalledWith('setAgentV2ChatActive', true);
  });

  it('keeps snapshot synchronization while the outgoing layout unmounts its chat after the incoming one', async () => {
    const incomingRoot = document.createElement('div');
    document.body.appendChild(incomingRoot);
    TeactDOM.render(<Harness />, root);
    TeactDOM.render(<Harness />, incomingRoot);
    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method, active]) => method === 'setAgentV2ChatActive' && active === true)
        .length === 2
    ), 10, 20)).toBe(true);

    TeactDOM.render(undefined, root);
    expect(callApiMock).toHaveBeenLastCalledWith('setAgentV2ChatActive', true);

    TeactDOM.render(undefined, incomingRoot);
    incomingRoot.remove();
    expect(callApiMock).toHaveBeenLastCalledWith('setAgentV2ChatActive', false);
  });

  it('keeps a chat on its thread while another thread changes', async () => {
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.messages.length === 1, 10, 20))
      .toBe(true);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2DefaultThread');
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', THREAD_ID);

    publishAgentV2Update({
      kind: 'threadChanged',
      threadId: REPLACEMENT_THREAD_ID,
      thread: { ...threadSummary(9), id: REPLACEMENT_THREAD_ID },
    });
    await pause(20);

    expect(result!.thread?.id).toBe(THREAD_ID);
    expect(result!.messages).toHaveLength(1);
  });

  it('keeps the answer still streaming in its thread when the chat opens again', async () => {
    publishAgentV2Update({
      kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Partial ' });

    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(await waitFor(() => result?.messages.at(-1)?.text === 'Partial ', 10, 20)).toBe(true);

    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'answer' });
    expect(await waitFor(() => result?.messages.at(-1)?.text === 'Partial answer', 10, 20)).toBe(true);
    expect(result!.messages.at(-1)?.isStreaming).toBe(true);
  });

  it.each([false, true])('resolves an opening thread even after unmount (%s)', async (shouldUnmount) => {
    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    let resolveCreate!: NoneToVoidFunction;
    callApiMock.mockImplementation((...args) => (args[0] === 'createAgentV2Thread'
      ? new Promise((resolve) => {
        resolveCreate = () => resolve(defaultImplementation(...args));
      }) as never
      : defaultImplementation(...args)));
    const onThreadResolved = jest.fn();
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} onThreadResolved={onThreadResolved} />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread'), 10, 20))
      .toBe(true);

    publishAgentV2Update({ kind: 'runtimeReady', generation: 108 });
    await pause(20);
    if (shouldUnmount) {
      TeactDOM.render(undefined, root);
      await pause(20);
    }
    resolveCreate();
    expect(await waitFor(() => onThreadResolved.mock.calls.length === 1, 10, 20)).toBe(true);
    expect(onThreadResolved).toHaveBeenCalledWith(REPLACEMENT_THREAD_ID);
    if (!shouldUnmount) {
      expect(await waitFor(() => result?.thread?.id === REPLACEMENT_THREAD_ID, 10, 20)).toBe(true);
    }

    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(onThreadResolved).toHaveBeenCalledTimes(1);
  });

  it('creates the thread of a new chat once and keeps it after the runtime restarts', async () => {
    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [];
    const onThreadResolved = jest.fn();
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} onThreadResolved={onThreadResolved} />, root);
    expect(await waitFor(() => result?.thread?.id === REPLACEMENT_THREAD_ID, 10, 20)).toBe(true);
    expect(onThreadResolved).toHaveBeenCalledWith(REPLACEMENT_THREAD_ID);

    callApiMock.mockClear();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 107 });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
      .toBe(true);

    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread');
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', REPLACEMENT_THREAD_ID);
    expect(onThreadResolved).toHaveBeenCalledTimes(1);
  });

  it('keeps the support entry inactive until the thread list loads', () => {
    expect(getCanRequestAgentV2SupportFromList(undefined)).toBe(false);
    expect(getCanRequestAgentV2SupportFromList([])).toBe(true);
  });

  it.each([false, true])('opens the freshest active support chat: freshest first=%s', async (isFreshestFirst) => {
    const latest = { ...threadSummary(5), id: REPLACEMENT_THREAD_ID, support: { state: 'operator' as const } };
    const older = {
      ...latest, id: THREAD_ID, isPinned: true as const,
      lastActivityAt: '2026-08-06T10:00:00.000Z', support: { state: 'waiting' as const },
    };
    defaultThreadId = REPLACEMENT_THREAD_ID;
    const openChat = jest.fn((target: AgentV2ChatTarget) => {
      TeactDOM.render(<TargetHarness target={target} />, root);
    });

    const items = isFreshestFirst ? [{ thread: latest }, { thread: older }] : [{ thread: older }, { thread: latest }];
    expect(requestAgentV2Support(items, openChat)).toBe(true);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    await pause(20);

    expect(openChat).toHaveBeenCalledTimes(1);
    expect(openChat).toHaveBeenCalledWith({ kind: 'thread', threadId: REPLACEMENT_THREAD_ID });
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', REPLACEMENT_THREAD_ID);
    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread');
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it('creates a new chat for a support starter request and sends it once the thread is ready', async () => {
    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    const onInitialMessageSent = jest.fn();

    expect(requestAgentV2Support([{ thread: { ...threadSummary(5), support: { state: 'closed' } } }], (
      target, options,
    ) => {
      TeactDOM.render(
        <TargetHarness
          target={target}
          shouldRequestSupport={options?.shouldRequestSupport}
          onInitialMessageSent={onInitialMessageSent}
        />, root);
    })).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread'), 10, 20))
      .toBe(true);
    const question = result!.messages.at(-1)!;
    expect(question).toMatchObject({ text: '$agent_support_request_message', isOutgoing: true });

    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(Date.now() + 60_000).toISOString() },
    });
    expect(await waitFor(() => result?.composerStatus?.mode === 'blocked', 10, 20)).toBe(true);
    creation.resolve();
    expect(await waitFor(() => onInitialMessageSent.mock.calls.length === 1, 10, 20)).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([[
      'startAgentV2Run', {
        threadId: REPLACEMENT_THREAD_ID,
        expectedThreadRevision: 5,
        input: { kind: 'append', text: '$agent_support_request_message' },
        entryPoint: { kind: 'supportRequest', source: 'starterHint' },
      },
    ]]);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([question]);
  });

  it('maps support messages and rates the stored operator reply by its own id', async () => {
    const avatarUrl = 'https://agent.test/api/v2/support/operators/operator-id/avatar?v=hash';
    const base = { threadId: THREAD_ID, status: 'complete' as const, createdAt: '2026-08-07T10:00:00.000Z' };
    hydratedMessages = [
      { ...base, id: MESSAGE_ID, role: 'event', code: 'support_requested' },
      {
        ...base, id: INPUT_MESSAGE_ID, role: 'event', code: 'operator_joined',
        author: { operatorId: 'operator-id', name: 'Alice' },
      },
      {
        ...base, id: ASSISTANT_MESSAGE_ID, role: 'operator', text: 'Hello **there**',
        author: { operatorId: 'operator-id', name: 'Alice', avatarUrl }, feedback: 'like',
      },
      { ...base, id: SECOND_ASSISTANT_MESSAGE_ID, role: 'event', code: 'support_closed', reason: 'operator' },
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([
      { text: '', isOutgoing: false, supportEvent: { code: 'support_requested' } },
      { text: '', isOutgoing: false, supportEvent: { code: 'operator_joined', operatorName: 'Alice' } },
      {
        text: 'Hello **there**', isOutgoing: false, isComplete: true, feedback: 'like',
        operator: { name: 'Alice', avatarUrl },
      },
      { text: '', isOutgoing: false, supportEvent: { code: 'support_closed', reason: 'operator' } },
    ]);
    result!.messages.forEach((message) => {
      expect(result!.isMessageRegenerable(message.id)).toBe(false);
      result!.retryMessage(message.id);
      if (!message.supportEvent) return;
      expect(message.followups).toBeUndefined();
      expect(message.isComplete).toBeUndefined();
      expect(message.feedback).toBeUndefined();
      void result!.rateMessage(message.id, 'like');
    });
    const operator = result!.messages[2];
    void result!.rateMessage(operator.id, 'dislike');
    await pause(20);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'setAgentV2MessageFeedback')).toEqual([
      ['setAgentV2MessageFeedback', THREAD_ID, ASSISTANT_MESSAGE_ID, 'dislike'],
    ]);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it('exposes the latest support summary and blocks regeneration during handoff', async () => {
    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    hydrationNextCursor = 'older-page';
    threadSupport = { state: 'waiting' };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.support).toEqual({ state: 'waiting' });
    const [question, answer] = result!.messages;
    expect(result!.isMessageEditable(question.id)).toBe(false);
    result!.retryMessage(answer.id);
    expect(result!.isMessageRegenerable(answer.id)).toBe(false);

    const support = { state: 'operator' as const, lastOperatorMessageAt: '2026-08-07T10:01:00.000Z' };
    publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread: { ...threadSummary(6), support } });
    expect(await waitFor(() => result?.support === support, 10, 20)).toBe(true);
    expect(result!.isMessageEditable(question.id)).toBe(false);
    result!.retryMessage(answer.id);
    expect(result!.isMessageRegenerable(answer.id)).toBe(false);
    await pause(20);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    threadSupport = { state: 'closed' };
    threadRevision = 7;
    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.support?.state === 'closed', 10, 20)).toBe(true);
    expect(result!.isMessageEditable(result!.messages.find(({ isOutgoing }) => isOutgoing)!.id)).toBe(true);
    expect(result!.isMessageRegenerable(answer.id)).toBe(true);
  });

  it.each(['waiting', 'operator'] as const)('sends an edit as a new message while support is %s', async (state) => {
    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    threadSupport = { state };
    startRunResponses = [{
      clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed',
    }];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const [question, answer] = result!.messages;
    expect(result!.isMessageEditable(question.id)).toBe(false);
    const requests = callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;

    result!.sendMessage('The edited question', question.id);
    expect(await waitFor(() => result?.messages.length === 3 && !result.isRunActive, 10, 20)).toBe(true);

    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      threadId: THREAD_ID, input: { kind: 'append', text: 'The edited question' },
    }));
    expect(result!.messages[0]).toBe(question);
    expect(result!.messages[1]).toBe(answer);
    expect(result!.messages[2]).toMatchObject({ text: 'The edited question', isOutgoing: true });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(requests + 1);
  });

  it.each([undefined, 'waiting', 'operator'] as const)(
    'allows messages at the daily quota only with active support: %s', async (state) => {
      threadSupport = state && { state };
      startRunResponses = [new Promise(() => undefined)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      publishAgentV2Update({
        kind: 'userQuotaChanged',
        quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(Date.now() + 60_000).toISOString() },
      });
      await pause(40);
      const isBlocked = state === undefined;
      expect(await waitFor(() => result?.isSendDisabled === isBlocked, 10, 20)).toBe(true);
      expect(result!.isInputDisabled).toBe(isBlocked);

      result!.sendMessage('Reply to support');
      await pause(40);
      const starts = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(starts).toHaveLength(isBlocked ? 0 : 1);
      if (isBlocked) return;
      expect(starts[0][1]).toMatchObject({ input: { kind: 'append', text: 'Reply to support' } });

      publishAgentV2Update({
        kind: 'runFailed', ...routing(), code: 'rate_limited', retryable: true, resetAt: Date.now() + 60_000,
      });
      expect(await waitFor(() => result?.composerStatus?.kind === 'rateLimit' && result.isSendDisabled, 10, 20))
        .toBe(true);
    },
  );

  it.each([undefined, 'waiting', 'operator'] as const)(
    'allows messages at exhausted capacity only with active support: %s', async (state) => {
      threadSupport = state && { state };
      startRunResponses = [new Promise(() => undefined)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      publishAgentV2Update({
        kind: 'availabilityChanged', availability: { state: 'capacity_exhausted', resetAt: Date.now() + 60_000 },
      });
      await pause(40);
      const isBlocked = state === undefined;
      expect(result!.isInputDisabled).toBe(isBlocked);
      expect(result!.isSendDisabled).toBe(isBlocked);

      result!.sendMessage('Reply to support');
      await pause(40);
      const starts = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(starts).toHaveLength(isBlocked ? 0 : 1);
      if (isBlocked) return;
      expect(starts[0][1]).toMatchObject({ input: { kind: 'append', text: 'Reply to support' } });

      publishAgentV2Update({
        kind: 'runFailed', ...routing(), code: 'rate_limited', retryable: true, resetAt: Date.now() + 60_000,
      });
      expect(await waitFor(() => result?.composerStatus?.kind === 'rateLimit' && result.isSendDisabled, 10, 20))
        .toBe(true);
    },
  );

  it('does not request support in a thread without consent', async () => {
    isConsentAccepted = false;
    const thread = threadSummary(5);
    TeactDOM.render(
      <TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} initialThread={thread} hasConsent={false} />,
      root,
    );
    expect(await waitFor(() => result?.isConsentAccepted === false, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread });
    expect(await waitFor(() => result?.thread?.id === THREAD_ID, 10, 20)).toBe(true);

    expect(result!.canRequestSupport).toBe(false);
    expect(result!.requestSupport('header')).toBe(false);
    await pause(50);
    expect(result!.messages).toEqual([]);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it.each([false, true])('replaces a failed support request without offering Retry: transport failure=%s', async (
    isTransportFailure,
  ) => {
    const support = createDeferred<AgentV2RunResult>();
    startRunResponses = [support.promise, new Promise(() => undefined)];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    expect(result!.requestSupport('header')).toBe(true);
    expect(await waitFor(() => result?.messages.at(-1)?.text === '$agent_support_request_message', 10, 20)).toBe(true);
    const question = result!.messages.at(-1)!;
    if (isTransportFailure) {
      support.reject(new Error('Connection interrupted'));
    } else {
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'network_error', retryable: true,
      });
      support.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    }
    expect(await waitFor(() => result?.isRunActive === false && result.messages.at(-1)?.error !== undefined, 10, 20))
      .toBe(true);
    expect(result!.messages.at(-1)).toMatchObject({ error: { code: 'network_error', retryable: false } });
    expect(result!.messages.at(-1)?.isRetryAvailable).toBeFalsy();

    expect(result!.requestSupport('header')).toBe(true);
    expect(await waitFor(() => result?.messages.at(-1)?.isOutgoing === true
      && result.messages.at(-1)?.id !== question.id
      && callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2, 10, 20)).toBe(true);
    expect(result!.messages).not.toContainEqual(question);
    expect(result!.messages.some(({ error }) => error)).toBe(false);
    expect(result!.messages.filter(({ text }) => text === '$agent_support_request_message')).toHaveLength(1);
  });

  it.each(['append', 'regenerate'] as const)(
    'shows the support failure once without Retry while preserving the capacity-held %s', async (kind) => {
      const held = createDeferred<AgentV2RunResult>();
      const support = createDeferred<AgentV2RunResult>();
      startRunResponses = [held.promise, support.promise, new Promise(() => undefined)];
      if (kind === 'regenerate') hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      if (kind === 'regenerate') result!.retryMessage(result!.messages[1].id);
      else result!.sendMessage('Held question');
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'agent_capacity_exhausted', retryable: true, resetAt: Date.now() + 60_000,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.isRunActive === false && result.isSendDisabled, 10, 20)).toBe(true);

      expect(result!.requestSupport('header')).toBe(true);
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: NEXT_CLIENT_RUN_ID, threadId: THREAD_ID, code: 'network_error', retryable: true,
      });
      support.resolve({ clientRunId: NEXT_CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);
      expect(result!.messages.filter(({ error }) => error?.code === 'network_error')).toHaveLength(1);
      expect(result!.messages.at(-1)?.isRetryAvailable).toBeFalsy();

      expect(result!.requestSupport('header')).toBe(true);
      expect(await waitFor(() => result?.isRunActive === true
        && callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 3, 10, 20))
        .toBe(true);
      expect(result!.messages.some(({ error }) => error?.code === 'network_error')).toBe(false);
      if (kind === 'append') expect(result!.messages.filter(({ text }) => text === 'Held question')).toHaveLength(1);
      expect(result!.messages.filter(({ text }) => text === '$agent_support_request_message')).toHaveLength(1);
    },
  );

  it.each(['user_quota_exhausted', 'agent_capacity_exhausted'] as const)(
    'keeps Retry for a question held by %s after support fails, and removes the failed support bubble', async (
      code,
    ) => {
      jest.useFakeTimers({
        doNotFake: ['setTimeout', 'clearTimeout', 'requestAnimationFrame', 'cancelAnimationFrame', 'performance'],
      });
      const held = createDeferred<AgentV2RunResult>();
      const support = createDeferred<AgentV2RunResult>();
      const retried = createDeferred<AgentV2RunResult>();
      startRunResponses = [held.promise, support.promise];
      retryRunResponse = retried.promise;
      const resetAt = Date.now() + 60_000;
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      result!.sendMessage('Held question');
      if (code === 'user_quota_exhausted') {
        publishAgentV2Update({
          kind: 'userQuotaChanged',
          quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString() },
        });
      }
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code, retryable: true, resetAt,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.isRunActive === false && result.isSendDisabled, 10, 20)).toBe(true);

      expect(result!.requestSupport('header')).toBe(true);
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: NEXT_CLIENT_RUN_ID, threadId: THREAD_ID, code: 'network_error', retryable: true,
      });
      support.resolve({ clientRunId: NEXT_CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.isRunActive === false
        && result.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);

      if (code === 'agent_capacity_exhausted') {
        expect(result!.messages.find(({ error }) => error?.code === code)?.isRetryAvailable).toBe(true);
      }
      jest.setSystemTime(resetAt + 1);
      result!.refreshExpiredComposerStatus();
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      result!.retryAdmission();
      expect(await waitFor(() => result?.isRunActive === true
        && callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run'), 10, 20))
        .toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
      expect(result!.messages.some(({ text }) => text === '$agent_support_request_message')).toBe(false);
      expect(result!.messages.some(({ text }) => text === 'Held question')).toBe(true);
    },
  );

  describe('support history polling', () => {
    let visibilityState: DocumentVisibilityState;
    let visibilitySpy: jest.SpyInstance;

    beforeEach(() => {
      threadSupport = { state: 'waiting' };
      visibilityState = 'visible';
      visibilitySpy = jest.spyOn(document, 'visibilityState', 'get').mockImplementation(() => visibilityState);
      jest.useFakeTimers({
        doNotFake: ['requestAnimationFrame', 'cancelAnimationFrame', 'setTimeout', 'clearTimeout'],
      });
    });

    afterEach(() => {
      TeactDOM.render(undefined, root);
      jest.useRealTimers();
      visibilitySpy.mockRestore();
    });

    it('merges saved messages every 15 seconds without duplicating or replacing messages already shown', async () => {
      hydrationNextCursor = 'older-page';
      olderHydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'user', 'Older request', 1)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(await waitFor(() => jest.getTimerCount() > 0, 10, 20)).toBe(true);
      await result!.loadOlderMessages();
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
      const [olderMessage, question] = result!.messages;
      const initialRequests = countLatestHistoryRequests();
      hydratedMessages = [
        persistedUserMessage(),
        {
          id: INPUT_MESSAGE_ID, threadId: THREAD_ID, role: 'event', status: 'complete',
          createdAt: '2026-08-07T10:00:00.500Z', code: 'operator_joined',
          author: { operatorId: 'operator-id', name: 'Alice' },
        },
        persistedOperatorMessage(),
        persistedMessage(
          SECOND_USER_MESSAGE_ID, 'user', 'From another device', Date.parse('2026-08-07T10:00:02Z') / 1000,
        ),
      ];
      threadRevision = 6;
      threadSupport = { state: 'operator', lastOperatorMessageAt: '2026-08-07T10:00:01.000Z' };

      await jest.advanceTimersByTimeAsync(14_999);
      expect(countLatestHistoryRequests()).toBe(initialRequests);
      await jest.advanceTimersByTimeAsync(1);
      expect(await waitFor(() => result?.messages.length === 5, 10, 20)).toBe(true);

      expect(result!.messages[0]).toBe(olderMessage);
      expect(result!.messages[1]).toBe(question);
      expect(result!.messages.slice(2)).toMatchObject([
        { supportEvent: { code: 'operator_joined', operatorName: 'Alice' } },
        { text: 'An operator reply', operator: { name: 'Alice' } },
        { text: 'From another device', isOutgoing: true },
      ]);
      expect(result!.support).toEqual(threadSupport);
      const shownMessages = result!.messages;
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 2);
      await pause(20);
      expect(result!.messages).toBe(shownMessages);
    });

    it('gates polling by visibility, active runs and support closure, and refreshes on return', async () => {
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(await waitFor(() => jest.getTimerCount() > 0, 10, 20)).toBe(true);
      const initialRequests = countLatestHistoryRequests();
      visibilityState = 'hidden';
      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(30_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests);

      visibilityState = 'visible';
      document.dispatchEvent(new Event('visibilitychange'));
      expect(await waitFor(() => countLatestHistoryRequests() === initialRequests + 1, 10, 20)).toBe(true);
      await pause(20);
      window.dispatchEvent(new Event('focus'));
      expect(await waitFor(() => countLatestHistoryRequests() === initialRequests + 2, 10, 20)).toBe(true);
      await pause(20);

      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
      expect(await waitFor(() => result?.isRunActive === true, 10, 20)).toBe(true);
      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 2);

      publishAgentV2Update({
        kind: 'messageCompleted', ...routing(), messageId: INPUT_MESSAGE_ID, finishReason: 'delivered_to_support',
      });
      expect(countLatestHistoryRequests()).toBe(initialRequests + 3);
      threadRevision = 7;
      threadSupport = { state: 'closed' };
      publishAgentV2Update({
        kind: 'threadChanged', threadId: THREAD_ID, thread: { ...threadSummary(7), support: threadSupport },
      });
      expect(await waitFor(() => result?.support?.state === 'closed', 10, 20)).toBe(true);
      // The closure reads the newest history once for the closing event, then polling stops
      expect(await waitFor(() => countLatestHistoryRequests() === initialRequests + 4, 10, 20)).toBe(true);
      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(30_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 4);
    });

    it('does not poll while history is loading', async () => {
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(await waitFor(() => jest.getTimerCount() > 0, 10, 20)).toBe(true);
      const defaultImplementation = callApiMock.getMockImplementation()!;
      const pendingHistory = createDeferred<unknown>();
      callApiMock.mockImplementation((...args) => (
        args[0] === 'getAgentV2Messages' && !args[2] ? pendingHistory.promise as never : defaultImplementation(...args)
      ));
      const initialRequests = countLatestHistoryRequests();
      publishAgentV2Update({ kind: 'runtimeReady', generation: 109 });
      expect(await waitFor(() => countLatestHistoryRequests() === initialRequests + 1, 10, 20)).toBe(true);
      expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);

      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
      pendingHistory.resolve(await defaultImplementation('getAgentV2Messages', THREAD_ID));
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    });

    it('refreshes when returning to the chat and stops when it leaves the screen or unmounts', async () => {
      const target = { kind: 'thread' as const, threadId: THREAD_ID };
      TeactDOM.render(<TargetHarness target={target} />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(await waitFor(() => jest.getTimerCount() > 0, 10, 20)).toBe(true);
      const initialRequests = countLatestHistoryRequests();
      TeactDOM.render(<TargetHarness target={target} isActive={false} />, root);
      await pause(20);
      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(30_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests);

      TeactDOM.render(<TargetHarness target={target} />, root);
      expect(await waitFor(() => countLatestHistoryRequests() === initialRequests + 1, 10, 20)).toBe(true);
      TeactDOM.render(undefined, root);
      window.dispatchEvent(new Event('focus'));
      document.dispatchEvent(new Event('visibilitychange'));
      await jest.advanceTimersByTimeAsync(30_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
    });

    it('keeps a failed refresh invisible, deduplicates in-flight reads, and retries on the next tick', async () => {
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(await waitFor(() => jest.getTimerCount() > 0, 10, 20)).toBe(true);
      const shownMessages = result!.messages;
      const defaultImplementation = callApiMock.getMockImplementation()!;
      let resolveRefresh!: (value: undefined) => void;
      let shouldDelayRefresh = true;
      callApiMock.mockImplementation((...args) => {
        if (args[0] === 'getAgentV2Messages' && !args[2] && shouldDelayRefresh) {
          shouldDelayRefresh = false;
          return new Promise((resolve) => {
            resolveRefresh = resolve;
          }) as never;
        }
        return defaultImplementation(...args);
      });
      const initialRequests = countLatestHistoryRequests();
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
      window.dispatchEvent(new Event('focus'));
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
      resolveRefresh(undefined);
      await jest.advanceTimersByTimeAsync(0);
      await pause(20);
      expect(result!.messages).toBe(shownMessages);
      expect(result!.historyFailure).toBeUndefined();
      expect(result!.isInputDisabled).toBe(false);
      expect(mockShowError).not.toHaveBeenCalled();

      hydratedMessages = [persistedUserMessage(), persistedOperatorMessage()];
      threadRevision = 6;
      threadSupport = { state: 'operator', lastOperatorMessageAt: '2026-08-07T10:00:01.000Z' };
      await jest.advanceTimersByTimeAsync(15_000);
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 2);
    });

    it('reads immediately when the list reports a different support state or operator timestamp', async () => {
      threadSupport = undefined;
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      const initialRequests = countLatestHistoryRequests();
      threadRevision = 6;
      threadSupport = { state: 'waiting' };
      notifyListedSupport();
      expect(await waitFor(() => result?.support?.state === 'waiting', 10, 20)).toBe(true);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
      notifyListedSupport();
      await jest.advanceTimersByTimeAsync(0);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);

      threadRevision = 7;
      threadSupport = { state: 'operator', lastOperatorMessageAt: '2026-08-07T10:00:01.000Z' };
      hydratedMessages = [persistedUserMessage(), persistedOperatorMessage()];
      notifyListedSupport();
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 2);

      threadRevision = 8;
      threadSupport = { ...threadSupport, lastOperatorMessageAt: '2026-08-07T10:00:02.000Z' };
      notifyListedSupport();
      expect(await waitFor(() => result?.support?.lastOperatorMessageAt === threadSupport?.lastOperatorMessageAt,
        10, 20)).toBe(true);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 3);
    });

    it('reads the newest history once when a live summary closes support', async () => {
      threadSupport = { state: 'operator', lastOperatorMessageAt: '2026-08-07T10:00:00.000Z' };
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      const initialRequests = countLatestHistoryRequests();

      threadRevision = 6;
      threadSupport = { state: 'closed', lastOperatorMessageAt: '2026-08-07T10:00:01.000Z' };
      hydratedMessages = [persistedUserMessage(), persistedOperatorMessage()];
      const thread = { ...threadSummary(threadRevision), support: threadSupport };
      publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread });
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);

      // Closure ends polling, and the same summary again reads nothing
      publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread });
      await jest.advanceTimersByTimeAsync(15_000);
      expect(countLatestHistoryRequests()).toBe(initialRequests + 1);
    });

    function countLatestHistoryRequests() {
      return callApiMock.mock.calls.filter(([method, , cursor]) => method === 'getAgentV2Messages' && !cursor).length;
    }

    function notifyListedSupport() {
      agentThreadListListeners.forEach((listener) => listener([
        { ...threadSummary(threadRevision), support: threadSupport },
      ]));
    }
  });

  it.each(['waiting', 'operator'] as const)('refreshes support %s immediately after a run', async (state) => {
    jest.useFakeTimers({
      doNotFake: ['requestAnimationFrame', 'cancelAnimationFrame', 'setTimeout', 'clearTimeout'],
    });
    jest.setSystemTime(new Date('2026-08-07T10:01:00.000Z'));
    hydratedMessages = [];
    let resolveRun!: (value: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    const countLatestHistoryRequests = () => callApiMock.mock.calls
      .filter(([method, , cursor]) => method === 'getAgentV2Messages' && !cursor).length;
    const requests = countLatestHistoryRequests();
    result!.sendMessage('Please help');
    expect(await waitFor(() => Boolean(resolveRun) && result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'threadChanged', ...routing(), thread: { ...threadSummary(6), support: { state } },
    });
    publishAgentV2Update({
      kind: 'messageCompleted', ...routing(), messageId: INPUT_MESSAGE_ID, finishReason: 'delivered_to_support',
    });
    expect(await waitFor(() => result?.messages[0]?.shouldCommitMarkdownTail === false, 10, 20)).toBe(true);
    const question = result!.messages[0];
    threadRevision = 6;
    threadSupport = { state };
    hydratedMessages = [{
      id: ASSISTANT_MESSAGE_ID, threadId: THREAD_ID, role: 'event', status: 'complete',
      createdAt: '2026-08-07T10:00:00.000Z', code: 'support_requested',
    }];
    expect(countLatestHistoryRequests()).toBe(requests);
    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed' });
    expect(await waitFor(() => result?.isRunActive === false && !result.isInputDisabled, 10, 20)).toBe(true);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages[0]).toBe(question);
    expect(question).toMatchObject({ text: 'Please help', isOutgoing: true });
    expect(question.error).toBeUndefined();
    expect(question.isRetryAvailable).toBeUndefined();
    expect(result!.messages[1]).toMatchObject({ supportEvent: { code: 'support_requested' } });
    expect(result!.historyFailure).toBeUndefined();
    expect(mockShowError).not.toHaveBeenCalled();
    await pause(20);
    expect(countLatestHistoryRequests()).toBe(requests + 1);
  });

  it('lets a stored answer be answered again, but not a question or a news post', async () => {
    hydratedMessages = [
      persistedUserMessage(),
      persistedAssistantTextMessage(),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

    const [question, answer] = result!.messages;
    expect(result!.isMessageRegenerable(question.id)).toBe(false);
    expect(result!.isMessageRegenerable(answer.id)).toBe(true);

    TeactDOM.render(undefined, root);
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    expect(result!.isMessageRegenerable(result!.messages[0].id)).toBe(false);
  });

  it('shows the question of a new chat at once and sends it in its place once the thread is ready', async () => {
    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    let resolveCreate!: NoneToVoidFunction;
    callApiMock.mockImplementation((...args) => (args[0] === 'createAgentV2Thread'
      ? new Promise((resolve) => {
        resolveCreate = () => resolve(defaultImplementation(...args));
      }) as never
      : defaultImplementation(...args)));
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} initialMessage=" What is TON? " />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread'), 10, 20))
      .toBe(true);

    const question = result!.messages.at(-1)!;
    expect(result!.messages).toHaveLength(1);
    expect(question).toMatchObject({ text: 'What is TON?', isOutgoing: true });
    expect(result!.hasPendingQuestion).toBe(true);
    expect(result!.isRunActive).toBe(true);
    expect(result!.activity).toEqual({ kind: 'analyzingRequest' });
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    resolveCreate();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls).toHaveLength(1);
    expect(runCalls[0][1]).toMatchObject({
      threadId: REPLACEMENT_THREAD_ID,
      input: { kind: 'append', text: 'What is TON?' },
    });
    expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ id: question.id, text: question.text, timestamp: question.timestamp }),
    ]);
  });

  it('cancels deletion before consent resolves without creating a thread or sending the opening question', async () => {
    const consent = createDeferred<boolean>();
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Consent'
      ? consent.promise
      : defaultImplementation(...args)));
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} initialMessage="Question" />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Consent'), 10, 20))
      .toBe(true);

    await expect(result!.cancelPendingRequests()).resolves.toBeUndefined();
    consent.resolve(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 200 });
    await pause(50);

    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread');
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(result!.historyFailure).toBeUndefined();
    expect(mockShowError).not.toHaveBeenCalled();
  });

  it.each([false, true])('retains only an in-flight create ID after deletion, unmounted=%s', async (shouldUnmount) => {
    hydratedMessages = [];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    const onThreadResolved = jest.fn();
    TeactDOM.render(
      <TargetHarness target={{ kind: 'new' }} initialMessage="Question" onThreadResolved={onThreadResolved} />,
      root,
    );
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread'), 10, 20))
      .toBe(true);

    const pendingThreadId = result!.cancelPendingRequests();
    if (shouldUnmount) TeactDOM.render(undefined, root);
    creation.resolve();
    await expect(pendingThreadId).resolves.toBe(THREAD_ID);
    await pause(50);

    expect(onThreadResolved).not.toHaveBeenCalled();
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(result!.historyFailure).toBeUndefined();
    expect(mockShowError).not.toHaveBeenCalled();
  });

  it.each([false, true])('does not present a failed create after deletion, alreadyFailed=%s', async (hasFailed) => {
    const creation = createDeferred<undefined>();
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'createAgentV2Thread'
      ? creation.promise
      : defaultImplementation(...args)));
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} initialMessage="Question" />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread'), 10, 20))
      .toBe(true);
    if (hasFailed) {
      creation.resolve(undefined);
      expect(await waitFor(() => Boolean(result!.historyFailure), 10, 20)).toBe(true);
    }

    const pendingThreadId = result!.cancelPendingRequests();
    creation.resolve(undefined);
    await expect(pendingThreadId).resolves.toBeUndefined();
    await pause(50);

    if (!hasFailed) expect(result!.historyFailure).toBeUndefined();
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(mockShowError).not.toHaveBeenCalled();
  });

  it('cancels an opening send while host context synchronizes before the run request', async () => {
    hydratedMessages = [];
    const context = createDeferred<unknown>();
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'updateAgentV2HostContext'
      ? context.promise as never
      : defaultImplementation(...args)));
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} initialMessage="Question" />, root);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'updateAgentV2HostContext'), 10, 20,
    )).toBe(true);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    await expect(result!.cancelPendingRequests()).resolves.toBe(THREAD_ID);
    context.resolve({ ok: true, value: { authorityChanged: false, generation: 1 } });
    await pause(50);

    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(result!.messages.some(({ failureText }) => failureText)).toBe(false);
    expect(mockShowError).not.toHaveBeenCalled();
  });

  it('leaves an already sent request for background thread deletion without reviving its chat', async () => {
    hydratedMessages = [];
    const run = createDeferred<AgentV2RunResult>();
    startRunResponses = [run.promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'new' }} initialMessage="Question" />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    const historyRequests = callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;

    await expect(result!.cancelPendingRequests()).resolves.toBe(THREAD_ID);
    run.resolve({ clientRunId: CLIENT_RUN_ID, state: 'interrupted' });
    publishAgentV2Update({ kind: 'runtimeReady', generation: 201 });
    await pause(50);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(historyRequests);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
    expect(result!.messages.some(({ failureText }) => failureText)).toBe(false);
    expect(mockShowError).not.toHaveBeenCalled();
  });

  it.each([true, false])('retries an opening question when input unblocks: active=%s', async (isActive) => {
    hydratedMessages = [];
    const createController = agentV2RunController.createAgentV2RunController;
    let unblockInput!: NoneToVoidFunction;
    const controllerSpy = jest.spyOn(agentV2RunController, 'createAgentV2RunController')
      .mockImplementationOnce((dependencies) => {
        const controller = createController(dependencies);
        const { sendMessage } = controller;
        jest.spyOn(controller, 'sendMessage').mockImplementationOnce((...args) => {
          dependencies.dispatch({ kind: 'runRequested', operationId: 99, operationKind: 'command' });
          unblockInput = () => dependencies.dispatch({ kind: 'runSettled', operationId: 99 });
          return sendMessage(...args);
        });
        return controller;
      });
    const onInitialMessageSent = jest.fn();
    TeactDOM.render(
      <TargetHarness
        target={{ kind: 'new' }}
        initialMessage="What is TON?"
        onInitialMessageSent={onInitialMessageSent}
      />,
      root,
    );
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.isInputDisabled, 10, 20))
      .toBe(true);
    controllerSpy.mockRestore();

    expect(result!.hasPendingQuestion).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'What is TON?' }),
    ]);
    expect(onInitialMessageSent).not.toHaveBeenCalled();
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    if (!isActive) {
      TeactDOM.render(<TargetHarness target={{ kind: 'new' }} isActive={false} />, root);
      await pause(50);
    }
    unblockInput();
    if (!isActive) {
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      await pause(50);
      expect(result!.hasPendingQuestion).toBe(true);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

      TeactDOM.render(
        <TargetHarness target={{ kind: 'new' }} onInitialMessageSent={onInitialMessageSent} />,
        root,
      );
    }
    expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
    expect(onInitialMessageSent).toHaveBeenCalledTimes(1);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toHaveLength(1);
  });

  it.each(['news', 'digest'] as const)('loads a %s discussion and its post before consent', async (kind) => {
    isConsentAccepted = false;
    if (kind === 'news') {
      createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    } else {
      createdThreadDigest = DIGEST;
    }
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    const target: AgentV2ChatTarget = kind === 'news'
      ? { kind, news: { eventId: 7, locale: 'en' } } : { kind, digest: { id: DIGEST.id } };
    TeactDOM.render(<TargetHarness target={target} />, root);

    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('createAgentV2Thread', kind === 'news'
      ? { news: { eventId: 7, locale: 'en' } } : { digest: { id: DIGEST.id } });
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', THREAD_ID);
    expect(result!.messages).toMatchObject([
      { text: 'Retried response', isOutgoing: false, isNewsPost: true, followups: [NEWS_FOLLOWUP] },
    ]);
    expect(result!.hints).toBeUndefined();
    expect(getStarterHintsCalls()).toHaveLength(0);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it.each([true, false])('loads a thread before consent only when it is a news discussion: %s', async (isNews) => {
    isConsentAccepted = false;
    if (isNews) {
      createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    }
    const target: AgentV2ChatTarget = { kind: 'thread', threadId: THREAD_ID, ...(isNews && { isNews }) };
    TeactDOM.render(<TargetHarness target={target} />, root);

    expect(await waitFor(() => result?.isConsentAccepted !== undefined, 10, 20)).toBe(true);
    expect(result!.isConsentAccepted).toBe(isNews);
    if (isNews) {
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(result!.messages).toMatchObject([{ isNewsPost: true }]);
      expect(getStarterHintsCalls()).toHaveLength(0);
    } else {
      await pause(50);
    }
    expect(callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')).toBe(isNews);
    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it.each(withDiscussions([
    { hasConsent: false }, { hasConsent: true },
  ]))('keeps an uncreated discussion local before and after consent: %o', async ({ discussion, hasConsent }) => {
    isConsentAccepted = hasConsent;
    isProblemReportAvailable = true;
    const onThreadResolved = jest.fn();
    const target = buildDeferredTarget(discussion, { title: 'Discussion title', followups: [NEWS_FOLLOWUP.text] });
    TeactDOM.render(
      <TargetHarness target={target} hasConsent={hasConsent} onThreadResolved={onThreadResolved} />, root,
    );
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result).toMatchObject({
      isInputDisabled: false,
      isSendDisabled: false,
      isRunActive: false,
      messages: [{
        isNewsPost: true,
        text: discussion === 'news' ? '**Feed headline**\n\n' : '',
        followups: [{ text: NEWS_FOLLOWUP.text }],
      }],
    });
    expect(result!.reportProblem).toBeUndefined();
    expect(result!.thread).toBeUndefined();
    expect(result!.hints).toBeUndefined();

    isConsentAccepted = true;
    TeactDOM.render(<TargetHarness target={target} hasConsent onThreadResolved={onThreadResolved} />, root);
    result!.checkConsentAgain();
    await pause(50);
    expect(await waitFor(() => result?.isConsentAccepted === true && result.isInitialLoadComplete, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 201 });
    await pause(50);
    expect(result!.historyFailure).toBeUndefined();
    expect(result!.reportProblem).toBeUndefined();
    TeactDOM.render(undefined, root);
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => (
      method === 'createAgentV2Thread' || method === 'getAgentV2Messages' || method === 'reportAgentV2Problem'
    ))).toEqual([]);
    expect(onThreadResolved).not.toHaveBeenCalled();
  });

  it.each(withDiscussions([
    { shouldRequestSupport: false }, { shouldRequestSupport: true },
  ]))('offers support in a deferred discussion: %o', async ({ discussion, shouldRequestSupport }) => {
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    TeactDOM.render(
      <TargetHarness
        target={buildDeferredTarget(discussion)}
        hasConsent
        shouldRequestSupport={shouldRequestSupport}
      />,
      root,
    );
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.messages[0]).toMatchObject({
      isNewsPost: true, text: discussion === 'news' ? '**Feed headline**\n\n' : '',
    });
    expect(result!.messages[0].followups).toBeUndefined();
    expect(result!.isSendDisabled).toBe(false);
    expect(result!.isSupportRequestVisible).toBe(true);
    expect(result!.canRequestSupport).toBe(true);
    expect(result!.requestSupport('header')).toBe(true);
    expect(result!.requestSupport('header')).toBe(false);
    expect(await waitFor(() => result?.thread?.id === THREAD_ID
      && callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20)).toBe(true);
    expect(discussion === 'news' ? result!.thread?.news : result!.thread?.digest)
      .toEqual(discussion === 'news' ? NEWS_TARGET.preview : DIGEST);
    expect(result!.isSupportRequestVisible).toBe(true);
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
      .toEqual([['createAgentV2Thread', DISCUSSION_CREATION[discussion]]]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([[
      'startAgentV2Run', {
        threadId: THREAD_ID, expectedThreadRevision: 5,
        input: { kind: 'append', text: '$agent_support_request_message' },
        entryPoint: { kind: 'supportRequest', source: 'header' },
      },
    ]]);
  });

  it.each(withDiscussions([{ failure: 'creation' }, { failure: 'history' }]))(
    'drops header support when deferred $discussion $failure fails', async ({ discussion, failure }) => {
      const creation = createDeferred<void>();
      createThreadPromise = creation.promise;
      const defaultImplementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => args[0] === 'getAgentV2Messages' && failure === 'history'
        ? Promise.resolve({ ok: false, error: { code: 'network_error', retryable: true } })
        : defaultImplementation(...args));
      TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      expect(result!.canRequestSupport).toBe(true);
      expect(result!.requestSupport('header')).toBe(true);
      if (failure === 'creation') creation.reject(new Error('Thread creation failed'));
      else creation.resolve();
      expect(await waitFor(() => result?.historyFailure !== undefined, 10, 20)).toBe(true);
      expect(result!.hasPendingQuestion).toBe(false);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
      expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([]);
    },
  );

  it.each(withDiscussions([{ shouldSwitchBack: false }, { shouldSwitchBack: true }]))(
    'drops deferred $discussion header support after a wallet switch, returned=$shouldSwitchBack', async ({
      discussion, shouldSwitchBack,
    }) => {
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const creation = createDeferred<void>();
      createThreadPromise = creation.promise;
      TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
      expect(await waitFor(() => result?.canRequestSupport === true, 10, 20)).toBe(true);
      expect(result!.requestSupport('header')).toBe(true);
      buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
      publishAgentV2Update({ kind: 'walletAuthorityChanged' });
      if (shouldSwitchBack) {
        buildAgentV2HostContextMock.mockReturnValue(hostContext());
        publishAgentV2Update({ kind: 'walletAuthorityChanged' });
      }
      creation.resolve();
      expect(await waitFor(() => result?.isInitialLoadComplete === true && result.thread?.id === THREAD_ID, 10, 20))
        .toBe(true);
      await pause(50);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([]);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
      expect(result!.hasPendingQuestion).toBe(false);
      expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
    },
  );

  it.each(withDiscussions([{ boundary: 'creation' }, { boundary: 'history' }, { boundary: 'admission' }]))(
    'keeps deferred $discussion header support after unmount during $boundary', async ({
      discussion, boundary,
    }) => {
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const creation = createDeferred<void>();
      const history = createDeferred<void>();
      const historyReturned = createDeferred<void>();
      const admission = createDeferred<void>();
      let hasAdmissionStarted = false;
      let shouldHoldAdmission = false;
      createThreadPromise = creation.promise;
      const defaultImplementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => {
        if (args[0] === 'getAgentV2Messages') {
          return history.promise.then(() => defaultImplementation(...args)).finally(() => historyReturned.resolve());
        }
        if (args[0] === 'updateAgentV2HostContext' && shouldHoldAdmission) {
          hasAdmissionStarted = true;
          return admission.promise.then(() => defaultImplementation(...args));
        }
        return defaultImplementation(...args);
      });
      TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
      expect(await waitFor(() => result?.canRequestSupport === true, 10, 20)).toBe(true);
      shouldHoldAdmission = boundary === 'admission';
      expect(result!.requestSupport('header')).toBe(true);
      if (boundary !== 'creation') {
        creation.resolve();
        expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
          .toBe(true);
      }
      if (boundary === 'admission') {
        history.resolve();
        await historyReturned.promise;
        expect(await waitFor(() => hasAdmissionStarted && result?.messages.some(({ isOutgoing, text }) => (
          isOutgoing && text === '$agent_support_request_message'
        )) === true, 10, 20)).toBe(true);
      }
      TeactDOM.render(undefined, root);
      if (boundary === 'admission') expect(getAgentV2LocalState().backgroundQueues.has(THREAD_ID)).toBe(true);
      creation.resolve();
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
        .toBe(true);
      history.resolve();
      await historyReturned.promise;
      admission.resolve();
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
        .toBe(true);
      await pause(50);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
        .toEqual([['createAgentV2Thread', DISCUSSION_CREATION[discussion]]]);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([[
        'startAgentV2Run', {
          threadId: THREAD_ID, expectedThreadRevision: 5,
          input: { kind: 'append', text: '$agent_support_request_message' },
          entryPoint: { kind: 'supportRequest', source: 'header' },
        },
      ]]);
      expect(getAgentV2LocalState().backgroundQueues.size).toBe(0);
      expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
    },
  );

  it.each(withDiscussions([
    { kind: 'userQuota', hasConsent: true },
    { kind: 'capacity', hasConsent: true },
    { kind: 'userQuota', hasConsent: false },
  ] as const))('checks $kind before creating a $discussion thread, consent=$hasConsent', async ({
    kind, hasConsent, discussion,
  }) => {
    isConsentAccepted = hasConsent;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    const status = createDeferred<void>();
    const resetAt = Date.now() + 60_000;
    let shouldBlock = true;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Availability') {
        return status.promise.then(() => {
          publishAgentV2Update({
            kind: 'availabilityChanged',
            availability: shouldBlock && kind === 'capacity' ? { state: 'capacity_exhausted', resetAt }
              : { state: 'available' },
          });
        });
      }
      if (args[0] === 'getAgentV2UserQuota') {
        return status.promise.then(() => {
          publishAgentV2Update({
            kind: 'userQuotaChanged',
            quota: { limit: 20, used: shouldBlock ? 20 : 0, remaining: shouldBlock && kind === 'userQuota' ? 0 : 20,
              resetAt: new Date(resetAt).toISOString() },
          });
        });
      }
      return defaultImplementation(...args);
    });
    const target = buildDeferredTarget(discussion, { title: 'Discussion title', followups: [NEWS_FOLLOWUP.text] });
    TeactDOM.render(<TargetHarness target={target} hasConsent={hasConsent} />, root);
    if (hasConsent) expect(result!.isSendDisabled).toBe(true);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    if (!hasConsent) {
      const beforeConsent = result!.prepareSend();
      await pause(50);
      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Availability');
      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2UserQuota');
      expect(await beforeConsent).toBe(false);
      isConsentAccepted = true;
      TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
      expect(result!.isSendDisabled).toBe(true);
    }
    const prepared = result!.prepareSend();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2UserQuota'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.isSendDisabled === true, 10, 20)).toBe(true);
    result!.sendMessage('Refused while checking');
    result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toEqual([]);
    status.resolve();
    expect(await prepared).toBe(false);
    expect(await waitFor(() => result?.composerStatus?.mode === 'blocked', 10, 20)).toBe(true);
    expect(result!.composerStatus?.kind).toBe(kind);
    result!.sendMessage('Refused by limit');
    result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(false);
    expect(callApiMock.mock.calls.filter(([method]) => (
      method === 'createAgentV2Thread' || method === 'getAgentV2Messages' || method === 'startAgentV2Run'
    ))).toEqual([]);

    shouldBlock = false;
    publishAgentV2Update({ kind: 'availabilityChanged', availability: { state: 'available' } });
    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: { limit: 20, used: 0, remaining: 20, resetAt: new Date(resetAt).toISOString() },
    });
    expect(await result!.prepareSend()).toBe(true);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Allowed question');
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
      .toEqual([['createAgentV2Thread', DISCUSSION_CREATION[discussion]]]);
    const methods = callApiMock.mock.calls.map(([method]) => method);
    expect(methods.indexOf('getAgentV2Availability')).toBeLessThan(methods.indexOf('createAgentV2Thread'));
    expect(methods.indexOf('getAgentV2UserQuota')).toBeLessThan(methods.indexOf('createAgentV2Thread'));
  });

  it.each(withDiscussions([{ text: 'First question' }, { text: 'Feed headline' }]))(
    'shows the first question at once and creates and sends once after history loads: %o', async ({
      discussion, text,
    }) => {
      const target = buildDeferredTarget(discussion);
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const creation = createDeferred<void>();
      const history = createDeferred<void>();
      createThreadPromise = creation.promise;
      const defaultImplementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
        ? history.promise.then(() => defaultImplementation(...args)) as never
        : defaultImplementation(...args)));
      let finishLoading!: NoneToVoidFunction;
      const createController = agentV2RunController.createAgentV2RunController;
      const controllerSpy = jest.spyOn(agentV2RunController, 'createAgentV2RunController')
        .mockImplementationOnce((dependencies) => {
          controllerSpy.mockRestore();
          finishLoading = () => dependencies.dispatch({ kind: 'hydrationFailed' });
          return createController(dependencies);
        });
      const onThreadResolved = jest.fn();
      TeactDOM.render(
        <TargetHarness target={target} hasConsent onThreadResolved={onThreadResolved} />,
        root,
      );
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      result!.sendMessage(` ${text} `);
      expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
      const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
      finishLoading();
      result!.sendMessage('Other text');
      await pause(50);
      expect(question).toMatchObject({ text });
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([question]);
      expect(result!.isSendDisabled).toBe(true);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
        .toEqual([['createAgentV2Thread', DISCUSSION_CREATION[discussion]]]);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

      creation.resolve();
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
        .toBe(true);
      await pause(50);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      history.resolve();
      expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
      await pause(50);
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(sends).toHaveLength(1);
      expect(sends[0][1]).toMatchObject({ threadId: THREAD_ID, input: { kind: 'append', text } });
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ id: question.id, text: question.text, timestamp: question.timestamp }),
      ]);
      expect(onThreadResolved).toHaveBeenCalledTimes(1);
      expect(onThreadResolved).toHaveBeenCalledWith(THREAD_ID);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    },
  );

  it.each(withDiscussions([
    { hasMatch: true }, { hasMatch: false },
  ]))('sends a preview follow-up through its exact saved match: %o', async ({ discussion, hasMatch }) => {
    const target = buildDeferredTarget(discussion, {
      title: 'Discussion title', followups: [NEWS_FOLLOWUP.text, 'Another question'],
    });
    hydratedMessages = [{
      ...persistedAssistantTextMessage(), newsPost: true,
      followups: [{ ...NEWS_FOLLOWUP, text: hasMatch ? NEWS_FOLLOWUP.text : `${NEWS_FOLLOWUP.text} ` }],
    }];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    let finishLoading!: NoneToVoidFunction;
    const createController = agentV2RunController.createAgentV2RunController;
    const controllerSpy = jest.spyOn(agentV2RunController, 'createAgentV2RunController')
      .mockImplementationOnce((dependencies) => {
        controllerSpy.mockRestore();
        finishLoading = () => dependencies.dispatch({ kind: 'hydrationFailed' });
        return createController(dependencies);
      });
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    const post = result!.messages[0];
    result!.sendFollowup(post.id, post.followups![0]);
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
    finishLoading();
    result!.sendFollowup(post.id, post.followups![1]);
    await pause(50);
    expect(question.text).toBe(NEWS_FOLLOWUP.text);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([question]);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    creation.resolve();
    expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: NEWS_FOLLOWUP.text } });
    if (hasMatch) {
      expect(sends[0][1]).toMatchObject({
        followupOf: { messageId: ASSISTANT_MESSAGE_ID, followupId: NEWS_FOLLOWUP.id },
      });
    } else {
      expect(sends[0][1]).not.toHaveProperty('followupOf');
    }
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
      .toEqual([['createAgentV2Thread', DISCUSSION_CREATION[discussion]]]);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ id: question.id, text: question.text, timestamp: question.timestamp }),
    ]);
  });

  it('keeps a pending preview follow-up when the controller refuses it and retries once input unblocks', async () => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    const createController = agentV2RunController.createAgentV2RunController;
    let unblockInput!: NoneToVoidFunction;
    const controllerSpy = jest.spyOn(agentV2RunController, 'createAgentV2RunController')
      .mockImplementationOnce((dependencies) => {
        const controller = createController(dependencies);
        const { sendFollowup } = controller;
        jest.spyOn(controller, 'sendFollowup').mockImplementationOnce((...args) => {
          dependencies.dispatch({ kind: 'runRequested', operationId: 99, operationKind: 'command' });
          unblockInput = () => dependencies.dispatch({ kind: 'runSettled', operationId: 99 });
          return sendFollowup(...args);
        });
        return controller;
      });
    try {
      TeactDOM.render(
        <TargetHarness
          target={{
            ...NEWS_TARGET, shouldDeferCreation: true,
            discussionNaming: { title: 'Discussion title', followups: [NEWS_FOLLOWUP.text] },
          }}
          hasConsent
        />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
      expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
      const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
      creation.resolve();
      expect(await waitFor(() => result?.isInitialLoadComplete === true && result.isInputDisabled, 10, 20)).toBe(true);
      await pause(50);
      expect(result!.hasPendingQuestion).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([question]);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      unblockInput();
      expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
      await pause(50);
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(sends).toHaveLength(1);
      expect(sends[0][1]).toMatchObject({
        input: { kind: 'append', text: NEWS_FOLLOWUP.text },
        followupOf: { messageId: ASSISTANT_MESSAGE_ID, followupId: NEWS_FOLLOWUP.id },
      });
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ id: question.id, text: question.text, timestamp: question.timestamp }),
      ]);
    } finally {
      controllerSpy.mockRestore();
    }
  });

  it.each(['message', 'followup', 'signout'] as const)(
    'keeps the first news question after unmount before creation resolves: %s', async (kind) => {
      createdThreadNews = NEWS_TARGET.preview;
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
      const creation = createDeferred<void>();
      createThreadPromise = creation.promise;
      const onThreadResolved = jest.fn();
      TeactDOM.render(
        <TargetHarness
          target={{
            ...NEWS_TARGET, shouldDeferCreation: true,
            discussionNaming: { title: 'Discussion title', followups: [NEWS_FOLLOWUP.text] },
          }}
          hasConsent
          onThreadResolved={onThreadResolved}
        />, root);
      expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
      if (kind === 'followup') result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
      else result!.sendMessage('First background question');
      expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
      TeactDOM.render(undefined, root);
      if (kind === 'signout') resetAgentV2LocalState();
      creation.resolve();
      if (kind !== 'signout') {
        expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
          .toBe(true);
      }
      await pause(50);
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
      if (kind === 'signout') {
        expect(sends).toEqual([]);
        expect(onThreadResolved).not.toHaveBeenCalled();
      } else {
        expect(sends).toHaveLength(1);
        expect(sends[0][1]).toMatchObject({
          input: { kind: 'append', text: kind === 'followup' ? NEWS_FOLLOWUP.text : 'First background question' },
        });
        expect(onThreadResolved).toHaveBeenCalledTimes(1);
        if (kind === 'followup') {
          expect(sends[0][1]).toMatchObject({
            followupOf: { messageId: ASSISTANT_MESSAGE_ID, followupId: NEWS_FOLLOWUP.id },
          });
        }
      }
    },
  );

  it.each(withDiscussions([
    { isSameAccount: false }, { isSameAccount: true },
  ]))('binds an opening question to its submitting wallet: %o', async ({ discussion, isSameAccount }) => {
    const target = buildDeferredTarget(discussion);
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    let activeContext = hostContext();
    const startedAccountIds: Array<string | undefined> = [];
    buildAgentV2HostContextMock.mockImplementation(() => activeContext);
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'startAgentV2Run') startedAccountIds.push(activeContext.activeAccountId);
      return defaultImplementation(...args);
    });
    startRunResponses = [new Promise(() => undefined)];
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('First');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    activeContext = isSameAccount ? { ...hostContext(), activeNetwork: 'tron' } : hostContext('account-two');
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    creation.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.thread?.id === THREAD_ID, 10, 20))
      .toBe(true);
    await pause(50);
    if (!isSameAccount) {
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      expect(result!.messages.find(({ isOutgoing }) => isOutgoing)?.text).toBe('First');
      const failure = result!.messages.at(-1)!;
      expect(failure).toMatchObject({ error: { code: 'internal_error', retryable: true }, isRetryAvailable: true });
      expect(result!.failedQueueFailureId).toBe(failure.id);
      result!.retryMessage(failure.id);
    } else {
      expect(result!.failedQueueFailureId).toBeUndefined();
      expect(result!.messages.some(({ error, failureText }) => error || failureText)).toBe(false);
    }
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: 'First' } });
    expect(startedAccountIds).toEqual([isSameAccount ? 'account-one' : 'account-two']);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
  });

  it.each([false, true])('fails a background opening news question after a wallet switch, queued=%s', async (
    isQueued,
  ) => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    const resetAt = new Date(Date.now() + 60_000).toISOString();
    let hasRequestedHistory = false;
    let shouldBlockQuota = isQueued;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages') {
        hasRequestedHistory = true;
        if (shouldBlockQuota) {
          publishAgentV2Update({
            kind: 'userQuotaChanged', quota: { limit: 20, used: 20, remaining: 0, resetAt },
          });
        }
      }
      return defaultImplementation(...args);
    });
    startRunResponses = [new Promise(() => undefined)];
    TeactDOM.render(<TargetHarness target={{ ...NEWS_TARGET, shouldDeferCreation: true }} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('First');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    if (isQueued) {
      creation.resolve();
      expect(await waitFor(() => hasRequestedHistory, 10, 20)).toBe(true);
      await pause(50);
    }
    buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    if (!isQueued) creation.resolve();
    expect(await waitFor(() => hasRequestedHistory, 10, 20)).toBe(true);
    shouldBlockQuota = false;
    publishAgentV2Update({ kind: 'userQuotaChanged', quota: { limit: 20, used: 0, remaining: 20, resetAt } });
    await pause(50);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID, isNews: true }} hasConsent />, root);
    expect(await waitFor(() => result?.failedQueueFailureId !== undefined, 10, 20)).toBe(true);
    expect(result!.messages.find(({ isOutgoing }) => isOutgoing)?.text).toBe('First');
    expect(result!.messages.at(-1)).toMatchObject({ error: { code: 'internal_error' }, isRetryAvailable: true });
    result!.retryMessage(result!.failedQueueFailureId!);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: 'First' } });
  });

  it.each(['background', 'thread', 'pending'] as const)('shows a quota-held opening question, reopen=%s', async (
    reopen,
  ) => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const creation = createDeferred<void>();
    createThreadPromise = creation.promise;
    const resetAt = new Date(Date.now() + 60_000).toISOString();
    let hasRequestedHistory = false;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages') {
        hasRequestedHistory = true;
        publishAgentV2Update({
          kind: 'userQuotaChanged', quota: { limit: 20, used: 20, remaining: 0, resetAt },
        });
      }
      return defaultImplementation(...args);
    });
    const target: AgentV2ChatTarget = { ...NEWS_TARGET, shouldDeferCreation: true };
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Quota-delayed opening question');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
    TeactDOM.render(undefined, root);
    await pause(50);
    if (reopen === 'pending') {
      TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
      expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    }
    creation.resolve();
    expect(await waitFor(() => hasRequestedHistory, 10, 20)).toBe(true);
    await pause(50);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    if (reopen !== 'background') {
      if (reopen === 'thread') {
        TeactDOM.render(
          <TargetHarness target={{ kind: 'thread', threadId: THREAD_ID, isNews: true }} hasConsent />, root,
        );
      }
      expect(await waitFor(() => result?.queuedMessageCount === 1, 10, 20)).toBe(true);
      expect(result!.hasPendingQuestion).toBe(false);
      expect(result!.isSendQueued).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ text: question.text, timestamp: question.timestamp }),
      ]);
      expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', mode: 'blocked' });
      await pause(50);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    }
    publishAgentV2Update({
      kind: 'userQuotaChanged', quota: { limit: 20, used: 0, remaining: 20, resetAt },
    });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: question.text } });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
  });

  it.each([false, true])('blocks a hydrated receiver until opening news admission, thread=%s', async (
    isThreadTarget,
  ) => {
    createdThreadNews = NEWS_TARGET.preview;
    const post: AgentV2HydratedMessage = {
      ...persistedAssistantTextMessage(), id: OLDER_MESSAGE_ID, newsPost: true, followups: [NEWS_FOLLOWUP],
    };
    hydratedMessages = [post];
    const creation = createDeferred<void>();
    const senderHistory = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult>();
    let historyReads = 0;
    createThreadPromise = creation.promise;
    startRunResponses = [run.promise];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages' && ++historyReads === 1) {
        return senderHistory.promise.then(() => defaultImplementation(...args)) as never;
      }
      if (args[0] === 'startAgentV2Run') {
        hydratedMessages = [post, {
          ...persistedUserMessage(), content: { kind: 'markdown', text: 'First' },
        }];
      }
      return defaultImplementation(...args);
    });
    const target: AgentV2ChatTarget = { ...NEWS_TARGET, shouldDeferCreation: true };
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('First');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    if (isThreadTarget) {
      creation.resolve();
      expect(await waitFor(() => historyReads === 1, 10, 20)).toBe(true);
    }
    TeactDOM.render(undefined, root);
    await pause(50);
    const receiverTarget: AgentV2ChatTarget = isThreadTarget
      ? { kind: 'thread', threadId: THREAD_ID, isNews: true } : target;
    TeactDOM.render(<TargetHarness target={receiverTarget} hasConsent />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    if (!isThreadTarget) creation.resolve();
    expect(await waitFor(() => (
      historyReads >= 2 && result?.thread?.id === THREAD_ID && result.isInitialLoadComplete
    ), 10, 20)).toBe(true);
    await pause(50);
    expect(result!.isSendDisabled).toBe(true);
    expect(result!.sendMessage('Second')).toBe(false);
    result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
    await pause(50);
    expect(result!.queuedMessageCount).toBe(0);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    senderHistory.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: 'First' } });
    expect(result!.isSendDisabled).toBe(true);
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: MESSAGE_ID });
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    expect(await waitFor(() => result!.messages.some(({ isOutgoing, text }) => isOutgoing && text === 'First'), 10, 20))
      .toBe(true);
    run.resolve({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: MESSAGE_ID, state: 'completed' });
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
  });

  it('queues the opening news question behind a run found while its sender hydrates', async () => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), id: OLDER_MESSAGE_ID, newsPost: true }];
    const creation = createDeferred<void>();
    const history = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult>();
    let hasRequestedHistory = false;
    let getQueuedTexts!: () => string[];
    const createController = agentV2RunController.createAgentV2RunController;
    const controllerSpy = jest.spyOn(agentV2RunController, 'createAgentV2RunController')
      .mockImplementationOnce((dependencies) => {
        controllerSpy.mockRestore();
        getQueuedTexts = () => dependencies.getState().queuedMessages.map(({ text }) => text);
        return createController(dependencies);
      });
    createThreadPromise = creation.promise;
    startRunResponses = [run.promise];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages') {
        hasRequestedHistory = true;
        return history.promise.then(() => defaultImplementation(...args)) as never;
      }
      return defaultImplementation(...args);
    });
    TeactDOM.render(<TargetHarness target={{ ...NEWS_TARGET, shouldDeferCreation: true }} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Opening question after the active run');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    creation.resolve();
    expect(await waitFor(() => hasRequestedHistory, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted', ...routing(), clientRunId: NEXT_CLIENT_RUN_ID, threadRevision: 6,
      inputMessageId: SECOND_USER_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), clientRunId: NEXT_CLIENT_RUN_ID,
      messageId: SECOND_ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    history.resolve();
    expect(await waitFor(() => getQueuedTexts().length === 1, 10, 20)).toBe(true);
    expect(getQueuedTexts()).toEqual(['Opening question after the active run']);
    await pause(50);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    publishAgentV2Update({
      kind: 'messageCompleted', ...routing(), clientRunId: NEXT_CLIENT_RUN_ID,
      messageId: SECOND_ASSISTANT_MESSAGE_ID, finishReason: 'complete',
    });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: 'Opening question after the active run' } });
    expect(getQueuedTexts()).toEqual([]);
    run.resolve({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: MESSAGE_ID, state: 'completed' });
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
  });

  it.each(withDiscussions([
    { shouldPublishAdmission: true }, { shouldPublishAdmission: false },
  ]))('follows the same pending thread after remount: %o', async ({ discussion, shouldPublishAdmission }) => {
    const target = buildDeferredTarget(discussion);
    const post: AgentV2HydratedMessage = {
      ...persistedAssistantTextMessage(), id: OLDER_MESSAGE_ID, newsPost: true,
    };
    hydratedMessages = [post];
    const creation = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult>();
    const observerHistory = createDeferred<void>();
    let historyReads = 0;
    createThreadPromise = creation.promise;
    startRunResponses = [run.promise];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages' && ++historyReads === 2) {
        return observerHistory.promise.then(() => defaultImplementation(...args)) as never;
      }
      if (args[0] === 'startAgentV2Run') {
        hydratedMessages = [post, {
          ...persistedUserMessage(), content: { kind: 'markdown', text: 'First shared question' },
        }];
        observerHistory.resolve();
        if (shouldPublishAdmission) {
          publishAgentV2Update({
            kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: MESSAGE_ID,
          });
        }
      }
      return defaultImplementation(...args);
    });
    const onFirstThreadResolved = jest.fn();
    const onObservedThreadResolved = jest.fn();
    TeactDOM.render(<TargetHarness target={target} hasConsent onThreadResolved={onFirstThreadResolved} />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('First shared question');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    TeactDOM.render(
      <TargetHarness
        target={target}
        initialMessage="Must not replay"
        hasConsent
        onThreadResolved={onObservedThreadResolved}
      />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(false);
    expect(result!.isSendDisabled).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    creation.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.thread?.id === THREAD_ID, 10, 20)).toBe(true);
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => text === 'First shared question')), 10, 20))
      .toBe(true);
    hydratedMessages = [...hydratedMessages, {
      ...persistedAssistantTextMessage(), content: { kind: 'markdown', text: 'Shared answer' },
    }];
    run.resolve({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: MESSAGE_ID, state: 'completed' });
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => text === 'Shared answer')), 10, 20))
      .toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'First shared question' }),
    ]);
    expect(onFirstThreadResolved).toHaveBeenCalledTimes(1);
    expect(onObservedThreadResolved).toHaveBeenCalledTimes(1);
    expect(onObservedThreadResolved).toHaveBeenCalledWith(THREAD_ID);

    TeactDOM.render(undefined, root);
    await pause(50);
    TeactDOM.render(<TargetHarness target={target} hasConsent initialMessage="Must not replay" />, root);
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => text === 'Shared answer')), 10, 20))
      .toBe(true);
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
    TeactDOM.render(undefined, root);
    await pause(50);
    resetAgentV2LocalState();
    const historyReadsBeforeReset = historyReads;
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && !result.isSendDisabled, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.thread).toBeUndefined();
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
    expect(historyReads).toBe(historyReadsBeforeReset);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
  });

  it.each(withDiscussions([
    { text: 'Reopened question', shouldReset: false },
    { text: 'Feed headline', shouldReset: false },
    { text: 'Reopened question', shouldReset: true },
  ]))('follows a pending thread creation from a new target of the discussion: %o', async ({
    discussion, text, shouldReset,
  }) => {
    const post: AgentV2HydratedMessage = { ...persistedAssistantTextMessage(), id: OLDER_MESSAGE_ID, newsPost: true };
    hydratedMessages = [post];
    const creation = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult>();
    createThreadPromise = creation.promise;
    startRunResponses = [run.promise];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'startAgentV2Run') {
        hydratedMessages = [post, {
          ...persistedUserMessage(), content: { kind: 'markdown', text },
        }];
        publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: MESSAGE_ID });
      }
      return defaultImplementation(...args);
    });
    const onThreadResolved = jest.fn();
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage(text);
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
    TeactDOM.render(undefined, root);
    await pause(50);
    // Other news, the same news in another language and another digest do not follow this creation
    const otherTargets: AgentV2ChatTarget[] = discussion === 'news' ? [
      { ...NEWS_TARGET, news: { eventId: 8, locale: 'en' }, shouldDeferCreation: true },
      { ...NEWS_TARGET, news: { eventId: 7, locale: 'ru' }, shouldDeferCreation: true },
    ] : [{ ...DIGEST_TARGET, digest: { id: 'digest-2' }, shouldDeferCreation: true }];
    for (const otherTarget of otherTargets) {
      TeactDOM.render(<TargetHarness target={otherTarget} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
      TeactDOM.render(undefined, root);
      await pause(50);
    }

    TeactDOM.render(
      <TargetHarness target={buildDeferredTarget(discussion)} hasConsent onThreadResolved={onThreadResolved} />, root,
    );
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(false);
    expect(result!.isSendDisabled).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: question.text, timestamp: question.timestamp }),
    ]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    if (shouldReset) {
      TeactDOM.render(undefined, root);
      await pause(50);
      resetAgentV2LocalState();
      TeactDOM.render(
        <TargetHarness target={buildDeferredTarget(discussion)} hasConsent onThreadResolved={onThreadResolved} />, root,
      );
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
      creation.resolve();
      await pause(50);
      expect(result!.thread).toBeUndefined();
      expect(onThreadResolved).not.toHaveBeenCalled();
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      return;
    }

    creation.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.thread?.id === THREAD_ID, 10, 20)).toBe(true);
    // The run's admission ends the entry before the run itself ends
    expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
    run.resolve({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: MESSAGE_ID, state: 'completed' });
    await pause(50);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([expect.objectContaining({ text })]);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ threadId: THREAD_ID, input: { kind: 'append', text } });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(onThreadResolved).toHaveBeenCalledWith(THREAD_ID);

    // Once the question has been sent, the discussion opens again as one that has not created its thread
    TeactDOM.render(undefined, root);
    await pause(50);
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    expect(result!.thread).toBeUndefined();
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
  });

  it.each(withDiscussions([
    { isOwnerMounted: false }, { isOwnerMounted: true },
  ]))('hands a failed creation question to a new target of the discussion: %o', async ({
    discussion, isOwnerMounted,
  }) => {
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const creation = createDeferred<void>();
    let creationAttempts = 0;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'createAgentV2Thread' && ++creationAttempts === 1) {
        return creation.promise.then(() => ({ ok: false, error: { code: 'rate_limited', retryable: true } })) as never;
      }
      return defaultImplementation(...args);
    });
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Failed opening question');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
    // The chat that asked keeps its failed question, and the discussion opened next starts afresh
    if (isOwnerMounted) {
      creation.resolve();
      expect(await waitFor(() => Boolean(result?.historyFailure), 10, 20)).toBe(true);
      await pause(50);
      const receiverRoot = document.createElement('div');
      document.body.appendChild(receiverRoot);
      try {
        TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, receiverRoot);
        expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
        await pause(50);
        expect(result!.hasPendingQuestion).toBe(false);
        expect(result!.isSendDisabled).toBe(false);
        expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
        expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
      } finally {
        TeactDOM.render(undefined, receiverRoot);
        receiverRoot.remove();
      }
      return;
    }
    TeactDOM.render(undefined, root);
    await pause(50);
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(false);

    creation.resolve();
    expect(await waitFor(() => Boolean(result?.historyFailure), 10, 20)).toBe(true);
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: question.text, timestamp: question.timestamp }),
    ]);
    expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);
    expect(creationAttempts).toBe(1);

    result!.retryHistory();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ threadId: THREAD_ID, input: { kind: 'append', text: question.text } });
    // The failed creation's entry is gone, so the retry creates the thread anew
    expect(creationAttempts).toBe(2);
  });

  it.each(withDiscussions([
    { deletedBy: 'follower', isHeaderSupportRequest: false },
    { deletedBy: 'owner', isHeaderSupportRequest: false },
    { deletedBy: 'thread', isHeaderSupportRequest: false },
    { deletedBy: 'feed', isHeaderSupportRequest: false },
    { deletedBy: 'sending', isHeaderSupportRequest: false },
    { deletedBy: 'follower', isHeaderSupportRequest: true },
  ] as const))('cancels the opening request when a chat of the discussion is deleted: %o', async ({
    discussion, deletedBy, isHeaderSupportRequest,
  }) => {
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const creation = createDeferred<void>();
    const ownerHistory = createDeferred<void>();
    const ownerSync = createDeferred<void>();
    let historyReads = 0;
    let syncs = 0;
    const isOwnerHistoryHeld = deletedBy === 'thread' || deletedBy === 'feed';
    createThreadPromise = creation.promise;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages' && isOwnerHistoryHeld && ++historyReads === 1) {
        return ownerHistory.promise.then(() => defaultImplementation(...args)) as never;
      }
      if (args[0] === 'updateAgentV2HostContext' && deletedBy === 'sending' && ++syncs === 1) {
        return ownerSync.promise.then(() => defaultImplementation(...args)) as never;
      }
      return defaultImplementation(...args);
    });
    const target = buildDeferredTarget(discussion);
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    if (isHeaderSupportRequest) {
      expect(result!.requestSupport('header')).toBe(true);
      expect(callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread')).toBe(true);
    } else {
      result!.sendMessage('Question of a deleted discussion');
      expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    }
    if (deletedBy !== 'owner') {
      TeactDOM.render(undefined, root);
      await pause(50);
    }
    // The thread is created while its first question waits for the history of the chat that asked it, or for the
    // wallet's state to reach the server. The feed then opens the discussion without deferring, or by its thread.
    if (deletedBy === 'thread' || deletedBy === 'feed' || deletedBy === 'sending') {
      creation.resolve();
      expect(await waitFor(() => (deletedBy === 'sending' ? syncs === 1 : historyReads === 1), 10, 20)).toBe(true);
    }
    if (deletedBy === 'thread') {
      TeactDOM.render(
        <TargetHarness target={{ kind: 'thread', threadId: THREAD_ID, isNews: true }} hasConsent />, root,
      );
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    } else if (deletedBy !== 'owner') {
      const followerTarget = deletedBy === 'feed'
        ? { ...(discussion === 'news' ? NEWS_TARGET : DIGEST_TARGET) } : buildDeferredTarget(discussion);
      TeactDOM.render(<TargetHarness target={followerTarget} hasConsent />, root);
      expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
      await pause(50);
      expect(result!.isSendDisabled).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual(isHeaderSupportRequest ? [] : [
        expect.objectContaining({ text: 'Question of a deleted discussion' }),
      ]);
    }

    const deletion = result!.cancelPendingRequests();
    TeactDOM.render(undefined, root);
    await pause(50);
    creation.resolve();
    expect(await deletion).toBe(THREAD_ID);
    // The deletion of a thread the chat holds a question for drops that chat's queue
    if (deletedBy === 'thread' || deletedBy === 'sending') dropAgentV2BackgroundQueue(THREAD_ID);
    ownerHistory.resolve();
    ownerSync.resolve();
    await pause(100);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(getAgentV2LocalState().pendingDiscussionThreads.size).toBe(0);

    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
  });

  it.each(withDiscussions([
    { isSyncFailed: false }, { isSyncFailed: true },
  ]))('follows an opening question being sent after its chat is left: %o', async ({ discussion, isSyncFailed }) => {
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const sync = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult>();
    let syncs = 0;
    startRunResponses = [run.promise];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'updateAgentV2HostContext' && ++syncs === 1) {
        return sync.promise.then(() => (isSyncFailed
          ? { ok: false, error: { code: 'network_error', retryable: true } }
          : defaultImplementation(...args))) as never;
      }
      return defaultImplementation(...args);
    });
    function getOpeningSends() {
      return callApiMock.mock.calls.filter(([method, command]) => method === 'startAgentV2Run'
        && (command as { input: { text: string } }).input.text === 'Question being sent');
    }
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Question being sent');
    expect(await waitFor(() => syncs === 1, 10, 20)).toBe(true);
    // A question asked meanwhile waits behind it
    result!.sendMessage('Second question');
    expect(await waitFor(() => result?.queuedMessageCount === 1, 10, 20)).toBe(true);

    // The opening question's start ends without a run while the chat that asked it is open
    if (isSyncFailed) {
      sync.resolve();
      expect(await waitFor(() => getAgentV2LocalState().pendingDiscussionThreads.size === 0, 10, 20)).toBe(true);
      expect(getOpeningSends()).toEqual([]);
      TeactDOM.render(undefined, root);
      await pause(50);
      TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
      return;
    }
    TeactDOM.render(undefined, root);
    await pause(50);

    // The feed has marked the discussion with its thread, so it opens without deferring
    const feedTarget = { ...(discussion === 'news' ? NEWS_TARGET : DIGEST_TARGET) };
    TeactDOM.render(<TargetHarness target={feedTarget} hasConsent />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.isSendDisabled).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'Question being sent' }),
    ]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);

    sync.resolve();
    expect(await waitFor(() => getOpeningSends().length === 1, 10, 20)).toBe(true);
    await pause(50);
    expect(getOpeningSends()).toHaveLength(1);
    expect(getOpeningSends()[0][1]).toMatchObject({ threadId: THREAD_ID });
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: MESSAGE_ID });
    expect(await waitFor(() => getAgentV2LocalState().pendingDiscussionThreads.size === 0, 10, 20)).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    run.resolve({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: MESSAGE_ID, state: 'completed' });
    await pause(50);
    expect(getOpeningSends()).toHaveLength(1);
  });

  it.each(DISCUSSIONS)('keeps following a later creation when a cancelled one fails: %s', async (discussion) => {
    const firstCreation = createDeferred<void>();
    const secondCreation = createDeferred<void>();
    let creationAttempts = 0;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'createAgentV2Thread' && ++creationAttempts === 1) {
        return firstCreation.promise.then(() => ({
          ok: false, error: { code: 'rate_limited', retryable: true },
        })) as never;
      }
      return defaultImplementation(...args);
    });
    createThreadPromise = secondCreation.promise;
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Cancelled question');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    void result!.cancelPendingRequests();
    TeactDOM.render(undefined, root);
    await pause(50);

    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Later question');
    expect(await waitFor(() => creationAttempts === 2, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    firstCreation.resolve();
    await pause(50);

    TeactDOM.render(<TargetHarness target={buildDeferredTarget(discussion)} hasConsent />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    await pause(50);
    expect(result!.isSendDisabled).toBe(true);
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'Later question' }),
    ]);
    expect(creationAttempts).toBe(2);
    secondCreation.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({ threadId: THREAD_ID, input: { kind: 'append', text: 'Later question' } });
    expect(creationAttempts).toBe(2);
  });

  it.each([
    { code: undefined, shouldMountFirst: false },
    { code: 'rate_limited', shouldMountFirst: true },
    { code: 'news_unavailable', shouldMountFirst: false },
  ] as const)('retains a failed news question after remount: %o', async ({ code, shouldMountFirst }) => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    const shouldSendFollowup = code === 'news_unavailable';
    const creation = createDeferred<void>();
    const defaultImplementation = callApiMock.getMockImplementation()!;
    let creationAttempts = 0;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'createAgentV2Thread' && ++creationAttempts <= 2) {
        const failure = code ? { ok: false, error: { code, retryable: true } } : undefined;
        return (creationAttempts === 1 ? creation.promise.then(() => failure) : Promise.resolve(failure)) as never;
      }
      return defaultImplementation(...args);
    });
    const target: AgentV2ChatTarget = {
      ...NEWS_TARGET, shouldDeferCreation: true,
      discussionNaming: { title: 'Discussion title', followups: [NEWS_FOLLOWUP.text] },
    };
    const receiverRoot = document.createElement('div');
    document.body.appendChild(receiverRoot);
    try {
      TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      if (shouldSendFollowup) result!.sendFollowup(result!.messages[0].id, result!.messages[0].followups![0]);
      else result!.sendMessage('Keep this question across layouts');
      expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
      const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
      if (!shouldMountFirst) {
        TeactDOM.render(undefined, root);
        await pause(50);
      }
      TeactDOM.render(<TargetHarness target={target} hasConsent />, receiverRoot);
      expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
      await pause(50);
      if (shouldMountFirst) {
        TeactDOM.render(undefined, root);
        await pause(50);
      }
      creation.resolve();
      expect(await waitFor(() => Boolean(result?.historyFailure), 10, 20)).toBe(true);
      await pause(50);
      expect(result!.hasPendingQuestion).toBe(true);
      const receiverQuestion = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ text: question.text, timestamp: question.timestamp }),
      ]);
      expect(result!.historyFailure).toMatchObject({ text: expect.any(String), isRetrying: false });
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
        .toEqual([['createAgentV2Thread', { news: NEWS_TARGET.news }]]);
      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

      result!.retryHistory();
      expect(await waitFor(() => creationAttempts === 2, 10, 20)).toBe(true);
      await pause(50);
      expect(result!.hasPendingQuestion).toBe(true);
      expect(result!.historyFailure).toMatchObject({ text: expect.any(String), isRetrying: false });
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([receiverQuestion]);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

      result!.retryHistory();
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
        .toBe(true);
      await pause(50);
      expect(result!.historyFailure).toBeUndefined();
      expect(result!.hasPendingQuestion).toBe(false);
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ id: receiverQuestion.id, text: question.text, timestamp: question.timestamp }),
      ]);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toEqual([
        ['createAgentV2Thread', { news: NEWS_TARGET.news }],
        ['createAgentV2Thread', { news: NEWS_TARGET.news }],
        ['createAgentV2Thread', { news: NEWS_TARGET.news }],
      ]);
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(sends).toHaveLength(1);
      expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: question.text } });
      if (shouldSendFollowup) {
        expect(sends[0][1]).toMatchObject({
          followupOf: { messageId: ASSISTANT_MESSAGE_ID, followupId: NEWS_FOLLOWUP.id },
        });
      }
    } finally {
      TeactDOM.render(undefined, receiverRoot);
      receiverRoot.remove();
    }
  });

  it.each([false, true])('drops a failed news creation question with no receiver: receiver closed=%s', async (
    shouldCloseReceiver,
  ) => {
    const creation = createDeferred<void>();
    let hasCreationFinished = false;
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'createAgentV2Thread') {
        return creation.promise.then(() => {
          hasCreationFinished = true;
          return undefined;
        }) as never;
      }
      return defaultImplementation(...args);
    });
    const target: AgentV2ChatTarget = { ...NEWS_TARGET, shouldDeferCreation: true };
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
    result!.sendMessage('Discard this closed question');
    expect(await waitFor(() => result?.hasPendingQuestion === true, 10, 20)).toBe(true);
    TeactDOM.render(undefined, root);
    await pause(50);
    if (shouldCloseReceiver) {
      TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
      expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
      await pause(50);
      TeactDOM.render(undefined, root);
      await pause(50);
    }
    creation.resolve();
    expect(await waitFor(() => hasCreationFinished, 10, 20)).toBe(true);
    await pause(50);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 204 });
    await pause(50);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && !result.isSendDisabled, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 205 });
    await pause(50);
    expect(result!.hasPendingQuestion).toBe(false);
    expect(result!.historyFailure).toBeUndefined();
    expect(result!.thread).toBeUndefined();
    expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it.each([false, true])('keeps a failed opening question for explicit retry after leaving: %s', async (
    shouldFailAfterUnmount,
  ) => {
    createdThreadNews = NEWS_TARGET.preview;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const history = createDeferred<void>();
    const defaultImplementation = callApiMock.getMockImplementation()!;
    let hasRequestedHistory = false;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages' && !hasRequestedHistory) {
        hasRequestedHistory = true;
        return history.promise.then(() => undefined) as never;
      }
      return defaultImplementation(...args);
    });
    const receiverRoot = document.createElement('div');
    document.body.appendChild(receiverRoot);
    try {
      TeactDOM.render(<TargetHarness target={{ ...NEWS_TARGET, shouldDeferCreation: true }} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      result!.sendMessage('Keep the failed question');
      expect(await waitFor(() => hasRequestedHistory, 10, 20)).toBe(true);
      if (shouldFailAfterUnmount) {
        TeactDOM.render(undefined, root);
        await pause(50);
      } else {
        history.resolve();
        expect(await waitFor(() => Boolean(result?.historyFailure), 10, 20)).toBe(true);
      }
      TeactDOM.render(
        <TargetHarness target={{ kind: 'thread', threadId: THREAD_ID, isNews: true }} hasConsent />, receiverRoot,
      );
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      await pause(50);
      if (shouldFailAfterUnmount) history.resolve();
      else TeactDOM.render(undefined, root);
      expect(await waitFor(() => result?.failedQueueFailureId !== undefined, 10, 20)).toBe(true);
      expect(result!.messages.find(({ isOutgoing }) => isOutgoing)?.text).toBe('Keep the failed question');
      expect(result!.messages.at(-1)).toMatchObject({ failureText: expect.any(String), isRetryAvailable: true });
      publishAgentV2Update({ kind: 'runtimeReady', generation: 203 });
      await pause(50);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([]);
      result!.retryMessage(result!.failedQueueFailureId!);
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
        .toBe(true);
      await pause(50);
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(sends).toHaveLength(1);
      expect(sends[0][1]).toMatchObject({ input: { kind: 'append', text: 'Keep the failed question' } });
    } finally {
      TeactDOM.render(undefined, receiverRoot);
      receiverRoot.remove();
    }
  });

  it.each(withDiscussions([{ code: undefined }, { code: 'rate_limited' }, { code: 'news_unavailable' }] as const))(
    'keeps the first question after a creation failure and sends it once on retry: %o',
    async ({ discussion, code }) => {
      const target = buildDeferredTarget(discussion);
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const defaultImplementation = callApiMock.getMockImplementation()!;
      let hasCreationFailed = false;
      callApiMock.mockImplementation((...args) => {
        if (args[0] === 'createAgentV2Thread' && !hasCreationFailed) {
          hasCreationFailed = true;
          return Promise.resolve(code ? { ok: false, error: { code, retryable: true } } : undefined) as never;
        }
        return defaultImplementation(...args);
      });
      TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      result!.sendMessage('Keep this question');
      expect(await waitFor(() => Boolean(result?.historyFailure), 10, 20)).toBe(true);
      await pause(50);
      const question = result!.messages.find(({ isOutgoing }) => isOutgoing)!;
      expect(question.text).toBe('Keep this question');
      expect(result!.hasPendingQuestion).toBe(true);
      expect(result!.isSendDisabled).toBe(true);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());
      result!.retryHistory();
      expect(await waitFor(() => result?.hasPendingQuestion === false, 10, 20)).toBe(true);
      await pause(50);
      expect(result!.historyFailure).toBeUndefined();
      expect(result!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
        expect.objectContaining({ id: question.id, text: question.text, timestamp: question.timestamp }),
      ]);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread'))
        .toEqual([DISCUSSION_CREATION[discussion], DISCUSSION_CREATION[discussion]].map((args) => (
          ['createAgentV2Thread', args]
        )));
      const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(sends).toHaveLength(1);
      expect(sends[0][1]).toMatchObject({
        threadId: THREAD_ID, input: { kind: 'append', text: 'Keep this question' },
      });
    },
  );

  it('shows a preview post at once and replaces it with the saved post without starting a run', async () => {
    defaultThreadId = REPLACEMENT_THREAD_ID;
    createdThreadNews = {
      eventId: 7, headline: 'Server headline', body: 'Server **body**',
      sources: [{ url: 'https://example.com/news', name: 'Source' }],
      publishedAt: '2026-10-21T10:00:00.000Z',
    };
    hydratedMessages = [{
      ...persistedAssistantTextMessage(),
      newsPost: true,
      followups: [NEWS_FOLLOWUP],
      content: { kind: 'markdown', text: '**Server headline**\n\nServer **body**' },
    }];
    const createThread = createDeferred<void>();
    createThreadPromise = createThread.promise;
    const target: AgentV2ChatTarget = {
      kind: 'news',
      news: { eventId: 7, locale: 'ru' },
      preview: { ...createdThreadNews, headline: 'Feed headline', body: 'Feed **body**' },
    };
    TeactDOM.render(<TargetHarness target={target} />, root);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('createAgentV2Thread', { news: { eventId: 7, locale: 'ru' } });
    expect(result).toMatchObject({
      isOpeningNews: true,
      isSupportRequestVisible: true,
      isInputDisabled: true,
      isRunActive: false,
      messages: [{ text: '**Feed headline**\n\nFeed **body**', isOutgoing: false, isNewsPost: true }],
      news: target.preview,
    });
    expect(result!.activity).toBeUndefined();
    const previewPost = result!.messages[0];
    expect(previewPost.followups).toBeUndefined();
    expect(result!.hints).toBeUndefined();
    expect(getStarterHintsCalls()).toHaveLength(0);

    createThread.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result).toMatchObject({
      isOpeningNews: false,
      isInputDisabled: false,
      isRunActive: false,
      news: createdThreadNews,
      messages: [{
        id: previewPost.id,
        timestamp: previewPost.timestamp,
        text: '**Server headline**\n\nServer **body**',
        isOutgoing: false,
        isNewsPost: true,
        followups: [NEWS_FOLLOWUP],
      }],
    });
    expect(result!.messages).toHaveLength(1);
    expect(result!.activity).toBeUndefined();
    expect(result!.hints).toBeUndefined();
    expect(getStarterHintsCalls()).toHaveLength(0);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it('shows a digest\'s post from the feed at once and keeps its place as the saved post comes', async () => {
    createdThreadDigest = DIGEST;
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const createThread = createDeferred<void>();
    createThreadPromise = createThread.promise;
    const target: AgentV2ChatTarget = { kind: 'digest', digest: { id: DIGEST.id }, digestPreview: DIGEST };
    TeactDOM.render(<TargetHarness target={target} />, root);
    await pause(20);

    expect(result).toMatchObject({
      isOpeningNews: true,
      digest: DIGEST,
      isSupportRequestVisible: true,
      messages: [{ isOutgoing: false, isNewsPost: true, timestamp: Date.parse(DIGEST.windowEnd) }],
    });
    expect(result!.messages).toHaveLength(1);
    const previewPost = result!.messages[0];

    createThread.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result).toMatchObject({
      isOpeningNews: false,
      digest: DIGEST,
      messages: [{ id: previewPost.id, isOutgoing: false, isNewsPost: true }],
    });
    expect(result!.messages).toHaveLength(1);
  });

  it('shows the feed copy of a listed discussion post at once while its history loads', async () => {
    createdThreadNews = {
      eventId: 7, headline: 'Server headline', body: 'Server **body**', publishedAt: '2026-10-21T10:00:00.000Z',
    };
    hydratedMessages = [{
      ...persistedAssistantTextMessage(),
      newsPost: true,
      content: { kind: 'markdown', text: '**Server headline**\n\nServer **body**' },
    }];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const history = createDeferred<void>();
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => defaultImplementation(...args)) as never
      : defaultImplementation(...args)));
    const target: AgentV2ChatTarget = {
      kind: 'thread',
      threadId: THREAD_ID,
      preview: { ...createdThreadNews, headline: 'Feed headline', body: 'Feed **body**' },
    };
    TeactDOM.render(<TargetHarness target={target} />, root);
    await pause(20);

    expect(result).toMatchObject({
      isOpeningNews: true,
      messages: [{ text: '**Feed headline**\n\nFeed **body**', isOutgoing: false, isNewsPost: true }],
      news: target.preview,
    });
    const previewPost = result!.messages[0];

    history.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result).toMatchObject({
      isOpeningNews: false,
      news: createdThreadNews,
      messages: [{
        id: previewPost.id,
        timestamp: previewPost.timestamp,
        text: '**Server headline**\n\nServer **body**',
        isNewsPost: true,
      }],
    });
    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread', expect.anything());
  });

  it.each([
    {
      scenario: 'creation',
      expected: {
        body: 'Creation body',
        sources: [{ url: 'https://example.com/creation' }],
        imageUrl: 'https://example.com/feed.png',
      },
    },
    {
      scenario: 'preview',
      expected: {
        body: 'Feed body', sources: [{ url: 'https://example.com/feed' }], imageUrl: 'https://example.com/feed.png',
      },
    },
    { scenario: 'explicit empty', expected: { body: '', sources: [], imageUrl: 'https://example.com/feed.png' } },
    {
      scenario: 'different event',
      expected: { body: undefined, sources: undefined, imageUrl: 'https://example.com/history.png' },
    },
  ])('fills missing news body and sources and keeps the feed\'s picture using $scenario', async ({
    scenario, expected,
  }) => {
    const preview: AgentThreadNewsCardV2 = {
      eventId: 7,
      headline: 'Feed headline',
      body: 'Feed body',
      sources: [{ url: 'https://example.com/feed' }],
      imageUrl: 'https://example.com/feed.png',
      publishedAt: '2026-10-21T10:00:00.000Z',
    };
    createdThreadNews = {
      ...preview,
      headline: 'Creation headline',
      body: scenario === 'preview' ? undefined : 'Creation body',
      sources: scenario === 'preview' ? undefined : [{ url: 'https://example.com/creation' }],
    };
    const historyNews: AgentThreadNewsCardV2 = {
      eventId: scenario === 'different event' ? 8 : 7,
      headline: 'History headline',
      excerpt: 'History excerpt',
      imageUrl: 'https://example.com/history.png',
      publishedAt: '2026-10-21T11:00:00.000Z',
      ...(scenario === 'explicit empty' && { body: '', sources: [] }),
    };
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? Promise.resolve({
        ok: true,
        value: { thread: { ...threadSummary(5), news: historyNews }, messages: [] },
      }) as never
      : implementation(...args)));

    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' }, preview }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result!.news).toEqual({ ...historyNews, ...expected });
  });

  it('sends a saved news post follow-up with its server message id and no entry point', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true, followups: [NEWS_FOLLOWUP] }];
    startRunResponses = [createDeferred<AgentV2RunResult>().promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    const post = result!.messages[0];
    result!.sendFollowup(post.id, post.followups![0]);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls).toHaveLength(1);
    expect(runCalls[0][1]).toMatchObject({
      threadId: THREAD_ID,
      input: { kind: 'append', text: NEWS_FOLLOWUP.text },
      followupOf: { messageId: ASSISTANT_MESSAGE_ID, followupId: NEWS_FOLLOWUP.id },
    });
    expect(runCalls[0][1]).not.toHaveProperty('entryPoint');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([
      { isNewsPost: true }, { text: NEWS_FOLLOWUP.text, isOutgoing: true },
    ]);
  });

  it('shows a legacy headline message as the news post without sending it again', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    starterHints = STAKING_STARTER_HINTS;
    hydratedMessages = [{
      ...persistedUserMessage(), content: { kind: 'markdown', text: createdThreadNews.headline },
      followups: [NEWS_FOLLOWUP],
    }, persistedAssistantTextMessage()];
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    expect(result!.messages).toMatchObject([
      { isNewsPost: true, isOutgoing: false }, { text: 'Retried response', isOutgoing: false },
    ]);
    expect(result!.messages).toHaveLength(2);
    expect(result!.messages[0].followups).toBeUndefined();
    expect(result!.hints).toBeUndefined();
    expect(getStarterHintsCalls()).toHaveLength(1);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it.each([
    ['thread', undefined], ['thread', 'older-page'], ['news', undefined], ['news', 'older-page'],
  ] as const)(
    'waits for an existing %s discussion history with cursor %s before marking it ready',
    async (kind, nextCursor) => {
      createdThreadNews = {
        eventId: 7, headline: 'Server headline', body: 'Server body', publishedAt: '2026-10-21T10:00:00.000Z',
      };
      starterHints = STAKING_STARTER_HINTS;
      hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
      hydrationNextCursor = nextCursor;
      const history = createDeferred<void>();
      const hints = createDeferred<void>();
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
        ? history.promise.then(() => implementation(...args)) as never
        : args[0] === 'getAgentV2StarterHints'
          ? hints.promise.then(() => implementation(...args)) as never
          : implementation(...args)));

      const target: AgentV2ChatTarget = kind === 'thread'
        ? { kind, threadId: THREAD_ID }
        : { kind, news: { eventId: 7, locale: 'en' } };
      TeactDOM.render(<TargetHarness target={target} />, root);
      expect(await waitFor(() => (
        callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')
      ), 10, 20)).toBe(true);
      if (kind === 'news') {
        expect(await waitFor(() => result?.thread?.id === THREAD_ID, 10, 20)).toBe(true);
      }
      expect(result).toMatchObject({
        isInitialLoadComplete: false,
        isOpeningNews: false,
        messages: kind === 'news' ? [{ isNewsPost: true }] : [],
      });
      expect(result!.hints).toBeUndefined();
      expect(getStarterHintsCalls())
        .toHaveLength(kind === 'thread' ? 1 : 0);

      history.resolve();
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(result!.isOpeningNews).toBe(false);
      expect(result!.messages).toMatchObject([
        ...(nextCursor ? [] : [{ isNewsPost: true, text: '**Server headline**\n\nServer body' }]),
        { text: 'Persisted request', isOutgoing: true },
        { text: 'Retried response', isOutgoing: false },
      ]);
      expect(result!.messages).toHaveLength(nextCursor ? 2 : 3);
      expect(result!.hasOlderMessages).toBe(Boolean(nextCursor));
      expect(result!.hints).toBeUndefined();
      expect(getStarterHintsCalls())
        .toHaveLength(kind === 'thread' ? 1 : 0);
      expect(callApiMock.mock.calls.some(([method]) => method === 'createAgentV2Thread')).toBe(kind === 'news');
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

      hints.resolve();
      await pause(20);
      expect(result!.hints).toBeUndefined();
    },
  );

  it('prefers a saved post to the legacy headline message', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{
      ...persistedUserMessage(), content: { kind: 'markdown', text: createdThreadNews.headline },
    }, { ...persistedAssistantTextMessage(), newsPost: true }];
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    expect(result!.messages).toMatchObject([
      { text: 'Retried response', isNewsPost: true, isOutgoing: false },
      { text: 'Server headline', isOutgoing: true },
    ]);
    expect(result!.messages).toHaveLength(2);
  });

  it('keeps a local post through recovery and clear of an empty old-server thread without sending', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [];
    clearThreadResponse = {
      ok: true,
      value: {
        protocolVersion: 3,
        thread: { ...threadSummary(6), news: createdThreadNews, messageCount: 0 },
        duplicate: false,
      },
    };
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([{ isNewsPost: true, isOutgoing: false }]);
    const postId = result!.messages[0].id;

    callApiMock.mockClear();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 109 });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    result!.clearChat();
    expect(await waitFor(() => result?.thread?.revision === 6, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([{ id: postId, isNewsPost: true, isOutgoing: false }]);
    expect(result!.messages).toHaveLength(1);
    expect(result!.activity).toBeUndefined();
    expect(result!.messages[0].followups).toBeUndefined();
    expect(result!.hints).toBeUndefined();
    expect(getStarterHintsCalls()).toHaveLength(0);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('retryAgentV2Run', expect.anything());

    startRunResponses = [createDeferred<AgentV2RunResult>().promise];
    result!.sendMessage('Question after clear');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(new Set(result!.messages.map(({ id }) => id)).size).toBe(2);
  });

  it('sends the first news question as an ordinary append without an entry point', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [];
    startRunResponses = [createDeferred<AgentV2RunResult>().promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    result!.sendMessage('What does this mean?');
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls).toHaveLength(1);
    expect(runCalls[0][1]).toMatchObject({
      input: { kind: 'append', text: 'What does this mean?' }, threadId: THREAD_ID,
    });
    expect(runCalls[0][1]).not.toHaveProperty('entryPoint');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([
      { isNewsPost: true, isOutgoing: false }, { text: 'What does this mean?', isOutgoing: true },
    ]);
  });

  it.each([
    { kind: 'news', phase: 'pending' }, { kind: 'news', phase: 'complete' }, { kind: 'digest', phase: 'complete' },
  ] as const)(
    'enables the $kind composer once created and preserves a $phase question through late history',
    async ({ kind, phase }) => {
      if (kind === 'news') {
        createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
      } else {
        createdThreadDigest = DIGEST;
      }
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const history = createDeferred<void>();
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
        ? history.promise.then(() => implementation(...args)) as never
        : implementation(...args)));
      startRunResponses = [createDeferred<AgentV2RunResult>().promise];
      const target: AgentV2ChatTarget = kind === 'news'
        ? { kind, news: { eventId: 7, locale: 'en' } } : { kind, digest: { id: DIGEST.id } };
      TeactDOM.render(<TargetHarness target={target} />, root);
      expect(await waitFor(() => result?.thread?.id === THREAD_ID && result.isInputDisabled === false, 10, 20))
        .toBe(true);
      expect(result!.isInitialLoadComplete).toBe(false);
      expect(result!.activity).toBeUndefined();
      result!.sendMessage('What does this mean?');
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
        .toBe(true);
      if (phase === 'complete') {
        publishAgentV2Update({
          kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
        });
        publishAgentV2Update({
          kind: 'messageStarted', ...routing(), messageId: SECOND_ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
        });
        publishAgentV2Update({
          kind: 'textDelta', ...routing(), messageId: SECOND_ASSISTANT_MESSAGE_ID, delta: 'A new answer',
        });
        publishAgentV2Update({
          kind: 'messageCompleted', ...routing(), messageId: SECOND_ASSISTANT_MESSAGE_ID, finishReason: 'stop',
        });
      }
      history.resolve();
      expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
      expect(result!.messages).toMatchObject([
        { isNewsPost: true }, { isOutgoing: true, text: 'What does this mean?' },
        ...(phase === 'complete' ? [{ text: 'A new answer' }] : []),
      ]);
      expect(result!.messages).toHaveLength(phase === 'complete' ? 3 : 2);
      if (phase === 'complete') expect(result!.thread?.revision).toBe(6);
      const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
      expect(runCalls).toHaveLength(1);
      expect(runCalls[0][1]).not.toHaveProperty('entryPoint');
    },
  );

  it.each(['runStarted', 'completed result'] as const)(
    'merges a news question loaded before its %s binding without changing its position',
    async (binding) => {
      createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
      hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
      const history = createDeferred<void>();
      const run = createDeferred<AgentV2RunResult>();
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
        ? history.promise.then(() => implementation(...args)) as never
        : implementation(...args)));
      startRunResponses = [run.promise];
      TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
      expect(await waitFor(() => result?.thread?.id === THREAD_ID && result.isInputDisabled === false, 10, 20))
        .toBe(true);
      result!.sendMessage('Q');
      expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
      const optimisticMessageId = result!.messages.find(({ text }) => text === 'Q')!.id;
      hydratedMessages = [
        ...hydratedMessages,
        { ...persistedUserMessage(), id: INPUT_MESSAGE_ID, content: { kind: 'markdown', text: 'Q' } },
        {
          ...persistedAssistantTextMessage(), id: SECOND_ASSISTANT_MESSAGE_ID,
          content: { kind: 'markdown', text: 'A saved answer' },
        },
      ];
      threadRevision = 6;
      history.resolve();
      expect(await waitFor(() => result?.messages.some(({ text }) => text === 'A saved answer') === true, 10, 20))
        .toBe(true);

      if (binding === 'runStarted') {
        publishAgentV2Update({
          kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
        });
      } else {
        run.resolve({
          clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed',
        });
      }
      expect(await waitFor(() => result?.messages.filter(({ text }) => text === 'Q').length === 1, 10, 20)).toBe(true);
      expect(result!.messages).toMatchObject([
        { isNewsPost: true },
        { id: optimisticMessageId, isOutgoing: true, text: 'Q' },
        { isOutgoing: false, text: 'A saved answer' },
      ]);
      expect(result!.messages).toHaveLength(3);
    },
  );

  it('keeps an early news question and its connection error when history finishes loading', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const history = createDeferred<void>();
    const run = createDeferred<AgentV2RunResult | undefined>();
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => implementation(...args)) as never
      : implementation(...args)));
    startRunResponses = [run.promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.thread?.id === THREAD_ID && result.isInputDisabled === false, 10, 20))
      .toBe(true);
    result!.sendMessage('Q');
    expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.find(({ text }) => text === 'Q')!.id;
    run.resolve(undefined);
    expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);
    const errorMessage = result!.messages.at(-1)!;

    history.resolve();
    expect(await waitFor(() => result?.messages[0].text === 'Retried response', 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([
      { isNewsPost: true },
      { id: optimisticMessageId, isOutgoing: true, text: 'Q' },
      { isOutgoing: false, error: { code: 'network_error', retryable: true } },
    ]);
    expect(result!.messages).toHaveLength(3);
    expect(result!.messages.filter(({ text }) => text === 'Q')).toHaveLength(1);
    expect(result!.messages.at(-1)).toEqual(errorMessage);
  });

  it('blocks news questions during runtime recovery until history has loaded', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    startRunResponses = [createDeferred<AgentV2RunResult>().promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    const history = createDeferred<void>();
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => implementation(...args)) as never
      : implementation(...args)));
    callApiMock.mockClear();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 111 });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    expect(result!.isInputDisabled).toBe(true);

    result!.sendMessage('Q');
    await pause(20);
    expect(result!.messages.some(({ text }) => text === 'Q')).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    history.resolve();
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.isRunActive).toBe(false);
    expect(result!.messages).toMatchObject([{ isNewsPost: true }]);
    expect(result!.messages).toHaveLength(1);

    result!.sendMessage('Q');
    expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Q')).toHaveLength(1);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Q' }, threadId: THREAD_ID,
    }));
  });

  it('blocks news input and clear after history fails until a retry succeeds', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const history = createDeferred<void>();
    const retryHistory = createDeferred<void>();
    let shouldFailHistory = true;
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] !== 'getAgentV2Messages') return implementation(...args);
      return shouldFailHistory
        ? history.promise.then(() => ({ ok: false, error: { code: 'network_error', retryable: true } })) as never
        : retryHistory.promise.then(() => implementation(...args)) as never;
    });
    startRunResponses = [createDeferred<AgentV2RunResult>().promise];
    clearThreadResponse = {
      ok: true,
      value: { protocolVersion: 3, thread: { ...threadSummary(6), news: createdThreadNews }, duplicate: false },
    };
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.thread?.id === THREAD_ID && result.isInputDisabled === false, 10, 20))
      .toBe(true);
    expect(result!.isInitialLoadComplete).toBe(false);

    history.resolve();
    expect(await waitFor(() => result?.historyFailure?.text === '$agent_connection_lost', 10, 20))
      .toBe(true);
    expect(result!.messages.some(({ failureText }) => failureText)).toBe(false);
    expect(result!.isInputDisabled).toBe(true);
    result!.sendMessage('Q');
    result!.clearChat();
    await pause(20);
    expect(result!.messages.some(({ text }) => text === 'Q')).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('clearAgentV2Thread', expect.anything(), expect.anything());

    shouldFailHistory = false;
    publishAgentV2Update({ kind: 'runtimeReady', generation: 113 });
    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length === 2
    ), 10, 20)).toBe(true);
    expect(result!.isInputDisabled).toBe(true);
    result!.sendMessage('Q');
    result!.clearChat();
    await pause(20);
    expect(result!.messages.some(({ text }) => text === 'Q')).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('clearAgentV2Thread', expect.anything(), expect.anything());

    retryHistory.resolve();
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    result!.clearChat();
    expect(await waitFor(() => result?.thread?.revision === 6 && result.isInputDisabled === false, 10, 20))
      .toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('clearAgentV2Thread', THREAD_ID, 5);
    result!.sendMessage('Q');
    expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Q')).toHaveLength(1);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Q' }, threadId: THREAD_ID,
    }));
  });

  it('keeps one news question after runtime recovery and an undefined run result', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const run = createDeferred<AgentV2RunResult | undefined>();
    startRunResponses = [run.promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    const history = createDeferred<void>();
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => implementation(...args)) as never
      : implementation(...args)));
    callApiMock.mockClear();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 110 });
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
      .toBe(true);
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    history.resolve();
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    result!.sendMessage('Q');
    expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.find(({ text }) => text === 'Q')!.id;
    run.resolve(undefined);
    expect(await waitFor(() => result?.isRunActive === false, 10, 20)).toBe(true);
    hydratedMessages = [...hydratedMessages, { ...persistedUserMessage(), content: { kind: 'markdown', text: 'Q' } }];
    publishAgentV2Update({ kind: 'runtimeReady', generation: 112 });
    expect(await waitFor(() => result?.messages.some(({ id, text }) => text === 'Q' && id !== optimisticMessageId)
      === true, 10, 20)).toBe(true);

    expect(result!.messages.filter(({ text }) => text === 'Q')).toHaveLength(1);
  });

  it('keeps one news question after an interrupted run recovers its persisted history', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const run = createDeferred<AgentV2RunResult>();
    startRunResponses = [run.promise];
    TeactDOM.render(<TargetHarness target={{ kind: 'news', news: { eventId: 7, locale: 'en' } }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);

    result!.sendMessage('Q');
    expect(await waitFor(() => result?.messages.some(({ text }) => text === 'Q') === true, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.find(({ text }) => text === 'Q')!.id;
    hydratedMessages = [...hydratedMessages, { ...persistedUserMessage(), content: { kind: 'markdown', text: 'Q' } }];
    run.resolve({ clientRunId: CLIENT_RUN_ID, state: 'interrupted' });
    expect(await waitFor(() => result?.messages.some(({ id, text }) => text === 'Q' && id !== optimisticMessageId)
      === true, 10, 20)).toBe(true);

    expect(result!.messages.filter(({ text }) => text === 'Q')).toHaveLength(1);
  });

  it('adds the local post only after the oldest history page has loaded', async () => {
    createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    hydrationNextCursor = 'older';
    olderHydratedMessages = [{
      ...persistedUserMessage(), id: OLDER_MESSAGE_ID,
      content: { kind: 'markdown', text: `${createdThreadNews.headline}!` },
    }];
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result!.messages).toHaveLength(1);
    expect(result!.messages.some(({ isNewsPost }) => isNewsPost)).toBe(false);

    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.hasOlderMessages === false, 10, 20)).toBe(true);
    expect(result!.messages).toMatchObject([
      { isNewsPost: true, isOutgoing: false },
      { text: 'Server headline!', isOutgoing: true },
      { text: 'Persisted request', isOutgoing: true },
    ]);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

  it('keeps the chat waiting while the consent read has no answer, and reads again once the SDK is ready', async () => {
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const consent: { answer?: boolean } = {};
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Consent'
      ? Promise.resolve(consent.answer) as never
      : defaultImplementation(...args)));
    const countConsentReads = () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Consent').length;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => countConsentReads() === 1, 10, 20)).toBe(true);
    await pause(20);
    expect(result!.isConsentAccepted).toBeUndefined();
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Messages', expect.anything());

    consent.answer = true;
    publishAgentV2Update({ kind: 'runtimeReady', generation: 110 });
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(countConsentReads()).toBe(2);
    expect(result!.messages.some(({ text }) => text === 'Persisted request')).toBe(true);
  });

  it('loads as allowed without reading the consent the chat list has read', async () => {
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} hasConsent />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result!.isConsentAccepted).toBe(true);
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Consent');
  });

  it('loads a new chat whose consent read says no once the Agent is allowed, and sends its question then', async () => {
    isConsentAccepted = false;
    const target = { kind: 'new' as const };
    TeactDOM.render(<TargetHarness target={target} initialMessage="What is TON?" hasConsent={false} />, root);
    expect(await waitFor(() => result?.isConsentAccepted === false, 10, 20)).toBe(true);
    await pause(20);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    // Allow stores the consent and tells the chat
    isConsentAccepted = true;
    TeactDOM.render(<TargetHarness target={target} initialMessage="What is TON?" hasConsent />, root);
    result!.checkConsentAgain();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(result!.isConsentAccepted).toBe(true);
    expect(callApiMock.mock.calls.find(([method]) => method === 'startAgentV2Run')![1]).toMatchObject({
      input: { kind: 'append', text: 'What is TON?' },
    });
  });

  it('does not activate snapshot synchronization on recovery without consent', async () => {
    isConsentAccepted = false;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === false, 10, 20)).toBe(true);
    callApiMock.mockClear();

    publishAgentV2Update({ kind: 'runtimeReady', generation: 106 });
    expect(callApiMock).not.toHaveBeenCalledWith('setAgentV2ChatActive', true);
  });

  it.each(['success', 'failure'] as const)('opens history before hints: %s', async (outcome) => {
    hydratedMessages = [];
    starterHints = STAKING_STARTER_HINTS;
    const history = createDeferred<void>();
    const hints = createDeferred<void>();
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages') {
        return history.promise.then(() => implementation(...args)) as never;
      }
      if (args[0] === 'getAgentV2StarterHints') {
        return hints.promise.then(() => (outcome === 'failure' ? undefined : implementation(...args))) as never;
      }
      return implementation(...args);
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => getStarterHintsCalls().length > 0, 10, 20)).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', THREAD_ID);
    expect(result!.isInitialLoadComplete).toBe(false);
    expect(result!.hints).toBeUndefined();

    history.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(result!.messages).toEqual([]);
    expect(result!.hints).toBeUndefined();

    hints.resolve();
    // The balances are not loaded, so the pick goes without the wallet's state
    if (outcome === 'failure') {
      await pause(20);
      expect(result!.hints).toBeUndefined();
      // A read of the history in the background keeps the failed pick until the chat opens again
      publishAgentV2Update({ kind: 'runtimeReady', generation: 111 });
      expect(await waitFor(() => (
        callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length === 2
      ), 10, 20)).toBe(true);
      await pause(20);
      expect(result!.hints).toBeUndefined();
      expect(getStarterHintsCalls()).toEqual([['getAgentV2StarterHints']]);
      return;
    }
    expect(await waitFor(() => Boolean(result?.hints?.length), 10, 20)).toBe(true);
    expect(result!.messages).toEqual([]);
    expect(result!.hints).toEqual([{
      id: 'staking.yield', langCode: 'en', title: '$agent_hint_staking_yield_title', subtitle: '',
      prompt: '$agent_hint_staking_yield_title',
    }]);
    expect(getStarterHintsCalls()).toEqual([['getAgentV2StarterHints']]);

    const hint = result!.hints![0];
    result!.sendHint(hint);

    expect(await waitFor(
      () => Boolean(result?.messages.some((message) => message.text === hint.title)), 10, 20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: hint.title },
      entryPoint: {
        kind: 'emptyState', surface: 'agentTab', hintId: 'staking.yield',
        catalogVersion: 'agent-starter-hints-v2',
      },
    }));
  });

  it.each(['loaded', 'failed'] as const)(
    'picks anew the hints of an empty chat a transition keeps mounted as it shows again, the first pick %s',
    async (firstPick) => {
      hydratedMessages = [];
      const marketStarterHints: AgentV2StarterHints = {
        catalogVersion: 'agent-starter-hints-v2', items: [{ id: 'market.today', group: 'market' }],
      };
      const picks = [firstPick === 'loaded' ? STAKING_STARTER_HINTS : undefined, marketStarterHints];
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2StarterHints'
        ? Promise.resolve(picks[getStarterHintsCalls().length - 1]) as never
        : implementation(...args)));
      const target = { kind: 'thread' as const, threadId: THREAD_ID };
      const renderScreens = (activeKey: number) => TeactDOM.render(
        <Transition name="semiFade" activeKey={activeKey} renderCount={2}>
          {(isActive: boolean, _isFrom: boolean, currentKey: number) => (currentKey === 0
            ? <TargetHarness target={target} isActive={isActive} />
            : <div />)}
        </Transition>,
        root,
      );

      renderScreens(0);
      expect(await waitFor(() => result?.isInitialLoadComplete === true && getStarterHintsCalls().length === 1, 10, 50))
        .toBe(true);
      await pause(20);
      expect(result!.hints?.map(({ id }) => id)).toEqual(firstPick === 'loaded' ? ['staking.yield'] : undefined);

      // Another screen comes over the chat, which stays mounted, and goes
      renderScreens(1);
      await pause(50);
      expect(getStarterHintsCalls()).toHaveLength(1);
      renderScreens(0);
      expect(await waitFor(() => result?.hints?.[0]?.id === 'market.today', 10, 50)).toBe(true);
      expect(getStarterHintsCalls()).toHaveLength(2);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(1);
    },
  );

  it.each([
    ['empty', 0n, 'empty'], ['funded', 1_000_000_000n, 'funded'], ['not loaded', undefined, undefined],
  ] as const)('picks the hints of an empty chat for a wallet whose balance is %s', async (_, amount, walletState) => {
    hydratedMessages = [];
    starterHints = STAKING_STARTER_HINTS;
    mockHasTokenInfo = true;
    mockAccountState = amount === undefined ? {} : { balances: { bySlug: { toncoin: amount } } };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => Boolean(result?.hints?.length), 10, 20)).toBe(true);
    expect(getStarterHintsCalls()).toEqual([
      walletState ? ['getAgentV2StarterHints', walletState] : ['getAgentV2StarterHints'],
    ]);
  });

  it('picks the hints of an empty chat once as it opens and anew as it opens again', async () => {
    hydratedMessages = [];
    const picks: AgentV2StarterHints[] = [STAKING_STARTER_HINTS, {
      catalogVersion: 'agent-starter-hints-v2', items: [{ id: 'market.today', group: 'market' }],
    }];
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2StarterHints'
      ? Promise.resolve(picks[getStarterHintsCalls().length - 1]) as never
      : implementation(...args)));
    const target = { kind: 'thread' as const, threadId: THREAD_ID };
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => Boolean(result?.hints?.length), 10, 20)).toBe(true);
    expect(result!.hints!.map(({ id }) => id)).toEqual(['staking.yield']);

    // Renders, as while the user types, and a read of the history in the background keep the pick
    TeactDOM.render(<TargetHarness target={target} />, root);
    TeactDOM.render(<TargetHarness target={target} />, root);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 110 });
    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length === 2
    ), 10, 20)).toBe(true);
    await pause(20);
    expect(result!.hints!.map(({ id }) => id)).toEqual(['staking.yield']);
    expect(getStarterHintsCalls()).toHaveLength(1);

    // The chat opened again, with the history it had, picks anew
    TeactDOM.render(undefined, root);
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(result!.isOpenedWithCachedHistory).toBe(true);
    expect(result!.hints).toBeUndefined();
    expect(await waitFor(() => Boolean(result?.hints?.length), 10, 20)).toBe(true);
    expect(result!.hints!.map(({ id }) => id)).toEqual(['market.today']);
    expect(getStarterHintsCalls()).toHaveLength(2);
  });

  it('sends the starter hint tapped under the chat list with its entry point', async () => {
    const entryPoint = {
      kind: 'emptyState', surface: 'agentTab', hintId: 'staking.yield', catalogVersion: 'agent-starter-hints-v2',
    } as const;
    TeactDOM.render(
      <TargetHarness target={{ kind: 'new' }} initialMessage="Staking yield" initialHintEntryPoint={entryPoint} />,
      root,
    );
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toEqual([[
      'startAgentV2Run', expect.objectContaining({ input: { kind: 'append', text: 'Staking yield' }, entryPoint }),
    ]]);
  });

  it('shows and sends a message with its recovery phrase replaced by the localized placeholder', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    result!.sendMessage('My words: scheme spot photo card baby mountain device kick cradle pact join borrow. Safe?');

    const sent = 'My words: $agent_secret_words_removed. Safe?';
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => text === sent)), 10, 20)).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: sent },
    }));
  });

  it.each([true, false])('keeps problem reports offered only while the server takes them: %s', async (isAvailable) => {
    isProblemReportAvailable = isAvailable;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.some(
      ([method]) => method === 'getAgentV2ProblemReportAvailability',
    ), 10, 20)).toBe(true);
    await pause(20);

    expect(Boolean(result!.reportProblem)).toBe(isAvailable);
  });

  it('offers no problem report in a news discussion before consent', async () => {
    isProblemReportAvailable = true;
    TeactDOM.render(<TargetHarness target={NEWS_TARGET} hasConsent={false} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    await pause(20);

    expect(result!.reportProblem).toBeUndefined();
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2ProblemReportAvailability');
  });

  it('offers the report of a news discussion at once and takes it away once the server refuses reports', async () => {
    const createThread = createDeferred<void>();
    const availability = createDeferred<boolean>();
    createThreadPromise = createThread.promise;
    problemReportAvailabilityPromise = availability.promise;
    TeactDOM.render(<TargetHarness target={NEWS_TARGET} hasConsent />, root);
    await pause(20);

    // The thread is still being created and the server has not said whether it takes reports
    expect(callApiMock).toHaveBeenCalledWith('createAgentV2Thread', { news: NEWS_TARGET.news });
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2ProblemReportAvailability');
    expect(result!.isOpeningNews).toBe(true);
    expect(result!.reportProblem).toBeDefined();
    const outcome = result!.reportProblem!(undefined, 'Wrong');

    createThread.resolve();
    availability.resolve(false);
    expect(await outcome).toBe('failed');
    expect(await waitFor(() => !result?.reportProblem, 10, 20)).toBe(true);
    expect(callApiMock).not.toHaveBeenCalledWith('reportAgentV2Problem', expect.anything(), expect.anything());
  });

  it('sends a report held while the news discussion creates its thread once the thread comes', async () => {
    isProblemReportAvailable = true;
    const createThread = createDeferred<void>();
    createThreadPromise = createThread.promise;
    TeactDOM.render(<TargetHarness target={NEWS_TARGET} hasConsent />, root);
    await pause(20);
    const outcome = result!.reportProblem!(undefined, 'Wrong');
    // The server has said that it takes reports; the report waits for the thread
    await pause(20);
    expect(callApiMock).not.toHaveBeenCalledWith('reportAgentV2Problem', expect.anything(), expect.anything());

    createThread.resolve();
    expect(await outcome).toBe('sent');
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'reportAgentV2Problem'))
      .toEqual([['reportAgentV2Problem', THREAD_ID, { comment: 'Wrong' }]]);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread')).toHaveLength(1);
  });

  it('coalesces an older-page request and prepends normalized messages', async () => {
    hydratedMessages = [persistedMessage(MESSAGE_ID, 'user', 'Latest request', 20)];
    hydrationNextCursor = 'older-page';
    olderHydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Oldest response', 10)];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);

    const firstRequest = result!.loadOlderMessages();
    const coalescedRequest = result!.loadOlderMessages();
    expect(coalescedRequest).toBe(firstRequest);
    await firstRequest;
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

    expect(result!.messages.map(({ text }) => text)).toEqual(['Oldest response', 'Latest request']);
    expect(result!.hasOlderMessages).toBe(false);
    expect(result!.isLoadingOlderMessages).toBe(false);
    expect(callApiMock.mock.calls.filter(([method, , cursor]) => (
      method === 'getAgentV2Messages' && cursor === 'older-page'
    ))).toHaveLength(1);
  });

  it('keeps a history that did not load apart from the messages and reads it again on Retry', async () => {
    const implementation = callApiMock.getMockImplementation()!;
    const retriedHistory = createDeferred<void>();
    let historyRequestCount = 0;
    callApiMock.mockImplementation((...args) => {
      if (args[0] !== 'getAgentV2Messages') return implementation(...args);
      historyRequestCount += 1;
      return historyRequestCount === 1
        ? Promise.resolve({ ok: false, error: { code: 'network_error', retryable: true } }) as never
        : retriedHistory.promise.then(() => implementation(...args)) as never;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.historyFailure !== undefined, 10, 20)).toBe(true);
    expect(result!.historyFailure).toEqual({ text: '$agent_connection_lost', isRetrying: false });
    expect(result!.messages).toEqual([]);

    result!.retryHistory();
    expect(await waitFor(() => result?.historyFailure?.isRetrying === true, 10, 20)).toBe(true);
    expect(result!.historyFailure!.text).toBe('$agent_connection_lost');

    retriedHistory.resolve();
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    expect(result!.historyFailure).toBeUndefined();
  });

  it('keeps pagination failures separate from the composer and allows retry', async () => {
    hydrationNextCursor = 'older-page';
    shouldFailOlderMessages = true;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);

    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.isLoadingOlderMessages === false, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text }) => text)).toEqual(['Persisted request']);
    expect(result!.isInputDisabled).toBe(false);
    expect(result!.hasOlderMessages).toBe(true);

    shouldFailOlderMessages = false;
    olderHydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Recovered history', 5)];
    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages[0].text).toBe('Recovered history');
  });

  it('drops a stale older page after runtime recovery replaces the cursor', async () => {
    hydrationNextCursor = 'older-page';
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.hasOlderMessages === true, 10, 20)).toBe(true);
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const stalePage = createDeferred<unknown>();
    callApiMock.mockImplementation((...args) => (
      args[0] === 'getAgentV2Messages' && args[2] === 'older-page'
        ? stalePage.promise as never
        : defaultImplementation(...args)
    ));

    const pageRequest = result!.loadOlderMessages();
    hydrationNextCursor = undefined;
    publishAgentV2Update({ kind: 'runtimeReady', generation: 103 });
    expect(await waitFor(() => result?.hasOlderMessages === false, 10, 20)).toBe(true);
    stalePage.resolve({
      ok: true,
      value: {
        thread: threadSummary(threadRevision),
        messages: [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Stale history', 5)],
      },
    });
    await pageRequest;

    expect(result!.messages.some(({ text }) => text === 'Stale history')).toBe(false);
  });

  it('does not preserve live content when interrupted recovery replaces the thread', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    result!.sendMessage('Old-thread optimistic request');
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: SECOND_ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: SECOND_ASSISTANT_MESSAGE_ID,
      delta: 'Old-thread live response',
    });
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Old-thread live response'
    ))), 10, 20)).toBe(true);

    defaultThreadId = REPLACEMENT_THREAD_ID;
    hydratedMessages = [persistedMessage(OLDER_MESSAGE_ID, 'assistant', 'Replacement response', 30)];
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'interrupted',
    });
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Replacement response'
    ))), 10, 20)).toBe(true);

    expect(result!.messages.some(({ text }) => text === 'Persisted request')).toBe(false);
    expect(result!.messages.some(({ text }) => text === 'Old-thread live response')).toBe(false);
    expect(result!.messages.some(({ text }) => text === 'Old-thread optimistic request')).toBe(false);
  });

  it('invokes browser animation frame methods with the global receiver', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    const requestFrameSpy = jest.spyOn(window, 'requestAnimationFrame').mockImplementation(
      function (this: typeof window) {
        expect(this).toBe(window);
        return 42;
      },
    );
    const cancelFrameSpy = jest.spyOn(window, 'cancelAnimationFrame').mockImplementation(
      function (this: typeof window) {
        expect(this).toBe(window);
      },
    );

    try {
      expect(() => publishAgentV2Update({
        kind: 'textDelta',
        ...routing(),
        messageId: ASSISTANT_MESSAGE_ID,
        delta: 'Buffered response',
      })).not.toThrow();
      expect(requestFrameSpy).toHaveBeenCalledTimes(1);

      TeactDOM.render(undefined, root);
      expect(cancelFrameSpy).toHaveBeenCalledWith(42);
    } finally {
      TeactDOM.render(undefined, root);
      requestFrameSpy.mockRestore();
      cancelFrameSpy.mockRestore();
    }
  });

  it('rehydrates a stale thread before allowing the next request', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    result!.sendMessage('Optimistic stale request');
    await pause(0);
    threadRevision = 6;
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'thread_revision_conflict',
      retryable: true,
    });
    await pause(20);

    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      'Persisted request',
      'The conversation was updated. Please try the request again.',
    ]);
    expect(result!.isInputDisabled).toBe(false);

    result!.sendMessage('Request after refresh');
    await pause(0);

    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls.at(-1)?.[1]).toMatchObject({
      threadId: THREAD_ID,
      expectedThreadRevision: 6,
      input: { kind: 'append', text: 'Request after refresh' },
    });
  });

  it('sends a message again once when support has moved the thread on', async () => {
    threadSupport = { state: 'operator' };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    let resolveResend!: (value: AgentV2RunResult) => void;
    const historyRequestsByRun: number[] = [];
    mockStartRuns(() => {
      threadRevision = 6;
      return conflictRun('conflicted-run');
    }, () => new Promise((resolve) => {
      resolveResend = resolve;
    }), historyRequestsByRun);

    result!.sendMessage('Question for support');
    expect(await waitFor(() => Boolean(resolveResend) && result?.isInputDisabled === true, 10, 20)).toBe(true);
    await pause(20);
    expect(selectOutgoingTexts()).toEqual(['Persisted request', 'Question for support']);
    expect(result!.messages.some(({ failureText, error }) => failureText || error)).toBe(false);

    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 7, inputMessageId: INPUT_MESSAGE_ID });
    threadRevision = 7;
    hydratedMessages = [persistedUserMessage(), {
      id: INPUT_MESSAGE_ID,
      threadId: THREAD_ID,
      role: 'user',
      status: 'complete',
      content: { kind: 'markdown', text: 'Question for support' },
      createdAt: '2026-08-07T10:01:00.000Z',
    }];
    resolveResend({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed' });
    expect(await waitFor(() => result?.isRunActive === false && !result.isInputDisabled, 10, 20)).toBe(true);
    await pause(20);

    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls.map(([, command]) => command)).toEqual([
      expect.objectContaining({ expectedThreadRevision: 5, input: { kind: 'append', text: 'Question for support' } }),
      expect.objectContaining({ expectedThreadRevision: 6, input: { kind: 'append', text: 'Question for support' } }),
    ]);
    expect(historyRequestsByRun[1] - historyRequestsByRun[0]).toBe(1);
    expect(selectOutgoingTexts()).toEqual(['Persisted request', 'Question for support']);
    expect(result!.messages.some(({ failureText, error }) => failureText || error)).toBe(false);
  });

  it('reports a second revision conflict of a support message without sending it a third time', async () => {
    threadSupport = { state: 'waiting' };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    mockStartRuns(() => {
      threadRevision = 6;
      return conflictRun('first-run');
    }, () => {
      threadRevision = 7;
      return conflictRun('second-run');
    });

    result!.sendMessage('Question for support');
    expect(await waitFor(() => Boolean(result?.messages.some(({ failureText }) => failureText)), 10, 20)).toBe(true);
    await pause(20);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(2);
    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      'Persisted request',
      'The conversation was updated. Please try the request again.',
    ]);
    expect(result!.isInputDisabled).toBe(false);
  });

  it('reports a revision conflict of a support message when the thread cannot be read again', async () => {
    threadSupport = { state: 'operator' };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    let isHistoryUnavailable = false;
    mockStartRuns(() => {
      isHistoryUnavailable = true;
      return conflictRun('conflicted-run');
    }, () => conflictRun('unexpected-run'));
    const baseImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (isHistoryUnavailable && args[0] === 'getAgentV2Messages'
      ? Promise.resolve({ ok: false, error: { code: 'network_error', retryable: true } }) as never
      : baseImplementation(...args)));

    result!.sendMessage('Question for support');
    expect(await waitFor(() => Boolean(result?.messages.some(({ failureText }) => failureText)), 10, 20)).toBe(true);
    await pause(20);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(1);
    expect(result!.messages.filter(({ failureText }) => failureText).map(({ failureText }) => failureText)).toEqual([
      'The conversation was updated. Please try the request again.',
    ]);
    expect(result!.isInputDisabled).toBe(false);
  });

  it.each([
    ['a message without support', 'append', undefined],
    ['a message after support closed the thread', 'append', { state: 'closed' as const }],
    ['an edit without support', 'edit', undefined],
    ['a regenerated answer without support', 'regenerate', undefined],
    ['a regenerated answer after support closed the thread', 'regenerate', { state: 'closed' as const }],
  ] as const)('reports a revision conflict of %s', async (_, command, support) => {
    threadSupport = support;
    if (command === 'regenerate') hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === hydratedMessages.length,
      10,
      20,
    )).toBe(true);
    const shownTexts = result!.messages.map(({ text }) => text);
    mockStartRuns(() => {
      threadRevision = 6;
      return conflictRun('conflicted-run');
    }, () => conflictRun('unexpected-run'));
    function countHistoryRequests() {
      return callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;
    }
    const historyRequests = countHistoryRequests();

    if (command === 'append') result!.sendMessage('Stale request');
    if (command === 'edit') result!.sendMessage('Edited request', result!.messages[0].id);
    if (command === 'regenerate') result!.retryMessage(result!.messages[1].id);
    expect(await waitFor(() => Boolean(result?.messages.some(({ failureText }) => failureText)), 10, 20)).toBe(true);
    await pause(20);

    const runCalls = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(runCalls).toHaveLength(1);
    expect(runCalls[0][1]).toMatchObject({ input: { kind: command } });
    expect(countHistoryRequests()).toBe(historyRequests + 1);
    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      ...shownTexts,
      'The conversation was updated. Please try the request again.',
    ]);
  });

  function mockStartRuns(
    firstRun: () => Promise<AgentV2RunResult | undefined>,
    secondRun: () => Promise<AgentV2RunResult | undefined>,
    historyRequestsByRun: number[] = [],
  ) {
    const baseImplementation = callApiMock.getMockImplementation()!;
    const runs = [firstRun, secondRun];
    callApiMock.mockImplementation((...args) => {
      if (args[0] !== 'startAgentV2Run') return baseImplementation(...args);
      historyRequestsByRun.push(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length);
      return runs.shift()!() as never;
    });
  }

  // The runtime reports a failed admission before the run settles
  function conflictRun(clientRunId: string) {
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId,
      threadId: THREAD_ID,
      code: 'thread_revision_conflict',
      retryable: true,
    });
    return Promise.resolve<AgentV2RunResult>({ clientRunId, state: 'failed' });
  }

  function selectOutgoingTexts() {
    return result!.messages.filter(({ isOutgoing }) => isOutgoing).map(({ text }) => text);
  }

  it('blocks clear, send and retry commands while a thread clear is pending', async () => {
    let resolveClear!: (value: AgentV2MutationResult<AgentThreadClearResponseV2>) => void;
    clearThreadResponse = new Promise((resolve) => {
      resolveClear = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    const messageId = result!.messages[0].id;
    result!.clearChat();
    result!.clearChat();
    result!.sendMessage('Concurrent request');
    result!.retryMessage(messageId);

    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'clearAgentV2Thread')).toHaveLength(1);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')).toHaveLength(0);

    resolveClear(successfulClear(6));
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 0,
      10,
      20,
    )).toBe(true);
  });

  it('preserves messages and allows retry after a thread clear failure', async () => {
    clearThreadResponse = {
      ok: false,
      error: { code: 'network_error', retryable: true },
    };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.clearChat();
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 2,
      10,
      20,
    )).toBe(true);

    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      'Persisted request',
      'Agent connection was interrupted.',
    ]);

    result!.sendMessage('Retry after clear failure');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run')
        && !result?.messages.some(({ failureText }) => failureText === 'Agent connection was interrupted.'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Retry after clear failure' },
    }));
  });

  it('shows a cleared thread when a clear that got no answer reached the server', async () => {
    clearThreadResponse = {
      ok: false,
      error: { code: 'network_error', retryable: true },
    };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);
    threadRevision = 6;
    hydratedMessages = [];

    result!.clearChat();
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 0,
      10,
      20,
    )).toBe(true);
    clearThreadResponse = {
      ok: true,
      value: { protocolVersion: 3, thread: { ...threadSummary(7), id: THREAD_ID }, duplicate: false },
    };
    result!.clearChat();

    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'clearAgentV2Thread').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('clearAgentV2Thread', THREAD_ID, 6);
  });

  it('clears the chat while an answer runs and never shows the cancelled answer', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    let resolveClear!: (value: AgentV2MutationResult<AgentThreadClearResponseV2>) => void;
    clearThreadResponse = new Promise((resolve) => {
      resolveClear = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Question');
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    expect(await waitFor(() => result?.messages.length === 3 && result.activity !== undefined, 10, 20)).toBe(true);

    result!.clearChat();
    expect(await waitFor(() => result?.messages.length === 0, 10, 20)).toBe(true);
    expect(result!.activity).toBeUndefined();
    expect(result!.isInputDisabled).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('clearAgentV2Thread', THREAD_ID, 6);

    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Late text' });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: SECOND_ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    publishAgentV2Update({ kind: 'runCancelled', ...routing() });
    resolveClear(successfulClear(8));
    await pause(20);
    expect(result!.messages).toEqual([]);
    expect(result!.isInputDisabled).toBe(true);

    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'cancelled' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages).toEqual([]);

    result!.sendMessage('Next question');
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      threadId: THREAD_ID,
      expectedThreadRevision: 8,
      input: { kind: 'append', text: 'Next question' },
    }));
    expect(await waitFor(() => result?.messages.map(({ text }) => text).join() === 'Next question', 10, 20)).toBe(true);
  });

  it.each([
    ['keeps the text a stopped answer has shown, without a rating or suggestions', 'Partial answer'],
    ['drops a stopped answer that has shown nothing', ''],
  ])('%s, also once the history is read again', async (_name, shownText) => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    expect(result!.canStopRun).toBe(false);

    result!.sendMessage('Question');
    expect(await waitFor(() => result?.canStopRun === true, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    if (shownText) {
      publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: shownText });
      publishAgentV2Update({
        kind: 'followupsAvailable', ...routing(), messageId: ASSISTANT_MESSAGE_ID, items: [NEWS_FOLLOWUP],
      });
    }
    expect(await waitFor(() => result?.messages.length === 3, 10, 20)).toBe(true);

    result!.stopRun();
    expect(callApiMock).toHaveBeenCalledWith('stopAgentV2Run', THREAD_ID);
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: ' late' });
    publishAgentV2Update({ kind: 'runCancelled', ...routing() });
    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'cancelled' });
    expect(await waitFor(() => result?.canStopRun === false && !result.isInputDisabled, 10, 20)).toBe(true);
    await pause(20);

    const expectedAnswers = shownText ? [{ text: shownText }] : [];
    const expectAnswers = () => {
      const answers = result!.messages.filter(({ isOutgoing }) => !isOutgoing);
      expect(answers).toEqual(expectedAnswers.map((answer) => expect.objectContaining(answer)));
      answers.forEach((answer) => {
        expect(answer).not.toHaveProperty('isComplete');
        expect(answer.followups).toBeUndefined();
        expect(answer.isStreaming).toBeUndefined();
      });
    };
    expectAnswers();
    expect(result!.activity).toBeUndefined();

    hydratedMessages = [persistedUserMessage(), {
      id: ASSISTANT_MESSAGE_ID,
      threadId: THREAD_ID,
      role: 'assistant',
      status: 'cancelled',
      content: { kind: 'markdown', text: shownText },
      createdAt: '2026-08-07T10:00:01.000Z',
    }];
    threadRevision = 7;
    const hydrationCount = callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;
    publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread: threadSummary(7) });
    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length > hydrationCount
      && result?.thread?.revision === 7 && !result.isInputDisabled
    ), 10, 20)).toBe(true);
    expect(result!.messages).toHaveLength(shownText ? 2 : 1);
    expectAnswers();
  });

  it('offers no stop for an answer that has ended while its run settles', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    result!.sendMessage('Question');
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Answer' });
    expect(await waitFor(() => result?.canStopRun === true && result.messages.at(-1)?.text === 'Answer', 10, 20))
      .toBe(true);

    publishAgentV2Update({
      kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
    });
    expect(await waitFor(() => result?.canStopRun === false, 10, 20)).toBe(true);
    expect(result!.isRunActive).toBe(true);
    result!.stopRun();
    expect(callApiMock).not.toHaveBeenCalledWith('stopAgentV2Run', THREAD_ID);

    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed' });
    expect(await waitFor(() => result?.isRunActive === false && !result.isInputDisabled, 10, 20)).toBe(true);
    expect(result!.canStopRun).toBe(false);
    expect(result!.messages.at(-1)).toMatchObject({ text: 'Answer', isComplete: true });
  });

  it('stops an answer the chat follows after it opens again during the answer', async () => {
    startRunResponses = [new Promise(() => undefined)];
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    result!.sendMessage('Question');
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Partial ' });
    expect(await waitFor(() => result?.messages.at(-1)?.text === 'Partial ', 10, 20)).toBe(true);

    TeactDOM.render(undefined, root);
    await pause(20);
    result = undefined;
    TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
    expect(await waitFor(() => result?.canStopRun === true && result.messages.at(-1)?.text === 'Partial ', 10, 20))
      .toBe(true);

    result!.stopRun();
    expect(callApiMock).toHaveBeenCalledWith('stopAgentV2Run', THREAD_ID);
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'late' });
    expect(await waitFor(() => result?.canStopRun === false && !result.isInputDisabled, 10, 20)).toBe(true);
    await pause(20);
    expect(result!.activity).toBeUndefined();
    expect(result!.messages.at(-1)).toMatchObject({ text: 'Partial ', isStreaming: undefined });
  });

  it('reads a stopped answer again from the server once the next answer has finished', async () => {
    let resolveFirstRun!: (result: AgentV2RunResult) => void;
    let resolveNextRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [
      new Promise((resolve) => {
        resolveFirstRun = resolve;
      }),
      new Promise((resolve) => {
        resolveNextRun = resolve;
      }),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);
    result!.sendMessage('Question');
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
    });
    publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Partial' });
    expect(await waitFor(() => result?.messages.at(-1)?.text === 'Partial', 10, 20)).toBe(true);
    result!.stopRun();
    resolveFirstRun({
      clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'cancelled',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    result!.sendMessage('Next question');
    expect(await waitFor(() => result?.canStopRun === true, 10, 20)).toBe(true);
    threadRevision = 7;
    hydratedMessages = [persistedUserMessage(), {
      id: ASSISTANT_MESSAGE_ID,
      threadId: THREAD_ID,
      role: 'assistant',
      status: 'complete',
      content: { kind: 'markdown', text: 'Partial answer the server finished' },
      createdAt: '2026-08-07T10:00:01.000Z',
    }];
    const getHydrationCount = () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;
    const hydrationCount = getHydrationCount();
    publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread: threadSummary(7) });
    await pause(40);
    expect(getHydrationCount()).toBe(hydrationCount);

    resolveNextRun({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
    expect(await waitFor(() => getHydrationCount() > hydrationCount, 10, 20)).toBe(true);
    expect(await waitFor(() => result?.messages.some(
      ({ text }) => text === 'Partial answer the server finished',
    ) === true, 10, 20)).toBe(true);
  });

  describe('questions sent during an answer', () => {
    const getStartedTexts = () => callApiMock.mock.calls
      .filter(([method]) => method === 'startAgentV2Run')
      .map(([, command]) => (command as { input: { text?: string } }).input.text);

    // Starts an answer that shows 'Partial', with `runs` as the results of its run and the runs after it
    async function startAnswer(runs: Array<Promise<AgentV2RunResult | undefined>>) {
      startRunResponses = runs;
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20))
        .toBe(true);
      result!.sendMessage('Question');
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
      publishAgentV2Update({
        kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
      });
      publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Partial' });
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Partial', 10, 20)).toBe(true);
    }

    function runResult(state: AgentV2RunResult['state']): AgentV2RunResult {
      return { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state };
    }

    function deferRun() {
      let resolve!: (result: AgentV2RunResult) => void;
      let reject!: (error: Error) => void;
      const promise = new Promise<AgentV2RunResult>((resolvePromise, rejectPromise) => {
        resolve = resolvePromise;
        reject = rejectPromise;
      });
      return { promise, resolve, reject };
    }

    function switchAccount(accountId: string) {
      buildAgentV2HostContextMock.mockReturnValue(hostContext(accountId));
      publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    }

    // Sends 'Question', which the user's quota holds back before the server takes it, with `queued` queued behind it
    async function holdQuestionByQuota(queued?: string) {
      const run = deferRun();
      startRunResponses = [run.promise, new Promise(() => undefined)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20))
        .toBe(true);
      result!.sendMessage('Question');
      if (queued) result!.sendMessage(queued);
      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'userQuotaChanged',
        quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString() },
      });
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'user_quota_exhausted',
        retryable: true, resetAt,
      });
      run.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.isRunActive === false && result.isSendDisabled, 10, 20)).toBe(true);
      expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
      return resetAt;
    }

    function resetQuota(resetAt: number) {
      publishAgentV2Update({
        kind: 'userQuotaChanged',
        quota: { limit: 20, used: 5, remaining: 15, resetAt: new Date(resetAt).toISOString() },
      });
    }

    const countRetries = () => callApiMock.mock.calls.filter(([method]) => method === 'retryAgentV2Run').length;

    it('shows a queued question at the end at once and sends it once, after the answer has ended', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      expect(result!.isSendQueued).toBe(true);
      expect(result!.isSendDisabled).toBe(false);

      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);
      expect(result!.queuedMessageCount).toBe(1);
      // The question that waits has no stored message to edit, unlike the one being answered
      expect(result!.isMessageEditable(result!.messages.at(-1)!.id)).toBe(false);
      expect(result!.isMessageEditable(result!.messages.find(({ text }) => text === 'Question')!.id)).toBe(true);
      // The answer goes on above the queued question, which waits
      publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: ' answer' });
      expect(await waitFor(() => result?.messages.at(-2)?.text === 'Partial answer', 10, 20)).toBe(true);
      expect(result!.isInputDisabled).toBe(true);
      expect(getStartedTexts()).toEqual(['Question']);

      publishAgentV2Update({
        kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
      });
      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      await pause(40);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      expect(result!.messages.filter(({ text }) => text === 'Next question')).toHaveLength(1);
      // The chat learns which question went, to pin it as a fresh send
      const nextQuestionId = result!.messages.find(({ text }) => text === 'Next question')!.id;
      expect(await waitFor(() => result?.sentQueuedMessage?.id === nextQuestionId, 10, 20)).toBe(true);
      expect(result!.queuedMessageCount).toBe(0);
    });

    it('sends queued questions one after another, in order', async () => {
      const first = deferRun();
      const second = deferRun();
      await startAnswer([first.promise, second.promise, new Promise(() => undefined)]);
      result!.sendMessage('Second');
      result!.sendMessage('Third');
      expect(await waitFor(() => result?.messages.slice(-2).map(({ text }) => text).join() === 'Second,Third', 10, 20))
        .toBe(true);

      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Second']);
      second.resolve({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
      expect(await waitFor(() => getStartedTexts().length === 3, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Second', 'Third']);
    });

    it('sends the queued question as soon as Stop ends the answer, and a second tap doesn\'t stop it', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);
      const countStops = () => callApiMock.mock.calls.filter(([method]) => method === 'stopAgentV2Run').length;

      result!.stopRun();
      result!.stopRun();
      // Stop stays in place, as on Android, while the stopped answer settles
      await pause(40);
      expect(result!.canStopRun).toBe(true);
      first.resolve(runResult('cancelled'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      // Until its run starts, the question the stop sent keeps Stop in place, which a second tap doesn't use
      await pause(40);
      expect(result!.canStopRun).toBe(true);
      result!.stopRun();
      await pause(40);
      expect(countStops()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);

      // Once its run has started, Stop stops it
      publishAgentV2Update({
        kind: 'runStarted', ...routing(), clientRunId: NEXT_CLIENT_RUN_ID, threadRevision: 7,
        inputMessageId: SECOND_USER_MESSAGE_ID,
      });
      await pause(40);
      result!.stopRun();
      expect(countStops()).toBe(2);
    });

    it('takes Stop away once an answer stopped with nothing queued settles', async () => {
      const first = deferRun();
      await startAnswer([first.promise]);

      result!.stopRun();
      await pause(40);
      expect(result!.canStopRun).toBe(false);
      first.resolve(runResult('cancelled'));
      expect(await waitFor(() => result?.isRunActive === false, 10, 20)).toBe(true);
      expect(result!.canStopRun).toBe(false);
      expect(getStartedTexts()).toEqual(['Question']);
    });

    it('fails questions queued for an account switched from; Retry queues them while the answer runs', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      switchAccount('account-two');
      expect(await waitFor(() => result?.messages.at(-1)?.isRetryAvailable === true, 10, 20)).toBe(true);
      expect(result!.messages.at(-2)?.text).toBe('Next question');
      expect(result!.failedQueueFailureId).toBe(result!.messages.at(-1)!.id);
      // The failed question and its failure stay below the answer, and the question has no stored message to edit
      expect(result!.queuedMessageCount).toBe(2);
      expect(result!.isMessageEditable(result!.messages.at(-2)!.id)).toBe(false);

      // Retry works while the answer runs, as on Android, and queues the question behind it
      result!.retryMessage(result!.messages.at(-1)!.id);
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);
      expect(result!.failedQueueFailureId).toBeUndefined();
      await pause(40);
      expect(getStartedTexts()).toEqual(['Question']);

      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it('keeps the queue waiting while the same account\'s authority is published again, with no failure', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      // The account's chains changed, and the runtime invalidated the thread, for the same account
      buildAgentV2HostContextMock.mockReturnValue({ ...hostContext(), activeNetwork: 'tron' });
      publishAgentV2Update({ kind: 'walletAuthorityChanged' });
      publishAgentV2Update({ kind: 'walletAuthorityChanged', threadId: THREAD_ID });
      await pause(40);
      expect(result!.messages.at(-1)?.text).toBe('Next question');
      expect(result!.messages.some(({ error }) => error)).toBe(false);
      expect(result!.failedQueueFailureId).toBeUndefined();
      expect(getStartedTexts()).toEqual(['Question']);

      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it('fails the queue when the active account changes before the runtime publishes its authority', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
      publishAgentV2Update({
        kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
      });
      first.resolve(runResult('completed'));
      expect(await waitFor(() => result?.isRunActive === false, 10, 20)).toBe(true);
      await pause(40);
      expect(getStartedTexts()).toEqual(['Question']);
      expect(result!.messages.at(-2)?.text).toBe('Next question');
      expect(result!.messages.at(-1)?.isRetryAvailable).toBe(true);
      const failureId = result!.messages.at(-1)!.id;
      expect(result!.failedQueueFailureId).toBe(failureId);

      publishAgentV2Update({ kind: 'walletAuthorityChanged' });
      await pause(40);
      expect(getStartedTexts()).toEqual(['Question']);
      expect(result!.failedQueueFailureId).toBe(failureId);
      expect(result!.messages.filter(({ error }) => error)).toHaveLength(1);

      result!.retryMessage(failureId);
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      expect(callApiMock).toHaveBeenCalledWith('updateAgentV2HostContext', hostContext('account-two'));
    });

    it('leaves questions a switch failed where they are, without Retry, once a later question goes', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Failed question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Failed question', 10, 20)).toBe(true);
      switchAccount('account-two');
      expect(await waitFor(() => result?.messages.at(-1)?.isRetryAvailable === true, 10, 20)).toBe(true);

      // A question queued after the failure takes its Retry away, as the failure no longer ends the chat
      result!.sendMessage('Later question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Later question', 10, 20)).toBe(true);
      expect(result!.messages.at(-2)?.isRetryAvailable).toBeFalsy();

      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Later question']);
      await pause(40);
      expect(result!.messages.slice(-3).map(({ text }) => text)).toEqual(['Failed question', '', 'Later question']);
      expect(result!.messages.at(-2)).toMatchObject({ error: { code: 'internal_error' } });
      expect(result!.messages.at(-2)?.isRetryAvailable).toBeUndefined();
      expect(result!.failedQueueFailureId).toBeUndefined();
    });

    it('keeps the failure a left chat\'s queue met, shown last with Retry once the chat opens again', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      TeactDOM.render(undefined, root);
      switchAccount('account-two');
      publishAgentV2Update({
        kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
      });
      first.resolve(runResult('completed'));
      await pause(60);
      expect(getStartedTexts()).toEqual(['Question']);

      result = undefined;
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => (
        result?.isInitialLoadComplete === true && result.messages.at(-1)?.isRetryAvailable === true
      ), 10, 20)).toBe(true);
      expect(result!.messages.at(-2)?.text).toBe('Next question');

      result!.retryMessage(result!.messages.at(-1)!.id);
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it('sends the question a limit held back first at the reset, as Retry does, then the queue', async () => {
      const retried = deferRun();
      retryRunResponse = retried.promise;
      const resetAt = await holdQuestionByQuota('Next question');
      await pause(40);
      expect(countRetries()).toBe(0);

      resetQuota(resetAt);
      expect(await waitFor(() => countRetries() === 1, 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
      await pause(40);
      // The queued question waits for it, rather than taking its place
      expect(getStartedTexts()).toEqual(['Question']);
      expect(result!.messages.filter(({ text }) => text === 'Question')).toHaveLength(1);

      retried.resolve({ ...runResult('completed') });
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      expect(countRetries()).toBe(1);
    });

    it('keeps the quota-held question and its resend after rejected support', async () => {
      const retried = deferRun();
      retryRunResponse = retried.promise;
      const resetAt = await holdQuestionByQuota('Next question');
      const heldQuestion = result!.messages.find(({ text }) => text === 'Question')!;
      const support = deferRun();
      startRunResponses = [support.promise, new Promise(() => undefined)];

      expect(result!.requestSupport('header')).toBe(true);
      expect(await waitFor(() => getStartedTexts().length === 2
        && result!.messages.some(({ text }) => text === '$agent_support_request_message'), 10, 20)).toBe(true);
      expect(result!.messages).toContainEqual(heldQuestion);

      publishAgentV2Update({
        kind: 'runFailed', clientRunId: NEXT_CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'support_escalation_rate_limited', retryable: false,
      });
      support.resolve({
        clientRunId: NEXT_CLIENT_RUN_ID,
        state: 'failed',
      });
      expect(await waitFor(() => result?.isRunActive === false, 10, 20)).toBe(true);
      expect(result!.messages).toContainEqual(heldQuestion);
      expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });

      resetQuota(resetAt);
      expect(await waitFor(() => countRetries() === 1, 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
      expect(getStartedTexts()).toEqual(['Question', '$agent_support_request_message']);

      retried.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 3, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', '$agent_support_request_message', 'Next question']);
      expect(countRetries()).toBe(1);
    });

    it('sends the held question before its queue as new appends to support with current revisions', async () => {
      const resetAt = await holdQuestionByQuota('Q2');
      const heldQuestion = result!.messages.find(({ text }) => text === 'Question')!;
      const queuedQuestion = result!.messages.find(({ text }) => text === 'Q2')!;
      const support = deferRun();
      const question = deferRun();
      startRunResponses = [support.promise, question.promise, new Promise(() => undefined)];
      expect(result!.requestSupport('header')).toBe(true);
      threadRevision = 6;
      publishAgentV2Update({
        kind: 'runStarted', ...routing(), clientRunId: NEXT_CLIENT_RUN_ID,
        threadRevision: 6, inputMessageId: SECOND_USER_MESSAGE_ID,
      });
      expect(await waitFor(() => result?.isRunActive === true
        && result.queuedMessageCount === 2, 10, 20)).toBe(true);
      expect(result!.messages.slice(-2).map(({ id }) => id)).toEqual([heldQuestion.id, queuedQuestion.id]);

      threadSupport = { state: 'waiting' };
      hydratedMessages = [persistedUserMessage(), {
        ...persistedUserMessage(), id: SECOND_USER_MESSAGE_ID,
        content: { kind: 'markdown', text: '$agent_support_request_message' },
      }];
      publishAgentV2Update({
        kind: 'threadChanged', threadId: THREAD_ID, thread: { ...threadSummary(6), support: threadSupport },
      });
      support.resolve({ clientRunId: NEXT_CLIENT_RUN_ID, runId: RUN_ID,
        inputMessageId: SECOND_USER_MESSAGE_ID, state: 'completed' });
      expect(await waitFor(() => getStartedTexts().length === 3 && result?.support?.state === 'waiting'
        && result.sentQueuedMessage?.id === heldQuestion.id, 10, 20)).toBe(true);
      expect(result!.support?.state).toBe('waiting');
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')[2][1]).toEqual({
        threadId: THREAD_ID, expectedThreadRevision: 6,
        input: { kind: 'append', text: 'Question' }, entryPoint: { kind: 'agentTab' },
      });
      expect(result!.messages.filter(({ text }) => text === 'Question')).toMatchObject([{ id: heldQuestion.id }]);

      threadRevision = 7;
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision, inputMessageId: INPUT_MESSAGE_ID });
      question.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 4
        && result?.sentQueuedMessage?.id === queuedQuestion.id, 10, 20)).toBe(true);
      expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')[3][1]).toEqual({
        threadId: THREAD_ID, expectedThreadRevision: 7,
        input: { kind: 'append', text: 'Q2' }, entryPoint: { kind: 'agentTab' },
      });
      resetQuota(resetAt);
      result!.retryAdmission();
      await pause(40);
      expect(countRetries()).toBe(0);
      expect(getStartedTexts()).toEqual(['Question', '$agent_support_request_message', 'Question', 'Q2']);
      expect(result!.messages.filter(({ text }) => text === 'Q2')).toMatchObject([{ id: queuedQuestion.id }]);
      expect(result!.messages.some(({ error }) => error?.code === 'thread_revision_conflict')).toBe(false);
    });

    it('reopens with only the quota-held question after a support request fails', async () => {
      const resetAt = await holdQuestionByQuota('Next question');
      const defaultImplementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => {
        if (args[0] === 'getAgentV2UserQuota') {
          publishAgentV2Update({
            kind: 'userQuotaChanged',
            quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString() },
          });
        }
        return defaultImplementation(...args);
      });
      const support = deferRun();
      startRunResponses = [support.promise, new Promise(() => undefined)];
      expect(result!.requestSupport('header')).toBe(true);
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: NEXT_CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'network_error', retryable: true,
      });
      support.resolve({ clientRunId: NEXT_CLIENT_RUN_ID, state: 'failed' });
      expect(await waitFor(() => result?.isRunActive === false, 10, 20)).toBe(true);

      TeactDOM.render(undefined, root);
      await pause(40);
      result = undefined;
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInitialLoadComplete === true && result.queuedMessageCount === 1, 10, 20))
        .toBe(true);
      expect(result!.messages.filter(({ text }) => text === 'Question')).toHaveLength(1);
      expect(result!.messages.some(({ text }) => text === '$agent_support_request_message')).toBe(false);
      expect(result!.messages.some(({ error }) => error?.code === 'network_error')).toBe(false);

      expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
      const questionRetry = deferRun();
      retryRunResponse = questionRetry.promise;
      resetQuota(resetAt);
      expect(await waitFor(() => countRetries() === 1, 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);

      questionRetry.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 3, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', '$agent_support_request_message', 'Next question']);
      expect(countRetries()).toBe(1);
    });

    it('leaves the question a limit held back for its Retry at the reset when nothing is queued', async () => {
      const resetAt = await holdQuestionByQuota();

      resetQuota(resetAt);
      expect(await waitFor(() => result?.isSendDisabled === false, 10, 20)).toBe(true);
      await pause(40);
      expect(countRetries()).toBe(0);
      expect(result!.composerStatus).toMatchObject({ mode: 'informational', clientRunId: CLIENT_RUN_ID });
    });

    it('retries a capacity-held question once without a reset and once more at a future reset', async () => {
      jest.useFakeTimers();
      const held = deferRun();
      const firstRetry = deferRun();
      const resetRetry = deferRun();
      startRunResponses = [held.promise, new Promise(() => undefined)];
      retryRunResponse = firstRetry.promise;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      result!.sendMessage('Question');
      result!.sendMessage('Next question');
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'agent_capacity_exhausted', retryable: true,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question']);

      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'agent_capacity_exhausted', retryable: true, resetAt,
      });
      retryRunResponse = resetRetry.promise;
      firstRetry.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(resetAt - Date.now() - 1);
      expect(countRetries()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question']);
      await jest.advanceTimersByTimeAsync(2);
      expect(countRetries()).toBe(2);
      expect(callApiMock).toHaveBeenLastCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
      expect(getStartedTexts()).toEqual(['Question']);

      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'agent_capacity_exhausted', retryable: true,
      });
      retryRunResponse = new Promise(() => undefined);
      resetRetry.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(2);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it('keeps the held question and its rate limit when a left chat reopens before the reset', async () => {
      jest.useFakeTimers();
      const held = deferRun();
      const retried = deferRun();
      startRunResponses = [held.promise, new Promise(() => undefined)];
      retryRunResponse = retried.promise;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      result!.sendMessage('Question');
      result!.sendMessage('Next question');
      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'rate_limited',
        retryable: true, resetAt,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);

      TeactDOM.render(undefined, root);
      await jest.advanceTimersByTimeAsync(100);
      result = undefined;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      expect(result!.isInitialLoadComplete).toBe(true);
      expect(result!.composerStatus).toMatchObject({ kind: 'rateLimit', clientRunId: CLIENT_RUN_ID });
      expect(result!.messages.filter(({ text }) => text === 'Question')).toHaveLength(1);
      expect(result!.messages.at(-1)?.text).toBe('Next question');
      await jest.advanceTimersByTimeAsync(resetAt - Date.now() - 1);
      expect(countRetries()).toBe(0);
      expect(getStartedTexts()).toEqual(['Question']);

      await jest.advanceTimersByTimeAsync(2);
      expect(countRetries()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question']);
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
      retried.resolve(runResult('completed'));
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      expect(result!.messages.filter(({ text }) => text === 'Question')).toHaveLength(1);
    });

    it.each(['reset', 'Retry'])('does not hand over a held question already sent again by %s', async (retrySource) => {
      jest.useFakeTimers();
      const held = deferRun();
      const retried = deferRun();
      startRunResponses = [held.promise, new Promise(() => undefined)];
      retryRunResponse = retried.promise;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      result!.sendMessage('Question');
      result!.sendMessage('Next question');
      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'rate_limited',
        retryable: true, resetAt,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);

      if (retrySource === 'Retry') {
        jest.setSystemTime(resetAt + 1);
        result!.retryAdmission();
        TeactDOM.render(undefined, root);
      } else {
        TeactDOM.render(undefined, root);
        await jest.advanceTimersByTimeAsync(resetAt - Date.now() + 1);
      }
      expect(countRetries()).toBe(1);
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
      hydratedMessages = [...hydratedMessages, {
        ...persistedUserMessage(), id: INPUT_MESSAGE_ID, content: { kind: 'markdown', text: 'Question' },
      }];
      result = undefined;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      expect(result!.isInitialLoadComplete).toBe(true);
      expect(result!.messages.filter(({ text }) => text === 'Question')).toHaveLength(1);
      expect(result!.messages.at(-1)?.text).toBe('Next question');
      expect(getStartedTexts()).toEqual(['Question']);

      publishAgentV2Update({
        kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
      });
      retried.resolve(runResult('completed'));
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(1);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it.each([false, true])('resumes a left chat at the rate limit reset unless disposed: %s', async (isDisposed) => {
      jest.useFakeTimers();
      const held = deferRun();
      const retried = deferRun();
      startRunResponses = [held.promise, new Promise(() => undefined)];
      retryRunResponse = retried.promise;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      expect(result!.isInputDisabled).toBe(false);
      result!.sendMessage('Question');
      result!.sendMessage('Next question');
      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'rate_limited',
        retryable: true, resetAt,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);
      expect(result!.isRunActive).toBe(false);
      expect(result!.composerStatus).toMatchObject({ kind: 'rateLimit', clientRunId: CLIENT_RUN_ID });
      expect(result!.messages.at(-1)?.text).toBe('Next question');

      TeactDOM.render(undefined, root);
      if (isDisposed) dropAgentV2BackgroundQueue(THREAD_ID);
      await jest.advanceTimersByTimeAsync(resetAt - Date.now() - 1);
      expect(countRetries()).toBe(0);
      expect(getStartedTexts()).toEqual(['Question']);

      await jest.advanceTimersByTimeAsync(2);
      expect(countRetries()).toBe(isDisposed ? 0 : 1);
      if (!isDisposed) expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
      // The queued question waits for the held question's answer
      expect(getStartedTexts()).toEqual(['Question']);
      retried.resolve(runResult('completed'));
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(isDisposed ? 0 : 1);
      expect(getStartedTexts()).toEqual(isDisposed ? ['Question'] : ['Question', 'Next question']);
    });

    it('keeps the question a limit held back while the same account comes again, not past a switch', async () => {
      await holdQuestionByQuota();

      buildAgentV2HostContextMock.mockReturnValue({ ...hostContext(), activeNetwork: 'tron' });
      publishAgentV2Update({ kind: 'walletAuthorityChanged' });
      await pause(40);
      expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });

      switchAccount('account-two');
      // Its limit still shows, without Retry
      expect(await waitFor(() => {
        const status = result?.composerStatus;
        return status?.kind === 'userQuota' && status.clientRunId === undefined;
      }, 10, 20)).toBe(true);
    });

    it('queues a question sent right after Regenerate, which the thread\'s invalidation doesn\'t fail', async () => {
      hydratedMessages = conversationMessages();
      const regeneration = deferRun();
      startRunResponses = [regeneration.promise, new Promise(() => undefined)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);

      result!.retryMessage(result!.messages[3].id);
      expect(await waitFor(() => result?.isSendQueued === true && !result.isSendDisabled, 10, 20)).toBe(true);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);
      // The runtime invalidates the thread as it starts the regeneration, which is admitted then
      publishAgentV2Update({ kind: 'walletAuthorityChanged', threadId: THREAD_ID });
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6 });
      expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
      expect(result!.messages.map(({ text }) => text))
        .toEqual(['First request', 'First response', 'Second request', 'Next question']);
      expect(result!.failedQueueFailureId).toBeUndefined();

      regeneration.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual([undefined, 'Next question']);
    });

    it('keeps questions a switch failed after the answer under way, and with those the next switch fails', async () => {
      startRunResponses = [new Promise(() => undefined)];
      TeactDOM.render(<Harness />, root);
      expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20))
        .toBe(true);
      result!.sendMessage('Question');
      result!.sendMessage('Second');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Second', 10, 20)).toBe(true);

      // The switch comes before the answer's first words, which still go above the failed question
      switchAccount('account-two');
      expect(await waitFor(() => result?.messages.at(-1)?.isRetryAvailable === true, 10, 20)).toBe(true);
      publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID });
      publishAgentV2Update({
        kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'markdown',
      });
      publishAgentV2Update({ kind: 'textDelta', ...routing(), messageId: ASSISTANT_MESSAGE_ID, delta: 'Partial' });
      expect(await waitFor(() => result?.messages.at(-3)?.text === 'Partial', 10, 20)).toBe(true);
      expect(result!.messages.at(-2)?.text).toBe('Second');
      expect(result!.messages.at(-1)?.isRetryAvailable).toBe(true);

      // A question queued since fails at the next switch, with the first under one failure
      result!.sendMessage('Third');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Third', 10, 20)).toBe(true);
      switchAccount('account-one');
      expect(await waitFor(() => result?.messages.at(-1)?.isRetryAvailable === true, 10, 20)).toBe(true);
      expect(result!.messages.slice(-4).map(({ text }) => text)).toEqual(['Partial', 'Second', 'Third', '']);
      expect(getStartedTexts()).toEqual(['Question']);
    });

    it('keeps sending the queue after the chat is left', async () => {
      const first = deferRun();
      const second = deferRun();
      await startAnswer([first.promise, second.promise]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      TeactDOM.render(undefined, root);
      first.resolve(runResult('completed'));
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      // The chat lets go once the queue has been answered
      second.resolve({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
      await pause(40);
    });

    it('holds the queue while a limit holds', async () => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'userQuotaChanged',
        quota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString() },
      });
      publishAgentV2Update({
        kind: 'runFailed', ...routing(), code: 'user_quota_exhausted', retryable: true, resetAt,
      });
      first.resolve(runResult('failed'));
      expect(await waitFor(() => result?.isSendDisabled === true && result.isRunActive === false, 10, 20))
        .toBe(true);
      await pause(40);
      // The question waits at the end of the chat, rather than meeting the same limit
      expect(getStartedTexts()).toEqual(['Question']);
      expect(result!.messages.at(-1)?.text).toBe('Next question');
    });

    it.each(['navigation', 'failed list deletion', 'failed open chat deletion'] as const)(
      'hands the waiting queue to the chat that reopens after %s', async (reason) => {
        const first = deferRun();
        await startAnswer([first.promise, new Promise(() => undefined)]);
        result!.sendMessage('Next question');
        expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

        if (reason === 'failed list deletion') holdAgentV2BackgroundQueue(THREAD_ID);
        if (reason === 'failed open chat deletion') await result!.cancelPendingRequests();
        TeactDOM.render(undefined, root);
        if (reason !== 'navigation') forgetAgentV2ThreadDeletion(THREAD_ID);
        TeactDOM.render(<Harness />, root);
        expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
        expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);
        // The answer replayed to the chat holds the question back
        await pause(40);
        expect(getStartedTexts()).toEqual(['Question']);

        // The answer ends; the left chat has nothing left to send, and the chat opened again sends the question
        publishAgentV2Update({
          kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
        });
        first.resolve(runResult('completed'));
        expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
        await pause(60);
        expect(getStartedTexts()).toEqual(['Question', 'Next question']);
        expect(result!.messages.filter(({ text }) => text === 'Next question')).toHaveLength(1);
      },
    );

    it.each(['completed', 'failed'] as const)(
      'keeps the queue behind a pending admission when the chat reopens, result=%s', async (outcome) => {
        jest.useFakeTimers();
        const first = deferRun();
        startRunResponses = [first.promise, new Promise(() => undefined)];
        TeactDOM.render(<Harness />, root);
        await jest.advanceTimersByTimeAsync(100);
        result!.sendMessage('Question');
        result!.sendMessage('Next question');
        await jest.advanceTimersByTimeAsync(100);
        expect(getStartedTexts()).toEqual(['Question']);

        TeactDOM.render(undefined, root);
        result = undefined;
        TeactDOM.render(<Harness />, root);
        await jest.advanceTimersByTimeAsync(100);
        expect(result!.isInitialLoadComplete).toBe(true);
        expect(getStartedTexts()).toEqual(['Question']);

        if (outcome === 'completed') {
          publishAgentV2Update({
            kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
          });
          await jest.advanceTimersByTimeAsync(100);
          expect(result!.messages.at(-1)?.text).toBe('Next question');
          expect(getStartedTexts()).toEqual(['Question']);
          publishAgentV2Update({
            kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete',
          });
          first.resolve(runResult('completed'));
        } else {
          first.reject(new Error('Connection lost before admission'));
        }
        await jest.advanceTimersByTimeAsync(100);
        expect(getStartedTexts()).toEqual(['Question', 'Next question']);
        expect(result!.messages.filter(({ text }) => text === 'Next question')).toHaveLength(1);
      },
    );

    it.each([true, false])('holds a list deletion queue left before the request=%s', async (isLeftFirst) => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.queuedMessageCount === 1, 10, 20)).toBe(true);

      if (isLeftFirst) TeactDOM.render(undefined, root);
      holdAgentV2BackgroundQueue(THREAD_ID);
      TeactDOM.render(undefined, root);
      first.resolve(runResult('completed'));
      await pause(60);
      expect(getStartedTexts()).toEqual(['Question']);

      forgetAgentV2ThreadDeletion(THREAD_ID);
      expect(await waitFor(() => getStartedTexts().length === 2, 10, 20)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it('holds a limit reset during deletion and resumes the held question before its queue after failure', async () => {
      jest.useFakeTimers();
      const held = deferRun();
      const retried = deferRun();
      startRunResponses = [held.promise, new Promise(() => undefined)];
      retryRunResponse = retried.promise;
      TeactDOM.render(<Harness />, root);
      await jest.advanceTimersByTimeAsync(100);
      result!.sendMessage('Question');
      result!.sendMessage('Next question');
      const resetAt = Date.now() + 60_000;
      publishAgentV2Update({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'rate_limited',
        retryable: true, resetAt,
      });
      held.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
      await jest.advanceTimersByTimeAsync(100);
      expect(result!.composerStatus).toMatchObject({ kind: 'rateLimit', clientRunId: CLIENT_RUN_ID });
      TeactDOM.render(undefined, root);
      holdAgentV2BackgroundQueue(THREAD_ID);
      await jest.advanceTimersByTimeAsync(resetAt - Date.now() + 1);
      expect(countRetries()).toBe(0);
      expect(getStartedTexts()).toEqual(['Question']);

      forgetAgentV2ThreadDeletion(THREAD_ID);
      await jest.advanceTimersByTimeAsync(100);
      expect(countRetries()).toBe(1);
      retried.resolve(runResult('completed'));
      await jest.advanceTimersByTimeAsync(100);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
    });

    it.each([
      ['left before', true],
      ['left after', false],
    ])('drops the queue of a chat %s its thread is deleted from the list', async (_name, isLeftFirst) => {
      const first = deferRun();
      await startAnswer([first.promise, new Promise(() => undefined)]);
      result!.sendMessage('Next question');
      expect(await waitFor(() => result?.messages.at(-1)?.text === 'Next question', 10, 20)).toBe(true);

      if (isLeftFirst) TeactDOM.render(undefined, root);
      dropAgentV2BackgroundQueue(THREAD_ID);
      first.resolve(runResult('completed'));
      await pause(60);
      expect(getStartedTexts()).toEqual(['Question']);
      TeactDOM.render(undefined, root);
      await pause(60);
      expect(getStartedTexts()).toEqual(['Question']);
    });
  });

  it('restores the server chat with the clear failure after cancelling a running answer', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    clearThreadResponse = { ok: false, error: { code: 'network_error', retryable: true } };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isInputDisabled === false && result.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Question');
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 5, inputMessageId: INPUT_MESSAGE_ID });
    result!.clearChat();
    expect(await waitFor(
      () => result?.messages.at(-1)?.failureText === 'Agent connection was interrupted.',
      10,
      20,
    )).toBe(true);
    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      'Persisted request',
      'Agent connection was interrupted.',
    ]);
    expect(result!.isInputDisabled).toBe(true);

    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'cancelled' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text, failureText }) => failureText ?? text)).toEqual([
      'Persisted request',
      'Agent connection was interrupted.',
    ]);
  });

  it('synchronizes newly saved addresses before starting a run', async () => {
    const currentHostContext = hostContext();
    const savedAddress = {
      id: 'account-one-saved-0',
      name: 'Andry',
      chain: 'ton' as const,
      address: 'EQ-andry',
    };
    currentHostContext.accounts[0].savedAddresses = [savedAddress];
    currentHostContext.savedAddresses = [savedAddress];
    buildAgentV2HostContextMock.mockReturnValue(currentHostContext);
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.sendMessage('Send Andry 0.2 GRAM');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);

    const synchronizeIndex = callApiMock.mock.calls.findIndex(([method]) => (
      method === 'updateAgentV2HostContext'
    ));
    const startIndex = callApiMock.mock.calls.findIndex(([method]) => method === 'startAgentV2Run');
    expect(synchronizeIndex).toBeGreaterThanOrEqual(0);
    expect(synchronizeIndex).toBeLessThan(startIndex);
    expect(callApiMock.mock.calls[synchronizeIndex]).toEqual([
      'updateAgentV2HostContext',
      expect.objectContaining({ savedAddresses: [savedAddress] }),
    ]);
  });

  it('ignores a pending clear completion after authoritative thread replacement', async () => {
    let resolveClear!: (value: AgentV2MutationResult<AgentThreadClearResponseV2>) => void;
    clearThreadResponse = new Promise((resolve) => {
      resolveClear = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.clearChat();
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'threadChanged',
      threadId: REPLACEMENT_THREAD_ID,
      thread: { ...threadSummary(9), id: REPLACEMENT_THREAD_ID },
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages).toEqual([]);

    result!.sendMessage('Request on replacement thread');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').at(-1)).toEqual([
      'startAgentV2Run', expect.objectContaining({
        threadId: REPLACEMENT_THREAD_ID,
        expectedThreadRevision: 9,
      }),
    ]);

    resolveClear(successfulClear(6));
    await pause(20);

    expect(result!.messages.map(({ text }) => text)).toEqual(['Request on replacement thread']);
  });

  it('binds an admitted append to its canonical input ID without ordinary hydration', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    const hydrationCallsBeforeRun = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.sendMessage('Optimistic request');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.at(-1)!.id;
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRun,
    );
    result!.sendMessage('Edited request', optimisticMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited request' },
    }));
  });

  it('truncates an edited suffix only after admission and rebinds the edited message', async () => {
    hydratedMessages = conversationMessages();
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
    const editedMessageId = result!.messages[2].id;

    result!.sendMessage('Edited second request', editedMessageId);
    await pause(0);
    expect(result!.messages.map(({ text }) => text)).toEqual([
      'First request', 'First response', 'Second request', 'Second response',
    ]);

    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    expect(await waitFor(() => result?.messages.length === 3, 10, 20)).toBe(true);
    expect(result!.messages.map(({ text }) => text)).toEqual([
      'First request', 'First response', 'Edited second request',
    ]);
    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    result!.sendMessage('Edited again', editedMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited again' },
    }));
  });

  it('truncates a regeneration target and suffix only after admission', async () => {
    hydratedMessages = conversationMessages();
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);

    result!.retryMessage(result!.messages[1].id);
    await pause(0);
    expect(result!.messages).toHaveLength(4);
    publishAgentV2Update({ kind: 'runStarted', ...routing(), threadRevision: 6 });
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
    expect(result!.messages[0].text).toBe('First request');

    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'completed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it('offers retry for a retryable persisted assistant failure after hydration', async () => {
    hydratedMessages = [
      persistedUserMessage(),
      {
        ...persistedAssistantTextMessage(),
        status: 'error',
        error: { code: 'provider_error', retryable: true },
      },
    ];

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

    expect(result!.messages.at(-1)).toMatchObject({
      error: { code: 'provider_error', retryable: true },
      isRetryAvailable: true,
    });
  });

  it('shows a rating over history at once, settles it by the latest request, keeps none after a clear', async () => {
    hydratedMessages = [
      persistedUserMessage(),
      { ...persistedAssistantTextMessage(), feedback: 'like' },
      { ...persistedAssistantTextMessage(), id: SECOND_ASSISTANT_MESSAGE_ID, status: 'cancelled' },
    ];
    const settleRequests: Array<(value: unknown) => void> = [];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => (args[0] === 'setAgentV2MessageFeedback'
      ? new Promise((resolve) => {
        settleRequests.push(resolve);
      }) as never
      : defaultImplementation(...args)));
    const countFailures = () => mockShowError.mock.calls
      .filter(([options]) => options.error === '$agent_feedback_failed').length;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 3, 10, 20)).toBe(true);
    const [, answer, cancelled] = result!.messages;
    const getFeedback = () => result!.messages[1]?.feedback;
    expect(answer).toMatchObject({ isComplete: true, feedback: 'like' });
    expect(cancelled.isComplete).toBeUndefined();

    expect(await result!.rateMessage(cancelled.id, 'like')).toBeUndefined();
    const supersededRating = result!.rateMessage(answer.id, 'dislike');
    const failedRating = result!.rateMessage(answer.id);
    expect(await waitFor(() => settleRequests.length === 2 && getFeedback() === undefined, 10, 20)).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('setAgentV2MessageFeedback', THREAD_ID, ASSISTANT_MESSAGE_ID, 'dislike');
    const countHydrations = () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;
    const hydrations = countHydrations();
    publishAgentV2Update({ kind: 'runtimeReady', generation: 100 });
    expect(await waitFor(() => countHydrations() > hydrations, 10, 20)).toBe(true);
    await pause(20);
    expect(getFeedback()).toBeUndefined();
    settleRequests[0]({ ok: true, value: { protocolVersion: 3, feedback: 'dislike' } });
    expect(await supersededRating).toBeUndefined();
    expect(getFeedback()).toBeUndefined();
    settleRequests[1]({ ok: false, error: { code: 'network_error', retryable: true } });
    expect(await failedRating).toBeUndefined();
    expect(await waitFor(() => getFeedback() === 'dislike', 10, 20)).toBe(true);
    expect(countFailures()).toBe(1);

    const savedRating = result!.rateMessage(answer.id, 'like');
    expect(await waitFor(() => settleRequests.length === 3, 10, 20)).toBe(true);
    settleRequests[2]({ ok: true, value: { protocolVersion: 3, feedback: 'like' } });
    const checkRating = (await savedRating)!;
    expect(checkRating()).toBe(true);

    const clearedRating = result!.rateMessage(answer.id, 'dislike');
    expect(checkRating()).toBe(false);
    expect(await waitFor(() => settleRequests.length === 4, 10, 20)).toBe(true);
    hydratedMessages = [];
    clearThreadResponse = {
      ok: true,
      value: { protocolVersion: 3, thread: { ...threadSummary(threadRevision + 1), id: THREAD_ID }, duplicate: false },
    };
    result!.clearChat();
    expect(await waitFor(() => result?.messages.length === 0, 10, 20)).toBe(true);
    settleRequests[3]({ ok: false, error: { code: 'network_error', retryable: true } });
    expect(await clearedRating).toBeUndefined();
    expect(checkRating()).toBe(false);
    expect(countFailures()).toBe(1);
    TeactDOM.render(undefined, root);
    expect(checkRating()).toBe(false);
  });

  it('keeps a historical failure without Retry after a newer user question is hydrated', async () => {
    hydratedMessages = conversationMessages();
    hydratedMessages[1] = {
      ...hydratedMessages[1], status: 'error', error: { code: 'provider_error', retryable: true },
    };
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
    expect(result!.messages[1].text).toBe('First response');
    expect(result!.messages[1].error).toEqual({ code: 'provider_error', retryable: true });
    expect(result!.messages[1].isRetryAvailable).toBeUndefined();
  });

  it('takes Retry from the previous failure when a new question is admitted and keeps its partial text', async () => {
    hydratedMessages = [persistedUserMessage(), {
      ...persistedAssistantTextMessage(), status: 'error', error: { code: 'provider_error', retryable: true },
    }];
    let resolveRun!: (value: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const failedMessage = result!.messages[1];
    result!.sendMessage('A new question');
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    expect(result!.messages[1].error).toEqual(failedMessage.error);
    expect(result!.messages[1].isRetryAvailable).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
    });
    expect(await waitFor(() => result?.messages[1].isRetryAvailable === undefined, 10, 20)).toBe(true);
    expect(result!.messages[1]).toMatchObject({
      id: failedMessage.id, text: failedMessage.text, error: failedMessage.error,
    });
    resolveRun({ clientRunId: CLIENT_RUN_ID, runId: RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'completed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it('renders a pre-admission network failure as an assistant message and retries the exact admission', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveRetry!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveInitial = resolve;
    })];
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Retry after reconnect');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveInitial({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'failed',
    });
    expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);

    expect(result!.composerStatus).toBeUndefined();
    expect(result!.messages).toHaveLength(3);
    expect(result!.messages.at(-2)).toMatchObject({
      text: 'Retry after reconnect',
      isOutgoing: true,
    });
    expect(result!.messages.at(-1)).toMatchObject({
      isOutgoing: false,
      error: { code: 'network_error', retryable: true },
      isRetryAvailable: true,
    });
    result!.retryMessage(result!.messages.at(-1)!.id);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRetry({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Retry after reconnect')).toHaveLength(1);
  });

  it('keeps a rejected retry on its existing failed assistant message', async () => {
    let resolveRetryRequest!: (result: AgentV2RunResult) => void;
    hydratedMessages = [
      persistedUserMessage(),
      {
        ...persistedAssistantTextMessage(),
        status: 'error',
        error: { code: 'provider_error', retryable: true },
      },
    ];
    startRunResponses = [new Promise((resolve) => {
      resolveRetryRequest = resolve;
    })];

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const failedMessageId = result!.messages.at(-1)!.id;

    result!.retryMessage(failedMessageId);
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveRetryRequest({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);

    expect(result!.composerStatus).toBeUndefined();
    expect(result!.messages).toHaveLength(2);
    expect(result!.messages.at(-1)).toMatchObject({
      id: failedMessageId,
      error: { code: 'provider_error', retryable: true },
      isRetryAvailable: true,
    });

    result!.retryMessage(failedMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run'),
      10,
      20,
    )).toBe(true);
  });

  it('starts a fresh regeneration after a non-retryable admission rejection', async () => {
    let resolveRetryRequest!: (result: AgentV2RunResult) => void;
    hydratedMessages = [
      persistedUserMessage(),
      {
        ...persistedAssistantTextMessage(),
        status: 'error',
        error: { code: 'provider_error', retryable: true },
      },
    ];
    startRunResponses = [new Promise((resolve) => {
      resolveRetryRequest = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const failedMessageId = result!.messages.at(-1)!.id;
    result!.retryMessage(failedMessageId);
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'regenerate_target_invalid',
      retryable: false,
    });
    resolveRetryRequest({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.at(-1)).toMatchObject({ id: failedMessageId, isRetryAvailable: true });

    result!.retryMessage(failedMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: {
        kind: 'regenerate',
        targetAssistantMessageId: persistedAssistantTextMessage().id,
        userMessageId: persistedUserMessage().id,
      },
    }));
    expect(callApiMock).not.toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
  });

  it('removes an unadmitted optimistic message when the user starts a different request', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveNext!: (result: AgentV2RunResult) => void;
    startRunResponses = [
      new Promise((resolve) => {
        resolveInitial = resolve;
      }),
      new Promise((resolve) => {
        resolveNext = resolve;
      }),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Request that was not admitted');
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'network_error',
      retryable: true,
    });
    resolveInitial({ clientRunId: CLIENT_RUN_ID, inputMessageId: INPUT_MESSAGE_ID, state: 'failed' });
    expect(await waitFor(() => result?.messages.at(-1)?.error?.code === 'network_error', 10, 20)).toBe(true);

    result!.sendMessage('Different request');
    expect(await waitFor(() => Boolean(
      result?.messages.some(({ text }) => text === 'Different request'),
    ), 10, 20))
      .toBe(true);
    expect(result!.messages.some(({ text }) => text === 'Request that was not admitted')).toBe(false);
    resolveNext({ clientRunId: CLIENT_RUN_ID, state: 'completed' });
  });

  it('reuses append admission and canonical binding after a pre-admission quota retry', async () => {
    let resolveInitial!: (result: AgentV2RunResult) => void;
    let resolveRetry!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveInitial = resolve;
    })];
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);

    result!.sendMessage('Quota-delayed request');
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    const optimisticMessageId = result!.messages.at(-1)!.id;
    publishRetryableQuota();
    resolveInitial({
      clientRunId: CLIENT_RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'failed',
    });
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    resolveRetry({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.messages.filter(({ text }) => text === 'Quota-delayed request')).toHaveLength(1);

    result!.sendMessage('After retry edit', optimisticMessageId);
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2,
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').at(-1)).toEqual([
      'startAgentV2Run', expect.objectContaining({
        input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'After retry edit' },
      }),
    ]);
  });

  it('offers quota replay only for a pre-run denial', async () => {
    const resetAt = Date.parse('2026-08-08T00:00:00.000Z');
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: {
        limit: 20,
        used: 19,
        remaining: 1,
        resetAt: new Date(resetAt).toISOString(),
      },
    });
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
    await pause(20);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });

    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
    await pause(20);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', resetAt });
    expect(result!.composerStatus).not.toHaveProperty('clientRunId');
    result!.retryAdmission();
    await pause(0);
    expect(callApiMock).not.toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
  });

  it('unlocks the composer after a successful quota replay and accepts the next request', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'completed' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === false
        && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);

    expect(callApiMock).toHaveBeenCalledWith('retryAgentV2Run', CLIENT_RUN_ID);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRetry,
    );
    expect(result!.composerStatus).toBeUndefined();
    expect(result!.activity).toBeUndefined();

    result!.sendMessage('Request after replay');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'),
      10,
      20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenLastCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: 'Request after replay' },
    }));
  });

  it('prevents duplicate limit replays while the first replay is pending', async () => {
    let resolveRetry!: (result: AgentV2RunResult) => void;
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    result!.retryAdmission();
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 20)).toBe(true);
    result!.retryAdmission();

    expect(callApiMock.mock.calls.filter(([method]) => method === 'retryAgentV2Run')).toHaveLength(1);
    resolveRetry({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it.each([
    ['failed', { clientRunId: CLIENT_RUN_ID, state: 'failed' } as AgentV2RunResult],
    ['missing', undefined],
  ])('unlocks the composer and preserves replay metadata after a %s retry result', async (_name, response) => {
    retryRunResponse = response;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'retryAgentV2Run')
        && result?.isInputDisabled === false,
      10,
      20,
    )).toBe(true);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
  });

  it('preserves replay metadata when a failed replay emitted runStarted', async () => {
    let resolveRetry!: (value: AgentV2RunResult) => void;
    retryRunResponse = new Promise((resolve) => {
      resolveRetry = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);

    result!.retryAdmission();
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: threadRevision + 1,
    });
    resolveRetry({ clientRunId: CLIENT_RUN_ID, state: 'failed' });

    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
  });

  it('terminalizes partial streaming state when only the cancelled result arrives', async () => {
    let resolveRun!: (result: AgentV2RunResult) => void;
    startRunResponses = [new Promise((resolve) => {
      resolveRun = resolve;
    })];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => (
      result?.isInputDisabled === false && result.messages.length === 1
    ), 10, 20)).toBe(true);
    const hydrationCallsBeforeRun = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.sendMessage('Cancel this request');
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run')
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({
      kind: 'runStarted',
      ...routing(),
      threadRevision: 6,
      inputMessageId: INPUT_MESSAGE_ID,
    });
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Partial cancelled response',
    });
    expect(await waitFor(() => result?.messages.at(-1)?.isStreaming === true, 10, 20)).toBe(true);
    const assistantMessageId = result!.messages.at(-1)!.id;

    resolveRun({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'cancelled',
    });
    expect(await waitFor(() => (
      result?.isInputDisabled === false
      && result.messages.at(-1)?.text === 'Partial cancelled response'
      && result.messages.at(-1)?.isStreaming === undefined
    ), 10, 20)).toBe(true);

    expect(result!.messages.at(-1)).toMatchObject({
      id: assistantMessageId,
      text: 'Partial cancelled response',
    });
    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.messages.at(-1)?.isTyping).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessageId]).toMatchObject({ status: 'error' });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRun,
    );
  });

  it('settles a cancelled replay without authoritative hydration', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'cancelled' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => result?.isInputDisabled === false
        && result.composerStatus === undefined,
      10,
      20,
    )).toBe(true);
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(
      hydrationCallsBeforeRetry,
    );
  });

  it('treats an interrupted replay as a retryable failure and preserves its error after hydration', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'interrupted' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    const hydrationCallsBeforeRetry = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    result!.retryAdmission();
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length
        > hydrationCallsBeforeRetry
        && result?.isInputDisabled === false
        && result.messages.length === 3,
      10,
      20,
    )).toBe(true);

    expect(result!.composerStatus).toMatchObject({ kind: 'userQuota', clientRunId: CLIENT_RUN_ID });
    expect(result!.messages.slice(0, 2).map(({ text }) => text)).toEqual([
      'Persisted request',
      'Retried response',
    ]);
    expect(result!.messages.at(-1)).toMatchObject({
      text: '',
      error: { code: 'network_error', retryable: true },
    });
  });

  it('tells an interrupted run once when its stored answer already holds the failure', async () => {
    retryRunResponse = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, state: 'interrupted' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishRetryableQuota();
    expect(await waitFor(() => result?.composerStatus?.kind === 'userQuota', 10, 20)).toBe(true);
    hydratedMessages = [persistedUserMessage(), {
      ...persistedAssistantTextMessage(), status: 'error', error: { code: 'provider_error', retryable: true },
    }];

    result!.retryAdmission();
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.at(-1)?.error?.code === 'provider_error',
      10,
      20,
    )).toBe(true);

    expect(result!.messages).toHaveLength(2);
    expect(result!.messages.filter(({ error }) => error)).toHaveLength(1);
    expect(result!.messages[1]).toMatchObject({ text: 'Retried response', isRetryAvailable: true });
  });

  it('does not let an earlier run settlement unlock a newer run', async () => {
    let resolveFirst!: (result: AgentV2RunResult) => void;
    let resolveSecond!: (result: AgentV2RunResult) => void;
    startRunResponses = [
      new Promise((resolve) => {
        resolveFirst = resolve;
      }),
      new Promise((resolve) => {
        resolveSecond = resolve;
      }),
    ];
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(
      () => result?.isInputDisabled === false && result.messages.length === 1,
      10,
      20,
    )).toBe(true);

    result!.sendMessage('First request');
    expect(await waitFor(() => result?.isInputDisabled === true, 10, 100)).toBe(true);
    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      code: 'agent_capacity_exhausted',
      retryable: true,
    });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
    expect(result!.composerStatus).toEqual({ kind: 'capacity', mode: 'degraded' });
    expect(result!.messages.at(-1)).toMatchObject({ text: 'First request', isOutgoing: true });

    result!.sendMessage('Second request');
    expect(await waitFor(
      () => callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run').length === 2
        && result?.isInputDisabled === true,
      10,
      20,
    )).toBe(true);

    resolveFirst({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    await pause(20);
    expect(result!.isInputDisabled).toBe(true);

    resolveSecond({ clientRunId: CLIENT_RUN_ID, state: 'failed' });
    expect(await waitFor(() => result?.isInputDisabled === false, 10, 20)).toBe(true);
  });

  it('keeps a V1 reveal session active until the streamed response settles visually', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Streamed answer',
    });
    await pause(20);

    const assistantMessage = result!.messages.at(-1)!;
    const presentation = result!.textRevealPresentations[assistantMessage.id];
    expect(assistantMessage).toMatchObject({ text: 'Streamed answer', isStreaming: true });
    expect(presentation).toMatchObject({ status: 'active', shouldRevealFromStart: true });

    result!.consumeTextRevealSession(assistantMessage.id, presentation.key);
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
    await pause(20);

    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessage.id]).toMatchObject({
      status: 'active',
      shouldRevealFromStart: false,
    });

    result!.settleTextRevealSession(assistantMessage.id, presentation.key);
    await pause(20);

    expect(result!.textRevealPresentations[assistantMessage.id]).toMatchObject({
      status: 'settled',
      shouldRevealFromStart: false,
    });
  });

  it('terminates the V1 reveal session when a V2 stream fails', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'markdown',
    });
    publishAgentV2Update({
      kind: 'textDelta',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      delta: 'Partial answer',
    });
    await pause(20);

    const assistantMessageId = result!.messages.at(-1)!.id;
    publishAgentV2Update({
      kind: 'runFailed',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      code: 'agent_capacity_exhausted',
      retryable: true,
    });
    await pause(20);

    expect(result!.messages.at(-1)?.isStreaming).toBeUndefined();
    expect(result!.textRevealPresentations[assistantMessageId]).toMatchObject({
      status: 'error',
      shouldRevealFromStart: false,
    });
  });

  it('opens a wallet deeplink only after activating Send', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    actionPresentationPromise = Promise.resolve(sendPresentation());
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
    await pause(20);
    const message = result!.messages.at(-1)!;
    expect(message.actions).toEqual([action]);
    expect(message.actionPresentations?.[action.id]).toEqual(sendPresentation());
    resolvedAction = {
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    };

    result!.activateAction(message.id, action);
    await pause(20);

    const synchronizeCall = callApiMock.mock.calls.findIndex(([method]) => method === 'updateAgentV2HostContext');
    const resolveCall = callApiMock.mock.calls.findIndex(([method]) => method === 'resolveAgentV2Action');
    expect(synchronizeCall).toBeGreaterThanOrEqual(0);
    expect(resolveCall).toBeGreaterThan(synchronizeCall);
    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(parseDeeplinkTransferParams).toHaveBeenCalledWith(
      'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000', expect.anything(),
    );
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'toncoin', amount: 500000000n, shouldRequireFreshAuth: true,
    });
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('opens Send without an amount through the direct Open Send action', async () => {
    jest.mocked(parseDeeplinkTransferParams).mockReturnValue({ tokenSlug: 'gram' });
    resolvedAction = {
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-defi-private?token=gram',
    } satisfies AgentV2ResolvedAction;
    actionPresentationPromise = Promise.resolve(sendFormPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendFormAction();

    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    await pause(20);

    expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    const message = result!.messages.find(({ actions }) => actions?.some(({ id }) => id === action.id))!;
    expect(message.actionPresentations?.[action.id]).toEqual(sendFormPresentation());
    result!.activateAction(message.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).toHaveBeenCalledWith({ tokenSlug: 'gram', shouldRequireFreshAuth: true });
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it.each([
    [{ toncoin: 5_000_000_000n }, { amount: 5_000_000_000n }],
    [{}, {}],
  ])('fills Send with the balance of an asset the agent was asked to send in full: %o', async (
    bySlug,
    expectedAmount,
  ) => {
    mockAccountState = { balances: { bySlug } };
    jest.mocked(parseDeeplinkTransferParams).mockReturnValue({ toAddress: 'EQ-mom-private', tokenSlug: 'toncoin' });
    resolvedAction = { kind: 'sendForm', url: 'mtw://send/ton:EQ-mom-private?token=toncoin', isMaxAmount: true };
    actionPresentationPromise = Promise.resolve(sendFormPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendFormAction();
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'semantic',
    });
    publishAgentV2Update({ kind: 'actionAvailable', ...routing(), messageId: ASSISTANT_MESSAGE_ID, action });
    await pause(20);
    const message = result!.messages.find(({ actions }) => actions?.some(({ id }) => id === action.id))!;

    result!.activateAction(message.id, action);
    await pause(20);

    expect(mockStartTransfer).toHaveBeenCalledWith({
      toAddress: 'EQ-mom-private', tokenSlug: 'toncoin', ...expectedAmount, shouldRequireFreshAuth: true,
    });
  });

  it.each([
    [false, '$dont_have_required_token', { toAddress: 'EQ-mom-private', tokenSlug: 'usdton' }],
    [true, '$dont_have_required_token', undefined],
    [false, '$unknown_token_address', undefined],
    [true, '$unknown_token_address', undefined],
    [false, '$transfer_link_expired', undefined],
    [true, '$transfer_link_expired', undefined],
  ])('opens Send with the requested asset only while balances load, loaded=%s, error=%s', async (
    areBalancesLoaded,
    error,
    expectedTransfer,
  ) => {
    mockAccountState = areBalancesLoaded ? { balances: { bySlug: {} } } : {};
    jest.mocked(parseDeeplinkTransferParams).mockReturnValue({
      toAddress: 'EQ-mom-private', tokenSlug: 'toncoin', error,
    });
    resolvedAction = { kind: 'sendForm', url: 'mtw://send/ton:EQ-mom-private?token=usdton' };
    actionPresentationPromise = Promise.resolve(sendFormPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendFormAction();
    publishAgentV2Update({
      kind: 'messageStarted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, contentKind: 'semantic',
    });
    publishAgentV2Update({ kind: 'actionAvailable', ...routing(), messageId: ASSISTANT_MESSAGE_ID, action });
    await pause(20);
    const message = result!.messages.find(({ actions }) => actions?.some(({ id }) => id === action.id))!;

    result!.activateAction(message.id, action);
    await pause(20);

    if (expectedTransfer) {
      expect(mockStartTransfer).toHaveBeenCalledWith({ ...expectedTransfer, shouldRequireFreshAuth: true });
      expect(mockShowError).not.toHaveBeenCalled();
    } else {
      expect(mockStartTransfer).not.toHaveBeenCalled();
      expect(mockShowError).toHaveBeenCalledWith({ error });
    }
  });

  it.each([
    {
      name: 'Receive',
      action: receiveAction(),
      resolved: { kind: 'openReceive', chain: 'ton' } satisfies AgentV2ResolvedAction,
      verify: () => expect(mockOpenReceiveModal).toHaveBeenCalledWith({ chain: 'ton' }),
    },
    {
      name: 'Open DApp',
      action: openDappAction(),
      resolved: { kind: 'openDapp', url: FRAGMENT_SITE.url } satisfies AgentV2ResolvedAction,
      verify: () => expect(openSiteMock).toHaveBeenCalledWith(
        FRAGMENT_SITE.url,
        FRAGMENT_SITE.isExternal,
        FRAGMENT_SITE.name,
      ),
    },
  ])('dispatches a resolved $name action after an explicit click', async ({ action, resolved, verify }) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    verify();
  });

  it.each([
    ['the app was removed from Explore', false, []],
    ['the app is restricted in the current region', true, [FRAGMENT_SITE]],
  ] as const)('does not open a DApp when %s', async (_name, isLimitedRegion, sites) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = openDappAction();
    publishAction(action);
    await pause(20);
    resolvedAction = { kind: 'openDapp', url: FRAGMENT_SITE.url } satisfies AgentV2ResolvedAction;
    mockExploreSites = [...sites];
    mockIsLimitedRegion = isLimitedRegion;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(openSiteMock).not.toHaveBeenCalled();
  });

  it.each([
    ['mtw://buy-with-card?chain=solana&provider=moonpay', true],
    ['mtw://buy-with-card?chain=ton&provider=moonpay', false],
    ['mtw://multisend', true],
    ['mtw://send', false],
    ['https://unlisted.example/', false],
  ] as const)('opens only the exact built-in route outside Explore: %s', async (url, shouldOpen) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    jest.mocked(buildAgentBuiltinDapps).mockReturnValue([{ name: 'Buy SOL via MoonPay',
      url: 'mtw://buy-with-card?chain=solana&provider=moonpay' }]);
    const action = { ...openDappAction(), url };
    publishAction(action);
    await pause(20);
    mockExploreSites = [];
    resolvedAction = { kind: 'openDapp', url };
    expect(processDeeplinkMock).not.toHaveBeenCalled();

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    if (shouldOpen) expect(processDeeplinkMock).toHaveBeenCalledWith(url);
    else expect(processDeeplinkMock).not.toHaveBeenCalled();
    expect(openSiteMock).not.toHaveBeenCalled();
    expect(openUrlMock).not.toHaveBeenCalled();
  });

  it('marks an action inactive when explicit resolution rejects it', async () => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = receiveAction();
    publishAction(action);
    await pause(20);
    resolvedAction = { kind: 'inactive' } satisfies AgentV2ResolvedAction;
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
    expect(mockShowError).toHaveBeenCalledWith({ error: 'This action is no longer available.' });
  });

  it.each([
    {
      name: 'source-sided Swap',
      action: swapAction('source'),
      resolved: {
        kind: 'openSwap',
        url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
        tokenInSlug: 'toncoin',
        tokenOutSlug: 'usdton',
        amount: '10',
        amountSide: 'source',
      } satisfies AgentV2ResolvedAction,

    },
    {
      name: 'destination-sided Swap',
      action: swapAction('destination'),
      resolved: {
        kind: 'openSwap',
        url: 'https://my.tt/swap?in=usdton&out=toncoin&amountOut=10',
        tokenInSlug: 'usdton',
        tokenOutSlug: 'toncoin',
        amount: '10',
        amountSide: 'destination',
      } satisfies AgentV2ResolvedAction,

    },
    {
      name: 'TRX purchase form without a source token or amount',
      action: {
        ...swapAction('source'),
        sourceAsset: undefined,
        destinationAsset: { slug: 'trx', chain: 'tron', symbol: 'TRX', decimals: 6 },
        amount: undefined,
        url: 'https://my.tt/swap?out=trx',
      },
      resolved: {
        kind: 'openSwap',
        url: 'https://my.tt/swap?out=trx',
        tokenInSlug: undefined,
        tokenOutSlug: 'trx',
        amount: undefined,
        amountSide: undefined,
      } satisfies AgentV2ResolvedAction,
    },
  ])('revalidates and opens $name in the existing Swap flow', async ({ action, resolved }) => {
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockSwitchToWallet).not.toHaveBeenCalled();
    expect(mockStartSwap).toHaveBeenCalledWith({
      tokenInSlug: resolved.tokenInSlug,
      tokenOutSlug: resolved.tokenOutSlug,
      amountIn: resolved.amountSide === 'source' ? resolved.amount : undefined,
    });
    if (resolved.amountSide === 'destination') {
      expect(mockSetSwapAmountOut).toHaveBeenCalledWith({ amount: resolved.amount });
    } else {
      expect(mockSetSwapAmountOut).not.toHaveBeenCalled();
    }
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('rejects a partial Swap when its requested token disappears from the current swap catalog', async () => {
    const action = {
      ...swapAction('source'),
      sourceAsset: undefined,
      destinationAsset: { slug: 'trx', chain: 'tron', symbol: 'TRX', decimals: 6 },
      amount: undefined,
      url: 'https://my.tt/swap?out=trx',
    };
    resolvedAction = { kind: 'openSwap', url: action.url, tokenOutSlug: 'trx' };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    delete mockSwapTokensBySlug.trx;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(mockShowError).toHaveBeenCalledWith({ error: '$unknown_swap_token' });
    expect(mockStartSwap).not.toHaveBeenCalled();
    expect(mockSwitchToWallet).not.toHaveBeenCalled();
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('rejects a resolved Swap when current wallet eligibility has not reached the runtime yet', async () => {
    const action = swapAction('source');
    resolvedAction = {
      kind: 'openSwap', url: action.url, tokenInSlug: 'toncoin', tokenOutSlug: 'usdton',
      amount: '10', amountSide: 'source',
    };
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    buildAgentV2HostContextMock.mockReturnValue({ ...hostContext(), isTestnet: true });

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(mockStartSwap).not.toHaveBeenCalled();
    expect(mockSwitchToWallet).not.toHaveBeenCalled();
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it.each([true, false])('keeps Agent open when the staking deeplink is handled=%s', async (isHandled) => {
    processDeeplinkMock.mockResolvedValue(isHandled);
    const action = exactStakeAction();
    const resolved = {
      kind: 'openStaking',
      productId: 'liquid',
      tokenSlug: 'toncoin',
      amount: { kind: 'exact', value: '10' },
    } satisfies AgentV2ResolvedAction;
    const deeplink = 'mtw://stake?product=liquid&asset=toncoin&amount=10';
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);
    resolvedAction = resolved;

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(processDeeplinkMock).toHaveBeenCalledWith(deeplink);
    expect(mockSwitchToWallet).not.toHaveBeenCalled();
  });

  it('uses current runtime authority for Swap without Send-specific host synchronization', async () => {
    const action = swapAction('source');
    resolvedAction = {
      kind: 'openSwap',
      url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
      tokenInSlug: 'toncoin',
      tokenOutSlug: 'usdton',
      amount: '10',
      amountSide: 'source',
    } satisfies AgentV2ResolvedAction;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartSwap).toHaveBeenCalledWith({ tokenInSlug: 'toncoin', tokenOutSlug: 'usdton', amountIn: '10' });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(0);
  });

  it('tells why Swap does not open in a view-only wallet', async () => {
    const action = swapAction('source');
    resolvedAction = { kind: 'inactive', reason: 'viewOnlyWallet' } satisfies AgentV2ResolvedAction;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartSwap).not.toHaveBeenCalled();
    expect(processDeeplinkMock).not.toHaveBeenCalled();
    expect(mockShowError).toHaveBeenCalledWith({ error: '$action_not_available_view_mode' });
  });

  it('does not apply an account action after the active account changes during resolution', async () => {
    const resolution = createDeferred<unknown>();
    resolvedActionPromise = resolution.promise;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = receiveAction();
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    buildAgentV2HostContextMock.mockReturnValue(hostContext('account-two'));
    resolution.resolve({ kind: 'openReceive', chain: 'ton' });
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(0);
  });

  it('keeps a hydrated Send action inactive without its local draft', async () => {
    const action = sendAction();
    hydratedMessages = [
      persistedUserMessage(),
      persistedAssistantMessage(action),
    ];
    actionPresentationPromise = Promise.resolve({ kind: 'inactive' });

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    await pause(20);

    const message = result!.messages.at(-1)!;
    expect(message.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
    result!.activateAction(message.id, action);
    await pause(0);

    expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).not.toHaveBeenCalled();
  });

  it('keeps a hydrated Send action inactive', async () => {
    const action = sendAction();
    hydratedMessages = [
      persistedUserMessage(),
      persistedAssistantMessage(action),
    ];
    actionPresentationPromise = Promise.resolve(sendPresentation());
    resolvedAction = { kind: 'inactive' } satisfies AgentV2ResolvedAction;

    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    await pause(20);

    const message = result!.messages.at(-1)!;
    expect(message.actionPresentations?.[action.id]).toEqual(sendPresentation());
    result!.activateAction(message.id, action);
    await pause(20);

    expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('reloads Send presentation after wallet authority changes and ignores the stale result', async () => {
    let resolvePresentation!: (presentation: AgentV2ActionPresentation) => void;
    actionPresentationPromise = new Promise((resolve) => {
      resolvePresentation = resolve;
    });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2ActionPresentation'),
      10,
      20,
    )).toBe(true);
    expect(await waitFor(
      () => Boolean(result!.messages.at(-1)?.actions?.some(({ id }) => id === action.id)),
      10,
      20,
    )).toBe(true);

    actionPresentationPromise = Promise.resolve(sendPresentation());
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    await pause(20);
    resolvePresentation(sendPresentation());
    await pause(20);

    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2ActionPresentation')).toHaveLength(2);
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual(sendPresentation());
  });

  it.each([false, true])('opens Send after a profile update with view-only=%s', async (isViewOnly) => {
    const host = hostContext();
    host.accounts[0].isViewOnly = isViewOnly;
    host.accounts[0].accountType = isViewOnly ? 'viewOnly' : 'regular';
    buildAgentV2HostContextMock.mockReturnValue(host);
    actionPresentationPromise = Promise.resolve(sendPresentation());
    resolvedAction = {
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    } satisfies AgentV2ResolvedAction;
    hasAuthorityChanged = true;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    await pause(20);

    expect(parseDeeplinkTransferParams).toHaveBeenCalledWith(
      'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000', expect.anything(),
    );
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'toncoin', amount: 500000000n, shouldRequireFreshAuth: true,
    });
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it('tells why Send does not open in a view-only wallet and keeps the reason for the next tap', async () => {
    actionPresentationPromise = Promise.resolve({ kind: 'inactive', reason: 'viewOnlyWallet' });
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;
    result!.activateAction(message.id, action);
    await pause(20);
    result!.activateAction(message.id, action);
    await pause(20);

    expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, action.id);
    expect(mockStartTransfer).not.toHaveBeenCalled();
    expect(mockShowError.mock.calls).toEqual([
      [{ error: '$action_not_available_view_mode' }],
      [{ error: '$action_not_available_view_mode' }],
    ]);
  });

  it('opens Send when an unrelated wallet-profile update arrives during action resolution', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({ kind: 'walletAuthorityChanged' });
    resolveSend({
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    });
    await pause(20);

    expect(parseDeeplinkTransferParams).toHaveBeenCalledWith(
      'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000', expect.anything(),
    );
    expect(mockStartTransfer).toHaveBeenCalledWith({
      tokenSlug: 'toncoin', amount: 500000000n, shouldRequireFreshAuth: true,
    });
    expect(processDeeplinkMock).not.toHaveBeenCalled();
  });

  it.each(['account', 'view-only'])('does not open Send when %s changes during resolution', async (change) => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    const changedHost = hostContext(change === 'account' ? 'account-two' : 'account-one');
    if (change === 'view-only') changedHost.accounts[0].isViewOnly = true;
    buildAgentV2HostContextMock.mockReturnValue(changedHost);
    hasAuthorityChanged = true;
    resolveSend({
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();
    expect(result!.messages.at(-1)?.actionPresentations?.[action.id]).toEqual({ kind: 'inactive' });
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(2);
  });

  it('does not open Send when the active sending address changes during resolution', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    const changedContext = hostContext();
    changedContext.accounts[0].addresses.ton = 'EQ-changed-public-address';
    buildAgentV2HostContextMock.mockReturnValue(changedContext);
    hasAuthorityChanged = true;
    resolveSend({
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();
    expect(callApiMock.mock.calls.filter(([method]) => method === 'updateAgentV2HostContext')).toHaveLength(2);
  });

  it('invalidates pending action resolutions when the runtime changes', async () => {
    let resolveSend!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveSend = resolve;
    });
    actionPresentationPromise = Promise.resolve(sendPresentation());
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = sendAction();
    publishSendAction(action);
    await pause(20);
    const message = result!.messages.at(-1)!;

    result!.activateAction(message.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 98 });
    resolveSend({
      kind: 'sendForm',
      url: 'mtw://send/ton:EQ-mom-private?token=toncoin&amount=500000000',
    });
    await pause(20);

    expect(mockStartTransfer).not.toHaveBeenCalled();

    let resolveReceive!: (resolved: unknown) => void;
    resolvedActionPromise = new Promise((resolve) => {
      resolveReceive = resolve;
    });
    const receive = receiveAction();
    publishAction(receive);
    const receiveMessage = result!.messages.at(-1)!;
    result!.activateAction(receiveMessage.id, receive);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 99 });
    resolveReceive({ kind: 'openReceive', chain: 'ton' });
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
  });

  it('does not apply an action that resolves after the Agent view is disposed', async () => {
    const resolution = createDeferred<unknown>();
    resolvedActionPromise = resolution.promise;
    TeactDOM.render(<Harness />, root);
    await pause(20);
    const action = receiveAction();
    publishAction(action);
    await pause(20);

    result!.activateAction(result!.messages.at(-1)!.id, action);
    expect(await waitFor(
      () => callApiMock.mock.calls.some(([method]) => method === 'resolveAgentV2Action'),
      10,
      20,
    )).toBe(true);
    TeactDOM.render(undefined, root);
    resolution.resolve({ kind: 'openReceive', chain: 'ton' });
    await pause(20);

    expect(mockOpenReceiveModal).not.toHaveBeenCalled();
  });

  it('ignores a stale hydration after a newer runtime hydration settles', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Persisted request'
    ))), 10, 20)).toBe(true);
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const staleHydration = createDeferred<unknown>();
    const currentHydration = createDeferred<unknown>();
    let hydrationCount = 0;
    callApiMock.mockImplementation((...args) => {
      if (args[0] !== 'getAgentV2Messages') return defaultImplementation(...args);
      hydrationCount += 1;
      return (hydrationCount === 1 ? staleHydration.promise : currentHydration.promise) as never;
    });

    publishAgentV2Update({ kind: 'runtimeReady', generation: 101 });
    expect(await waitFor(() => hydrationCount === 1, 10, 20)).toBe(true);
    publishAgentV2Update({ kind: 'runtimeReady', generation: 102 });
    expect(await waitFor(() => hydrationCount === 2, 10, 20)).toBe(true);
    currentHydration.resolve(hydrationResult('Current runtime response'));
    expect(await waitFor(() => Boolean(result?.messages.some(({ text }) => (
      text === 'Current runtime response'
    ))), 10, 20)).toBe(true);
    staleHydration.resolve(hydrationResult('Stale runtime response'));
    await pause(20);

    expect(result?.messages.some(({ text }) => text === 'Stale runtime response')).toBe(false);
  });

  it('rehydrates an accepted conversation when a new runtime becomes ready', async () => {
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.isConsentAccepted === true, 10, 20)).toBe(true);
    expect(await waitFor(() => (
      callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')
    ), 10, 20)).toBe(true);
    const initialHydrationCount = callApiMock.mock.calls
      .filter(([method]) => method === 'getAgentV2Messages').length;

    publishAgentV2Update({ kind: 'runtimeReady', generation: 100 });

    expect(await waitFor(() => (
      callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length
      > initialHydrationCount
    ), 10, 20)).toBe(true);
  });

  describe('cached history', () => {
    // Each read of the device's copy and of the latest history page settles when the test resolves it. A history
    // read resolved without a value returns the history the suite prepares.
    let cachedReads: Array<ReturnType<typeof createDeferred<unknown>>>;
    let historyReads: Array<ReturnType<typeof createDeferred<unknown>>>;
    let heldAvailability: Promise<unknown> | undefined;

    beforeEach(() => {
      cachedReads = [];
      historyReads = [];
      heldAvailability = undefined;
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => {
        if (args[0] === 'getAgentV2Availability' && heldAvailability) return heldAvailability as never;
        if (args[0] === 'getAgentV2CachedMessages') {
          const read = createDeferred<unknown>();
          cachedReads.push(read);
          return read.promise as never;
        }
        if (args[0] === 'getAgentV2Messages' && !args[2]) {
          const read = createDeferred<unknown>();
          historyReads.push(read);
          return read.promise.then((value) => value ?? implementation(...args)) as never;
        }
        return implementation(...args);
      });
    });

    it('shows the cached history until the history loads, then the history alone in its place', async () => {
      hydratedMessages = conversationMessages();
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => historyReads.length === 1, 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('getAgentV2CachedMessages', THREAD_ID);

      cachedReads[0].resolve(cachedHistory([
        persistedMessage(MESSAGE_ID, 'user', 'Cached request', 1),
        {
          ...persistedMessage(ASSISTANT_MESSAGE_ID, 'assistant', 'Cached response', 2),
          actions: [persistedReceiveAction()],
          followups: [NEWS_FOLLOWUP],
        },
      ]));
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
      expect(result!.messages.map(({ text }) => text)).toEqual(['Cached request', 'Cached response']);
      expect(result!.messages[1].followups).toEqual([NEWS_FOLLOWUP]);
      expect(result).toMatchObject({
        isHistoryCached: true, isInitialLoadComplete: false, isInputDisabled: true, thread: { revision: 4 },
      });
      const cachedIds = result!.messages.map(({ id }) => id);

      historyReads[0].resolve(undefined);
      expect(await waitFor(() => result?.isHistoryCached === false, 10, 20)).toBe(true);
      expect(result!.messages.map(({ text }) => text))
        .toEqual(['First request', 'First response', 'Second request', 'Second response']);
      // The messages the copy holds keep their places in the list
      expect(result!.messages.slice(0, 2).map(({ id }) => id)).toEqual(cachedIds);
      expect(result!.messages[1].actions).toBeUndefined();
      expect(result).toMatchObject({ isInputDisabled: false, thread: { revision: 5 } });
    });

    it('ignores a cached copy read for an earlier hydration or settling after the history', async () => {
      hydratedMessages = [];
      const availability = createDeferred<unknown>();
      heldAvailability = availability.promise;
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => historyReads.length === 1, 10, 20)).toBe(true);
      publishAgentV2Update({ kind: 'runtimeReady', generation: 110 });
      expect(await waitFor(() => cachedReads.length === 2 && historyReads.length === 2, 10, 20)).toBe(true);

      cachedReads[0].resolve(cachedHistory([persistedUserMessage()]));
      await pause(20);
      expect(result!.messages).toEqual([]);

      // The history has arrived while the availability it loads with is still on its way
      historyReads[1].resolve(undefined);
      await pause(20);
      cachedReads[1].resolve(cachedHistory([persistedUserMessage()]));
      await pause(20);
      expect(result!.messages).toEqual([]);
      expect(result!.isHistoryCached).toBe(false);

      availability.resolve(undefined);
      expect(await waitFor(() => result?.thread?.revision === 5, 10, 20)).toBe(true);
      expect(result!.messages).toEqual([]);
    });

    it('does not show a cached copy over an answer that starts while it is read', async () => {
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
      publishAgentV2Update({
        kind: 'runStarted', ...routing(), threadRevision: 6, inputMessageId: INPUT_MESSAGE_ID,
      });
      expect(await waitFor(() => result?.isRunActive === true, 10, 20)).toBe(true);

      cachedReads[0].resolve(cachedHistory([persistedUserMessage()]));
      await pause(20);

      expect(result!.messages).toEqual([]);
      expect(result!.isHistoryCached).toBe(false);
    });

    it('offers no action of the cached history and loads actions only from the history', async () => {
      const send = sendAction();
      const receive = persistedReceiveAction();
      const answer = persistedAssistantMessage(send);
      answer.actions!.push(receive);
      hydratedMessages = [persistedUserMessage(), answer];
      actionPresentationPromise = Promise.resolve(sendPresentation());
      resolvedAction = { kind: 'openReceive', chain: 'ton' } satisfies AgentV2ResolvedAction;
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
      cachedReads[0].resolve(cachedHistory([persistedUserMessage(), answer]));
      expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);

      const cachedAnswer = result!.messages[1];
      expect(cachedAnswer.actionPresentations).toEqual({ [send.id]: { kind: 'inactive' } });
      expect(result!.isInputDisabled).toBe(true);
      result!.activateAction(cachedAnswer.id, receive);
      result!.activateAction(cachedAnswer.id, send);
      publishAgentV2Update({ kind: 'walletContextChanged' });
      await pause(20);

      expect(callApiMock).not.toHaveBeenCalledWith('resolveAgentV2Action', expect.anything(), expect.anything());
      expect(callApiMock)
        .not.toHaveBeenCalledWith('getAgentV2ActionPresentation', expect.anything(), expect.anything());
      expect(mockOpenReceiveModal).not.toHaveBeenCalled();

      historyReads[0].resolve(undefined);
      expect(await waitFor(() => (
        result?.messages[1]?.actionPresentations?.[send.id]?.kind === 'send'
      ), 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('getAgentV2ActionPresentation', ASSISTANT_MESSAGE_ID, send.id);
      result!.activateAction(result!.messages[1].id, receive);
      expect(await waitFor(() => mockOpenReceiveModal.mock.calls.length === 1, 10, 20)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('resolveAgentV2Action', ASSISTANT_MESSAGE_ID, receive.id);
    });

    it('offers no rating, regeneration, edit, older page or question over the cached history', async () => {
      hydratedMessages = conversationMessages();
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
      cachedReads[0].resolve(cachedHistory(conversationMessages()));
      expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
      const answerId = result!.messages[3].id;
      const questionId = result!.messages.find(({ isOutgoing }) => isOutgoing)!.id;

      expect(result).toMatchObject({ hasOlderMessages: false, isInputDisabled: true });
      expect(result!.isMessageEditable(questionId)).toBe(false);
      expect(result!.isMessageRegenerable(answerId)).toBe(false);
      await result!.rateMessage(answerId, 'like');
      await result!.loadOlderMessages();
      result!.sendMessage('New question');
      await pause(20);

      expect(callApiMock).not.toHaveBeenCalledWith(
        'setAgentV2MessageFeedback', expect.anything(), expect.anything(), expect.anything(),
      );
      expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages')).toHaveLength(1);
      expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
      expect(result!.messages.map(({ text }) => text)).not.toContain('New question');
      expect(result!.messages[3].feedback).toBeUndefined();

      historyReads[0].resolve(undefined);
      expect(await waitFor(() => result?.isHistoryCached === false, 10, 20)).toBe(true);
      expect(result!.isMessageEditable(questionId)).toBe(true);
      expect(result!.isMessageRegenerable(answerId)).toBe(true);
    });

    it.each([false, true])(
      'keeps the cached history inactive with the failure and Retry until the history loads (runtime restart: %s)',
      async (isRuntimeRestarted) => {
        hydratedMessages = conversationMessages();
        TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
        expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
        cachedReads[0].resolve(cachedHistory([persistedUserMessage()]));
        expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
        // The read after a runtime restart fails silently in a chat that shows its history
        if (isRuntimeRestarted) {
          publishAgentV2Update({ kind: 'runtimeReady', generation: 111 });
          expect(await waitFor(() => historyReads.length === 2, 10, 20)).toBe(true);
        }
        const failedRead = historyReads.length - 1;

        historyReads[failedRead].resolve({ ok: false, error: { code: 'network_error', retryable: true } });
        expect(await waitFor(() => result?.historyFailure !== undefined, 10, 20)).toBe(true);
        expect(result).toMatchObject({
          historyFailure: { text: '$agent_connection_lost', isRetrying: false },
          messages: [{ text: 'Persisted request' }],
          isHistoryCached: true,
          isInitialLoadComplete: true,
          isInputDisabled: true,
        });

        result!.retryHistory();
        expect(await waitFor(() => historyReads.length === failedRead + 2, 10, 20)).toBe(true);
        historyReads[failedRead + 1].resolve(undefined);
        expect(await waitFor(() => result?.messages.length === 4, 10, 20)).toBe(true);
        expect(result).toMatchObject({ historyFailure: undefined, isHistoryCached: false, isInputDisabled: false });
        expect(cachedReads).toHaveLength(1);
      },
    );

    it('shows no cached copy read after the history failed, leaving the failure and Retry as without it', async () => {
      TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
      expect(await waitFor(() => historyReads.length === 1, 10, 20)).toBe(true);
      historyReads[0].resolve({ ok: false, error: { code: 'network_error', retryable: true } });
      expect(await waitFor(() => result?.historyFailure !== undefined, 10, 20)).toBe(true);
      // The read after a runtime restart fails silently, before its cached copy comes
      publishAgentV2Update({ kind: 'runtimeReady', generation: 112 });
      expect(await waitFor(() => cachedReads.length === 2 && historyReads.length === 2, 10, 20)).toBe(true);
      historyReads[1].resolve({ ok: false, error: { code: 'network_error', retryable: true } });
      await pause(20);
      cachedReads[1].resolve(cachedHistory([persistedUserMessage()]));
      await pause(20);

      expect(result).toMatchObject({
        messages: [],
        isHistoryCached: false,
        historyFailure: { text: '$agent_connection_lost', isRetrying: false },
      });
      result!.retryHistory();
      expect(await waitFor(() => historyReads.length === 3, 10, 20)).toBe(true);
      historyReads[2].resolve(undefined);
      expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
      expect(result).toMatchObject({ historyFailure: undefined, isHistoryCached: false, isInputDisabled: false });
    });

    it.each([true, false])(
      'shows no cached history once the server no longer has the thread (copy read first: %s)',
      async (isCopyReadFirst) => {
        const onThreadNotFound = jest.fn();
        TeactDOM.render(
          <TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} onThreadNotFound={onThreadNotFound} />, root,
        );
        expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
        if (isCopyReadFirst) {
          cachedReads[0].resolve(cachedHistory([persistedUserMessage()]));
          expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
        }

        historyReads[0].resolve({ ok: false, error: { code: 'thread_not_found', retryable: false } });
        expect(await waitFor(() => onThreadNotFound.mock.calls.length === 1, 10, 20)).toBe(true);
        cachedReads[0].resolve(cachedHistory([persistedUserMessage()]));
        await pause(20);

        expect(result).toMatchObject({
          messages: [], thread: undefined, isHistoryCached: false, isInputDisabled: true,
        });
      },
    );

    it.each<{ name: string; target?: AgentV2ChatTarget; initialThread?: AgentThreadSummaryV2 }>([
      { name: 'the default chat' },
      { name: 'a chat of the default thread', target: { kind: 'default' } },
      { name: 'a new chat', target: { kind: 'new' } },
      { name: 'a news discussion', target: { kind: 'news', news: { eventId: 7, locale: 'en' } } },
      {
        name: 'a discussion opened with its news',
        target: {
          kind: 'thread',
          threadId: THREAD_ID,
          preview: { eventId: 7, headline: 'Headline', publishedAt: '2026-10-21T10:00:00.000Z' },
        },
      },
      {
        name: 'a discussion the list knows',
        target: { kind: 'thread', threadId: THREAD_ID },
        initialThread: {
          ...threadSummary(5), news: { eventId: 7, headline: 'Headline', publishedAt: '2026-10-21T10:00:00.000Z' },
        },
      },
      { name: 'a digest discussion', target: { kind: 'digest', digest: { id: DIGEST.id } } },
      {
        name: 'a discussion the list opens by its thread',
        target: { kind: 'thread', threadId: THREAD_ID, isNews: true },
      },
      {
        name: 'a digest discussion the list knows',
        target: { kind: 'thread', threadId: THREAD_ID },
        initialThread: { ...threadSummary(5), digest: DIGEST },
      },
    ])('reads no cached history for $name', async ({ target, initialThread }) => {
      TeactDOM.render(target ? <TargetHarness target={target} initialThread={initialThread} /> : <Harness />, root);
      expect(await waitFor(() => historyReads.length === 1, 10, 20)).toBe(true);

      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2CachedMessages', expect.anything());
    });

    it.each<{ name: string; settle: (read: ReturnType<typeof createDeferred<unknown>>) => void }>([
      { name: 'no copy', settle: (read) => read.resolve(undefined) },
      { name: 'a copy that fails to read', settle: (read) => read.reject(new Error('Unreadable')) },
      { name: 'an empty copy', settle: (read) => read.resolve(cachedHistory([])) },
      {
        name: 'a copy of a news discussion',
        settle: (read) => read.resolve({
          ...cachedHistory([persistedUserMessage()]),
          thread: {
            ...threadSummary(4), news: { eventId: 7, headline: 'Headline', publishedAt: '2026-10-21T10:00:00.000Z' },
          },
        }),
      },
      {
        name: 'a copy of a digest discussion',
        settle: (read) => read.resolve({
          ...cachedHistory([persistedUserMessage()]), thread: { ...threadSummary(4), digest: DIGEST },
        }),
      },
    ])('loads the history as usual after $name', async ({ settle }) => {
      const onUnhandledRejection = jest.fn();
      process.on('unhandledRejection', onUnhandledRejection);
      try {
        TeactDOM.render(<TargetHarness target={{ kind: 'thread', threadId: THREAD_ID }} />, root);
        expect(await waitFor(() => cachedReads.length === 1, 10, 20)).toBe(true);
        settle(cachedReads[0]);
        await pause(20);

        expect(result).toMatchObject({ messages: [], isHistoryCached: false });
        historyReads[0].resolve(undefined);
        expect(await waitFor(() => result?.messages.length === 1, 10, 20)).toBe(true);
        expect(onUnhandledRejection).not.toHaveBeenCalled();
      } finally {
        process.off('unhandledRejection', onUnhandledRejection);
      }
    });
  });

  it.each([false, true])('waits for fresh history when unread state is unknown: %s', async (isUnreadStateUnknown) => {
    const target = { kind: 'thread' as const, threadId: THREAD_ID };
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.messages.length === 1, 10, 20))
      .toBe(true);
    expect(result!.isOpenedWithCachedHistory).toBe(false);
    const shownMessage = result!.messages[0];
    TeactDOM.render(undefined, root);

    callApiMock.mockClear();
    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const history = createDeferred<void>();
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => defaultImplementation(...args)) as never
      : defaultImplementation(...args)));
    TeactDOM.render(<TargetHarness target={target} isUnreadStateUnknown={isUnreadStateUnknown} />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages'), 10, 20))
      .toBe(true);
    expect(result!.isOpenedWithCachedHistory).toBe(!isUnreadStateUnknown);
    expect(result!.isInitialLoadComplete).toBe(!isUnreadStateUnknown);
    expect(result!.messages).toEqual(isUnreadStateUnknown ? [] : [shownMessage]);
    if (!isUnreadStateUnknown) expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Consent');

    // The newer history takes its place, and the message shown keeps its own
    history.resolve();
    expect(await waitFor(() => result?.messages.length === 2, 10, 20)).toBe(true);
    expect(result!.messages[0].id).toBe(shownMessage.id);
    expect(result!.isInputDisabled).toBe(false);
  });

  it('sends a message typed over a cached history at once, and keeps it when the history read ends', async () => {
    const target = { kind: 'thread' as const, threadId: THREAD_ID };
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.messages.length === 1, 10, 20))
      .toBe(true);
    TeactDOM.render(undefined, root);

    hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
    const defaultImplementation = callApiMock.getMockImplementation()!;
    const history = createDeferred<void>();
    callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
      ? history.promise.then(() => defaultImplementation(...args)) as never
      : defaultImplementation(...args)));
    startRunResponses = [new Promise(() => undefined)];
    const countHistoryReads = () => callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Messages').length;
    const historyReadsBefore = countHistoryReads();
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => result?.isOpenedWithCachedHistory === true, 1, 20)).toBe(true);
    // The message is sent while the history is being read again
    expect(await waitFor(() => countHistoryReads() > historyReadsBefore, 10, 20)).toBe(true);

    // The field is open while the history loads again, and the message goes at once
    expect(result!.isInputDisabled).toBe(false);
    expect(result!.sendMessage('Asked at once')).toBe(true);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 20))
      .toBe(true);

    // The read that the message outdated leaves the message and the history it was sent over
    history.resolve();
    await pause(50);
    const texts = result!.messages.map(({ text }) => text);
    expect(texts).toContain('Persisted request');
    expect(texts).toContain('Asked at once');
    expect(texts).not.toContain('Retried response');
  });

  it.each([
    { kind: 'news', hasConsent: true }, { kind: 'news', hasConsent: false },
    { kind: 'digest', hasConsent: true }, { kind: 'digest', hasConsent: false },
  ])('restores a cached $kind discussion only with consent: $hasConsent', async ({ kind, hasConsent }) => {
    if (kind === 'news') {
      createdThreadNews = { eventId: 7, headline: 'Server headline', publishedAt: '2026-10-21T10:00:00.000Z' };
    } else {
      createdThreadDigest = DIGEST;
    }
    hydratedMessages = [{ ...persistedAssistantTextMessage(), newsPost: true }];
    const target = { kind: 'thread' as const, threadId: THREAD_ID };
    TeactDOM.render(<TargetHarness target={target} hasConsent />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.messages.length === 1, 10, 20))
      .toBe(true);
    TeactDOM.render(undefined, root);

    // Shown with its history, the chat keeps the wallet's state up to date on the server, which needs the consent
    result = undefined;
    TeactDOM.render(<TargetHarness target={target} hasConsent={hasConsent} />, root);
    expect(await waitFor(() => result !== undefined, 1, 20)).toBe(true);
    expect(result!.isOpenedWithCachedHistory).toBe(hasConsent);
    expect(result!.messages.length).toBe(hasConsent ? 1 : 0);
  });

  it('opens a chat afresh once it was deleted', async () => {
    const target = { kind: 'thread' as const, threadId: THREAD_ID };
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => result?.isInitialLoadComplete === true && result.messages.length === 1, 10, 20))
      .toBe(true);
    await result!.cancelPendingRequests();
    TeactDOM.render(undefined, root);

    callApiMock.mockClear();
    TeactDOM.render(<TargetHarness target={target} />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Consent'), 10, 20))
      .toBe(true);
    expect(result!.isOpenedWithCachedHistory).toBe(false);
  });

  function Harness() {
    result = useAgentV2Messages({ isActive: true, lang });
    return <div />;
  }

  // A news or digest discussion of the feed that has no thread yet, whose creation brings the thread of its card
  function buildDeferredTarget(
    discussion: typeof DISCUSSIONS[number], discussionNaming?: AgentNewsFeedDiscussionNamingV2,
  ): AgentV2ChatTarget {
    if (discussion === 'news') createdThreadNews = NEWS_TARGET.preview;
    else createdThreadDigest = DIGEST;
    return {
      ...(discussion === 'news' ? NEWS_TARGET : DIGEST_TARGET),
      shouldDeferCreation: true,
      ...(discussionNaming && { discussionNaming }),
    };
  }

  function TargetHarness({
    target, initialThread, initialMessage, initialHintEntryPoint, shouldRequestSupport = false,
    onInitialMessageSent, onThreadResolved, onThreadNotFound, isActive = true,
    hasConsent, isUnreadStateUnknown = false,
  }: {
    target: AgentV2ChatTarget;
    initialThread?: AgentThreadSummaryV2;
    initialMessage?: string;
    initialHintEntryPoint?: AgentV2StarterHintEntryPoint;
    shouldRequestSupport?: boolean;
    onInitialMessageSent?: NoneToVoidFunction;
    onThreadResolved?: (threadId: string) => void;
    onThreadNotFound?: NoneToVoidFunction;
    isActive?: boolean;
    hasConsent?: boolean;
    isUnreadStateUnknown?: boolean;
  }) {
    result = useAgentV2Messages({
      isActive, lang, target, initialThread, initialMessage, initialHintEntryPoint, shouldRequestSupport,
      onInitialMessageSent, onThreadResolved, onThreadNotFound,
      hasConsent, isUnreadStateUnknown,
    });
    return <div />;
  }

  function publishSendAction(action: ReturnType<typeof sendAction>) {
    publishAction(action);
  }

  function publishAction(action: AgentV2LiveAction) {
    publishAgentV2Update({
      kind: 'messageStarted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      contentKind: 'semantic',
    });
    publishAgentV2Update({
      kind: 'actionAvailable',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      action,
    });
    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: ASSISTANT_MESSAGE_ID,
      finishReason: 'complete',
    });
  }

  function publishRetryableQuota() {
    const resetAt = Date.now() - 1_000;
    publishAgentV2Update({
      kind: 'userQuotaChanged',
      quota: {
        limit: 20,
        used: 19,
        remaining: 1,
        resetAt: new Date(resetAt).toISOString(),
      },
    });
    publishAgentV2Update({
      kind: 'runFailed',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      code: 'user_quota_exhausted',
      retryable: true,
      resetAt,
    });
  }
});

// Each case runs for a news discussion and a digest one
function getStarterHintsCalls() {
  return jest.mocked(callApi).mock.calls.filter(([method]) => method === 'getAgentV2StarterHints');
}

function withDiscussions<T extends object>(cases: readonly T[]) {
  return DISCUSSIONS.flatMap((discussion) => cases.map((item) => ({ ...item, discussion })));
}

function threadSummary(revision: number): AgentThreadSummaryV2 {
  return {
    id: THREAD_ID,
    revision,
    createdAt: '2026-08-07T10:00:00.000Z',
    updatedAt: '2026-08-07T10:00:00.000Z',
    lastActivityAt: '2026-08-07T10:00:00.000Z',
    messageCount: 1,
  };
}

function successfulClear(revision: number): AgentV2MutationResult<AgentThreadClearResponseV2> {
  return {
    ok: true,
    value: {
      protocolVersion: 3,
      thread: threadSummary(revision),
      duplicate: false,
    },
  };
}

function routing() {
  return {
    clientRunId: CLIENT_RUN_ID,
    runId: RUN_ID,
    threadId: THREAD_ID,
  };
}

function sendAction() {
  return { ...sendFormAction(), id: '66666666-6666-4666-8666-666666666666' };
}

function receiveAction(): Extract<AgentV2LiveAction, { kind: 'receive' }> {
  return {
    id: '66666666-6666-4666-8666-666666666661',
    kind: 'receive',
    labelCode: 'open_receive',
    title: 'Review prepared action',
    effect: 'open_receive',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
      activeNetwork: 'ton',
    },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function persistedReceiveAction(): AgentPersistedActionV2 {
  return {
    id: receiveAction().id,
    kind: 'receive',
    title: 'Open Receive',
    labelCode: 'open_receive',
    effect: 'open_receive',
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function exactStakeAction(): Extract<AgentV2LiveAction, { kind: 'stake' }> {
  return {
    id: '66666666-6666-4666-8666-666666666660',
    schemaVersion: 2,
    kind: 'stake',
    labelCode: 'open_staking',
    title: 'Review prepared action',
    effect: 'open_staking',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
    },
    productId: 'liquid',
    asset: {
      slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9,
    },
    amount: { kind: 'exact', value: '10' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function swapAction(side: 'source' | 'destination'): Extract<AgentV2LiveAction, { kind: 'swap' }> {
  const isSource = side === 'source';
  return {
    id: isSource
      ? '66666666-6666-4666-8666-666666666667'
      : '66666666-6666-4666-8666-666666666668',
    schemaVersion: 2,
    kind: 'swap',
    labelCode: 'open_swap',
    title: 'Review prepared action',
    effect: 'open_swap',
    url: 'https://my.tt/swap?in=toncoin&out=usdton&amount=10',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
    },
    sourceAsset: isSource
      ? { slug: 'toncoin', chain: 'ton', symbol: 'TON' }
      : { slug: 'usdton', chain: 'ton', symbol: 'USDT' },
    destinationAsset: isSource
      ? { slug: 'usdton', chain: 'ton', symbol: 'USDT' }
      : { slug: 'toncoin', chain: 'ton', symbol: 'TON' },
    amount: { value: '10', valueType: 'decimal', side },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function sendFormAction(): Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> {
  return {
    id: '66666666-6666-4666-8666-666666666660',
    kind: 'send',
    labelCode: 'open_send',
    title: 'Review prepared action',
    effect: 'open_send',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
      activeNetwork: 'ton',
    },
    asset: { slug: 'gram', chain: 'ton' },
    recipient: { kind: 'savedAddress', addressRef: 'address-defi' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function openDappAction(): Extract<AgentV2LiveAction, { kind: 'openDapp' }> {
  return {
    id: '77777777-7777-4777-8777-777777777777',
    schemaVersion: 1,
    kind: 'openDapp',
    labelCode: 'open_external_link',
    title: 'Review prepared action',
    url: FRAGMENT_SITE.url,
    requiresConfirmation: true,
  };
}

function sendPresentation(): AgentV2ActionPresentation {
  return {
    kind: 'send',
    status: 'active',
    amount: { value: '1.5', symbol: 'TON' },
    network: 'ton',
    accountLabel: 'Main',
    recipient: { kind: 'savedAddress', label: 'Mom' },
    feeStatus: 'calculated_in_wallet',
    warningCodes: ['new_address'],
    expiresAt: '2099-08-07T10:10:00.000Z',
  };
}

function sendFormPresentation(): AgentV2ActionPresentation {
  return {
    kind: 'send',
    status: 'active',
    network: 'ton',
    accountLabel: 'Main',
    recipient: { kind: 'savedAddress', label: 'DeFi' },
    feeStatus: 'calculated_in_wallet',
    warningCodes: [],
  };
}

function persistedUserMessage(): AgentV2HydratedMessage {
  return {
    id: MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'user',
    status: 'complete',
    content: { kind: 'markdown', text: 'Persisted request' },
    createdAt: '2026-08-07T10:00:00.000Z',
  };
}

function persistedAssistantTextMessage(): AgentV2HydratedMessage {
  return {
    id: ASSISTANT_MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    content: { kind: 'markdown', text: 'Retried response' },
    createdAt: '2026-08-07T10:00:01.000Z',
  };
}

function persistedOperatorMessage(): AgentV2HydratedMessage {
  return {
    id: ASSISTANT_MESSAGE_ID, threadId: THREAD_ID, role: 'operator', status: 'complete',
    text: 'An operator reply', author: { operatorId: 'operator-id', name: 'Alice' },
    createdAt: '2026-08-07T10:00:01.000Z',
  };
}

function persistedAssistantMessage(action: ReturnType<typeof sendAction>): AgentV2HydratedMessage {
  return {
    id: ASSISTANT_MESSAGE_ID,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    actions: [{ id: action.id, kind: 'send', labelCode: 'open_send', title: action.title,
      effect: 'live_only', localDraftRequired: false, requiresConfirmation: false }],
    createdAt: '2026-08-07T10:00:01.000Z',
  };
}

function persistedMessage(
  id: string,
  role: 'user' | 'assistant',
  text: string,
  timestamp: number,
): AgentV2HydratedMessage {
  return {
    id,
    threadId: THREAD_ID,
    role,
    status: 'complete',
    content: { kind: 'markdown', text },
    createdAt: new Date(timestamp * 1_000).toISOString(),
  };
}

function conversationMessages() {
  return [
    persistedMessage(MESSAGE_ID, 'user', 'First request', 1),
    persistedMessage(ASSISTANT_MESSAGE_ID, 'assistant', 'First response', 2),
    persistedMessage(SECOND_USER_MESSAGE_ID, 'user', 'Second request', 3),
    persistedMessage(SECOND_ASSISTANT_MESSAGE_ID, 'assistant', 'Second response', 4),
  ];
}

function hostContext(accountId = 'account-one'): AgentV2HostContextSnapshot {
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    activeAccountId: accountId,
    activeNetwork: 'ton',
    isTestnet: false,
    accounts: [{
      accountId,
      label: 'Main',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton'],
      addresses: { ton: 'EQ-public' },
      holdings: [{
        asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '10',
      }],
    }],
    savedAddresses: [],
  };
}

function hydrationResult(text: string) {
  return {
    ok: true as const,
    value: {
      thread: threadSummary(5),
      messages: [{
        ...persistedAssistantTextMessage(),
        content: { kind: 'markdown' as const, text },
      }],
    },
  };
}

function cachedHistory(messages: AgentV2HydratedMessage[]) {
  return { thread: threadSummary(4), messages, hasOlder: true };
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}
