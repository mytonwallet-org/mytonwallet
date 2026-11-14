import type {
  AgentThreadClearResponseV2,
  AgentThreadSummaryV2,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2HydratedMessage,
  AgentV2MutationResult,
  AgentV2RunCommand,
  AgentV2RunResult,
  AgentV2ThreadHydration,
} from '../../../api/agentV2/types';
import type { LangFn } from '../../../hooks/useLang';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
} from './agentV2MessagesState';
import type { TextRevealPresentations } from './textRevealPresentation';

import { getIsAgentV2SupportEntryVisible } from '../../../global/agentV2/uiCapabilities';
import { AgentClientTrace, type ClientTimingEvent } from '../../../api/agentV2/developmentTelemetry';
import { decodeHttpError } from '../../../api/agentV2/identity';
import { getAgentV2ErrorText } from '../../agentV2/agentV2Copy';
import * as developmentTiming from './agentDevelopmentTiming';
import {
  type AgentV2HydrationControllerDependencies,
  createAgentV2HydrationController,
} from './agentV2HydrationController';
import {
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  selectAgentV2Activity,
  selectAgentV2HeldLimitRunId,
  selectCanRequestAgentV2Support,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const RUN_ID = '33333333-3333-4333-8333-333333333333';
const INPUT_MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const ASSISTANT_MESSAGE_ID = '55555555-5555-4555-8555-555555555555';

describe('Agent V2 controllers', () => {
  it.each([false, true])('requests support with an optimistic message, including at the daily quota (%s)', async (
    isQuotaExhausted,
  ) => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1),
      ...(isQuotaExhausted && {
        userQuota: { limit: 20, used: 20, remaining: 0, resetAt: '2026-08-12T00:00:00.000Z' },
      }),
    });
    const { controller, startRun } = createSupportRunHarness(state);

    expect(controller.requestSupport('header')).toBe(true);
    await flushPromises();

    expect(startRun).toHaveBeenCalledTimes(1);
    expect(startRun.mock.calls[0][0]).toEqual({
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'append', text: '$agent_support_request_message' },
      entryPoint: { kind: 'supportRequest', source: 'header' },
    });
    expect(state.getState().messages).toEqual([
      expect.objectContaining({ text: '$agent_support_request_message', isOutgoing: true }),
    ]);
    controller.dispose();
  });

  it.each(['answering', 'waiting', 'operator'] as const)('does not request support while %s', async (phase) => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: { ...threadSummary(1), ...(phase !== 'answering' && { support: { state: phase } }) },
      run: phase === 'answering' ? { phase: 'streaming', clientRunId: CLIENT_RUN_ID } : { phase: 'idle' },
    });
    const { controller, startRun } = createSupportRunHarness(state);

    expect(controller.requestSupport('header')).toBe(false);
    await flushPromises();

    expect(startRun).not.toHaveBeenCalled();
    expect(state.getState().messages).toEqual([]);
    controller.dispose();
  });

  it('blocks another support request until the user rate limit resets', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1),
    });
    const { controller, startRun, retryRun, now } = createSupportRunHarness(state);
    jest.useFakeTimers();
    try {
      expect(controller.requestSupport('header')).toBe(true);
      controller.handleUpdate({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
        code: 'rate_limited', retryable: true, resetAt: 1000,
      });
      await flushPromises();

      const canRequestSupport = selectCanRequestAgentV2Support(state.getState(), now());
      const isRequested = controller.requestSupport('header');
      await flushPromises();

      expect(canRequestSupport).toBe(false);
      expect(isRequested).toBe(false);
      expect(state.getState().messages).toHaveLength(1);
      expect(startRun).toHaveBeenCalledTimes(1);
      expect(state.getState().userRateLimit).toEqual({ kind: 'rateLimit', resetAt: 1000 });
      expect(controller.getHeldLimitRun()).toBeUndefined();

      now.mockReturnValue(1000);
      await jest.advanceTimersByTimeAsync(1000);
      controller.retryAdmission();
      await flushPromises();
      expect(startRun).toHaveBeenCalledTimes(1);
      expect(retryRun).not.toHaveBeenCalled();
      expect(selectCanRequestAgentV2Support(state.getState(), now())).toBe(true);
      expect(controller.requestSupport('header')).toBe(true);
      await flushPromises();
      expect(startRun).toHaveBeenCalledTimes(2);
    } finally {
      controller.dispose();
      jest.useRealTimers();
    }
  });

  it('requests support even when agent capacity is exhausted', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1),
      availability: { state: 'capacity_exhausted', resetAt: 1000 },
    });
    const { controller, startRun, now } = createSupportRunHarness(state);

    expect(selectCanRequestAgentV2Support(state.getState(), now())).toBe(true);
    expect(controller.requestSupport('header')).toBe(true);
    await flushPromises();

    expect(startRun).toHaveBeenCalledTimes(1);
    expect(startRun.mock.calls[0][0]).toMatchObject({
      entryPoint: { kind: 'supportRequest', source: 'header' },
    });
    controller.dispose();
  });

  it.each(['quotaRetry', 'userRateLimit'] as const)(
    'removes the superseded %s question and failed support bubble when sending a new question', async (limitKind) => {
      const question = { id: 7, text: 'Q', isOutgoing: true, timestamp: 1 };
      const retry = { clientRunId: 'held', optimisticMessageId: question.id, resetAt: 1000 };
      const state = createStateHarness({
        ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
        thread: threadSummary(1), messages: [question],
        ...(limitKind === 'quotaRetry' ? {
          quotaRetry: retry,
          userQuota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(retry.resetAt).toISOString() },
        } : { userRateLimit: { ...retry, kind: 'rateLimit' as const } }),
      });
      const { controller, startRun, now } = createSupportRunHarness(state);
      now.mockReturnValue(retry.resetAt);
      expect(controller.requestSupport('header')).toBe(true);
      controller.handleUpdate({
        kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'network_error', retryable: true,
      });
      await flushPromises();
      expect(state.getState().messages).toContainEqual(question);
      expect(state.getState().admissionFailure?.optimisticMessageId).toBeDefined();

      expect(controller.sendMessage('New question')).toBe(true);
      controller.handleUpdate({
        kind: 'runStarted', clientRunId: CLIENT_RUN_ID, runId: RUN_ID,
        threadId: THREAD_ID, threadRevision: 2, inputMessageId: INPUT_MESSAGE_ID,
      });
      await flushPromises();
      expect(startRun).toHaveBeenCalledTimes(2);
      expect(startRun.mock.calls[1][0].input).toEqual({ kind: 'append', text: 'New question' });
      expect(state.getState().messages.map(({ text }) => text)).toEqual(['New question']);
      expect(selectAgentV2HeldLimitRunId(state.getState())).toBeUndefined();
      controller.dispose();
    },
  );

  it.each([undefined, 'quotaRetry', 'userRateLimit'] as const)(
    'removes only an unheld admission failure when requesting support: limit=%s', async (limitKind) => {
      const question = { id: 7, text: 'Q', isOutgoing: true, timestamp: 1 };
      const retry = { clientRunId: 'x', optimisticMessageId: question.id, resetAt: 100 };
      const state = createStateHarness({
        ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
        thread: threadSummary(1),
        messages: [question],
        admissionFailure: {
          error: { code: 'network_error', retryable: true },
          clientRunId: 'x', optimisticMessageId: question.id, timestamp: 1,
        },
        ...(limitKind === 'quotaRetry' && {
          quotaRetry: retry,
          userQuota: { limit: 20, used: 20, remaining: 0, resetAt: new Date(retry.resetAt).toISOString() },
        }),
        ...(limitKind === 'userRateLimit' && { userRateLimit: { ...retry, kind: 'rateLimit' as const } }),
      });
      const { controller } = createSupportRunHarness(state);

      expect(controller.requestSupport('header')).toBe(true);
      await flushPromises();

      expect(state.getState().messages.filter(({ id }) => id === question.id)).toEqual(limitKind ? [question] : []);
      expect(state.getState().admissionFailure).toBeUndefined();
      if (limitKind) expect(state.getState()[limitKind]?.optimisticMessageId).toBe(question.id);
      controller.dispose();
    },
  );

  it.each(['none', 'runtime', 'transport', 'quotaRetry'] as const)(
    'preserves a capacity-held question through a support request: failure=%s', async (failureKind) => {
      const question = { id: 7, text: 'Q', isOutgoing: true, timestamp: 1 };
      const failure = {
        error: { code: 'agent_capacity_exhausted' as const, retryable: true },
        clientRunId: 'x', optimisticMessageId: question.id, timestamp: 1,
      };
      const state = createStateHarness({
        ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
        thread: threadSummary(1), messages: [question],
        availability: { state: 'capacity_exhausted', resetAt: 1000 },
        admissionFailure: failure,
        ...(failureKind === 'quotaRetry' && { quotaRetry: { clientRunId: 'x', optimisticMessageId: question.id } }),
      });
      const { controller, startRun } = createSupportRunHarness(state);
      if (failureKind === 'transport') startRun.mockRejectedValueOnce(new Error('Connection interrupted'));

      expect(controller.requestSupport('header')).toBe(true);
      if (failureKind === 'runtime') {
        controller.handleUpdate({
          kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, code: 'network_error', retryable: true,
        });
      }
      await flushPromises();

      expect(state.getState().messages).toContainEqual(question);
      expect(state.getState().admissionFailure).toBe(failure);
      expect(selectAgentV2HeldLimitRunId(state.getState())).toBe('x');
      if (failureKind === 'runtime' || failureKind === 'transport') {
        const failedSupportMessage = state.getState().messages.at(-1)!;
        expect(state.getState().error).toMatchObject({ cause: { code: 'network_error', retryable: false } });
        expect(controller.requestSupport('header')).toBe(true);
        await flushPromises();
        expect(state.getState().messages).not.toContainEqual(failedSupportMessage);
        expect(state.getState().messages).toContainEqual(question);
        expect(state.getState().admissionFailure).toBe(failure);
      }
      controller.dispose();
    },
  );

  it.each([50, 1000])('preserves the rate-held question when support is rate limited until %s', async (resetAt) => {
    const question = { id: 7, text: 'Q', isOutgoing: true, timestamp: 1 };
    const limit = { kind: 'rateLimit' as const, clientRunId: 'x', optimisticMessageId: question.id, resetAt: 100 };
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1), messages: [question], userRateLimit: limit,
    });
    const { controller } = createSupportRunHarness(state);

    expect(controller.requestSupport('header')).toBe(true);
    controller.handleUpdate({
      kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
      code: 'rate_limited', retryable: true, resetAt,
    });
    await flushPromises();

    expect(state.getState().messages).toContainEqual(question);
    expect(state.getState().userRateLimit).toEqual({ ...limit, resetAt: Math.max(limit.resetAt, resetAt) });
    expect(selectAgentV2HeldLimitRunId(state.getState())).toBe('x');
    controller.dispose();
  });

  it.each(['news', 'digest'] as const)('offers and requests support in a %s chat', async (kind) => {
    const thread = {
      ...threadSummary(1),
      ...(kind === 'news'
        ? { news: { eventId: 1, headline: 'News', publishedAt: '2026-08-11T09:00:00.000Z' } }
        : { digest: { id: 'digest', windowEnd: '2026-08-11T09:00:00.000Z', total: 1,
          top: [{ eventId: 1, headline: 'News' }] } }),
    };
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread, hasHydratedHistory: true,
    });
    const { controller, startRun } = createSupportRunHarness(state);

    const isRequested = controller.requestSupport('header');
    await flushPromises();
    expect(getIsAgentV2SupportEntryVisible(thread)).toBe(true);
    expect(isRequested).toBe(true);
    expect(startRun).toHaveBeenCalledWith(expect.objectContaining({
      input: { kind: 'append', text: '$agent_support_request_message' },
      entryPoint: { kind: 'supportRequest', source: 'header' },
    }), expect.any(Function));
    controller.dispose();
  });

  it('settles the failed queue into messages when requesting support', async () => {
    const question = { id: 7, text: 'Q', isOutgoing: true, timestamp: 1 };
    const failure = {
      id: 8, text: '', isOutgoing: false, timestamp: 1,
      error: { code: 'internal_error' as const, retryable: true },
    };
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1),
      failedQueue: { messages: [question], failure },
    });
    const { controller } = createSupportRunHarness(state);

    expect(controller.requestSupport('header')).toBe(true);
    await flushPromises();

    expect(state.getState().failedQueue).toBeUndefined();
    expect(state.getState().messages).toEqual([
      question, failure, expect.objectContaining({ text: '$agent_support_request_message', isOutgoing: true }),
    ]);
    controller.dispose();
  });

  it('shows a support escalation limit as an ordinary send failure without Retry', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE, isConsentAccepted: true,
      thread: threadSummary(1),
    });
    const { controller, retryRun } = createSupportRunHarness(state);
    const error = await decodeHttpError({
      status: 429,
      headers: new Headers({ 'Content-Type': 'application/json' }),
      json: () => Promise.resolve({
        protocolVersion: 3, error: { code: 'support_escalation_rate_limited', retryable: false },
      }),
    } as Response);
    expect(error.status).toBe(429);
    controller.requestSupport('menu');
    controller.handleUpdate({
      kind: 'runFailed', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID,
      code: error.code, retryable: error.retryable,
    });
    await flushPromises();

    expect(state.actions).toContainEqual(expect.objectContaining({
      kind: 'runFailed', errorText: '$agent_support_rate_limited', retryable: false, optimisticMessageId: 1,
    }));
    expect(state.getState().admissionFailure).toMatchObject({
      error: { code: 'support_escalation_rate_limited', retryable: false },
    });
    expect(state.getState().admissionFailure?.clientRunId).toBeUndefined();
    controller.retryAdmission();
    await flushPromises();
    expect(retryRun).not.toHaveBeenCalled();
    controller.dispose();
  });

  it('records the first UI frame after committing streamed text without repeating it for every delta', () => {
    const timings: ClientTimingEvent[] = [];
    const trace = new AgentClientTrace('a'.repeat(32), (events) => timings.push(...events));
    const spy = jest.spyOn(developmentTiming, 'agentUiTrace').mockReturnValue(trace);
    const state = createStateHarness();
    const stream = createStreamHarness(state);
    try {
      stream.publish({ ...messageStarted(), developmentTraceId: trace.traceId });
      stream.publish({ ...textDelta('First'), developmentTraceId: trace.traceId });
      stream.publish({ ...textDelta(' response'), developmentTraceId: trace.traceId });
      expect(timings.some((event) => event.operation === 'ui_text_frame')).toBe(false);
      stream.flushFrames();
      stream.flushFrames();
      expect(state.actions).toContainEqual({ kind: 'textDeltasFlushed', deltas: [[1, 'First response']] });
      expect(timings.filter((event) => event.operation === 'ui_text_committed')).toHaveLength(1);
      expect(timings.filter((event) => event.operation === 'ui_text_frame')).toHaveLength(1);
    } finally {
      stream.controller.dispose();
      spy.mockRestore();
    }
  });

  it('keeps live and persisted response languages scoped to their own messages', () => {
    const state = createStateHarness();
    const stream = createStreamHarness(state);

    stream.publish({ ...messageStarted(), responseLanguage: 'ru' as const });
    const [persisted] = stream.controller.mapPersistedMessageEntries([{
      ...persistedMessage('English response'),
      id: '77777777-7777-4777-8777-777777777777',
      responseLanguage: 'en',
    }]);

    expect(state.getState().messages[0].responseLanguage).toBe('ru');
    expect(persisted.message.responseLanguage).toBe('en');
  });

  it('keeps live and persisted answer links on their messages', () => {
    const state = createStateHarness();
    const stream = createStreamHarness(state);
    const link = { textOffset: 0, textLength: 4, url: 'https://help.mywallet.io/' };

    stream.publish(messageStarted());
    stream.publish({ kind: 'answerLinkAdded', ...routing(), messageId: ASSISTANT_MESSAGE_ID, link });
    stream.publish({ kind: 'answerLinkAdded', ...routing(), messageId: ASSISTANT_MESSAGE_ID,
      link: { ...link, textOffset: 5 } });
    const [persisted] = stream.controller.mapPersistedMessageEntries([{
      ...persistedMessage('Help'),
      content: { kind: 'markdown', text: 'Help', links: [link] },
    }]);

    expect(state.getState().messages[0].links).toEqual([link, { ...link, textOffset: 5 }]);
    expect(persisted.message.links).toEqual([link]);
  });

  it('shows a stopped answer from the history without its suggestions, and not at all when it showed nothing', () => {
    const state = createStateHarness();
    const stream = createStreamHarness(state);
    const followup = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', kind: 'suggested_prompt' as const, text: 'More?' };

    const entries = stream.controller.mapPersistedMessageEntries([
      { ...persistedMessage('Partial'), status: 'cancelled', followups: [followup] },
      { ...persistedMessage(' '), id: '77777777-7777-4777-8777-777777777777', status: 'cancelled' },
      { ...persistedMessage('Complete'), id: '88888888-8888-4888-8888-888888888888', followups: [followup] },
    ]);

    expect(entries.map(({ message }) => message.text)).toEqual(['Partial', 'Complete']);
    expect(entries[0].message.followups).toBeUndefined();
    expect(entries[1].message.followups).toEqual([followup]);
  });

  it('owns stream IDs, RAF batching and terminal disposal', () => {
    const state = createStateHarness();
    const stream = createStreamHarness(state);

    stream.publish(messageStarted());
    stream.publish(textDelta('First'));
    stream.publish(textDelta(' response'));

    expect(stream.requestFrame).toHaveBeenCalledTimes(1);
    stream.flushFrames();
    expect(state.actions).toContainEqual({
      kind: 'textDeltasFlushed',
      deltas: [[1, 'First response']],
    });

    stream.publish(textDelta(' ignored'));
    const actionCount = state.actions.length;
    stream.controller.dispose();
    stream.flushFrames();
    stream.publish(messageStarted('late-message'));

    expect(stream.cancelFrame).toHaveBeenCalledTimes(1);
    expect(stream.controller.getActionLifecycleGeneration()).toBe(1);
    expect(stream.controller.getActionPresentationGeneration()).toBe(1);
    expect(state.actions).toHaveLength(actionCount);
  });

  it('refreshes action presentations for wallet updates without resetting the action lifecycle', () => {
    const state = createStateHarness();
    const stream = createStreamHarness(state);

    stream.publish({ kind: 'walletContextChanged' });

    expect(stream.controller.getActionPresentationGeneration()).toBe(1);
    expect(stream.controller.getActionLifecycleGeneration()).toBe(0);
    expect(state.actions).toContainEqual({ kind: 'walletContextChanged' });

    stream.publish({ kind: 'walletAuthorityChanged' });

    expect(stream.controller.getActionPresentationGeneration()).toBe(2);
    expect(stream.controller.getActionLifecycleGeneration()).toBe(0);

    stream.publish({ kind: 'runtimeReady', generation: 2 });

    expect(stream.controller.getActionPresentationGeneration()).toBe(3);
    expect(stream.controller.getActionLifecycleGeneration()).toBe(1);
  });

  it('owns coalesced history operations and ignores a page that settles after disposal', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      isConsentAccepted: true,
      thread: threadSummary(1),
      messages: [{ id: 10, text: 'Current', isOutgoing: false, timestamp: 20 }],
      sourceIdByMessageId: { 10: ASSISTANT_MESSAGE_ID },
      nextCursor: 'cursor-1',
    });
    const stream = createStreamHarness(state);
    const firstPage = createDeferred<AgentV2MutationResult<AgentV2ThreadHydration> | undefined>();
    const secondPage = createDeferred<AgentV2MutationResult<AgentV2ThreadHydration> | undefined>();
    const getMessages = jest.fn()
      .mockReturnValueOnce(firstPage.promise)
      .mockReturnValueOnce(secondPage.promise);
    const reportIncompatibleMessages = jest.fn();
    const controller = createAgentV2HydrationController({
      buildHistoryError: () => ({ message: 'History unavailable', isRetryable: true }),
      dispatch: state.dispatch,
      resolveThreadId: () => Promise.resolve({ ok: true, value: THREAD_ID }),
      getStarterHints: () => Promise.resolve(undefined),
      getHintsShowingId: () => 1,
      getMessages,
      getState: state.getState,
      isConsentAccepted: () => true,
      isChatVisible: () => true,
      loadAvailability: () => Promise.resolve(undefined),
      loadUserQuota: () => Promise.resolve(undefined),
      now: () => 100,
      releaseStaleThreadClearOperation: jest.fn(),
      reportIncompatibleMessages,
      stream: stream.controller,
    });

    const firstRequest = controller.loadOlderMessages();
    const coalescedRequest = controller.loadOlderMessages();
    expect(coalescedRequest).toBe(firstRequest);
    expect(getMessages).toHaveBeenCalledTimes(1);

    const olderHydration = successfulHydration('Older', 'cursor-2');
    olderHydration.value.incompatibleMessages = [incompatibleMessage(2)];
    firstPage.resolve(olderHydration);
    await firstRequest;
    expect(state.getState()).toMatchObject({
      messages: [{ text: 'Older' }, { text: 'Current' }],
      nextCursor: 'cursor-2',
      isLoadingOlderMessages: false,
    });
    expect(reportIncompatibleMessages).toHaveBeenCalledWith(
      THREAD_ID,
      [incompatibleMessage(2)],
    );

    const lateRequest = controller.loadOlderMessages();
    const actionCount = state.actions.length;
    controller.dispose();
    const lateHydration = successfulHydration('Too late');
    lateHydration.value.incompatibleMessages = [incompatibleMessage(3)];
    secondPage.resolve(lateHydration);
    await lateRequest;

    expect(state.actions).toHaveLength(actionCount);
    expect(state.getState().messages.map(({ text }) => text)).toEqual(['Older', 'Current']);
    expect(reportIncompatibleMessages).toHaveBeenCalledTimes(1);
  });

  it('reads back latest pages until they reach a shown message, without duplicates', async () => {
    const state = createStateHarness(supportChatState());
    const getMessages = jest.fn()
      .mockResolvedValueOnce(historyPage(['m5', 'm6'], 'cursor-b', 3))
      .mockResolvedValueOnce(historyPage(['m3', 'm4'], 'cursor-c'))
      .mockResolvedValueOnce(historyPage(['m1', 'm2'], 'cursor-d'));
    const controller = createHydrationHarness(state, getMessages);

    await controller.refreshLatestMessages();

    expect(getMessages.mock.calls).toEqual([[THREAD_ID, undefined], [THREAD_ID, 'cursor-b'], [THREAD_ID, 'cursor-c']]);
    expect(state.getState().messages.map(({ text }) => text)).toEqual(['m1', 'm2', 'm3', 'm4', 'm5', 'm6']);
    expect(state.getState().thread?.revision).toBe(3);
    expect(state.getState().nextCursor).toBe('older-cursor');
  });

  it('stops reading back latest pages at the page limit and keeps what is shown', async () => {
    const state = createStateHarness(supportChatState());
    const getMessages = jest.fn((_: string, cursor?: string) => {
      const page = cursor ? Number(cursor) : 0;
      return Promise.resolve(historyPage([`new-${page}`], String(page + 1)));
    });
    const controller = createHydrationHarness(state, getMessages);

    await controller.refreshLatestMessages();

    expect(getMessages).toHaveBeenCalledTimes(10);
    expect(state.getState().messages.map(({ text }) => text)).toEqual([
      'm1', 'm2', ...Array.from({ length: 10 }, (_, i) => `new-${9 - i}`),
    ]);
  });

  it('reads the latest page once an older page reports support closure, after loading finishes', async () => {
    const state = createStateHarness({ ...supportChatState(), nextCursor: 'older-cursor' });
    const getMessages = jest.fn()
      .mockResolvedValueOnce(historyPage(['m0'], undefined, 1, { state: 'closed' }))
      .mockResolvedValue(historyPage(['m1', 'm2', 'closing-event'], undefined, 2, { state: 'closed' }));
    const controller = createHydrationHarness(state, getMessages);
    state.dispatch({ kind: 'consentLoadingStarted' });

    await controller.loadOlderMessages();
    expect(getMessages).toHaveBeenCalledTimes(1);

    state.dispatch({ kind: 'hydrationFailed' });
    await flushPromises();
    state.dispatch({ kind: 'hydrationFailed' });
    await flushPromises();

    expect(getMessages).toHaveBeenCalledTimes(2);
    expect(getMessages).toHaveBeenLastCalledWith(THREAD_ID, undefined);
    expect(state.getState().messages.map(({ text }) => text)).toEqual(['m0', 'm1', 'm2', 'closing-event']);
    expect(state.getState().thread?.support).toEqual({ state: 'closed' });
  });

  it('reads the latest page after an in-flight refresh returns older than a closure from an older page', async () => {
    const state = createStateHarness(supportChatState());
    const poll = createDeferred<AgentV2MutationResult<AgentV2ThreadHydration> | undefined>();
    const getMessages = jest.fn()
      .mockReturnValueOnce(poll.promise)
      .mockResolvedValueOnce(historyPage(['m0'], undefined, 2, { state: 'closed' }))
      .mockResolvedValue(historyPage(['m1', 'm2', 'closing-event'], undefined, 2, { state: 'closed' }));
    const controller = createHydrationHarness(state, getMessages);

    const polling = controller.refreshLatestMessages();
    await controller.loadOlderMessages();
    expect(getMessages).toHaveBeenCalledTimes(2);
    poll.resolve(historyPage(['m1', 'm2', 'stale'], undefined, 1));
    await polling;
    await flushPromises();

    expect(getMessages).toHaveBeenCalledTimes(3);
    expect(getMessages).toHaveBeenLastCalledWith(THREAD_ID, undefined);
    expect(state.getState().messages.map(({ text }) => text)).toEqual(['m0', 'm1', 'm2', 'closing-event']);
  });

  it('reports incompatible messages without failing authoritative hydration', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      isConsentAccepted: true,
    });
    const stream = createStreamHarness(state);
    const reportIncompatibleMessages = jest.fn();
    const hydration = successfulHydration('Compatible');
    hydration.value.incompatibleMessages = [incompatibleMessage(0)];
    const controller = createAgentV2HydrationController({
      buildHistoryError: () => ({ message: 'History unavailable', isRetryable: true }),
      dispatch: state.dispatch,
      resolveThreadId: () => Promise.resolve({ ok: true, value: THREAD_ID }),
      getStarterHints: () => Promise.resolve(undefined),
      getHintsShowingId: () => 1,
      getMessages: () => Promise.resolve(hydration),
      getState: state.getState,
      isConsentAccepted: () => true,
      isChatVisible: () => true,
      loadAvailability: () => Promise.resolve(undefined),
      loadUserQuota: () => Promise.resolve(undefined),
      now: () => 100,
      releaseStaleThreadClearOperation: jest.fn(),
      reportIncompatibleMessages,
      stream: stream.controller,
    });

    await controller.hydrate();

    expect(state.getState().messages).toEqual([expect.objectContaining({ text: 'Compatible' })]);
    expect(state.getState().error).toBeUndefined();
    expect(reportIncompatibleMessages).toHaveBeenCalledWith(
      THREAD_ID,
      [incompatibleMessage(0)],
    );
  });

  it('reports a thread the server no longer has instead of showing another one', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      isConsentAccepted: true,
    });
    const stream = createStreamHarness(state);
    const onThreadNotFound = jest.fn();
    const controller = createAgentV2HydrationController({
      buildHistoryError: () => ({ message: 'History unavailable', isRetryable: true }),
      dispatch: state.dispatch,
      resolveThreadId: () => Promise.resolve({ ok: true, value: THREAD_ID }),
      onThreadNotFound,
      getStarterHints: () => Promise.resolve(undefined),
      getHintsShowingId: () => 1,
      getMessages: () => Promise.resolve({ ok: false, error: { code: 'thread_not_found', retryable: false } }),
      getState: state.getState,
      isConsentAccepted: () => true,
      isChatVisible: () => true,
      loadAvailability: () => Promise.resolve(undefined),
      loadUserQuota: () => Promise.resolve(undefined),
      now: () => 100,
      releaseStaleThreadClearOperation: jest.fn(),
      stream: stream.controller,
    });

    await controller.hydrate();

    expect(onThreadNotFound).toHaveBeenCalledTimes(1);
    expect(state.getState().thread).toBeUndefined();
    expect(state.getState()).toMatchObject({ error: { text: 'History unavailable' } });
  });

  it('owns run admission and terminal settlement without authoritative hydration', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
    });
    const stream = createStreamHarness(state);
    const runResult = createDeferred<AgentV2RunResult | undefined>();
    const hydrate = jest.fn(() => Promise.resolve(true));
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread: () => Promise.resolve(undefined),
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getSupportRequestText: () => '$agent_support_request_message',
      getState: state.getState,
      getActiveAccountId: () => 'account',
      hydrate,
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
      stopRun: () => Promise.resolve(),
      stream: stream.controller,
      hideSecretPhrases: (text) => text,
    });
    const publish = (update: AgentV2ClientUpdate) => {
      stream.controller.handleUpdate(update);
      controller.handleUpdate(update);
    };

    controller.sendMessage('Question');
    publish(runStarted());
    publish(messageStarted());
    publish(textDelta('Partial response'));
    stream.flushFrames();
    runResult.resolve({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'cancelled',
    });
    await flushPromises();

    expect(state.getState().sourceIdByMessageId[1]).toBe(INPUT_MESSAGE_ID);
    expect(state.getState().messages).toEqual([
      expect.objectContaining({ id: 1, text: 'Question', isOutgoing: true }),
      expect.objectContaining({ id: 2, text: 'Partial response', isStreaming: undefined }),
    ]);
    expect(stream.getPresentations()[2]).toMatchObject({ status: 'error' });
    expect(hydrate).not.toHaveBeenCalled();
    expect(state.getState().run).toEqual({ phase: 'idle' });
  });

  it('cancels a running answer on a confirmed clear and ignores its later output', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
    });
    const stream = createStreamHarness(state);
    const runResult = createDeferred<AgentV2RunResult | undefined>();
    const clearResult = createDeferred<AgentV2MutationResult<AgentThreadClearResponseV2> | undefined>();
    const clearThread = jest.fn(() => clearResult.promise);
    const hydrate = jest.fn(() => Promise.resolve(true));
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread,
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getSupportRequestText: () => '$agent_support_request_message',
      getState: state.getState,
      getActiveAccountId: () => 'account',
      hydrate,
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
      stopRun: () => Promise.resolve(),
      stream: stream.controller,
      hideSecretPhrases: (text) => text,
    });
    const publish = (update: AgentV2ClientUpdate) => {
      if (controller.isCancelledRunUpdate(update)) return;
      stream.controller.handleUpdate(update);
      controller.handleUpdate(update);
    };

    controller.sendMessage('Question');
    publish(runStarted());
    publish(messageStarted());
    publish(textDelta('Partial response'));
    controller.clearChat();

    expect(clearThread).toHaveBeenCalledWith(THREAD_ID, 2);
    expect(state.getState()).toMatchObject({
      messages: [],
      sourceIdByMessageId: {},
      threadMutation: { phase: 'clearing', threadRevision: 2 },
    });
    expect(selectAgentV2Activity(state.getState())).toBeUndefined();
    expect(stream.getPresentations()).toEqual({});
    expect(controller.isInputBlocked()).toBe(true);

    publish(textDelta(' after the clear'));
    publish(messageStarted('77777777-7777-4777-8777-777777777777'));
    publish({ kind: 'runActivityChanged', ...routing(), event: runActivity() });
    publish({ kind: 'runCancelled', ...routing() });
    stream.flushFrames();
    expect(state.getState().messages).toEqual([]);

    clearResult.resolve({
      ok: true,
      value: { protocolVersion: 3, thread: threadSummary(4), duplicate: false },
    });
    await flushPromises();
    expect(state.getState()).toMatchObject({
      messages: [],
      thread: { revision: 4 },
      threadMutation: { phase: 'idle' },
    });
    // The cancelled operation keeps input blocked until its run settles
    expect(controller.isInputBlocked()).toBe(true);

    publish({ kind: 'messageCompleted', ...routing(), messageId: ASSISTANT_MESSAGE_ID, finishReason: 'complete' });
    runResult.resolve({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'interrupted',
    });
    await flushPromises();

    expect(state.getState()).toMatchObject({ messages: [], run: { phase: 'idle' }, error: undefined });
    expect(hydrate).not.toHaveBeenCalled();
    expect(controller.isInputBlocked()).toBe(false);
  });

  it('shows and sends a new or edited message with its recovery phrase replaced', async () => {
    const editedMessageId = 7;
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
      messages: [{ id: editedMessageId, text: 'Earlier question', isOutgoing: true, timestamp: 90 }],
      sourceIdByMessageId: { [editedMessageId]: INPUT_MESSAGE_ID },
    });
    const stream = createStreamHarness(state);
    stream.controller.bindMessageSource(editedMessageId, INPUT_MESSAGE_ID);
    const startRun = jest.fn(() => Promise.resolve(undefined));
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread: () => Promise.resolve(undefined),
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getSupportRequestText: () => '$agent_support_request_message',
      getState: state.getState,
      getActiveAccountId: () => 'account',
      hydrate: () => Promise.resolve(true),
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun,
      stopRun: () => Promise.resolve(),
      stream: stream.controller,
      hideSecretPhrases: (text) => text.replace('creek aisle average', '[removed]'),
    });

    controller.sendMessage('  My words: creek aisle average. Is my wallet safe?  ');

    expect(state.getState().messages).toContainEqual(
      expect.objectContaining({ text: 'My words: [removed]. Is my wallet safe?', isOutgoing: true }),
    );
    expect(startRun).toHaveBeenLastCalledWith(expect.objectContaining({
      input: { kind: 'append', text: 'My words: [removed]. Is my wallet safe?' },
    }), expect.any(Function));
    await flushPromises();

    controller.sendMessage('Edited: creek aisle average', editedMessageId);

    expect(startRun).toHaveBeenLastCalledWith(expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited: [removed]' },
    }), expect.any(Function));
  });

  it('ignores a run result that settles after disposal', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
    });
    const stream = createStreamHarness(state);
    const runResult = createDeferred<AgentV2RunResult | undefined>();
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread: () => Promise.resolve(undefined),
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getSupportRequestText: () => '$agent_support_request_message',
      getState: state.getState,
      getActiveAccountId: () => 'account',
      hydrate: () => Promise.resolve(true),
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
      stopRun: () => Promise.resolve(),
      stream: stream.controller,
      hideSecretPhrases: (text) => text,
    });

    controller.sendMessage('Question');
    const actionCount = state.actions.length;
    controller.dispose();
    runResult.resolve({
      clientRunId: CLIENT_RUN_ID,
      runId: RUN_ID,
      inputMessageId: INPUT_MESSAGE_ID,
      state: 'completed',
    });
    await flushPromises();

    expect(state.actions).toHaveLength(actionCount);
  });
});

