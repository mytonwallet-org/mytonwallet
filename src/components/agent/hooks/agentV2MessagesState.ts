import type {
  AgentHintsResponseV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentRunActivityEvent,
  AgentThreadSummaryV2,
  AgentUserQuotaV2,
  AgentV2ErrorCode,
  AgentV2LiveAction,
  AgentV2MessageError,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2AvailabilityState,
  AgentV2RateLimitState,
} from '../../../api/agentV2/types';
import type { AgentHint, AgentMessage } from '../../../global/types';
import type { AgentRunActivityType } from '../AgentRunActivity';

import memoize from '../../../util/memoize';

type AgentV2RunWithOperation = {
  operationId?: number;
  operationKind?: AgentV2RunOperationKind;
};

type AgentV2RunOperationKind = 'command' | 'admissionRetry';

export type AgentV2RunState =
  | { phase: 'idle' }
  | {
    phase: 'admitting';
    operationId: number;
    operationKind: AgentV2RunOperationKind;
    activity?: AgentRunActivityType;
  }
  | AgentV2RunWithOperation & {
    phase: 'streaming';
    clientRunId: string;
    activity?: AgentRunActivityType;
  }
  | AgentV2RunWithOperation & {
    phase: 'terminal';
    clientRunId: string;
  };

type AgentV2ThreadMutationState =
  | { phase: 'idle' }
  | {
    phase: 'clearing';
    operationId: number;
    threadId: string;
    threadRevision: number;
  };

interface AgentV2HistoryPageRequest {
  requestId: number;
  threadId: string;
  cursor: string;
}

export interface AgentV2NormalizedMessageEntry {
  message: AgentMessage;
  sourceId: string;
}

export interface AgentV2MessagesState {
  isConsentAccepted?: boolean;
  thread?: AgentThreadSummaryV2;
  messages: AgentMessage[];
  hints?: AgentHint[];
  hintsResponse?: AgentHintsResponseV2;
  hintsLangCode?: AgentHint['langCode'];
  error?: {
    text: string;
    timestamp: number;
    cause?: AgentV2MessageError;
  };
  admissionFailure?: {
    error: AgentV2MessageError;
    timestamp: number;
    clientRunId?: string;
    optimisticMessageId?: number;
    retryMessageId?: number;
  };
  availability: AgentV2AvailabilityState;
  userQuota?: AgentUserQuotaV2;
  quotaRetry?: {
    clientRunId?: string;
    resetAt?: number;
    optimisticMessageId?: number;
  };
  userRateLimit?: AgentV2RateLimitState & { optimisticMessageId?: number };
  isLoading: boolean;
  nextCursor?: string;
  isLoadingOlderMessages: boolean;
  historyPageRequest?: AgentV2HistoryPageRequest;
  sourceIdByMessageId: Record<number, string>;
  run: AgentV2RunState;
  threadMutation: AgentV2ThreadMutationState;
}

interface HydrationHints {
  hints: AgentHint[];
  response: AgentHintsResponseV2;
  langCode: AgentHint['langCode'];
}

