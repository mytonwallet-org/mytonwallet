import type {
  AgentHintsResponseV2,
  AgentThreadSummaryV2,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2IncompatibleHistoryMessage,
  AgentV2MutationResult,
  AgentV2OperationError,
  AgentV2ThreadHydration,
} from '../../../api/agentV2/types';
import type { AgentHint } from '../../../global/types';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
} from './agentV2MessagesState';
import type { AgentV2StreamController } from './agentV2StreamController';

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
  getHints: (langCode: string) => Promise<AgentHintsResponseV2 | undefined>;
  getLangCode: () => AgentHint['langCode'];
  getMessages: (
    threadId: string,
    cursor?: string,
  ) => Promise<AgentV2MutationResult<AgentV2ThreadHydration> | undefined>;
  getState: () => AgentV2MessagesState;
  isConsentAccepted: () => boolean;
  loadAvailability: () => Promise<unknown>;
  loadUserQuota: () => Promise<unknown>;
  mapHints: (response: AgentHintsResponseV2, langCode: AgentHint['langCode']) => AgentHint[];
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
  dispose: NoneToVoidFunction;
  handleUpdate: (update: AgentV2ClientUpdate) => void;
  hydrate: (shouldPreserveLiveContent?: boolean, isFailureSilent?: boolean) => Promise<void>;
  loadOlderMessages: () => Promise<void>;
  refreshHints: () => Promise<void>;
  resetHistory: NoneToVoidFunction;
}

export function createAgentV2HydrationController(
  dependencies: AgentV2HydrationControllerDependencies,
): AgentV2HydrationController {
  let nextHydrationRequestId = 0;
  let nextHistoryPageRequestId = 0;
  let nextHintsRequestId = 0;
  let pendingHintsRequest: { requestId: number; langCode: AgentHint['langCode'] } | undefined;
  let activeHistoryPageOperation: AgentV2HistoryPageOperation | undefined;
  let isDisposed = false;

  return { dispose, handleUpdate, hydrate, loadOlderMessages, refreshHints, resetHistory };

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
    if (isDisposed) return;
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
    if (!isHydrationCurrent(requestId)) return;
    if (!resolvedThreadId?.ok) {
      finishHydrationFailure(isFailureSilent, dependencies.buildHistoryError(resolvedThreadId?.error).message);
      return;
    }
    const threadId = resolvedThreadId.value;

    const langCode = dependencies.getLangCode();
    const hintsRequestId = nextHintsRequestId;
    pendingHintsRequest = { requestId: hintsRequestId, langCode };
    const hintsResponse = dependencies.getHints(langCode).catch(() => undefined);
    const [hydrationResult] = await Promise.all([
      dependencies.getMessages(threadId),
      dependencies.loadAvailability().catch(() => undefined),
      dependencies.loadUserQuota().catch(() => undefined),
    ]);
    if (!isHydrationCurrent(requestId)) return;
    if (!hydrationResult?.ok) {
      finishHintsRequest(hintsRequestId);
      finishHydrationFailure(
        isFailureSilent,
        dependencies.buildHistoryError(hydrationResult?.error).message,
      );
      if (hydrationResult?.error.code === 'thread_not_found') dependencies.onThreadNotFound?.();
      return;
    }

    const hydration = hydrationResult.value;
    if (hydration.incompatibleMessages?.length) {
      dependencies.reportIncompatibleMessages?.(hydration.thread.id, hydration.incompatibleMessages);
    }
    const entries = hydration.messages.map(dependencies.stream.mapPersistedMessageEntry);
    const current = dependencies.getState();
    // A chat that has not loaded its thread yet holds only the live run its updates replayed, as the reducer allows
    const shouldPreserveCurrentLiveContent = shouldPreserveLiveContent
      && (!current.thread || current.thread.id === hydration.thread.id);
    const retainedMessageIds = new Set(entries.map(({ message }) => message.id));
    if (shouldPreserveCurrentLiveContent) {
      current.messages.forEach((message) => {
        if (message.isStreaming || message.isTyping
          || (shouldPreserveOpeningMessages && current.thread?.news
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
    void hintsResponse.then((response) => {
      const latest = dependencies.getState();
      if (
        !isHydrationCurrent(requestId)
        || hintsRequestId !== nextHintsRequestId
        || dependencies.getLangCode() !== langCode
        || latest.thread?.id !== threadId
        || latest.thread.news
      ) return;
      if (!response) {
        finishHintsRequest(hintsRequestId);
        void refreshHints();
        return;
      }
      dependencies.dispatch({
        kind: 'hintsLoaded',
        hints: {
          hints: dependencies.mapHints(response, langCode),
          response,
          langCode,
        },
      });
    }).finally(() => finishHintsRequest(hintsRequestId));
    dependencies.stream.loadSendActionPresentations(
      hydration.messages,
      dependencies.stream.getActionPresentationGeneration(),
    );
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

  async function refreshHints() {
    const current = dependencies.getState();
    const threadId = current.thread?.id;
    const langCode = dependencies.getLangCode();
    if (
      isDisposed
      || !threadId
      || current.thread?.news
      || current.isLoading
      || current.isConsentAccepted !== true
      || current.hintsLangCode === langCode
      || (pendingHintsRequest?.requestId === nextHintsRequestId
        && pendingHintsRequest.langCode === langCode)
    ) return;

    const requestId = ++nextHintsRequestId;
    pendingHintsRequest = { requestId, langCode };
    const response = await dependencies.getHints(langCode).finally(() => finishHintsRequest(requestId));
    const latest = dependencies.getState();
    if (
      isDisposed
      || requestId !== nextHintsRequestId
      || dependencies.getLangCode() !== langCode
      || latest.thread?.id !== threadId
      || latest.thread.news
      || !response
    ) return;
    dependencies.dispatch({
      kind: 'hintsLoaded',
      hints: {
        hints: dependencies.mapHints(response, langCode),
        response,
        langCode,
      },
    });
  }

  function finishHintsRequest(requestId: number) {
    if (pendingHintsRequest?.requestId === requestId) pendingHintsRequest = undefined;
  }

  function resetHistory() {
    nextHistoryPageRequestId += 1;
    activeHistoryPageOperation = undefined;
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
      const entries = result.value.messages.map(dependencies.stream.mapPersistedMessageEntry);
      dependencies.dispatch({
        kind: 'historyPageSucceeded',
        requestId: operation.requestId,
        threadId: operation.threadId,
        cursor: operation.cursor,
        entries,
        nextCursor: result.value.nextCursor,
      });
      dependencies.stream.loadSendActionPresentations(
        result.value.messages,
        dependencies.stream.getActionPresentationGeneration(),
      );
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
    if (!isSilent) {
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
