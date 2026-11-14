import type { AgentThreadSummaryV2 } from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2IncompatibleHistoryMessage,
  AgentV2MutationResult,
  AgentV2OperationError,
  AgentV2StarterHints,
  AgentV2ThreadHydration,
} from '../../../api/agentV2/types';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
} from './agentV2MessagesState';
import type { AgentV2StreamController } from './agentV2StreamController';

import { selectIsAgentV2RunActive } from './agentV2MessagesState';

const MAX_LATEST_REFRESH_PAGES = 10;

type AgentV2HistoryPageOperation = {
  requestId: number;
  threadId: string;
  cursor: string;
  promise?: Promise<void>;
};

export interface AgentV2HydrationControllerDependencies {
  buildHistoryError: (error?: AgentV2OperationError) => {
    message: string;
    isRetryable: boolean;
  };
  dispatch: (action: AgentV2MessagesStateAction) => void;
  /** The id of the thread this chat shows */
  resolveThreadId: () => Promise<AgentV2MutationResult<string> | undefined>;
  /** The server no longer has the thread, for example after it was deleted elsewhere */
  onThreadNotFound?: NoneToVoidFunction;
  /** The device's copy of the thread's latest messages, which shows until the history loads */
  getCachedMessages?: (threadId: string) => Promise<Pick<AgentV2ThreadHydration, 'thread' | 'messages'> | undefined>;
  /** Picks the starter hints anew; a failed pick leaves the chat without hints */
  getStarterHints: () => Promise<AgentV2StarterHints | undefined>;
  /** Counts the times the chat has come on screen; each picks its starter hints anew */
  getHintsShowingId: () => number;
  getMessages: (
    threadId: string,
    cursor?: string,
  ) => Promise<AgentV2MutationResult<AgentV2ThreadHydration> | undefined>;
  getState: () => AgentV2MessagesState;
  isConsentAccepted: () => boolean;
  isChatVisible: () => boolean;
  loadAvailability: () => Promise<unknown>;
  loadUserQuota: () => Promise<unknown>;
  now: () => number;
  releaseStaleThreadClearOperation: (
    thread: AgentThreadSummaryV2,
    shouldMatchRevision: boolean,
  ) => void;
  reportIncompatibleMessages?: (
    threadId: string,
    messages: AgentV2IncompatibleHistoryMessage[],
  ) => void;
  stream: AgentV2StreamController;
}

export interface AgentV2HydrationController {
  cancelLatestRefresh: NoneToVoidFunction;
  dispose: NoneToVoidFunction;
  handleUpdate: (update: AgentV2ClientUpdate) => void;
  /** Resolves to `true` once this read has applied the thread's history */
  hydrate: (shouldPreserveLiveContent?: boolean, isFailureSilent?: boolean) => Promise<boolean>;
  loadOlderMessages: () => Promise<void>;
  /** The chat came on screen: its starter hints are picked for this showing, once the history has loaded */
  pickStarterHints: NoneToVoidFunction;
  refreshLatestMessages: () => Promise<void>;
  /** Reads the newest history once the chat allows it, also in a chat support has closed */
  requestLatestRefresh: NoneToVoidFunction;
  resetHistory: NoneToVoidFunction;
  /** Runs a requested refresh once the chat allows it */
  resumeLatestRefresh: NoneToVoidFunction;
}