function supportChatState(): AgentV2MessagesState {
  return {
    ...INITIAL_AGENT_V2_MESSAGES_STATE,
    isConsentAccepted: true,
    hasHydratedHistory: true,
    thread: { ...threadSummary(1), support: { state: 'operator' } },
    messages: [
      { id: 101, text: 'm1', isOutgoing: true, timestamp: 1 },
      { id: 102, text: 'm2', isOutgoing: false, timestamp: 2 },
    ],
    sourceIdByMessageId: { 101: 'm1', 102: 'm2' },
    nextCursor: 'older-cursor',
  };
}

function historyPage(
  ids: string[],
  nextCursor?: string,
  revision = 1,
  support: AgentThreadSummaryV2['support'] = { state: 'operator' },
): Extract<AgentV2MutationResult<AgentV2ThreadHydration>, { ok: true }> {
  return {
    ok: true,
    value: {
      thread: { ...threadSummary(revision), support },
      messages: ids.map((id) => ({ ...persistedMessage(id), id })),
      nextCursor,
    },
  };
}

function createHydrationHarness(
  state: ReturnType<typeof createStateHarness>,
  getMessages: AgentV2HydrationControllerDependencies['getMessages'],
) {
  const stream = createStreamHarness(state);
  // Like the chat hook, every state change gives a deferred latest refresh its chance to run
  const dispatch = state.dispatch;
  state.dispatch = (action) => {
    dispatch(action);
    controller.resumeLatestRefresh();
  };
  const controller = createAgentV2HydrationController({
    buildHistoryError: () => ({ message: 'History unavailable', isRetryable: true }),
    dispatch: (action) => state.dispatch(action),
    resolveThreadId: () => Promise.resolve({ ok: true, value: THREAD_ID }),
    getStarterHints: () => Promise.resolve(undefined),
    getHintsShowingId: () => 1,
    getMessages,
    getState: state.getState,
    isConsentAccepted: () => true,
    isChatVisible: () => true,
    loadAvailability: () => Promise.resolve(undefined),
    loadUserQuota: () => Promise.resolve(undefined),
    now: () => 100,
    releaseStaleThreadClearOperation: jest.fn(),
    stream: stream.controller,
  });
  return controller;
}