export type AgentV2MessagesStateAction =
  | { kind: 'consentLoadingStarted' }
  | { kind: 'consentResolved'; isAccepted: boolean }
  | { kind: 'consentAccepted' }
  | { kind: 'hydrationStarted'; shouldClearError: boolean }
  | {
    kind: 'hydrationSucceeded';
    thread: AgentThreadSummaryV2;
    entries: AgentV2NormalizedMessageEntry[];
    nextCursor?: string;
    shouldPreserveLiveContent: boolean;
    shouldClearError: boolean;
    hints?: HydrationHints;
  }
  | { kind: 'hydrationFailed' }
  | { kind: 'hintsLoaded'; hints: HydrationHints }
  | { kind: 'optimisticMessageAdded'; message: AgentMessage }
  | { kind: 'messageSourceBound'; messageId: number; sourceId: string }
  | { kind: 'messageSourceReserved'; messageId: number; sourceId: string }
  | { kind: 'messageSourcesPruned'; retainedMessageIds: Set<number> }
  | { kind: 'messageSourcesReset' }
  | { kind: 'threadMutationReconciled'; thread: AgentThreadSummaryV2; shouldMatchRevision: boolean }
  | { kind: 'historyPageStarted'; requestId: number; threadId: string; cursor: string }
  | {
    kind: 'historyPageSucceeded';
    requestId: number;
    threadId: string;
    cursor: string;
    entries: AgentV2NormalizedMessageEntry[];
    nextCursor?: string;
  }
  | {
    kind: 'historyPageFailed';
    requestId: number;
    threadId: string;
    cursor: string;
  }
  | { kind: 'editRunAdmitted'; targetMessageId: number; text: string }
  | { kind: 'regenerateRunAdmitted'; targetMessageId: number }
  | {
    kind: 'threadClearStarted';
    operationId: number;
    threadId: string;
    threadRevision: number;
  }
  | { kind: 'threadClearSucceeded'; operationId: number; thread: AgentThreadSummaryV2 }
  | {
    kind: 'threadClearFailed';
    operationId: number;
    error: NonNullable<AgentV2MessagesState['error']>;
  }
  | { kind: 'errorSet'; error: NonNullable<AgentV2MessagesState['error']> }
  | {
    kind: 'runConnectionFailed';
    operationId: number;
    error: NonNullable<AgentV2MessagesState['error']>;
  }
  | {
    kind: 'runRequested';
    operationId: number;
    operationKind: AgentV2RunOperationKind;
  }
  | {
    kind: 'runStarted';
    clientRunId: string;
    threadId: string;
    threadRevision: number;
  }
  | {
    kind: 'toolActivityChanged';
    clientRunId: string;
    activity: AgentRunActivityType;
  }
  | { kind: 'runActivityChanged'; clientRunId: string; event: AgentRunActivityEvent }
  | { kind: 'messageStarted'; clientRunId: string; message: AgentMessage }
  | { kind: 'textDeltasFlushed'; deltas: Array<[messageId: number, delta: string]> }
  | { kind: 'messageContentEnded'; messageId: number }
  | { kind: 'followupsAvailable'; messageId: number; items: AgentPublicFollowUpV2[] }
  | {
    kind: 'actionAvailable';
    messageId: number;
    action: AgentV2LiveAction | AgentPersistedActionV2;
  }
  | { kind: 'answerTablesChanged'; messageId: number; tables: AgentMessage['tables'];
    tableReferences: AgentMessage['tableReferences']; }
    | { kind: 'answerLinkAdded'; messageId: number; link: NonNullable<AgentMessage['links']>[number] }
    | { kind: 'semanticContentAvailable'; messageId: number; content: AgentMessage['semanticContent'] }
    | {
      kind: 'messageCompleted';
      clientRunId: string;
      messageId: number;
      finishReason: string;
    }
    | { kind: 'threadChanged'; thread: AgentThreadSummaryV2 }
    | {
      kind: 'runFailed';
      clientRunId: string;
      code: AgentV2ErrorCode;
      retryable: boolean;
      messageId?: number;
      resetAt?: number;
      resetAtIso?: string;
      hasRunId: boolean;
      optimisticMessageId?: number;
      retryMessageId?: number;
      errorText: string;
      timestamp: number;
    }
    | { kind: 'runCancelled'; clientRunId: string }
    | { kind: 'runSettled'; operationId: number }
    | { kind: 'admissionRetryConsumed'; operationId: number }
    | { kind: 'composerStatusExpired' }
    | { kind: 'availabilityChanged'; availability: AgentV2AvailabilityState }
    | { kind: 'userQuotaChanged'; quota?: AgentUserQuotaV2 }
    | { kind: 'walletAuthorityChanged'; threadId?: string }
    | { kind: 'walletContextChanged' }
    | {
      kind: 'actionPresentationChanged';
      messageId: number;
      actionId: string;
      presentation: AgentV2ActionPresentation;
    };

const ANALYZING_REQUEST_ACTIVITY: AgentRunActivityType = { kind: 'analyzingRequest' };

export const INITIAL_AGENT_V2_MESSAGES_STATE: AgentV2MessagesState = {
  messages: [],
  isLoading: false,
  isLoadingOlderMessages: false,
  sourceIdByMessageId: {},
  run: { phase: 'idle' },
  threadMutation: { phase: 'idle' },
  availability: { state: 'available' },
};

