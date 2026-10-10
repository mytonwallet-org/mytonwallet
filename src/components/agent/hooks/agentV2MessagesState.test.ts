import type { AgentRunActivityCodeV1, AgentThreadSummaryV2 } from '../../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../../global/types';

import {
  type AgentV2MessagesState,
  type AgentV2MessagesStateAction,
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  selectAgentV2Activity,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
} from './agentV2MessagesState';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const RESET_AT = Date.parse('2026-08-12T00:00:00.000Z');

describe('Agent V2 messages state', () => {
  it('owns hydration and preserves live message-only content', () => {
    const semanticContent = {
      kind: 'notice' as const,
      schemaVersion: 1 as const,
      code: 'agent_unavailable' as const,
    };
    const current = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      messages: [{ ...message(), semanticContent }],
    };

    const loading = reduce(current, { kind: 'hydrationStarted', shouldClearError: true });
    const hydrated = reduce(loading, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('persisted-response', message('Persisted response'))],
      nextCursor: 'older-page',
      shouldPreserveLiveContent: true,
      shouldClearError: true,
    });

    expect(hydrated).toMatchObject({
      isLoading: false,
      isLoadingOlderMessages: false,
      nextCursor: 'older-page',
      thread: { id: THREAD_ID, revision: 2 },
      messages: [{ text: 'Persisted response', semanticContent }],
      sourceIdByMessageId: { 1: 'persisted-response' },
    });
  });

  it('preserves a recovery error through silent authoritative hydration', () => {
    const error = { text: 'Connection interrupted', timestamp: 10 };
    const current = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      messages: [message('Partial response')],
      sourceIdByMessageId: { 1: 'live-response' },
      error,
    };

    const loading = reduce(current, { kind: 'hydrationStarted', shouldClearError: false });
    const hydrated = reduce(loading, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('live-response', message('Authoritative response'))],
      shouldPreserveLiveContent: true,
      shouldClearError: false,
    });

    expect(hydrated).toMatchObject({
      error,
      isLoading: false,
      messages: [{ text: 'Authoritative response' }],
      sourceIdByMessageId: { 1: 'live-response' },
    });
  });

  it('preserves live-only messages and their source bindings during recovery hydration', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      messages: [
        message('Persisted response', 1),
        { ...message('Partial live response', 2), isStreaming: true },
      ],
      sourceIdByMessageId: { 1: 'persisted-source', 2: 'live-source' },
    };

    const hydrated = reduce(current, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('persisted-source', message('Authoritative response', 1))],
      shouldPreserveLiveContent: true,
      shouldClearError: false,
    });

    expect(hydrated.messages.map(({ text }) => text)).toEqual([
      'Authoritative response', 'Partial live response',
    ]);
    expect(hydrated.sourceIdByMessageId).toEqual({
      1: 'persisted-source',
      2: 'live-source',
    });
  });

  it('does not preserve live messages or source bindings across replacement-thread hydration', () => {
    const replacementThreadId = '11111111-1111-4111-8111-111111111112';
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [{ ...message('Old live response'), isStreaming: true }],
      sourceIdByMessageId: { 1: 'old-live-source' },
      nextCursor: 'old-cursor',
    };

    const hydrated = reduce(current, {
      kind: 'hydrationSucceeded',
      thread: { ...threadSummary(1), id: replacementThreadId },
      entries: [entry('replacement-source', message('Replacement response', 2))],
      nextCursor: 'replacement-cursor',
      shouldPreserveLiveContent: true,
      shouldClearError: false,
    });

    expect(hydrated.messages.map(({ text }) => text)).toEqual(['Replacement response']);
    expect(hydrated.sourceIdByMessageId).toEqual({ 2: 'replacement-source' });
    expect(hydrated.nextCursor).toBe('replacement-cursor');
  });

  it('rebinds a local message to its canonical source identity', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      messages: [message('Optimistic request')],
      sourceIdByMessageId: { 1: 'local-request' },
    };

    const rebound = reduce(current, {
      kind: 'messageSourceBound', messageId: 1, sourceId: 'canonical-request',
    });

    expect(rebound.sourceIdByMessageId).toEqual({ 1: 'canonical-request' });
  });

  it('prepends chronological history with exact request identity and source-ID deduplication', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [message('Current question', 3, true), message('Current answer', 4)],
      nextCursor: 'cursor-1',
      sourceIdByMessageId: { 3: 'source-3', 4: 'source-4' },
    };
    const firstRequest = reduce(current, {
      kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1',
    });
    const currentRequest = reduce(firstRequest, {
      kind: 'historyPageStarted', requestId: 2, threadId: THREAD_ID, cursor: 'cursor-1',
    });
    const staleSuccess = reduce(currentRequest, {
      kind: 'historyPageSucceeded',
      requestId: 1,
      threadId: THREAD_ID,
      cursor: 'cursor-1',
      entries: [entry('source-stale', message('Stale', 10))],
      nextCursor: 'stale-cursor',
    });

    expect(staleSuccess).toBe(currentRequest);

    const succeeded = reduce(currentRequest, {
      kind: 'historyPageSucceeded',
      requestId: 2,
      threadId: THREAD_ID,
      cursor: 'cursor-1',
      entries: [
        entry('source-1', message('Old question', 1, true)),
        entry('source-3', message('Duplicate source', 30, true)),
        entry('source-colliding-id', message('Duplicate local id', 1)),
        entry('source-2', message('Old answer', 2)),
      ],
      nextCursor: 'cursor-2',
    });

    expect(succeeded).toMatchObject({
      isLoadingOlderMessages: false,
      nextCursor: 'cursor-2',
      historyPageRequest: undefined,
      sourceIdByMessageId: {
        1: 'source-1',
        2: 'source-2',
        3: 'source-3',
        4: 'source-4',
      },
    });
    expect(succeeded.messages.map(({ text }) => text)).toEqual([
      'Old question',
      'Old answer',
      'Current question',
      'Current answer',
    ]);
  });

  it('keeps pagination failures separate and leaves the composer usable', () => {
    const messages = [message('Current answer')];
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages,
      nextCursor: 'cursor-1',
    };
    const loading = reduce(current, {
      kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1',
    });
    const staleFailure = reduce(loading, {
      kind: 'historyPageFailed',
      requestId: 1,
      threadId: THREAD_ID,
      cursor: 'stale-cursor',
    });
    const failed = reduce(loading, {
      kind: 'historyPageFailed',
      requestId: 1,
      threadId: THREAD_ID,
      cursor: 'cursor-1',
    });

    expect(staleFailure).toBe(loading);
    expect(failed.messages).toBe(messages);
    expect(failed.nextCursor).toBe('cursor-1');
    expect(failed.error).toBeUndefined();
    expect(failed.isLoadingOlderMessages).toBe(false);
    expect(selectIsAgentV2InputDisabled(failed, false)).toBe(false);
  });

  it('drops pagination and source bindings when the authoritative thread is replaced', () => {
    const replacementThreadId = '11111111-1111-4111-8111-111111111112';
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [message()],
      nextCursor: 'cursor-1',
      sourceIdByMessageId: { 1: 'old-thread-source' },
      isLoadingOlderMessages: true,
      historyPageRequest: { requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1' },
    };

    const replaced = reduce(current, {
      kind: 'threadChanged',
      thread: { ...threadSummary(3), id: replacementThreadId },
    });

    expect(replaced).toMatchObject({
      thread: { id: replacementThreadId },
      nextCursor: undefined,
      isLoadingOlderMessages: false,
      historyPageRequest: undefined,
      sourceIdByMessageId: {},
    });
  });

  it('truncates superseded suffixes only after edit or regeneration admission', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [
        message('First question', 1, true),
        message('First answer', 2),
        message('Second question', 3, true),
        message('Second answer', 4),
      ],
      sourceIdByMessageId: {
        1: 'source-1', 2: 'source-2', 3: 'source-3', 4: 'source-4',
      },
      nextCursor: 'cursor-1',
      isLoadingOlderMessages: true,
      historyPageRequest: { requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1' },
    };

    const edited = reduce(current, {
      kind: 'editRunAdmitted', targetMessageId: 3, text: 'Edited second question',
    });
    expect(edited.messages.map(({ text }) => text)).toEqual([
      'First question', 'First answer', 'Edited second question',
    ]);
    expect(edited.sourceIdByMessageId).toEqual({ 1: 'source-1', 2: 'source-2' });
    expect(edited.nextCursor).toBe('cursor-1');
    expect(edited.isLoadingOlderMessages).toBe(false);
    expect(edited.historyPageRequest).toBeUndefined();

    const regenerated = reduce(current, { kind: 'regenerateRunAdmitted', targetMessageId: 2 });
    expect(regenerated.messages.map(({ text }) => text)).toEqual(['First question']);
    expect(regenerated.sourceIdByMessageId).toEqual({ 1: 'source-1' });
    expect(reduce(current, { kind: 'regenerateRunAdmitted', targetMessageId: 3 })).toBe(current);
  });

  it('settles thread clear operations without applying stale completions', () => {
    const current = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
      messages: [message()],
      error: { text: 'Previous error', timestamp: 5 },
    };
    const firstClear = reduce(current, {
      kind: 'threadClearStarted',
      operationId: 1,
      threadId: THREAD_ID,
      threadRevision: 1,
    });
    const secondClear = reduce(firstClear, {
      kind: 'threadClearStarted',
      operationId: 2,
      threadId: THREAD_ID,
      threadRevision: 1,
    });

    const afterStaleSuccess = reduce(secondClear, {
      kind: 'threadClearSucceeded',
      operationId: 1,
      thread: threadSummary(2),
    });
    const afterStaleFailure = reduce(secondClear, {
      kind: 'threadClearFailed',
      operationId: 1,
      error: { text: 'Stale failure', timestamp: 10 },
    });

    expect(firstClear).toMatchObject({
      error: undefined,
      messages: [],
      threadMutation: { phase: 'clearing', operationId: 1 },
    });
    expect(afterStaleSuccess).toBe(secondClear);
    expect(afterStaleFailure).toBe(secondClear);

    const failed = reduce(secondClear, {
      kind: 'threadClearFailed',
      operationId: 2,
      error: { text: 'Connection interrupted', timestamp: 20 },
    });
    expect(failed).toMatchObject({
      error: { text: 'Connection interrupted', timestamp: 20 },
      threadMutation: { phase: 'idle' },
    });

    const clearingAgain = reduce(failed, {
      kind: 'threadClearStarted',
      operationId: 3,
      threadId: THREAD_ID,
      threadRevision: 1,
    });
    const succeeded = reduce(clearingAgain, {
      kind: 'threadClearSucceeded',
      operationId: 3,
      thread: threadSummary(3),
    });
    expect(succeeded).toMatchObject({
      error: undefined,
      messages: [],
      thread: { revision: 3 },
      threadMutation: { phase: 'idle' },
    });
  });

  it('moves a streamed run through admission, terminal state and matching settlement', () => {
    const admitting = reduce({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      error: { text: 'Previous error', timestamp: 1 },
    }, {
      kind: 'runRequested',
      operationId: 1,
      operationKind: 'command',
    });
    const streaming = reduce(admitting, {
      kind: 'runStarted',
      clientRunId: CLIENT_RUN_ID,
      threadId: THREAD_ID,
      threadRevision: 2,
    });
    const started = reduce(streaming, {
      kind: 'messageStarted',
      clientRunId: CLIENT_RUN_ID,
      message: { ...message(''), isStreaming: true },
    });
    const withText = reduce(started, {
      kind: 'textDeltasFlushed',
      deltas: [[1, 'Streamed response']],
    });
    const contentEnded = reduce(withText, {
      kind: 'messageContentEnded',
      messageId: 1,
    });
    const terminal = reduce(contentEnded, {
      kind: 'messageCompleted',
      clientRunId: CLIENT_RUN_ID,
      messageId: 1,
      finishReason: 'complete',
    });

    expect(streaming.run).toMatchObject({
      phase: 'streaming',
      operationId: 1,
      clientRunId: CLIENT_RUN_ID,
    });
    expect(admitting.error).toBeUndefined();
    expect(withText.messages[0]).toMatchObject({ text: 'Streamed response', isStreaming: true });
    expect(selectAgentV2Activity(withText)).toBeUndefined();
    expect(contentEnded.run).toMatchObject({
      phase: 'streaming',
      operationId: 1,
      clientRunId: CLIENT_RUN_ID,
    });
    expect(contentEnded.messages[0]).toMatchObject({
      isStreaming: undefined,
      shouldCommitMarkdownTail: true,
    });
    expect(terminal.run).toEqual({
      phase: 'terminal',
      operationId: 1,
      operationKind: 'command',
      clientRunId: CLIENT_RUN_ID,
    });
    expect(terminal.messages[0]).toMatchObject({
      isStreaming: undefined,
      shouldCommitMarkdownTail: true,
    });

    const settled = reduce(terminal, { kind: 'runSettled', operationId: 1 });
    expect(settled.run).toEqual({ phase: 'idle' });
  });

  it('ignores a stale settlement from an earlier local operation', () => {
    const current = reduce(INITIAL_AGENT_V2_MESSAGES_STATE, {
      kind: 'runRequested',
      operationId: 2,
      operationKind: 'command',
    });

    const afterStaleSettlement = reduce(current, { kind: 'runSettled', operationId: 1 });

    expect(afterStaleSettlement).toBe(current);
    expect(afterStaleSettlement.run).toMatchObject({ phase: 'admitting', operationId: 2 });
  });

  it('normalizes terminal failures, limits and cancellation', () => {
    const running = reduce(
      { ...INITIAL_AGENT_V2_MESSAGES_STATE, messages: [{ ...message('Partial'), isStreaming: true }] },
      { kind: 'runRequested', operationId: 1, operationKind: 'command' },
    );
    const capacity = reduce(running, runFailure('agent_capacity_exhausted', {
      messageId: 1,
      resetAt: RESET_AT,
      resetAtIso: '2026-08-12T00:00:00.000Z',
    }));
    const rateLimit = reduce(running, runFailure('rate_limited', { messageId: 1, resetAt: RESET_AT }));
    const quota = reduce(running, runFailure('user_quota_exhausted', { messageId: 1, resetAt: RESET_AT }));
    const generic = reduce(running, runFailure('internal_error', { messageId: 1 }));
    const preAdmission = reduce(running, runFailure('provider_error', { optimisticMessageId: 1 }));
    const cancelling = reduce(running, { kind: 'runCancelled', clientRunId: CLIENT_RUN_ID });
    const cancelled = reduce(cancelling, { kind: 'runSettled', operationId: 1 });

    expect(capacity).toMatchObject({
      run: { phase: 'idle' },
      messages: [{
        isStreaming: undefined,
        error: { code: 'agent_capacity_exhausted', resetAt: '2026-08-12T00:00:00.000Z' },
      }],
    });
    expect(rateLimit.userRateLimit).toEqual({
      kind: 'rateLimit',
      clientRunId: CLIENT_RUN_ID,
      resetAt: RESET_AT,
    });
    expect(quota.quotaRetry).toEqual({ clientRunId: CLIENT_RUN_ID, resetAt: RESET_AT });
    expect(rateLimit.messages[0].error).toMatchObject({ code: 'rate_limited' });
    expect(quota.messages[0].error).toMatchObject({ code: 'user_quota_exhausted' });
    expect(generic).toMatchObject({
      run: { phase: 'idle' },
      messages: [{ text: 'Partial', error: { code: 'internal_error', retryable: true } }],
    });
    expect(preAdmission).toMatchObject({
      admissionFailure: {
        clientRunId: CLIENT_RUN_ID,
        optimisticMessageId: 1,
        error: { code: 'provider_error', retryable: true },
      },
    });
    expect(preAdmission.error).toBeUndefined();
    expect(cancelled).toMatchObject({
      run: { phase: 'idle' },
      messages: [{ isStreaming: undefined }],
    });
  });

  it('retains a pre-admission capacity request without creating an assistant message', () => {
    const optimisticMessage = message('Try later', 7, true);
    const admitting = reduce(
      { ...INITIAL_AGENT_V2_MESSAGES_STATE, messages: [optimisticMessage] },
      { kind: 'runRequested', operationId: 1, operationKind: 'command' },
    );

    const failed = reduce(admitting, runFailure('agent_capacity_exhausted', {
      optimisticMessageId: optimisticMessage.id,
    }));

    expect(failed).toMatchObject({
      messages: [optimisticMessage],
      availability: { state: 'capacity_exhausted' },
      admissionFailure: {
        clientRunId: CLIENT_RUN_ID,
        optimisticMessageId: optimisticMessage.id,
        error: { code: 'agent_capacity_exhausted', retryable: true },
      },
    });
  });

  it('preserves an expired rate retry and removes authority-bound action presentation state', () => {
    const state: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
      userRateLimit: { kind: 'rateLimit', clientRunId: CLIENT_RUN_ID, resetAt: RESET_AT },
      messages: [{
        ...message(),
        actionPresentations: { action: { kind: 'inactive' } },
      }],
    };

    const expired = reduce(state, { kind: 'composerStatusExpired' });
    const invalidated = reduce(expired, { kind: 'walletAuthorityChanged', threadId: THREAD_ID });

    expect(expired.userRateLimit).toEqual(state.userRateLimit);
    expect(invalidated.messages[0]).not.toHaveProperty('actionPresentations');
  });

  it('derives activity and composer blocking from the lifecycle', () => {
    const admitting = reduce(INITIAL_AGENT_V2_MESSAGES_STATE, {
      kind: 'runRequested',
      operationId: 1,
      operationKind: 'command',
    });

    expect(selectAgentV2Activity(admitting)).toEqual({ kind: 'analyzingRequest' });
    expect(selectIsAgentV2RunActive(admitting)).toBe(true);
    expect(selectIsAgentV2InputDisabled(admitting, false)).toBe(true);
    expect(selectIsAgentV2InputDisabled({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      threadMutation: {
        phase: 'clearing', operationId: 1, threadId: THREAD_ID, threadRevision: 1,
      },
    }, false)).toBe(true);
    expect(selectIsAgentV2InputDisabled(INITIAL_AGENT_V2_MESSAGES_STATE, true)).toBe(true);
    expect(selectIsAgentV2InputDisabled(INITIAL_AGENT_V2_MESSAGES_STATE, false)).toBe(false);
  });

  it('shows only visible active run activity until answer text arrives', () => {
    const started = reduce(reduce(INITIAL_AGENT_V2_MESSAGES_STATE, {
      kind: 'runRequested', operationId: 1, operationKind: 'command',
    }), {
      kind: 'runStarted', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
    });
    const searching = reduce(started, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('web.searching', 'active'),
    });
    const searchingCompleted = reduce(searching, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('web.searching', 'completed'),
    });
    const hiddenComputing = reduce(searchingCompleted, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('analysis.computing', 'active'),
    });
    const readingSources = reduce(hiddenComputing, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('web.reading_sources', 'active'),
    });
    const sourcesCompleted = reduce(readingSources, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('web.reading_sources', 'completed'),
    });
    const messageStarted = reduce(sourcesCompleted, {
      kind: 'messageStarted',
      clientRunId: CLIENT_RUN_ID,
      message: { ...message(''), isStreaming: true },
    });
    const withAnswer = reduce(messageStarted, {
      kind: 'textDeltasFlushed',
      deltas: [[1, 'Answer']],
    });
    const lateCompletion = reduce(withAnswer, {
      kind: 'runActivityChanged',
      clientRunId: CLIENT_RUN_ID,
      event: runActivityEvent('data.reading_market', 'completed'),
    });

    expect(selectAgentV2Activity(searchingCompleted)).toEqual({ kind: 'server', code: 'web.searching' });
    expect(selectAgentV2Activity(hiddenComputing)).toEqual({ kind: 'server', code: 'web.searching' });
    expect(selectAgentV2Activity(sourcesCompleted)).toEqual({ kind: 'server', code: 'web.reading_sources' });
    expect(selectAgentV2Activity(messageStarted)).toEqual({ kind: 'preparingResponse' });
    expect(selectAgentV2Activity(withAnswer)).toBeUndefined();
    expect(selectAgentV2Activity(lateCompletion)).toBeUndefined();
  });
});

function runActivityEvent(
  code: AgentRunActivityCodeV1,
  status: 'active' | 'completed',
) {
  return {
    type: 'run_activity' as const,
    protocolVersion: 3 as const,
    runId: THREAD_ID,
    sequence: 2,
    code,
    status,
  };
}

function reduce(state: AgentV2MessagesState, action: AgentV2MessagesStateAction) {
  return reduceAgentV2MessagesState(state, action);
}

function runFailure(
  code: Extract<AgentV2MessagesStateAction, { kind: 'runFailed' }>['code'],
  extra: Partial<Extract<AgentV2MessagesStateAction, { kind: 'runFailed' }>> = {},
): Extract<AgentV2MessagesStateAction, { kind: 'runFailed' }> {
  return {
    kind: 'runFailed',
    clientRunId: CLIENT_RUN_ID,
    code,
    retryable: true,
    hasRunId: false,
    errorText: 'Agent failed',
    timestamp: 10,
    ...extra,
  };
}

function message(text = 'Response', id = 1, isOutgoing = false): AgentMessage {
  return {
    id,
    text,
    isOutgoing,
    timestamp: 10,
  };
}

function entry(sourceId: string, currentMessage: AgentMessage) {
  return { sourceId, message: currentMessage };
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