function createStateHarness(initial: AgentV2MessagesState = INITIAL_AGENT_V2_MESSAGES_STATE) {
  let state = initial;
  const actions: AgentV2MessagesStateAction[] = [];
  return {
    actions,
    dispatch(action: AgentV2MessagesStateAction) {
      actions.push(action);
      state = reduceAgentV2MessagesState(state, action);
    },
    getState() {
      return state;
    },
  };
}

function createSupportRunHarness(state: ReturnType<typeof createStateHarness>) {
  const stream = createStreamHarness(state);
  const now = jest.fn(() => 100);
  const retryRun = jest.fn(() => Promise.resolve(undefined));
  const startRun = jest.fn((_command: AgentV2RunCommand) => (
    Promise.resolve({ clientRunId: CLIENT_RUN_ID, state: 'failed' as const })
  ));
  const controller = createAgentV2RunController({
    buildConnectionError: () => 'Connection interrupted',
    clearThread: () => Promise.resolve(undefined),
    dispatch: state.dispatch,
    getErrorText: (code) => getAgentV2ErrorText(code, ((key: string) => key) as LangFn),
    getSupportRequestText: () => '$agent_support_request_message',
    getState: state.getState,
    getActiveAccountId: () => 'account',
    hydrate: () => Promise.resolve(true),
    now,
    retryRun,
    resetHistory: jest.fn(),
    startRun,
    stopRun: () => Promise.resolve(),
    stream: stream.controller,
    hideSecretPhrases: (text) => text,
  });
  return { controller, startRun, retryRun, now };
}