export function reduceAgentV2MessagesState(
  state: AgentV2MessagesState,
  action: AgentV2MessagesStateAction,
): AgentV2MessagesState {
  switch (action.kind) {
    case 'consentLoadingStarted':
      return { ...state, isLoading: true };
    case 'consentResolved':
      return {
        ...state,
        isConsentAccepted: action.isAccepted,
        isLoading: action.isAccepted,
      };
    case 'consentAccepted':
      return {
        ...state,
        isConsentAccepted: true,
        isLoading: true,
        error: undefined,
      };
    case 'hydrationStarted':
      return {
        ...state,
        isLoading: true,
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
        ...(action.shouldClearError ? { error: undefined } : {}),
      };
    case 'hydrationSucceeded': {
      const entries = normalizeHydrationEntries(action);
      const messages = entries.map(({ message }) => message);
      const shouldPreserveLiveContent = action.shouldPreserveLiveContent
        && (!state.thread || state.thread.id === action.thread.id);
      const hydratedMessages = shouldPreserveLiveContent
        ? reconcileHydratedMessages(state.messages, messages)
        : messages;
      return {
        ...state,
        thread: action.thread,
        messages: hydratedMessages,
        sourceIdByMessageId: buildSourceIdIndex(
          entries,
          hydratedMessages,
          state.sourceIdByMessageId,
          shouldPreserveLiveContent,
        ),
        nextCursor: action.nextCursor,
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
        hints: action.hints?.hints ?? state.hints,
        hintsResponse: action.hints?.response ?? state.hintsResponse,
        hintsLangCode: action.hints?.langCode ?? state.hintsLangCode,
        ...(action.shouldClearError ? { error: undefined } : {}),
        isLoading: false,
        threadMutation: reconcileThreadMutation(state.threadMutation, action.thread, true),
      };
    }
    case 'hydrationFailed':
      return {
        ...state,
        isLoading: false,
      };
    case 'hintsLoaded':
      return {
        ...state,
        hints: action.hints.hints,
        hintsResponse: action.hints.response,
        hintsLangCode: action.hints.langCode,
      };
    case 'optimisticMessageAdded':
      return { ...state, messages: [...state.messages, action.message] };
    case 'messageSourceBound':
      return state.messages.some(({ id }) => id === action.messageId)
        ? bindMessageSource(state, action.messageId, action.sourceId)
        : state;
    case 'messageSourceReserved':
      return bindMessageSource(state, action.messageId, action.sourceId);
    case 'messageSourcesPruned':
      return {
        ...state,
        sourceIdByMessageId: Object.fromEntries(Object.entries(state.sourceIdByMessageId)
          .filter(([id]) => action.retainedMessageIds.has(Number(id)))),
      };
    case 'messageSourcesReset':
      return { ...state, sourceIdByMessageId: {} };
    case 'threadMutationReconciled':
      return {
        ...state,
        threadMutation: reconcileThreadMutation(state.threadMutation, action.thread, action.shouldMatchRevision),
      };
    case 'historyPageStarted':
      if (!doesHistoryPageTargetCurrentCursor(state, action)) return state;
      return {
        ...state,
        isLoadingOlderMessages: true,
        historyPageRequest: selectHistoryPageRequest(action),
      };
    case 'historyPageSucceeded':
      if (!isHistoryPageRequestCurrent(state, action)) return state;
      return prependHistoryPage(state, action.entries, action.nextCursor);
    case 'historyPageFailed':
      if (!isHistoryPageRequestCurrent(state, action)) return state;
      return {
        ...state,
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
      };
    case 'editRunAdmitted':
      return truncateMessagesForEdit(state, action.targetMessageId, action.text);
    case 'regenerateRunAdmitted':
      return truncateMessagesForRegeneration(state, action.targetMessageId);
    case 'threadClearStarted': {
      const clearing: AgentV2MessagesState = {
        ...state,
        messages: [],
        sourceIdByMessageId: {},
        nextCursor: undefined,
        admissionFailure: undefined,
        error: undefined,
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
        threadMutation: {
          phase: 'clearing',
          operationId: action.operationId,
          threadId: action.threadId,
          threadRevision: action.threadRevision,
        },
      };
      // A cancelled answer's operation keeps input blocked until it settles, without showing its activity
      return getRunOperationId(state.run) === undefined
        ? { ...clearing, run: { phase: 'idle' } }
        : clearRunActivity(clearing);
    }
    case 'threadClearSucceeded':
      if (!selectIsAgentV2ThreadMutationCurrent(state, action.operationId)) return state;
      return selectDoesAgentV2ThreadMutationMatch(state, action.thread)
        ? {
          ...state,
          thread: action.thread,
          messages: [],
          sourceIdByMessageId: {},
          nextCursor: undefined,
          isLoadingOlderMessages: false,
          historyPageRequest: undefined,
          admissionFailure: undefined,
          error: undefined,
          threadMutation: { phase: 'idle' },
        }
        : { ...state, threadMutation: { phase: 'idle' } };
    case 'threadClearFailed':
      if (!selectIsAgentV2ThreadMutationCurrent(state, action.operationId)) return state;
      return selectDoesAgentV2ThreadMutationMatch(state)
        ? {
          ...state,
          error: action.error,
          threadMutation: { phase: 'idle' },
        }
        : { ...state, threadMutation: { phase: 'idle' } };
    case 'errorSet':
      return {
        ...state,
        error: action.error,
        isLoading: false,
        run: { phase: 'idle' },
      };
    case 'runConnectionFailed':
      return selectIsAgentV2RunOperationCurrent(state, action.operationId)
        ? {
          ...state,
          error: action.error,
          isLoading: false,
          run: { phase: 'idle' },
        }
        : state;
    case 'runRequested':
      return {
        ...state,
        messages: action.operationKind === 'command' && selectRetryOptimisticMessageId(state) !== undefined
          ? state.messages.filter(({ id }) => id !== selectRetryOptimisticMessageId(state))
          : state.messages,
        run: {
          phase: 'admitting',
          operationId: action.operationId,
          operationKind: action.operationKind,
          activity: ANALYZING_REQUEST_ACTIVITY,
        },
        admissionFailure: undefined,
        error: undefined,
      };
    case 'runStarted':
      return {
        ...state,
        thread: state.thread?.id === action.threadId
          ? { ...state.thread, revision: action.threadRevision }
          : state.thread,
        ...(state.run.phase !== 'admitting' || state.run.operationKind !== 'admissionRetry'
          ? { userRateLimit: undefined, quotaRetry: undefined }
          : {}),
        run: {
          phase: 'streaming',
          ...getRunOperationBinding(state.run),
          clientRunId: action.clientRunId,
          activity: selectAgentV2Activity(state) ?? ANALYZING_REQUEST_ACTIVITY,
        },
      };
    case 'toolActivityChanged':
      return {
        ...state,
        run: updateRunActivityCurrent(state.run, action.clientRunId, action.activity),
      };
    case 'runActivityChanged':
      return {
        ...state,
        run: applyServerRunActivity(state.run, action.clientRunId, action.event),
      };
    case 'messageStarted':
      return {
        ...state,
        messages: upsertMessage(state.messages, action.message),
        run: updateRunActivityCurrent(state.run, action.clientRunId, { kind: 'preparingResponse' }),
      };
    case 'textDeltasFlushed':
      return applyTextDeltas(state, action.deltas);
    case 'messageContentEnded':
      return updateMessage(state, action.messageId, (message) => ({
        ...message,
        isTyping: undefined,
        isStreaming: undefined,
        shouldCommitMarkdownTail: true,
      }));
    case 'followupsAvailable':
      return updateMessage(state, action.messageId, (message) => ({
        ...message,
        followups: action.items,
      }));
    case 'actionAvailable':
      return updateMessage(state, action.messageId, (message) => ({
        ...message,
        actions: [
          ...(message.actions ?? []).filter(({ id }) => id !== action.action.id),
          action.action,
        ],
        ...(action.action.kind === 'send' ? {
          actionPresentations: removeActionPresentation(message.actionPresentations, action.action.id),
        } : {}),
      }));
    case 'answerTablesChanged':
      return updateMessage(state, action.messageId, (message) => ({
        ...message, tables: action.tables, tableReferences: action.tableReferences,
      }));
    case 'answerLinkAdded':
      return updateMessage(state, action.messageId, (message) => ({
        ...message, links: [...(message.links ?? []), action.link],
      }));
    case 'semanticContentAvailable':
      return clearRunActivity(updateMessage(state, action.messageId, (message) => ({
        ...message,
        semanticContent: action.content,
      })));
    case 'messageCompleted':
      return completeMessage(state, action);
    case 'threadChanged': {
      const isReplacement = state.thread?.id !== action.thread.id;
      return {
        ...state,
        thread: action.thread,
        ...(isReplacement ? {
          nextCursor: undefined,
          isLoadingOlderMessages: false,
          historyPageRequest: undefined,
          sourceIdByMessageId: {},
          admissionFailure: undefined,
        } : {}),
        threadMutation: reconcileThreadMutation(state.threadMutation, action.thread, false),
      };
    }
    case 'runFailed':
      return failRun(state, action);
    case 'runCancelled':
      return cancelRun(state, action.clientRunId);
    case 'runSettled':
      return getRunOperationId(state.run) === action.operationId
        ? { ...state, run: { phase: 'idle' } }
        : state;
    case 'admissionRetryConsumed':
      return selectIsAgentV2RunOperationCurrent(state, action.operationId)
        ? {
          ...state,
          admissionFailure: undefined,
          quotaRetry: undefined,
          userRateLimit: undefined,
        }
        : state;
    case 'composerStatusExpired':
      return { ...state };
    case 'availabilityChanged':
      return { ...state, availability: action.availability };
    case 'userQuotaChanged':
      return { ...state, userQuota: action.quota };
    case 'walletAuthorityChanged':
    case 'walletContextChanged':
      return {
        ...state,
        ...(action.kind === 'walletAuthorityChanged' ? { admissionFailure: undefined } : {}),
        messages: action.kind === 'walletContextChanged'
          || !action.threadId
          || state.thread?.id === action.threadId
          ? state.messages.map(({ actionPresentations, ...message }) => message)
          : state.messages,
      };
    case 'actionPresentationChanged':
      return updateMessage(state, action.messageId, (message) => {
        if (!message.actions?.some(({ id }) => id === action.actionId)) return message;
        return {
          ...message,
          actionPresentations: {
            ...message.actionPresentations,
            [action.actionId]: action.presentation,
          },
        };
      });
    default:
      return assertUnreachable(action);
  }
}

