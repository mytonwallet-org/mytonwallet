import type { AgentRunActivityCodeV1, AgentThreadSummaryV2 } from '../../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../../global/types';

import {
  type AgentV2MessagesState,
  type AgentV2MessagesStateAction,
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  restoreAgentV2MessagesState,
  selectAgentV2Activity,
  selectAgentV2CachedChat,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
} from './agentV2MessagesState';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const RESET_AT = Date.parse('2026-08-12T00:00:00.000Z');
const ACTIVE_SEND = {
  kind: 'send' as const,
  status: 'active' as const,
  network: 'ton' as const,
  accountLabel: 'Main',
  feeStatus: 'estimated' as const,
  warningCodes: [],
};

describe('Agent V2 messages state', () => {
  it('leaves a loaded chat\'s saved history to open with, and restores it until the history loads again', () => {
    const hydrated = reduce(INITIAL_AGENT_V2_MESSAGES_STATE, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('persisted-response', message('Persisted response'))],
      nextCursor: 'older-page',
      shouldPreserveLiveContent: false,
    });
    const cachedChat = selectAgentV2CachedChat(hydrated)!;
    expect(cachedChat).toMatchObject({
      thread: threadSummary(2),
      messages: hydrated.messages,
      sourceIdByMessageId: { 1: 'persisted-response' },
      nextCursor: 'older-page',
    });

    // A message the server doesn't keep and a failure of the chat stay out; a news discussion and a chat loading
    // again in place leave their history too
    const failed = selectAgentV2CachedChat({
      ...hydrated,
      messages: [...hydrated.messages, message('Failed to go', 2, true)],
      error: { text: 'Error', timestamp: 1 },
    })!;
    expect(failed.messages).toEqual(hydrated.messages);
    expect(failed.sourceIdByMessageId).toEqual({ 1: 'persisted-response' });
    expect(failed).not.toHaveProperty('error');
    expect(selectAgentV2CachedChat({ ...hydrated, isLoading: true })?.messages).toEqual(hydrated.messages);
    const news = { ...threadSummary(2), news: newsCard() };
    expect(selectAgentV2CachedChat({ ...hydrated, thread: news })?.thread).toEqual(news);
    // Nothing is left while an answer is produced, the chat is cleared, or the history is not loaded
    const answering = reduce(hydrated, { kind: 'runRequested', operationId: 1, operationKind: 'command' });
    expect(selectAgentV2CachedChat(answering)).toBeUndefined();
    expect(selectAgentV2CachedChat(INITIAL_AGENT_V2_MESSAGES_STATE)).toBeUndefined();

    const restored = restoreAgentV2MessagesState(cachedChat);
    expect(restored).toMatchObject({
      isConsentAccepted: true, hasHydratedHistory: true, isShowingCachedHistory: true, messages: hydrated.messages,
    });
    const refreshing = reduce(restored, { kind: 'hydrationStarted', shouldClearError: false });
    expect(refreshing.isShowingCachedHistory).toBe(true);
    expect(reduce(refreshing, { kind: 'hydrationFailed' }).isShowingCachedHistory).toBeUndefined();
    expect(reduce(refreshing, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('persisted-response', message('Persisted response'))],
      shouldPreserveLiveContent: true,
    }).isShowingCachedHistory).toBeUndefined();
  });

  it('takes a restored chat\'s actions from the server, keeping the presentations of unchanged ones', () => {
    const kept = receiveAction('33333333-3333-4333-8333-333333333331');
    const changed = receiveAction('33333333-3333-4333-8333-333333333332');
    const dropped = receiveAction('33333333-3333-4333-8333-333333333333');
    const restored = restoreAgentV2MessagesState({
      thread: threadSummary(2),
      messages: [{
        ...message('Answer', 2),
        actions: [kept, changed, dropped],
        actionPresentations: { [kept.id]: ACTIVE_SEND, [changed.id]: ACTIVE_SEND, [dropped.id]: ACTIVE_SEND },
      }],
      sourceIdByMessageId: { 2: 'answer' },
    });
    const serverChanged = { ...changed, title: 'Receive TON' };

    const hydrated = reduce(reduce(restored, { kind: 'hydrationStarted', shouldClearError: false }), {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('answer', {
        ...message('Answer', 2),
        actions: [kept, serverChanged],
        actionPresentations: { [kept.id]: { kind: 'inactive' }, [serverChanged.id]: { kind: 'inactive' } },
      })],
      shouldPreserveLiveContent: true,
    });

    expect(hydrated.messages[0].actions).toEqual([kept, serverChanged]);
    expect(hydrated.messages[0].actionPresentations).toEqual({
      [kept.id]: ACTIVE_SEND, [serverChanged.id]: { kind: 'inactive' },
    });
  });

  it('keeps a live run\'s actions over the history read during it', () => {
    const liveAction = receiveAction('33333333-3333-4333-8333-333333333334');
    const live: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [
        {
          ...message('Replayed answer', 2),
          actions: [liveAction],
          actionPresentations: { [liveAction.id]: ACTIVE_SEND },
        },
        { ...message('Streaming answer', 3), isStreaming: true, actions: [liveAction] },
      ],
      sourceIdByMessageId: { 2: 'replayed', 3: 'streaming' },
    };
    const readDuringRun = (state: AgentV2MessagesState) => reduce(state, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('replayed', message('Replayed answer', 2)), entry('streaming', message('Streaming', 3))],
      shouldPreserveLiveContent: true,
    });

    expect(readDuringRun(live).messages.map(({ actions }) => actions)).toEqual([[liveAction], [liveAction]]);
    expect(readDuringRun(live).messages[0].actionPresentations).toEqual({ [liveAction.id]: ACTIVE_SEND });
    // Over a cached history, the answer the stream is writing keeps its live actions too
    expect(readDuringRun({ ...live, isShowingCachedHistory: true }).messages[1].actions).toEqual([liveAction]);
  });

  it('keeps the text a stopped answer showed while the server holds less of it, until it holds as much', () => {
    const question = message('Question', 1, true);
    const shownText = 'The answer streamed this far';
    const streaming: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      hasHydratedHistory: true,
      messages: [question, { ...message(shownText, 2), isStreaming: true }],
      sourceIdByMessageId: { 1: 'question', 2: 'answer' },
    };
    const stopped = reduce(streaming, { kind: 'runStopped', messageId: 2 });
    const shownAnswer = stopped.messages[1];
    expect(shownAnswer).toMatchObject({ id: 2, text: shownText });
    expect(shownAnswer.isStreaming).toBeUndefined();

    // The server leaves out the answer it cancelled before saving what streamed, so the shown one stays in its place
    const later = message('Later question', 3, true);
    const withoutAnswer = readHistory(stopped, [entry('question', question), entry('later', later)]);
    expect(withoutAnswer.messages).toEqual([question, shownAnswer, later]);
    expect(withoutAnswer.sourceIdByMessageId).toEqual({ 1: 'question', 2: 'answer', 3: 'later' });

    // A shorter saved text gives way to the shown one, with no follow-ups and nothing to rate
    const shorter = readHistory(withoutAnswer, [entry('question', question), entry('answer', {
      ...message('The answer', 2),
      isComplete: true,
      followups: [{ id: 'followup', kind: 'suggested_prompt', text: 'Tell me more' }],
    })]);
    expect(shorter.messages).toEqual([question, shownAnswer]);

    // The chat opened again in this session keeps it too
    const reopened = restoreAgentV2MessagesState(selectAgentV2CachedChat(shorter)!);
    expect(readHistory(reopened, [entry('question', question)]).messages).toEqual([question, shownAnswer]);

    // Once the server holds as much, its answer shows, and a later read shows only what the server has
    const savedAnswer = { ...message(`${shownText}, and the rest`, 2), isComplete: true };
    const caughtUp = readHistory(shorter, [entry('question', question), entry('answer', savedAnswer)]);
    expect(caughtUp.messages).toEqual([question, savedAnswer]);
    expect(caughtUp.stoppedAnswers).toBeUndefined();
    expect(readHistory(caughtUp, [entry('question', question)]).messages).toEqual([question]);

    // An answer stopped before its first words leaves nothing to keep
    expect(reduce({
      ...streaming, messages: [question, { ...message('', 2), isStreaming: true }],
    }, { kind: 'runStopped', messageId: 2 }).stoppedAnswers).toBeUndefined();
  });

  it('keeps a stopped answer whose question is on an older page out of the newest messages until it loads', () => {
    const question = message('Question', 1, true);
    const shownText = 'The answer streamed this far';
    const stopped = reduce({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      hasHydratedHistory: true,
      messages: [question, { ...message(shownText, 2), isStreaming: true }],
      sourceIdByMessageId: { 1: 'question', 2: 'answer' },
    }, { kind: 'runStopped', messageId: 2 });
    const shownAnswer = stopped.messages[1];

    // Later messages have pushed the question past the newest page, and the server left the answer out
    const laterQuestion = message('Later question', 3, true);
    const laterAnswer = message('Later answer', 4);
    const newest = reduce(stopped, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('later-question', laterQuestion), entry('later-answer', laterAnswer)],
      nextCursor: 'older',
      shouldPreserveLiveContent: false,
    });
    expect(newest.messages).toEqual([laterQuestion, laterAnswer]);
    expect(newest.stoppedAnswers).toHaveLength(1);

    // The older page brings the question, and the answer goes after it again
    const loading = reduce(newest, {
      kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'older',
    });
    const olderPage = {
      kind: 'historyPageSucceeded' as const, requestId: 1, threadId: THREAD_ID, cursor: 'older', threadRevision: 3,
    };
    const older = reduce(loading, { ...olderPage, entries: [entry('question', question)] });
    expect(older.messages).toEqual([question, shownAnswer, laterQuestion, laterAnswer]);
    expect(older.sourceIdByMessageId).toMatchObject({ 1: 'question', 2: 'answer' });
    expect(older.stoppedAnswers).toHaveLength(1);

    // A shorter saved answer on that page gives way to the shown one
    const withShorter = reduce(loading, {
      ...olderPage, entries: [entry('question', question), entry('answer', message('The answer', 5))],
    });
    expect(withShorter.messages).toEqual([question, { ...shownAnswer, id: 5 }, laterQuestion, laterAnswer]);
  });

  it('keeps a stopped answer waiting for an older page through an admitted edit or regeneration later on', () => {
    const question = message('Question', 1, true);
    const stopped = reduce({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      hasHydratedHistory: true,
      messages: [question, { ...message('The answer streamed this far', 2), isStreaming: true }],
      sourceIdByMessageId: { 1: 'question', 2: 'answer' },
    }, { kind: 'runStopped', messageId: 2 });
    const shownAnswer = stopped.messages[1];
    const laterQuestion = message('Later question', 3, true);
    const laterAnswer = message('Later answer', 4);
    const newest = reduce(stopped, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('later-question', laterQuestion), entry('later-answer', laterAnswer)],
      nextCursor: 'older',
      shouldPreserveLiveContent: false,
    });
    // The later answer was stopped too, as it showed
    const waiting = newest.stoppedAnswers!;
    const withLaterStopped: AgentV2MessagesState = {
      ...newest,
      stoppedAnswers: [...waiting, {
        message: { ...laterAnswer, text: 'Later answer as it showed' },
        sourceId: 'later-answer',
        previousSourceId: 'later-question',
      }],
    };

    const truncations: AgentV2MessagesStateAction[] = [
      { kind: 'regenerateRunAdmitted', targetMessageId: 4 },
      { kind: 'editRunAdmitted', targetMessageId: 3, text: 'Later question, edited' },
    ];
    truncations.forEach((truncation) => {
      const truncated = reduce(withLaterStopped, truncation);
      expect(truncated.stoppedAnswers).toEqual(waiting);

      const loading = reduce(truncated, {
        kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'older',
      });
      const older = reduce(loading, {
        kind: 'historyPageSucceeded',
        requestId: 1,
        threadId: THREAD_ID,
        cursor: 'older',
        threadRevision: 3,
        entries: [entry('question', question)],
      });
      expect(older.messages.slice(0, 2)).toEqual([question, shownAnswer]);
    });
  });

  it('forgets a stopped answer regenerated after it came back on an older page under a new id', () => {
    const question = message('Question', 1, true);
    const stopped = reduce({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      hasHydratedHistory: true,
      messages: [question, { ...message('The answer streamed this far', 2), isStreaming: true }],
      sourceIdByMessageId: { 1: 'question', 2: 'answer' },
    }, { kind: 'runStopped', messageId: 2 });
    const laterQuestion = message('Later question', 3, true);
    const laterAnswer = message('Later answer', 4);
    const newest = reduce(stopped, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(3),
      entries: [entry('later-question', laterQuestion), entry('later-answer', laterAnswer)],
      nextCursor: 'older',
      shouldPreserveLiveContent: false,
    });
    const loading = reduce(newest, {
      kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'older',
    });
    // The older page brings the answer's shorter saved copy under a new id
    const older = reduce(loading, {
      kind: 'historyPageSucceeded',
      requestId: 1,
      threadId: THREAD_ID,
      cursor: 'older',
      threadRevision: 3,
      entries: [entry('question', question), entry('answer', message('The answer', 5))],
    });
    expect(older.messages[1]).toMatchObject({ id: 5, text: 'The answer streamed this far' });

    const regenerated = reduce(older, { kind: 'regenerateRunAdmitted', targetMessageId: 5 });
    expect(regenerated.stoppedAnswers).toBeUndefined();
    const reloaded = readHistory(regenerated, [
      entry('question', question),
      entry('new-answer', message('A new answer', 6)),
      entry('later-question', laterQuestion),
      entry('later-answer', laterAnswer),
    ]);
    expect(reloaded.messages.map(({ text }) => text)).toEqual([
      'Question', 'A new answer', 'Later question', 'Later answer',
    ]);
  });

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

  it('clears a history failure after silent authoritative hydration', () => {
    const current = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      error: { text: 'Failed to load chat', timestamp: 10, isHistoryFailure: true },
    };

    const loading = reduce(current, { kind: 'hydrationStarted', shouldClearError: false });
    const hydrated = reduce(loading, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('persisted-response', message('Persisted response'))],
      shouldPreserveLiveContent: true,
    });

    expect(loading.error).toBe(current.error);
    expect(hydrated.error).toBeUndefined();
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
    });

    expect(hydrated.messages.map(({ text }) => text)).toEqual([
      'Authoritative response', 'Partial live response',
    ]);
    expect(hydrated.sourceIdByMessageId).toEqual({
      1: 'persisted-source',
      2: 'live-source',
    });
  });

  it('keeps an answer the stream is still writing when history already holds its text', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      messages: [{ ...message('', 2), isStreaming: true }],
      sourceIdByMessageId: { 2: 'live-source' },
    };

    const hydrated = reduce(current, {
      kind: 'hydrationSucceeded',
      thread: threadSummary(2),
      entries: [entry('live-source', { ...message('Complete answer', 2), timestamp: 20, isComplete: true })],
      shouldPreserveLiveContent: true,
    });
    const streamed = reduce(hydrated, { kind: 'textDeltasFlushed', deltas: [[2, 'Complete answer']] });

    expect(streamed.messages).toMatchObject([{ text: 'Complete answer', timestamp: 20, isStreaming: true }]);
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
      threadRevision: 2,
      requestId: 1,
      threadId: THREAD_ID,
      cursor: 'cursor-1',
      entries: [entry('source-stale', message('Stale', 10))],
      nextCursor: 'stale-cursor',
    });

    expect(staleSuccess).toBe(currentRequest);

    const succeeded = reduce(currentRequest, {
      kind: 'historyPageSucceeded',
      threadRevision: 2,
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

  it.each([1, 2, 3])('updates support from history only at the known revision or newer: %s', (threadRevision) => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: { ...threadSummary(2), support: { state: 'closed' } },
      nextCursor: 'cursor-1',
    };
    const loading = reduce(current, {
      kind: 'historyPageStarted', requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1',
    });
    const support = { state: 'operator' as const, lastOperatorMessageAt: '2026-08-11T10:00:00.000Z' };
    const succeeded = reduce(loading, {
      kind: 'historyPageSucceeded', requestId: 1, threadId: THREAD_ID, cursor: 'cursor-1',
      threadRevision, support, entries: [entry('older-source', message('Older message'))],
    });

    expect(succeeded.thread?.support).toEqual(threadRevision >= 2 ? support : { state: 'closed' });
    expect(succeeded.thread?.revision).toBe(Math.max(2, threadRevision));
    expect(succeeded.messages).toEqual([message('Older message')]);
    expect(succeeded.isLoadingOlderMessages).toBe(false);
    // The reply the summary announces is not on this page, so it is not read yet
    expect(succeeded.loadedOperatorMessageAt).toBeUndefined();
  });

  it('counts an operator reply as loaded only from the newest history, not from a thread summary', () => {
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: { ...threadSummary(2), support: { state: 'waiting' } },
    };
    const support = { state: 'operator' as const, lastOperatorMessageAt: '2026-08-11T10:00:00.000Z' };

    const announced = reduce(current, { kind: 'threadChanged', thread: { ...threadSummary(3), support } });
    expect(announced.thread?.support).toEqual(support);
    expect(announced.loadedOperatorMessageAt).toBeUndefined();

    const loaded = reduce(announced, {
      kind: 'latestMessagesReceived',
      thread: { ...threadSummary(3), support },
      entries: [entry('reply-source', message('Operator reply'))],
      sourceIds: ['reply-source'],
    });
    expect(loaded.loadedOperatorMessageAt).toBe(support.lastOperatorMessageAt);
  });

  it('places refreshed messages in the server history order before local messages', () => {
    const earlier = message('Earlier answer', 1);
    const question = message('Question', 2, true);
    const local = message('Not confirmed yet', 3, true);
    const current: AgentV2MessagesState = {
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(2),
      messages: [earlier, question, local],
      sourceIdByMessageId: { 1: 'earlier-source', 2: 'question-source' },
    };

    const merged = reduce(current, {
      kind: 'latestMessagesReceived',
      thread: threadSummary(3),
      entries: [entry('reply-source', message('Operator reply', 4)), entry('closed-source', message('Closed', 5))],
      sourceIds: ['earlier-source', 'reply-source', 'question-source', 'closed-source'],
    });

    expect(merged.messages.map(({ text }) => text)).toEqual([
      'Earlier answer', 'Operator reply', 'Question', 'Closed', 'Not confirmed yet',
    ]);
    expect(merged.messages[2]).toBe(question);
    expect(merged.sourceIdByMessageId).toEqual({
      1: 'earlier-source', 2: 'question-source', 4: 'reply-source', 5: 'closed-source',
    });
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
      isComplete: true,
    });
    expect(started.messages[0].isComplete).toBeUndefined();
    expect(reduce(contentEnded, {
      kind: 'messageCompleted', clientRunId: CLIENT_RUN_ID, messageId: 1, finishReason: 'cancelled',
    }).messages[0].isComplete).toBeUndefined();

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

  it.each(['messageStarted', 'runActivityChanged'] as const)(
    'settles an interrupted run adopted through %s without a local operation',
    (kind) => {
      const streaming = reduce(INITIAL_AGENT_V2_MESSAGES_STATE, kind === 'messageStarted' ? {
        kind,
        clientRunId: CLIENT_RUN_ID,
        message: { ...message('Partial response'), isStreaming: true },
      } : {
        kind,
        clientRunId: CLIENT_RUN_ID,
        event: runActivityEvent('web.searching', 'active'),
      });
      const interrupted = reduce(streaming, {
        kind: 'messageCompleted',
        clientRunId: CLIENT_RUN_ID,
        messageId: 1,
        finishReason: 'run_interrupted',
      });

      expect(streaming.run).toMatchObject({ phase: 'streaming', clientRunId: CLIENT_RUN_ID });
      expect(interrupted.run).toEqual({ phase: 'idle' });
      expect(selectIsAgentV2InputDisabled(interrupted, false)).toBe(false);
    },
  );

  it('keeps an interrupted local operation active until its matching settlement', () => {
    const requested = reduce(INITIAL_AGENT_V2_MESSAGES_STATE, {
      kind: 'runRequested', operationId: 1, operationKind: 'command',
    });
    const streaming = reduce(requested, {
      kind: 'messageStarted',
      clientRunId: CLIENT_RUN_ID,
      message: { ...message('Partial response'), isStreaming: true },
    });
    const interrupted = reduce(streaming, {
      kind: 'messageCompleted',
      clientRunId: CLIENT_RUN_ID,
      messageId: 1,
      finishReason: 'run_interrupted',
    });

    expect(interrupted.run).toBe(streaming.run);
    expect(interrupted.messages[0].isStreaming).toBeUndefined();
    expect(selectIsAgentV2InputDisabled(interrupted, false)).toBe(true);
    expect(reduce(interrupted, { kind: 'runSettled', operationId: 1 }).run).toEqual({ phase: 'idle' });
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

  // The chat renders again for every new state, so an update that changes nothing keeps the one it has
  it('keeps the state for updates that change nothing', () => {
    const streaming = reduce(
      { ...INITIAL_AGENT_V2_MESSAGES_STATE, messages: [message('Answer')] },
      {
        kind: 'runStarted', clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
      },
    );
    const withText = reduce(streaming, { kind: 'textDeltasFlushed', deltas: [[1, ' grows']] });

    expect(reduce(withText, { kind: 'textDeltasFlushed', deltas: [[99, 'lost']] })).toBe(withText);
    expect(reduce(withText, { kind: 'textDeltasFlushed', deltas: [[1, ' more']] })).not.toBe(withText);
    expect(reduce(withText, { kind: 'messageContentEnded', messageId: 99 })).toBe(withText);
    expect(reduce(withText, {
      kind: 'runActivityChanged', clientRunId: CLIENT_RUN_ID, event: runActivityEvent('analysis.computing', 'active'),
    })).toBe(withText);
    expect(reduce(withText, {
      kind: 'toolActivityChanged', clientRunId: 'another-run', activity: { kind: 'preparingResponse' },
    })).toBe(withText);
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

function receiveAction(id: string) {
  return {
    id,
    kind: 'receive' as const,
    title: 'Receive',
    labelCode: 'open_receive' as const,
    effect: 'open_receive' as const,
    localDraftRequired: false as const,
    requiresConfirmation: false as const,
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

// A read of the latest history page, as after a stop
function readHistory(state: AgentV2MessagesState, entries: ReturnType<typeof entry>[]) {
  return reduce(state, {
    kind: 'hydrationSucceeded', thread: threadSummary(3), entries, shouldPreserveLiveContent: false,
  });
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

function newsCard() {
  return {
    eventId: 1,
    headline: 'News',
    excerpt: 'Excerpt',
    publishedAt: '2026-08-11T10:00:00.000Z',
  };
}
