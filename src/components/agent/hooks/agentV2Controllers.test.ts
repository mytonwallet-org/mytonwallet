import type {
  AgentThreadClearResponseV2,
  AgentThreadSummaryV2,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2HydratedMessage,
  AgentV2MutationResult,
  AgentV2RunResult,
  AgentV2ThreadHydration,
} from '../../../api/agentV2/types';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
} from './agentV2MessagesState';
import type { TextRevealPresentations } from './textRevealPresentation';

import { AgentClientTrace, type ClientTimingEvent } from '../../../api/agentV2/developmentTelemetry';
import * as developmentTiming from './agentDevelopmentTiming';
import { createAgentV2HydrationController } from './agentV2HydrationController';
import {
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  selectAgentV2Activity,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const RUN_ID = '33333333-3333-4333-8333-333333333333';
const INPUT_MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const ASSISTANT_MESSAGE_ID = '55555555-5555-4555-8555-555555555555';

describe('Agent V2 controllers', () => {
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
    const persisted = stream.controller.mapPersistedMessageEntry({
      ...persistedMessage('English response'),
      id: '77777777-7777-4777-8777-777777777777',
      responseLanguage: 'en',
    });

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
    const persisted = stream.controller.mapPersistedMessageEntry({
      ...persistedMessage('Help'),
      content: { kind: 'markdown', text: 'Help', links: [link] },
    });

    expect(state.getState().messages[0].links).toEqual([link, { ...link, textOffset: 5 }]);
    expect(persisted.message.links).toEqual([link]);
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
      getDefaultThread: () => Promise.resolve({ ok: true, value: {
        protocolVersion: 3,
        thread: threadSummary(1),
        created: false,
      } }),
      getHints: () => Promise.resolve(undefined),
      getLangCode: () => 'en',
      getMessages,
      getState: state.getState,
      isConsentAccepted: () => true,
      loadAvailability: () => Promise.resolve(undefined),
      loadUserQuota: () => Promise.resolve(undefined),
      mapHints: () => [],
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
      getDefaultThread: () => Promise.resolve({ ok: true, value: {
        protocolVersion: 3,
        thread: threadSummary(1),
        created: false,
      } }),
      getHints: () => Promise.resolve(undefined),
      getLangCode: () => 'en',
      getMessages: () => Promise.resolve(hydration),
      getState: state.getState,
      isConsentAccepted: () => true,
      loadAvailability: () => Promise.resolve(undefined),
      loadUserQuota: () => Promise.resolve(undefined),
      mapHints: () => [],
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

  it('owns run admission and terminal settlement without authoritative hydration', async () => {
    const state = createStateHarness({
      ...INITIAL_AGENT_V2_MESSAGES_STATE,
      thread: threadSummary(1),
    });
    const stream = createStreamHarness(state);
    const runResult = createDeferred<AgentV2RunResult | undefined>();
    const hydrate = jest.fn(() => Promise.resolve());
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread: () => Promise.resolve(undefined),
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getState: state.getState,
      hydrate,
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
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
    const hydrate = jest.fn(() => Promise.resolve());
    const controller = createAgentV2RunController({
      buildConnectionError: () => 'Connection interrupted',
      clearThread,
      dispatch: state.dispatch,
      getErrorText: () => 'Run failed',
      getState: state.getState,
      hydrate,
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
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
      getState: state.getState,
      hydrate: () => Promise.resolve(),
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun,
      stream: stream.controller,
      hideSecretPhrases: (text) => text.replace('creek aisle average', '[removed]'),
    });

    controller.sendMessage('  My words: creek aisle average. Is my wallet safe?  ');

    expect(state.getState().messages).toContainEqual(
      expect.objectContaining({ text: 'My words: [removed]. Is my wallet safe?', isOutgoing: true }),
    );
    expect(startRun).toHaveBeenLastCalledWith(expect.objectContaining({
      input: { kind: 'append', text: 'My words: [removed]. Is my wallet safe?' },
    }));
    await flushPromises();

    controller.sendMessage('Edited: creek aisle average', editedMessageId);

    expect(startRun).toHaveBeenLastCalledWith(expect.objectContaining({
      input: { kind: 'edit', targetUserMessageId: INPUT_MESSAGE_ID, text: 'Edited: [removed]' },
    }));
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
      getState: state.getState,
      hydrate: () => Promise.resolve(),
      now: () => 100,
      retryRun: () => Promise.resolve(undefined),
      resetHistory: jest.fn(),
      startRun: () => runResult.promise,
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