export function selectAgentV2Activity(state: AgentV2MessagesState) {
  return state.run.phase === 'admitting' || state.run.phase === 'streaming'
    ? state.run.activity
    : undefined;
}

export function selectIsAgentV2RunActive(state: AgentV2MessagesState) {
  return state.run.phase !== 'idle';
}

function selectRetryOptimisticMessageId(state: AgentV2MessagesState) {
  return state.admissionFailure?.optimisticMessageId
    ?? state.quotaRetry?.optimisticMessageId
    ?? state.userRateLimit?.optimisticMessageId;
}

function selectIsAgentV2RunOperationCurrent(state: AgentV2MessagesState, operationId: number) {
  return getRunOperationId(state.run) === operationId;
}

export function selectIsAgentV2InputDisabled(state: AgentV2MessagesState, isLimitBlocking: boolean) {
  return state.isLoading
    || selectIsAgentV2RunActive(state)
    || state.threadMutation.phase === 'clearing'
    || isLimitBlocking;
}

function selectIsAgentV2ThreadMutationCurrent(state: AgentV2MessagesState, operationId: number) {
  return state.threadMutation.phase === 'clearing'
    && state.threadMutation.operationId === operationId;
}

function selectDoesAgentV2ThreadMutationMatch(
  state: AgentV2MessagesState,
  succeededThread?: AgentThreadSummaryV2,
) {
  if (state.threadMutation.phase !== 'clearing' || !state.thread) return false;
  return (
    state.thread.id === state.threadMutation.threadId
    && state.thread.revision === state.threadMutation.threadRevision
  ) || (
    succeededThread !== undefined
    && succeededThread.id === state.threadMutation.threadId
    && state.thread.id === succeededThread.id
    && state.thread.revision === succeededThread.revision
  );
}

