import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type {
  AgentHintsResponseV2,
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
} from '../../../api/agentV2/types';
import type { LangFn } from '../../../hooks/useLang';

import { buildAgentV2HostContext } from '../../../global/agentV2/buildHostContext';
import { buildAgentBuiltinDapps } from '../../../global/agentV2/builtinDapps';
import { agentThreadListListeners, resetAgentV2LocalState } from '../../../util/agent/agentV2LocalState';
import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
} from '../../../util/agentV2Updates';
import { parseDeeplinkTransferParams, processDeeplink } from '../../../util/deeplink';
import { openUrl } from '../../../util/openUrl';
import { pause, waitFor } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { hostUiCapabilities } from '../../../api/agentV2/testing/hostUiCapabilities';
import { openSite } from '../../explore/helpers/utils';
import * as agentV2RunController from './agentV2RunController';
import useAgentV2Messages, { type AgentV2ChatTarget, type UseAgentV2MessagesResult } from './useAgentV2Messages';

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
    exploreData: { sites: mockExploreSites },
    restrictions: { isLimitedRegion: mockIsLimitedRegion },
    currentAccountId: '0-mainnet',
    byAccountId: { '0-mainnet': mockAccountState },
    swapTokenInfo: { bySlug: mockSwapTokensBySlug },
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
const NEWS_FOLLOWUP = {
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  kind: 'suggested_prompt' as const,
  text: 'What does this mean?',
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
  let hintsResponse: AgentHintsResponseV2 | undefined;
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
    hintsResponse = undefined;
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
        case 'getAgentV2Hints':
          return Promise.resolve(hintsResponse);
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
    const [, answer] = result!.messages;
    expect(result!.canEditMessages).toBe(false);
    result!.retryMessage(answer.id);
    expect(result!.isMessageRegenerable(answer.id)).toBe(false);

    const support = { state: 'operator' as const, lastOperatorMessageAt: '2026-08-07T10:01:00.000Z' };
    publishAgentV2Update({ kind: 'threadChanged', threadId: THREAD_ID, thread: { ...threadSummary(6), support } });
    expect(await waitFor(() => result?.support === support, 10, 20)).toBe(true);
    expect(result!.canEditMessages).toBe(false);
    result!.retryMessage(answer.id);
    expect(result!.isMessageRegenerable(answer.id)).toBe(false);
    await pause(20);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    threadSupport = { state: 'closed' };
    threadRevision = 7;
    await result!.loadOlderMessages();
    expect(await waitFor(() => result?.support?.state === 'closed', 10, 20)).toBe(true);
    expect(result!.canEditMessages).toBe(true);
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
    expect(result!.canEditMessages).toBe(false);
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
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Hints', expect.anything());
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
      expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Hints', expect.anything());
    } else {
      await pause(50);
    }
    expect(callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Messages')).toBe(isNews);
    expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
  });

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
      isInputDisabled: true,
      isRunActive: false,
      messages: [{ text: '**Feed headline**\n\nFeed **body**', isOutgoing: false, isNewsPost: true }],
      news: target.preview,
    });
    expect(result!.activity).toBeUndefined();
    const previewPost = result!.messages[0];
    expect(previewPost.followups).toBeUndefined();
    expect(result!.hints).toBeUndefined();
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Hints', expect.anything());

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
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Hints', expect.anything());
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());
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
    hintsResponse = {
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [{ id: 'learn.staking' }],
    };
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
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Hints')).toHaveLength(1);
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
      hintsResponse = {
        protocolVersion: 3,
        catalogVersion: 'agent-starter-hints-v1',
        items: [{ id: 'learn.staking' }],
      };
      hydratedMessages = [persistedUserMessage(), persistedAssistantTextMessage()];
      hydrationNextCursor = nextCursor;
      const history = createDeferred<void>();
      const hints = createDeferred<void>();
      const implementation = callApiMock.getMockImplementation()!;
      callApiMock.mockImplementation((...args) => (args[0] === 'getAgentV2Messages'
        ? history.promise.then(() => implementation(...args)) as never
        : args[0] === 'getAgentV2Hints'
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
      expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Hints'))
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
      expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Hints'))
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
    expect(callApiMock).not.toHaveBeenCalledWith('getAgentV2Hints', expect.anything());
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

  it.each(['success', 'late failure', 'early failure'])('opens history before hints: %s', async (outcome) => {
    const shouldFailFirstHints = outcome !== 'success';
    hydratedMessages = [];
    hintsResponse = {
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [{ id: 'learn.staking' }],
    };
    const history = createDeferred<void>();
    const hints = createDeferred<void>();
    const retryHints = createDeferred<void>();
    let hintsRequestCount = 0;
    const implementation = callApiMock.getMockImplementation()!;
    callApiMock.mockImplementation((...args) => {
      if (args[0] === 'getAgentV2Messages') {
        return history.promise.then(() => implementation(...args)) as never;
      }
      if (args[0] === 'getAgentV2Hints' && ++hintsRequestCount === 1) {
        return hints.promise.then(() => shouldFailFirstHints ? undefined : implementation(...args)) as never;
      }
      if (args[0] === 'getAgentV2Hints' && outcome === 'early failure') {
        return retryHints.promise.then(() => implementation(...args)) as never;
      }
      return implementation(...args);
    });
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Hints'), 10, 20))
      .toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Messages', THREAD_ID);
    expect(result!.isInitialLoadComplete).toBe(false);
    expect(result!.hints).toBeUndefined();

    if (outcome === 'early failure') {
      hints.resolve();
      await pause(20);
    }
    history.resolve();
    expect(await waitFor(() => result?.isInitialLoadComplete === true, 10, 20)).toBe(true);
    if (outcome === 'early failure') await pause(20);
    expect(result!.messages).toEqual([]);
    expect(result!.hints).toBeUndefined();
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Hints'))
      .toHaveLength(outcome === 'early failure' ? 2 : 1);

    if (outcome === 'early failure') retryHints.resolve();
    else hints.resolve();
    expect(await waitFor(() => Boolean(result?.hints?.length), 10, 20)).toBe(true);
    expect(result!.messages).toEqual([]);
    expect(callApiMock).toHaveBeenCalledWith('getAgentV2Hints', 'en');
    expect(callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2Hints'))
      .toHaveLength(shouldFailFirstHints ? 2 : 1);

    const hint = result!.hints![0];
    result!.sendHint(hint);

    expect(await waitFor(
      () => Boolean(result?.messages.some((message) => message.text === hint.title)), 10, 20,
    )).toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('startAgentV2Run', expect.objectContaining({
      input: { kind: 'append', text: hint.title },
      entryPoint: {
        kind: 'emptyState', surface: 'agentTab', hintId: 'learn.staking',
        catalogVersion: 'agent-starter-hints-v1',
      },
    }));
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

      expect(result).toMatchObject({ canEditMessages: false, hasOlderMessages: false, isInputDisabled: true });
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
      expect(result!.canEditMessages).toBe(true);
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

  function TargetHarness({
    target, initialThread, initialMessage, onInitialMessageSent, onThreadResolved, onThreadNotFound, isActive = true,
    hasConsent, isUnreadStateUnknown = false,
  }: {
    target: AgentV2ChatTarget;
    initialThread?: AgentThreadSummaryV2;
    initialMessage?: string;
    onInitialMessageSent?: NoneToVoidFunction;
    onThreadResolved?: (threadId: string) => void;
    onThreadNotFound?: NoneToVoidFunction;
    isActive?: boolean;
    hasConsent?: boolean;
    isUnreadStateUnknown?: boolean;
  }) {
    result = useAgentV2Messages({
      isActive, lang, target, initialThread, initialMessage, onInitialMessageSent, onThreadResolved, onThreadNotFound,
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