function createStreamHarness(state: ReturnType<typeof createStateHarness>) {
  let presentations: TextRevealPresentations = {};
  let nextFrameId = 0;
  const frames = new Map<number, NoneToVoidFunction>();
  const cancelFrame = jest.fn((frameId: number) => {
    frames.delete(frameId);
  });
  const requestFrame = jest.fn((callback: NoneToVoidFunction) => {
    const frameId = ++nextFrameId;
    frames.set(frameId, callback);
    return frameId;
  });
  const controller = createAgentV2StreamController({
    cancelFrame,
    dispatch: state.dispatch,
    getActionPresentation: () => Promise.resolve(undefined),
    getState: state.getState,
    now: () => 100,
    requestFrame,
    setTextRevealPresentations: (update) => {
      presentations = update(presentations);
    },
  });

  return {
    cancelFrame,
    controller,
    flushFrames() {
      const pending = [...frames.values()];
      frames.clear();
      pending.forEach((callback) => callback());
    },
    getPresentations() {
      return presentations;
    },
    publish(update: AgentV2ClientUpdate) {
      controller.handleUpdate(update);
    },
    requestFrame,
  };
}

function threadSummary(revision: number): AgentThreadSummaryV2 {
  return {
    id: THREAD_ID,
    revision,
    createdAt: '2026-08-11T10:00:00.000Z',
    updatedAt: '2026-08-11T10:00:00.000Z',
    lastActivityAt: '2026-08-11T10:00:00.000Z',
    messageCount: 1,
  };
}