function reconcileThreadMutation(
  mutation: AgentV2ThreadMutationState,
  thread: AgentThreadSummaryV2,
  shouldMatchRevision: boolean,
): AgentV2ThreadMutationState {
  if (mutation.phase === 'idle') return mutation;
  const isMatching = mutation.threadId === thread.id
    && (!shouldMatchRevision || mutation.threadRevision === thread.revision);
  return isMatching ? mutation : { phase: 'idle' };
}

function doesHistoryPageTargetCurrentCursor(
  state: AgentV2MessagesState,
  request: AgentV2HistoryPageRequest,
) {
  return state.thread?.id === request.threadId && state.nextCursor === request.cursor;
}

function isHistoryPageRequestCurrent(
  state: AgentV2MessagesState,
  request: AgentV2HistoryPageRequest,
) {
  const current = state.historyPageRequest;
  return state.isLoadingOlderMessages
    && current?.requestId === request.requestId
    && current.threadId === request.threadId
    && current.cursor === request.cursor
    && doesHistoryPageTargetCurrentCursor(state, request);
}

function selectHistoryPageRequest(request: AgentV2HistoryPageRequest): AgentV2HistoryPageRequest {
  return {
    requestId: request.requestId,
    threadId: request.threadId,
    cursor: request.cursor,
  };
}

function bindMessageSource(state: AgentV2MessagesState, messageId: number, sourceId: string) {
  const sourceIdByMessageId = Object.fromEntries(
    Object.entries(state.sourceIdByMessageId).filter(([currentMessageId, currentSourceId]) => (
      Number(currentMessageId) !== messageId && currentSourceId !== sourceId
    )),
  );
  sourceIdByMessageId[messageId] = sourceId;
  return { ...state, sourceIdByMessageId };
}