export function createAgentV2HydrationController(
  dependencies: AgentV2HydrationControllerDependencies,
): AgentV2HydrationController {
  let nextHydrationRequestId = 0;
  let nextHistoryPageRequestId = 0;
  let nextHintsRequestId = 0;
  let latestRefreshRequestId = 0;
  let isRefreshingLatest = false;
  let requestedLatestRefreshCount = 0;
  let completedLatestRefreshCount = 0;
  let activeHistoryPageOperation: AgentV2HistoryPageOperation | undefined;
  // The pick of the chat's current showing, which every read of its history during the showing keeps, even a failed one
  let starterHintsPick: { showingId: number; promise: Promise<AgentV2StarterHints | undefined> } | undefined;
  let isDisposed = false;

  return {
    cancelLatestRefresh, dispose, handleUpdate, hydrate, loadOlderMessages, pickStarterHints,
    refreshLatestMessages, requestLatestRefresh, resetHistory, resumeLatestRefresh,
  };

  function dispose() {
    isDisposed = true;
    nextHydrationRequestId += 1;
    nextHintsRequestId += 1;
    resetHistory();
  }

  function handleUpdate(update: AgentV2ClientUpdate) {
    if (isDisposed) return;
    if (update.kind === 'runtimeReady') {
      if (dependencies.isConsentAccepted()) void hydrate(false, true);
      return;
    }
    if (
      update.kind === 'threadChanged'
      && dependencies.getState().thread?.id !== update.thread.id
    ) {
      resetHistory();
      nextHintsRequestId += 1;
    }
  }

  async function hydrate(shouldPreserveLiveContent = false, isFailureSilent = false) {
    if (isDisposed) return false;
    const { run: runAtStart, isShowingCachedHistory } = dependencies.getState();
    const requestId = ++nextHydrationRequestId;
    const shouldPreserveOpeningMessages = shouldPreserveLiveContent
      && requestId === 1 && !dependencies.getState().messages.length;
    nextHintsRequestId += 1;
    resetHistory();
    dependencies.dispatch({
      kind: 'hydrationStarted',
      shouldClearError: !isFailureSilent,
      ...(shouldPreserveOpeningMessages && { shouldPreserveOpeningMessages: true }),
    });
    const resolvedThreadId = await dependencies.resolveThreadId();
    if (!isHydrationCurrent(requestId)) return false;
    if (!resolvedThreadId?.ok) {
      finishHydrationFailure(isFailureSilent, dependencies.buildHistoryError(resolvedThreadId?.error).message);
      return false;
    }
    const threadId = resolvedThreadId.value;
    // The device's copy shows only while the history is being read; a copy shown before a failed read stays
    let isCachedHistoryStale = false;
    if (dependencies.getCachedMessages && canShowCachedHistory()) {
      void dependencies.getCachedMessages(threadId).catch(() => undefined).then((cached) => {
        if (cached && !isCachedHistoryStale && isHydrationCurrent(requestId)) showCachedHistory(cached);
      });
    }

    const hintsRequestId = nextHintsRequestId;
    takeStarterHintsPick();
    const [hydrationResult] = await Promise.all([
      dependencies.getMessages(threadId).finally(() => {
        isCachedHistoryStale = true;
      }),
      dependencies.loadAvailability().catch(() => undefined),
      dependencies.loadUserQuota().catch(() => undefined),
    ]);
    if (!isHydrationCurrent(requestId)) return false;
    // A message sent over a cached history goes on with that history, as iOS drops a read that a run outdated. The
    // history read meanwhile waits for the next read.
    if (isShowingCachedHistory && dependencies.getState().run !== runAtStart) {
      dependencies.dispatch({ kind: 'hydrationFailed' });
      return false;
    }
    if (!hydrationResult?.ok) {
      finishHydrationFailure(
        isFailureSilent,
        dependencies.buildHistoryError(hydrationResult?.error).message,
      );
      if (hydrationResult?.error.code === 'thread_not_found') {
        dependencies.dispatch({ kind: 'cachedHistoryDiscarded' });
        dependencies.onThreadNotFound?.();
      }
      return false;
    }

    const hydration = hydrationResult.value;
    if (hydration.incompatibleMessages?.length) {
      dependencies.reportIncompatibleMessages?.(hydration.thread.id, hydration.incompatibleMessages);
    }
    const entries = dependencies.stream.mapPersistedMessageEntries(hydration.messages);
    const current = dependencies.getState();
    // A chat that has not loaded its thread yet holds only the live run its updates replayed, as the reducer allows
    const shouldPreserveCurrentLiveContent = shouldPreserveLiveContent
      && (!current.thread || current.thread.id === hydration.thread.id);
    const retainedMessageIds = new Set(entries.map(({ message }) => message.id));
    if (shouldPreserveCurrentLiveContent) {
      current.messages.forEach((message) => {
        if (message.isStreaming || message.isTyping
          || (shouldPreserveOpeningMessages && (current.thread?.news || current.thread?.digest)
            && current.thread.revision > hydration.thread.revision)) {
          retainedMessageIds.add(message.id);
        }
      });
    }
    dependencies.stream.invalidateActionPresentations();
    dependencies.stream.advanceTextRevealGeneration();
    dependencies.stream.pruneMessageArtifacts(retainedMessageIds);
    dependencies.releaseStaleThreadClearOperation(hydration.thread, true);
    dependencies.dispatch({
      kind: 'hydrationSucceeded',
      thread: hydration.thread,
      entries,
      nextCursor: hydration.nextCursor,
      shouldPreserveLiveContent: shouldPreserveCurrentLiveContent,
    });
    showStarterHints(takeStarterHintsPick(), () => (
      isHydrationCurrent(requestId) && hintsRequestId === nextHintsRequestId
      && dependencies.getState().thread?.id === threadId
    ));
    dependencies.stream.loadSendActionPresentations(
      hydration.messages,
      dependencies.stream.getActionPresentationGeneration(),
    );
    return true;
  }

  function pickStarterHints() {
    // Before consent, or while the history has not loaded yet, the read of the history picks them
    if (isDisposed || !dependencies.isConsentAccepted() || !dependencies.getState().hasHydratedHistory) return;
    showStarterHints(takeStarterHintsPick(), () => true);
  }

  function takeStarterHintsPick() {
    const showingId = dependencies.getHintsShowingId();
    if (starterHintsPick?.showingId !== showingId) {
      starterHintsPick = { showingId, promise: dependencies.getStarterHints().catch(() => undefined) };
    }
    return starterHintsPick;
  }

  function showStarterHints(pick: NonNullable<typeof starterHintsPick>, isCurrent: () => boolean) {
    void pick.promise.then((starterHints) => {
      const latest = dependencies.getState();
      if (
        !starterHints
        || isDisposed
        || !isCurrent()
        || pick !== starterHintsPick
        || latest.starterHintsShowingId === pick.showingId
        || !latest.thread
        || latest.thread.news
        || latest.thread.digest
      ) return;
      dependencies.dispatch({ kind: 'hintsLoaded', starterHints, showingId: pick.showingId });
    });
  }

  function showCachedHistory(cached: Pick<AgentV2ThreadHydration, 'thread' | 'messages'>) {
    if (cached.thread.news || cached.thread.digest || !canShowCachedHistory()) return;
    const entries = dependencies.stream.mapPersistedMessageEntries(cached.messages);
    if (!entries.length) return;
    dependencies.dispatch({ kind: 'cachedHistoryApplied', thread: cached.thread, entries });
  }

  // A chat without its thread's summary has shown no history yet
  function canShowCachedHistory() {
    const current = dependencies.getState();
    return !current.thread && !current.messages.length && !selectIsAgentV2RunActive(current);
  }

  function loadOlderMessages() {
    const current = dependencies.getState();
    const threadId = current.thread?.id;
    const cursor = current.nextCursor;
    if (!threadId || !cursor || isDisposed) return Promise.resolve();
    if (activeHistoryPageOperation) {
      return activeHistoryPageOperation.promise ?? Promise.resolve();
    }

    const operation: AgentV2HistoryPageOperation = {
      requestId: ++nextHistoryPageRequestId,
      threadId,
      cursor,
    };
    activeHistoryPageOperation = operation;
    dependencies.dispatch({
      kind: 'historyPageStarted',
      requestId: operation.requestId,
      threadId,
      cursor,
    });
    operation.promise = loadHistoryPage(operation);
    return operation.promise;
  }

  function resetHistory() {
    cancelLatestRefresh();
    completedLatestRefreshCount = requestedLatestRefreshCount;
    nextHistoryPageRequestId += 1;
    activeHistoryPageOperation = undefined;
  }

  function cancelLatestRefresh() {
    latestRefreshRequestId += 1;
    isRefreshingLatest = false;
  }

  function requestLatestRefresh() {
    requestedLatestRefreshCount += 1;
    resumeLatestRefresh();
  }

  function resumeLatestRefresh() {
    if (requestedLatestRefreshCount > completedLatestRefreshCount) void refreshLatestMessages();
  }

  async function refreshLatestMessages() {
    const current = dependencies.getState();
    if (isRefreshingLatest || !canRefreshLatest(current)) return;
    const threadId = current.thread!.id;
    const requestId = ++latestRefreshRequestId;
    const requestedCount = requestedLatestRefreshCount;
    isRefreshingLatest = true;
    let isMerged = false;
    try {
      const pages = await loadLatestPages(threadId, requestId);
      const latest = dependencies.getState();
      const newestPage = pages?.[0];
      if (!newestPage || requestId !== latestRefreshRequestId || !canRefreshLatest(latest)
        || latest.thread?.id !== threadId || newestPage.thread.id !== threadId
        || newestPage.thread.revision < latest.thread.revision) return;

      const knownSourceIds = new Set(latest.messages.map(({ id }) => latest.sourceIdByMessageId[id]));
      const pageMessages = [...pages].reverse().flatMap(({ messages }) => messages);
      const messages = pageMessages.filter(({ id }) => !knownSourceIds.has(id));
      dependencies.dispatch({
        kind: 'latestMessagesReceived',
        thread: newestPage.thread,
        entries: dependencies.stream.mapPersistedMessageEntries(messages),
        sourceIds: pageMessages.map(({ id }) => id),
      });
      completedLatestRefreshCount = Math.max(completedLatestRefreshCount, requestedCount);
      isMerged = true;
      dependencies.stream.loadSendActionPresentations(
        messages, dependencies.stream.getActionPresentationGeneration(),
      );
    } catch {
      // A refresh leaves the visible conversation in place and tries again at the next poll
    } finally {
      if (requestId === latestRefreshRequestId) {
        isRefreshingLatest = false;
        // A refresh requested while this one ran gets its own attempt, while a failed request waits for the next change
        if (isMerged || requestedLatestRefreshCount > requestedCount) resumeLatestRefresh();
      }
    }
  }

  // Reads back from the newest page until it reaches a message the chat already shows, newest page first
  async function loadLatestPages(threadId: string, requestId: number) {
    const pages: AgentV2ThreadHydration[] = [];
    let cursor: string | undefined;
    do {
      const result = await dependencies.getMessages(threadId, cursor);
      if (!result?.ok) return undefined;
      pages.push(result.value);
      if (isDisposed || requestId !== latestRefreshRequestId) return pages;

      const latest = dependencies.getState();
      const knownSourceIds = new Set(latest.messages.map(({ id }) => latest.sourceIdByMessageId[id]));
      if (result.value.messages.some(({ id }) => knownSourceIds.has(id))) return pages;
      cursor = result.value.nextCursor;
    } while (cursor && pages.length < MAX_LATEST_REFRESH_PAGES);
    return pages;
  }

  function canRefreshLatest(state: AgentV2MessagesState) {
    return !isDisposed && dependencies.isChatVisible() && state.thread && state.hasHydratedHistory
      && !state.isLoading && !state.isLoadingOlderMessages && !selectIsAgentV2RunActive(state)
      && state.threadMutation.phase === 'idle';
  }

  async function loadHistoryPage(operation: AgentV2HistoryPageOperation) {
    try {
      const result = await dependencies.getMessages(operation.threadId, operation.cursor);
      if (!isHistoryPageOperationCurrent(operation)) return;
      if (!result?.ok) {
        dependencies.dispatch({
          kind: 'historyPageFailed',
          requestId: operation.requestId,
          threadId: operation.threadId,
          cursor: operation.cursor,
        });
        return;
      }

      if (result.value.incompatibleMessages?.length) {
        dependencies.reportIncompatibleMessages?.(
          result.value.thread.id,
          result.value.incompatibleMessages,
        );
      }
      const entries = dependencies.stream.mapPersistedMessageEntries(result.value.messages);
      const previousSupport = dependencies.getState().thread?.support;
      dependencies.dispatch({
        kind: 'historyPageSucceeded',
        requestId: operation.requestId,
        threadId: operation.threadId,
        cursor: operation.cursor,
        entries,
        support: result.value.thread.support,
        threadRevision: result.value.thread.revision,
        nextCursor: result.value.nextCursor,
      });
      dependencies.stream.loadSendActionPresentations(
        result.value.messages,
        dependencies.stream.getActionPresentationGeneration(),
      );
      const support = dependencies.getState().thread?.support;
      // The newest page carries the operator reply and the closing event an older page's summary announces
      if (support?.state !== previousSupport?.state
        || support?.lastOperatorMessageAt !== previousSupport?.lastOperatorMessageAt) {
        requestLatestRefresh();
      }
    } catch {
      if (!isHistoryPageOperationCurrent(operation)) return;
      dependencies.dispatch({
        kind: 'historyPageFailed',
        requestId: operation.requestId,
        threadId: operation.threadId,
        cursor: operation.cursor,
      });
    } finally {
      if (isSameHistoryPageOperation(activeHistoryPageOperation, operation)) {
        activeHistoryPageOperation = undefined;
      }
    }
  }

  function isHydrationCurrent(requestId: number) {
    return !isDisposed && requestId === nextHydrationRequestId;
  }

  function isHistoryPageOperationCurrent(operation: AgentV2HistoryPageOperation) {
    const current = dependencies.getState();
    return !isDisposed
      && isSameHistoryPageOperation(activeHistoryPageOperation, operation)
      && current.thread?.id === operation.threadId
      && current.nextCursor === operation.cursor;
  }

  function finishHydrationFailure(isSilent: boolean, message: string) {
    // The device's copy of the history offers nothing to do, so its failure always offers Retry
    if (!isSilent || dependencies.getState().isHistoryCached) {
      dependencies.dispatch({
        kind: 'errorSet',
        error: { text: message, timestamp: dependencies.now(), isHistoryFailure: true },
      });
      return;
    }
    dependencies.dispatch({ kind: 'hydrationFailed' });
  }
}

function isSameHistoryPageOperation(
  first: AgentV2HistoryPageOperation | undefined,
  second: AgentV2HistoryPageOperation,
) {
  return first?.requestId === second.requestId
    && first.threadId === second.threadId
    && first.cursor === second.cursor;
}