function successfulHydration(
  text: string,
  nextCursor?: string,
): Extract<AgentV2MutationResult<AgentV2ThreadHydration>, { ok: true }> {
  return {
    ok: true,
    value: {
      thread: threadSummary(1),
      messages: [persistedMessage(text)],
      nextCursor,
    },
  };
}

function incompatibleMessage(index: number) {
  return {
    index,
    category: 'contract' as const,
    boundary: `$.messages[${index}].content`,
    messageId: ASSISTANT_MESSAGE_ID,
  };
}

function persistedMessage(text: string): AgentV2HydratedMessage {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    content: { kind: 'markdown', text },
    createdAt: '2026-08-11T09:00:00.000Z',
  };
}

function messageStarted(
  messageId = ASSISTANT_MESSAGE_ID,
): Extract<AgentV2ClientUpdate, { kind: 'messageStarted' }> {
  return {
    kind: 'messageStarted',
    ...routing(),
    messageId,
    contentKind: 'markdown',
  };
}

function textDelta(delta: string): AgentV2ClientUpdate {
  return {
    kind: 'textDelta',
    ...routing(),
    messageId: ASSISTANT_MESSAGE_ID,
    delta,
  };
}

function runStarted(): AgentV2ClientUpdate {
  return {
    kind: 'runStarted',
    ...routing(),
    threadRevision: 2,
    inputMessageId: INPUT_MESSAGE_ID,
  };
}

function runActivity(): Extract<AgentV2ClientUpdate, { kind: 'runActivityChanged' }>['event'] {
  return {
    type: 'run_activity',
    protocolVersion: 3,
    runId: RUN_ID,
    sequence: 4,
    code: 'web.searching',
    status: 'active',
  };
}

function routing() {
  return { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, threadId: THREAD_ID };
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
}