function prependHistoryPage(
  state: AgentV2MessagesState,
  entries: AgentV2NormalizedMessageEntry[],
  nextCursor: string | undefined,
): AgentV2MessagesState {
  const existingSourceIds = new Set(state.messages.map(({ id }) => state.sourceIdByMessageId[id]));
  const existingMessageIds = new Set(state.messages.map(({ id }) => id));
  const pageSourceIds = new Set<string>();
  const pageMessageIds = new Set<number>();
  const prependedEntries = entries.filter(({ message, sourceId }) => {
    if (
      existingSourceIds.has(sourceId)
      || existingMessageIds.has(message.id)
      || pageSourceIds.has(sourceId)
      || pageMessageIds.has(message.id)
    ) return false;

    pageSourceIds.add(sourceId);
    pageMessageIds.add(message.id);
    return true;
  });
  const sourceIdByMessageId = { ...state.sourceIdByMessageId };
  prependedEntries.forEach(({ message, sourceId }) => {
    sourceIdByMessageId[message.id] = sourceId;
  });

  return {
    ...state,
    messages: [...prependedEntries.map(({ message }) => message), ...state.messages],
    sourceIdByMessageId,
    nextCursor,
    isLoadingOlderMessages: false,
    historyPageRequest: undefined,
  };
}

function truncateMessagesForEdit(
  state: AgentV2MessagesState,
  targetMessageId: number,
  text: string,
): AgentV2MessagesState {
  const targetIndex = state.messages.findIndex(({ id, isOutgoing }) => id === targetMessageId && isOutgoing);
  if (targetIndex < 0) return state;

  const target = state.messages[targetIndex];
  const messages = [
    ...state.messages.slice(0, targetIndex),
    {
      id: target.id,
      text,
      isOutgoing: true,
      timestamp: target.timestamp,
    },
  ];
  return finishAdmittedTruncation(state, messages, targetMessageId);
}

function truncateMessagesForRegeneration(
  state: AgentV2MessagesState,
  targetMessageId: number,
): AgentV2MessagesState {
  const targetIndex = state.messages.findIndex(({ id, isOutgoing }) => id === targetMessageId && !isOutgoing);
  if (targetIndex < 0) return state;
  return finishAdmittedTruncation(state, state.messages.slice(0, targetIndex));
}

function finishAdmittedTruncation(
  state: AgentV2MessagesState,
  messages: AgentMessage[],
  replacedMessageId?: number,
): AgentV2MessagesState {
  const retainedMessageIds = new Set(messages.map(({ id }) => id));
  const sourceIdByMessageId = Object.fromEntries(
    Object.entries(state.sourceIdByMessageId).filter(([messageId]) => (
      Number(messageId) !== replacedMessageId && retainedMessageIds.has(Number(messageId))
    )),
  );
  return {
    ...state,
    messages,
    sourceIdByMessageId,
    isLoadingOlderMessages: false,
    historyPageRequest: undefined,
  };
}

function applyTextDeltas(
  state: AgentV2MessagesState,
  deltas: Array<[messageId: number, delta: string]>,
): AgentV2MessagesState {
  const deltasByMessageId = new Map(deltas);
  let hasVisibleText = false;
  const messages = state.messages.map((message) => {
    const delta = deltasByMessageId.get(message.id);
    if (!delta) return message;

    const text = `${message.text}${delta}`;
    hasVisibleText ||= Boolean(text.trim());
    return { ...message, text, isTyping: undefined };
  });
  return hasVisibleText ? clearRunActivity({ ...state, messages }) : { ...state, messages };
}

function completeMessage(
  state: AgentV2MessagesState,
  action: Extract<AgentV2MessagesStateAction, { kind: 'messageCompleted' }>,
): AgentV2MessagesState {
  const updated = updateMessage(state, action.messageId, (message) => ({
    ...message,
    isTyping: undefined,
    isStreaming: undefined,
    shouldCommitMarkdownTail: action.finishReason === 'complete',
  }));
  if (!isRunUpdateCurrent(state.run, action.clientRunId)) return updated;
  const operationBinding = getRunOperationBinding(state.run);
  return {
    ...updated,
    run: operationBinding.operationId === undefined
      ? { phase: 'idle' }
      : {
        phase: 'terminal',
        ...operationBinding,
        clientRunId: action.clientRunId,
      },
  };
}

function failRun(
  state: AgentV2MessagesState,
  action: Extract<AgentV2MessagesStateAction, { kind: 'runFailed' }>,
): AgentV2MessagesState {
  let nextState = terminalizeStreamingMessages(state, action.messageId);
  const cause: AgentV2MessageError = {
    code: action.code,
    retryable: action.retryable,
    ...(action.resetAtIso ? { resetAt: action.resetAtIso } : {}),
  };
  const admissionFailure = !action.hasRunId && action.messageId === undefined
    ? buildAdmissionFailure(action, cause)
    : undefined;
  if (action.messageId !== undefined) {
    nextState = updateMessage(nextState, action.messageId, (message) => ({
      ...message,
      error: cause,
      isRetryAvailable: action.retryable,
    }));
  }
  if (action.code === 'thread_revision_conflict') return { ...nextState, run: { phase: 'idle' } };
  if (action.code === 'agent_capacity_exhausted') {
    return {
      ...nextState,
      ...(admissionFailure ? { admissionFailure } : {}),
      availability: {
        state: 'capacity_exhausted',
        ...(action.resetAt ? { resetAt: action.resetAt } : {}),
      },
      run: { phase: 'idle' },
    };
  }
  if (action.code === 'rate_limited' && action.resetAt) {
    return {
      ...nextState,
      userRateLimit: {
        kind: 'rateLimit',
        clientRunId: action.clientRunId,
        resetAt: action.resetAt,
        ...(action.optimisticMessageId !== undefined
          ? { optimisticMessageId: action.optimisticMessageId }
          : {}),
      },
      run: { phase: 'idle' },
    };
  }
  if (action.code === 'user_quota_exhausted') {
    return {
      ...nextState,
      quotaRetry: {
        ...(!action.hasRunId ? { clientRunId: action.clientRunId } : {}),
        ...(action.resetAt ? { resetAt: action.resetAt } : {}),
        ...(action.optimisticMessageId !== undefined
          ? { optimisticMessageId: action.optimisticMessageId }
          : {}),
      },
      run: { phase: 'idle' },
    };
  }
  if (!action.hasRunId) {
    return {
      ...nextState,
      admissionFailure,
      error: undefined,
      isLoading: false,
      run: { phase: 'idle' },
    };
  }
  return {
    ...nextState,
    ...(action.messageId === undefined
      ? { error: { text: action.errorText, timestamp: action.timestamp, cause } }
      : {}),
    isLoading: false,
    run: { phase: 'idle' },
  };
}

function buildAdmissionFailure(
  action: Extract<AgentV2MessagesStateAction, { kind: 'runFailed' }>,
  error: AgentV2MessageError,
): NonNullable<AgentV2MessagesState['admissionFailure']> {
  return {
    error,
    ...(action.retryable ? { clientRunId: action.clientRunId } : {}),
    ...(action.optimisticMessageId !== undefined
      ? { optimisticMessageId: action.optimisticMessageId }
      : {}),
    ...(action.retryMessageId !== undefined ? { retryMessageId: action.retryMessageId } : {}),
    timestamp: action.timestamp,
  };
}

function cancelRun(state: AgentV2MessagesState, clientRunId: string): AgentV2MessagesState {
  const nextState = terminalizeStreamingMessages(state);
  if (!isRunUpdateCurrent(state.run, clientRunId)) return nextState;
  const operationBinding = getRunOperationBinding(state.run);
  return {
    ...nextState,
    run: operationBinding.operationId === undefined
      ? { phase: 'idle' }
      : {
        phase: 'terminal',
        ...operationBinding,
        clientRunId,
      },
  };
}

function terminalizeStreamingMessages(
  state: AgentV2MessagesState,
  messageId?: number,
): AgentV2MessagesState {
  return {
    ...state,
    messages: state.messages.map((message) => (
      (messageId !== undefined ? message.id === messageId : message.isStreaming)
        ? {
          ...message,
          isTyping: undefined,
          isStreaming: undefined,
          shouldCommitMarkdownTail: undefined,
        }
        : message
    )),
  };
}

function clearRunActivity(state: AgentV2MessagesState): AgentV2MessagesState {
  if (state.run.phase !== 'admitting' && state.run.phase !== 'streaming') return state;
  const { activity, ...run } = state.run;
  return { ...state, run };
}

function updateRunActivityCurrent(
  run: AgentV2RunState,
  clientRunId: string,
  activity: AgentRunActivityType,
): AgentV2RunState {
  if (!isRunUpdateCurrent(run, clientRunId)) return run;
  return {
    phase: 'streaming',
    ...getRunOperationBinding(run),
    clientRunId,
    activity,
  };
}

function applyServerRunActivity(
  run: AgentV2RunState,
  clientRunId: string,
  event: AgentRunActivityEvent,
): AgentV2RunState {
  if (event.status !== 'active' || event.code === 'analysis.computing') {
    return run;
  }
  return updateRunActivityCurrent(run, clientRunId, { kind: 'server', code: event.code });
}

function isRunUpdateCurrent(run: AgentV2RunState, clientRunId: string) {
  return run.phase === 'idle'
    || run.phase === 'admitting'
    || run.clientRunId === clientRunId;
}

function getRunOperationBinding(run: AgentV2RunState): AgentV2RunWithOperation {
  if (run.phase === 'idle' || run.operationId === undefined) return {};
  return { operationId: run.operationId, operationKind: run.operationKind };
}

export function getRunOperationId(run: AgentV2RunState) {
  return run.phase === 'idle' ? undefined : run.operationId;
}

function updateMessage(
  state: AgentV2MessagesState,
  messageId: number,
  update: (message: AgentMessage) => AgentMessage,
): AgentV2MessagesState {
  return {
    ...state,
    messages: state.messages.map((message) => message.id === messageId ? update(message) : message),
  };
}

function reconcileHydratedMessages(
  currentMessages: AgentMessage[],
  hydratedMessages: AgentMessage[],
) {
  const currentById = new Map(currentMessages.map((message) => [message.id, message]));
  const hydratedMessageIds = new Set(hydratedMessages.map(({ id }) => id));
  const reconciledMessages = hydratedMessages.map((message) => {
    const current = currentById.get(message.id);
    const semanticContent = message.semanticContent ?? current?.semanticContent;
    const actions = current?.actions ?? message.actions;
    const actionPresentations = current?.actionPresentations ?? message.actionPresentations;
    if (!semanticContent && !actions && !actionPresentations) return message;
    return {
      ...message,
      ...(semanticContent ? { semanticContent } : {}),
      ...(actions ? { actions } : {}),
      ...(actionPresentations ? { actionPresentations } : {}),
    };
  });
  const liveOnlyMessages = currentMessages.filter((message) => (
    !hydratedMessageIds.has(message.id) && (message.isStreaming || message.isTyping)
  ));
  return [...reconciledMessages, ...liveOnlyMessages];
}

function normalizeHydrationEntries(
  action: Extract<AgentV2MessagesStateAction, { kind: 'hydrationSucceeded' }>,
) {
  const sourceIds = new Set<string>();
  const messageIds = new Set<number>();
  return action.entries.filter(({ message, sourceId }) => {
    if (sourceIds.has(sourceId) || messageIds.has(message.id)) return false;
    sourceIds.add(sourceId);
    messageIds.add(message.id);
    return true;
  });
}

function buildSourceIdIndex(
  entries: Array<{ message: AgentMessage; sourceId?: string }>,
  messages: AgentMessage[],
  currentIndex: Record<number, string>,
  shouldPreserveCurrent: boolean,
) {
  const messageIds = new Set(messages.map(({ id }) => id));
  const preservedEntries = shouldPreserveCurrent
    ? Object.entries(currentIndex).filter(([messageId]) => messageIds.has(Number(messageId)))
    : [];
  return Object.fromEntries([
    ...preservedEntries,
    ...entries.flatMap(({ message, sourceId }) => (
      sourceId && messageIds.has(message.id) ? [[message.id, sourceId]] : []
    )),
  ]);
}

function removeActionPresentation(
  presentations: AgentMessage['actionPresentations'],
  actionId: string,
) {
  if (!presentations) return undefined;
  return Object.fromEntries(Object.entries(presentations).filter(([id]) => id !== actionId));
}

function upsertMessage(messages: AgentMessage[], message: AgentMessage) {
  const index = messages.findIndex(({ id }) => id === message.id);
  if (index < 0) return [...messages, message];
  const result = [...messages];
  result[index] = message;
  return result;
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 messages state action: ${String(value)}`);
}

const getMessageIdBySourceId = memoize((sources: AgentV2MessagesState['sourceIdByMessageId']) => (
  new Map(Object.entries(sources).map(([id, sourceId]) => [sourceId, Number(id)]))
));

export function findAgentV2MessageId(state: AgentV2MessagesState, sourceId: string) {
  return getMessageIdBySourceId(state.sourceIdByMessageId).get(sourceId);
}
