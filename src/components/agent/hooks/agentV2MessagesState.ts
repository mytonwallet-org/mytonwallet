import type {
  AgentAnswerFeedbackV2,
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
  AgentV2StarterHints,
} from '../../../api/agentV2/types';
import type { AgentMessage } from '../../../global/types';
import type { AgentRunActivityType } from '../AgentRunActivity';

import { getIsAgentV2SupportActive, getIsAgentV2SupportEntryVisible } from '../../../global/agentV2/uiCapabilities';
import { areDeepEqual } from '../../../util/areDeepEqual';
import memoize from '../../../util/memoize';
import { selectAgentV2ComposerStatus } from '../../agentV2/agentComposerStatus';

export type AgentV2HeldLimitState = Pick<AgentV2MessagesState, 'quotaRetry' | 'userRateLimit' | 'admissionFailure'>;

type AgentV2RunWithOperation = {
  operationId?: number;
  operationKind?: AgentV2RunOperationKind;
};

export type AgentV2RunOperationKind = 'command' | 'admissionRetry' | 'supportRequest';

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
  /** The starter hints picked as the empty chat came on screen, for its showing `starterHintsShowingId` */
  starterHints?: AgentV2StarterHints;
  starterHintsShowingId?: number;
  error?: {
    text: string;
    timestamp: number;
    cause?: AgentV2MessageError;
    optimisticMessageId?: number;
    isHistoryFailure?: boolean;
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
  isOpeningHistory: boolean;
  hasHydratedHistory: boolean;
  /** The messages are the device's copy of the history, which shows until the history loads and offers nothing to do */
  isHistoryCached: boolean;
  /** The chat shows the history it had when it was last open, which loads again in place */
  isShowingCachedHistory?: boolean;
  /** `support.lastOperatorMessageAt` of the newest history page loaded, so a reply is marked read only once it shows */
  loadedOperatorMessageAt?: string;
  nextCursor?: string;
  isLoadingOlderMessages: boolean;
  historyPageRequest?: AgentV2HistoryPageRequest;
  sourceIdByMessageId: Record<number, string>;
  /**
   * The answers the user stopped in this chat, as they were shown when stopped. The server may keep less of such an
   * answer than was shown, or nothing, so a history read keeps the shown text until the server's holds as much.
   */
  stoppedAnswers?: AgentV2StoppedAnswer[];
  run: AgentV2RunState;
  /**
   * Questions sent while an answer is being produced. They show at the end of the chat at once, after whatever the
   * answer adds, and go one at a time, in order, once the chat is free.
   */
  queuedMessages: AgentMessage[];
  /**
   * Questions that waited for an answer under a wallet the user switched from, with their failure, whose Retry queues
   * them again. They show at the end of the chat, as the queue does, before the questions queued since. A later
   * question that goes leaves them where they are, without Retry, as on Android.
   */
  failedQueue?: AgentV2FailedQueue;
  threadMutation: AgentV2ThreadMutationState;
}

export interface AgentV2FailedQueue {
  messages: AgentMessage[];
  failure: AgentMessage;
}

interface AgentV2StoppedAnswer {
  message: AgentMessage;
  sourceId: string;
  /** The message before it, after which it goes again when the server leaves it out */
  previousSourceId?: string;
}

export type AgentV2MessagesStateAction =
  | { kind: 'consentLoadingStarted' }
  | { kind: 'consentReset' }
  | { kind: 'consentResolved'; isAccepted: boolean }
  | { kind: 'hydrationStarted'; shouldClearError: boolean; shouldPreserveOpeningMessages?: boolean }
  | {
    kind: 'hydrationSucceeded';
    thread: AgentThreadSummaryV2;
    entries: AgentV2NormalizedMessageEntry[];
    nextCursor?: string;
    shouldPreserveLiveContent: boolean;
  }
  | { kind: 'hydrationFailed' }
  | { kind: 'cachedHistoryApplied'; thread: AgentThreadSummaryV2; entries: AgentV2NormalizedMessageEntry[] }
  | { kind: 'cachedHistoryDiscarded' }
  | {
    kind: 'latestMessagesReceived';
    thread: AgentThreadSummaryV2;
    entries: AgentV2NormalizedMessageEntry[];
    /** Every message the refresh read, in the server's history order */
    sourceIds: string[];
  }
  | { kind: 'hintsLoaded'; starterHints: AgentV2StarterHints; showingId: number }
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
    threadRevision: number;
    support?: AgentThreadSummaryV2['support'];
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
    optimisticMessageId?: number;
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
    | { kind: 'messageQueued'; message: AgentMessage }
    /** The queued questions fail, as they were asked for an account that is no longer the active one */
    | { kind: 'queuedMessagesFailed'; failure: AgentMessage }
    | { kind: 'queuedMessagesRetried' }
    /** The queued and failed questions go to another chat of the same thread, which sends them or shows them failed */
    | { kind: 'queuedMessagesTaken' }
    /** The chat takes over the queued and failed questions its thread's chat left */
    | { kind: 'leftQueueRestored'; queuedMessages: AgentMessage[]; failedQueue?: AgentV2FailedQueue }
    | { kind: 'heldLimitRestored'; limit: AgentV2HeldLimitState; message?: AgentMessage }
    /** Another account is active, for which a run a limit held does not go again */
    | { kind: 'activeAccountChanged' }
    /** `messageId` is the answer the stopped run has started */
    | { kind: 'runStopped'; messageId?: number }
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
    }
    | { kind: 'messageFeedbackChanged'; messageId: number; feedback?: AgentAnswerFeedbackV2 };

export const ANALYZING_REQUEST_ACTIVITY: AgentRunActivityType = { kind: 'analyzingRequest' };

export const INITIAL_AGENT_V2_MESSAGES_STATE: AgentV2MessagesState = {
  messages: [],
  isLoading: false,
  isOpeningHistory: false,
  hasHydratedHistory: false,
  isHistoryCached: false,
  isLoadingOlderMessages: false,
  sourceIdByMessageId: {},
  run: { phase: 'idle' },
  queuedMessages: [],
  threadMutation: { phase: 'idle' },
  availability: { state: 'available' },
};

/**
 * A chat's history as it was last shown, which the chat shows at once when it opens again, as on iOS. Its starter
 * hints stay out: an empty chat picks them anew each time it opens.
 */
export type AgentV2CachedChat = Pick<
  AgentV2MessagesState,
  'messages' | 'sourceIdByMessageId' | 'nextCursor' | 'loadedOperatorMessageAt' | 'stoppedAnswers'
> & { thread: AgentThreadSummaryV2 };

/**
 * The history a chat leaves to show when it opens again, as iOS keeps its recent chats loaded: a loaded thread's saved
 * messages, a news discussion's too. A message the server doesn't keep, as a question that failed to go, and a failure
 * of the chat itself stay out, as a fresh load doesn't bring them either. A chat being answered or cleared leaves
 * nothing.
 */
export function selectAgentV2CachedChat(state: AgentV2MessagesState): AgentV2CachedChat | undefined {
  const { thread } = state;
  if (
    !thread
    || !state.hasHydratedHistory
    || selectIsAgentV2RunActive(state)
    || state.threadMutation.phase !== 'idle'
  ) return undefined;

  const { messages, sourceIdByMessageId } = selectAgentV2SavedHistory(state);
  return {
    thread,
    messages,
    sourceIdByMessageId,
    nextCursor: state.nextCursor,
    loadedOperatorMessageAt: state.loadedOperatorMessageAt,
    stoppedAnswers: state.stoppedAnswers,
  };
}

function selectAgentV2SavedHistory(state: AgentV2MessagesState) {
  const isSaved = ({ id, isStreaming, isTyping }: AgentMessage) => (
    !isStreaming && !isTyping && Boolean(state.sourceIdByMessageId[id])
  );
  if (state.messages.every(isSaved)) return state;

  const messages = state.messages.filter(isSaved);
  const savedIds = new Set(messages.map(({ id }) => String(id)));
  return {
    messages,
    sourceIdByMessageId: Object.fromEntries(Object.entries(state.sourceIdByMessageId)
      .filter(([id]) => savedIds.has(id))),
  };
}

/** A chat opened again with the history it had, which it shows at once and loads again in place */
export function restoreAgentV2MessagesState(cachedChat: AgentV2CachedChat): AgentV2MessagesState {
  return {
    ...INITIAL_AGENT_V2_MESSAGES_STATE,
    ...cachedChat,
    isConsentAccepted: true,
    hasHydratedHistory: true,
    isShowingCachedHistory: true,
  };
}

export function reduceAgentV2MessagesState(
  state: AgentV2MessagesState,
  action: AgentV2MessagesStateAction,
): AgentV2MessagesState {
  switch (action.kind) {
    case 'consentLoadingStarted':
      return { ...state, isLoading: true };
    case 'consentReset':
      return { ...state, isConsentAccepted: undefined };
    case 'consentResolved':
      return {
        ...state,
        isConsentAccepted: action.isAccepted,
        isLoading: action.isAccepted,
      };
    case 'hydrationStarted':
      return {
        ...state,
        isLoading: true,
        isOpeningHistory: Boolean(action.shouldPreserveOpeningMessages
          && (!state.thread || state.thread.news || state.thread.digest)),
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
        ...(action.shouldClearError ? { error: undefined } : {}),
      };
    case 'hydrationSucceeded': {
      const entries = normalizeHydrationEntries(action);
      const messages = entries.map(({ message }) => message);
      const shouldPreserveLiveContent = action.shouldPreserveLiveContent
        && (!state.thread || state.thread.id === action.thread.id);
      const shouldPreserveOpeningMessages = shouldPreserveLiveContent
        && Boolean(state.isOpeningHistory && (state.thread?.news || state.thread?.digest));
      const hasNewerContent = shouldPreserveOpeningMessages
        && (state.thread?.revision ?? 0) > action.thread.revision;
      // The history takes the place of the device's copy, keeping nothing of it
      const currentMessages = state.isHistoryCached ? state.messages.filter(isLiveMessage) : state.messages;
      const reconciledMessages = shouldPreserveLiveContent
        ? reconcileHydratedMessages(
          currentMessages, messages,
          shouldPreserveOpeningMessages ? state.sourceIdByMessageId : undefined, hasNewerContent,
          Boolean(state.isShowingCachedHistory),
        )
        : messages;
      const sourceIdByMessageId = buildSourceIdIndex(
        entries,
        reconciledMessages,
        state.sourceIdByMessageId,
        shouldPreserveLiveContent,
      );
      const hydrated = state.thread?.id === action.thread.id
        ? keepStoppedAnswers(reconciledMessages, sourceIdByMessageId, state.stoppedAnswers)
        : { messages: reconciledMessages, sourceIdByMessageId, stoppedAnswers: undefined };
      return {
        ...state,
        thread: hasNewerContent ? state.thread : action.thread,
        loadedOperatorMessageAt: hasNewerContent
          ? state.loadedOperatorMessageAt : action.thread.support?.lastOperatorMessageAt,
        ...hydrated,
        nextCursor: action.nextCursor,
        isLoadingOlderMessages: false,
        historyPageRequest: undefined,
        isLoading: false,
        isOpeningHistory: false,
        hasHydratedHistory: true,
        isHistoryCached: false,
        isShowingCachedHistory: undefined,
        error: state.error?.isHistoryFailure ? undefined : state.error,
        threadMutation: reconcileThreadMutation(state.threadMutation, action.thread, true),
      };
    }
    case 'hydrationFailed':
      return {
        ...state,
        isLoading: false,
        isOpeningHistory: false,
        isShowingCachedHistory: undefined,
      };
    case 'cachedHistoryApplied': {
      const entries = normalizeHydrationEntries(action);
      const messages = entries.map(({ message }) => message);
      return {
        ...state,
        thread: action.thread,
        messages,
        sourceIdByMessageId: buildSourceIdIndex(entries, messages, state.sourceIdByMessageId, false),
        isHistoryCached: true,
      };
    }
    case 'cachedHistoryDiscarded': {
      if (!state.isHistoryCached) return state;
      const messages = state.messages.filter(isLiveMessage);
      return {
        ...state,
        thread: undefined,
        messages,
        sourceIdByMessageId: buildSourceIdIndex([], messages, state.sourceIdByMessageId, true),
        isHistoryCached: false,
      };
    }
    case 'latestMessagesReceived':
      return mergeLatestMessages(state, action);
    case 'hintsLoaded':
      return { ...state, starterHints: action.starterHints, starterHintsShowingId: action.showingId };
    case 'optimisticMessageAdded': {
      const settled = settleFailedQueue(state);
      return {
        ...settled,
        messages: [...settled.messages, action.message],
        // A queued question that goes leaves the queue for its place in the chat, which is the same
        queuedMessages: state.queuedMessages.some(({ id }) => id === action.message.id)
          ? state.queuedMessages.filter(({ id }) => id !== action.message.id)
          : state.queuedMessages,
      };
    }
    case 'messageQueued':
      return { ...state, queuedMessages: [...state.queuedMessages, action.message] };
    case 'queuedMessagesFailed':
      return state.queuedMessages.length ? {
        ...state,
        queuedMessages: [],
        // Questions an earlier switch failed stay failed with them, under the latest failure
        failedQueue: {
          messages: [...(state.failedQueue?.messages ?? []), ...state.queuedMessages],
          failure: action.failure,
        },
      } : state;
    case 'queuedMessagesRetried':
      return state.failedQueue ? {
        ...state,
        queuedMessages: [...state.failedQueue.messages, ...state.queuedMessages],
        failedQueue: undefined,
      } : state;
    case 'queuedMessagesTaken':
      return state.queuedMessages.length || state.failedQueue
        ? { ...state, queuedMessages: [], failedQueue: undefined }
        : state;
    case 'leftQueueRestored':
      return {
        ...state,
        queuedMessages: [...state.queuedMessages, ...action.queuedMessages],
        failedQueue: action.failedQueue ? {
          messages: [...(state.failedQueue?.messages ?? []), ...action.failedQueue.messages],
          failure: action.failedQueue.failure,
        } : state.failedQueue,
      };
    case 'activeAccountChanged':
      return dropHeldLimitRun(state);
    case 'heldLimitRestored':
      return {
        ...state,
        ...action.limit,
        messages: action.message ? [...state.messages, action.message] : state.messages,
      };
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
      return prependHistoryPage({
        ...state,
        thread: action.threadRevision >= state.thread!.revision
          ? { ...state.thread!, revision: action.threadRevision, support: action.support }
          : state.thread,
      }, action.entries, action.nextCursor);
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
        queuedMessages: [],
        failedQueue: undefined,
        sourceIdByMessageId: {},
        stoppedAnswers: undefined,
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
        isOpeningHistory: false,
        run: { phase: 'idle' },
      };
    case 'runConnectionFailed': {
      if (!selectIsAgentV2RunOperationCurrent(state, action.operationId)) return state;
      const shouldPreserveAdmissionFailure = selectIsAgentV2AdmissionFailureHeld(state);
      return {
        ...state,
        error: action.optimisticMessageId === undefined ? action.error
          : (shouldPreserveAdmissionFailure ? { ...action.error, optimisticMessageId: action.optimisticMessageId }
            : undefined),
        ...(action.optimisticMessageId !== undefined && !shouldPreserveAdmissionFailure ? {
          admissionFailure: {
            error: action.error.cause!,
            optimisticMessageId: action.optimisticMessageId,
            timestamp: action.error.timestamp,
          },
        } : {}),
        isLoading: false,
        run: { phase: 'idle' },
      };
    }
    case 'runRequested': {
      // A new question takes the place of a failed one that wasn't asked again
      const isCommand = action.operationKind === 'command';
      const isSupportRequest = action.operationKind === 'supportRequest';
      const heldRun = selectAgentV2HeldLimitRun(state);
      const supersededMessageId = isCommand ? heldRun?.optimisticMessageId : undefined;
      const canReplaceAdmissionFailure = action.operationKind !== 'admissionRetry'
        || !state.admissionFailure?.clientRunId;
      const failedSupportId = state.error?.optimisticMessageId;
      const failedId = isCommand ? selectRetryOptimisticMessageId(state)
        : (canReplaceAdmissionFailure ? state.admissionFailure?.optimisticMessageId : undefined);
      const isHeldMessage = isSupportRequest && failedId !== undefined && heldRun?.optimisticMessageId === failedId;
      const settled = isCommand || isSupportRequest ? settleFailedQueue(state) : state;
      return {
        ...settled,
        messages: supersededMessageId !== undefined || failedSupportId !== undefined
          || (failedId !== undefined && !isHeldMessage)
          ? settled.messages.filter(({ id }) => (
            id !== supersededMessageId && id !== failedSupportId && (id !== failedId || isHeldMessage)
          ))
          : settled.messages,
        run: {
          phase: 'admitting',
          operationId: action.operationId,
          operationKind: action.operationKind,
          activity: ANALYZING_REQUEST_ACTIVITY,
        },
        admissionFailure: isSupportRequest && selectIsAgentV2AdmissionFailureHeld(state)
          ? state.admissionFailure : undefined,
        error: undefined,
      };
    }
    case 'runStarted': {
      const operationBinding = getRunOperationBinding(state.run);
      const isSupportRequest = operationBinding.operationKind === 'supportRequest';
      const heldMessageId = isSupportRequest ? selectAgentV2HeldLimitRun(state)?.optimisticMessageId : undefined;
      const heldMessage = heldMessageId !== undefined
        ? state.messages.find(({ id }) => id === heldMessageId) : undefined;
      return {
        ...state,
        messages: heldMessageId !== undefined
          ? state.messages.filter(({ id }) => id !== heldMessageId) : state.messages,
        queuedMessages: heldMessage ? [heldMessage, ...state.queuedMessages] : state.queuedMessages,
        admissionFailure: isSupportRequest ? undefined : state.admissionFailure,
        thread: state.thread?.id === action.threadId
          ? { ...state.thread, revision: action.threadRevision }
          : state.thread,
        ...((state.run.phase !== 'admitting' || state.run.operationKind !== 'admissionRetry')
          ? { userRateLimit: undefined, quotaRetry: undefined }
          : {}),
        run: {
          phase: 'streaming',
          ...operationBinding,
          clientRunId: action.clientRunId,
          activity: selectAgentV2Activity(state) ?? ANALYZING_REQUEST_ACTIVITY,
        },
      };
    }
    case 'toolActivityChanged':
      return withRun(state, updateRunActivityCurrent(state.run, action.clientRunId, action.activity));
    case 'runActivityChanged':
      return withRun(state, applyServerRunActivity(state.run, action.clientRunId, action.event));
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
        isOpeningHistory: state.isOpeningHistory && Boolean(action.thread.news || action.thread.digest),
        ...(isReplacement ? {
          hasHydratedHistory: false,
          loadedOperatorMessageAt: undefined,
          nextCursor: undefined,
          isLoadingOlderMessages: false,
          historyPageRequest: undefined,
          sourceIdByMessageId: {},
          stoppedAnswers: undefined,
          admissionFailure: undefined,
          failedQueue: undefined,
        } : {}),
        threadMutation: reconcileThreadMutation(state.threadMutation, action.thread, false),
      };
    }
    case 'runFailed':
      return failRun(state, action);
    case 'runCancelled':
      return cancelRun(state, action.clientRunId);
    case 'runStopped':
      return stopRun(state, action.messageId);
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
    case 'messageFeedbackChanged':
      return updateMessage(state, action.messageId, ({ feedback, ...message }) => (
        action.feedback ? { ...message, feedback: action.feedback } : message
      ));
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

export function selectCanRequestAgentV2Support(
  state: AgentV2MessagesState, now = Date.now(), canCreateThread = false,
) {
  return state.isConsentAccepted === true && Boolean(state.thread || canCreateThread)
    && getIsAgentV2SupportEntryVisible(state.thread)
    && !selectIsAgentV2SendDisabled(state, false)
    && !(state.userRateLimit && state.userRateLimit.resetAt > now)
    && !selectIsAgentV2RunActive(state);
}

export function selectAgentV2ComposerStatusForState(state: AgentV2MessagesState, now = Date.now()) {
  const hasActiveSupport = getIsAgentV2SupportActive(state.thread);
  return selectAgentV2ComposerStatus(
    hasActiveSupport ? undefined : state.availability,
    hasActiveSupport ? undefined : state.userQuota,
    state.quotaRetry,
    state.userRateLimit,
    now,
  );
}

/**
 * The run a limit held back, which Retry sends again once the limit has reset, as do the questions queued behind it
 * before they go
 */
export function selectAgentV2HeldLimitRunId(state: AgentV2MessagesState) {
  return selectAgentV2HeldLimitRun(state)?.clientRunId;
}

export function selectIsAgentV2AdmissionFailureHeld(state: AgentV2MessagesState) {
  return state.admissionFailure !== undefined && selectAgentV2HeldLimitRun(state) === state.admissionFailure;
}

function selectAgentV2HeldLimitRun(state: AgentV2MessagesState) {
  const heldRun = state.quotaRetry?.clientRunId !== undefined ? state.quotaRetry
    : (state.userRateLimit?.clientRunId !== undefined ? state.userRateLimit : undefined);
  const { admissionFailure } = state;
  if (admissionFailure?.error.code === 'agent_capacity_exhausted' && admissionFailure.clientRunId !== undefined
    && (!heldRun || heldRun.clientRunId === admissionFailure.clientRunId)) return admissionFailure;
  return heldRun;
}

function selectRetryOptimisticMessageId(state: AgentV2MessagesState) {
  return state.admissionFailure?.optimisticMessageId
    ?? state.quotaRetry?.optimisticMessageId
    ?? state.userRateLimit?.optimisticMessageId;
}

function selectIsAgentV2RunOperationCurrent(state: AgentV2MessagesState, operationId: number) {
  return getRunOperationId(state.run) === operationId;
}

/**
 * Suggestions, edits and answering again wait for a free chat: no answer being produced and no question queued. The
 * field stays open over a cached history while it loads again, as on iOS.
 */
export function selectIsAgentV2InputDisabled(state: AgentV2MessagesState, isLimitBlocking: boolean) {
  return selectIsAgentV2SendDisabled(state, isLimitBlocking)
    || selectIsAgentV2RunActive(state)
    || state.queuedMessages.length > 0;
}

/** A question can't be sent, nor queued behind the answer being produced */
export function selectIsAgentV2SendDisabled(state: AgentV2MessagesState, isLimitBlocking: boolean) {
  return (state.isLoading && !state.isOpeningHistory && !state.isShowingCachedHistory)
    || Boolean((state.thread?.news || state.thread?.digest) && !state.hasHydratedHistory
      && !(state.isLoading && state.isOpeningHistory))
    || state.threadMutation.phase === 'clearing'
    || state.isHistoryCached
    || isLimitBlocking;
}

/** A question sent now waits for the answer being produced, or for those queued before it */
export function selectIsAgentV2SendQueued(state: AgentV2MessagesState) {
  return selectIsAgentV2RunActive(state) || state.queuedMessages.length > 0;
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
  const duplicate = state.messages.find(({ id }) => (
    id !== messageId && state.sourceIdByMessageId[id] === sourceId
  ));
  const sourceIdByMessageId = Object.fromEntries(
    Object.entries(state.sourceIdByMessageId).filter(([currentMessageId, currentSourceId]) => (
      Number(currentMessageId) !== messageId && currentSourceId !== sourceId
    )),
  );
  sourceIdByMessageId[messageId] = sourceId;
  return {
    ...state,
    messages: duplicate
      ? state.messages.filter(({ id }) => id !== messageId)
        .map((message) => message.id === duplicate.id ? { ...message, id: messageId } : message)
      : state.messages,
    sourceIdByMessageId,
  };
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
  // Stopped answers that wait for an older page go in once it holds the message they followed
  const waitingStoppedAnswers = state.stoppedAnswers?.filter(({ sourceId }) => !existingSourceIds.has(sourceId));
  const page = keepStoppedAnswers(
    [...prependedEntries.map(({ message }) => message), ...state.messages],
    sourceIdByMessageId,
    waitingStoppedAnswers,
  );
  const stoppedAnswers = [
    ...(state.stoppedAnswers?.filter(({ sourceId }) => existingSourceIds.has(sourceId)) ?? []),
    ...(page.stoppedAnswers ?? []),
  ];

  return {
    ...state,
    ...page,
    stoppedAnswers: stoppedAnswers.length ? stoppedAnswers : undefined,
    nextCursor,
    isLoadingOlderMessages: false,
    historyPageRequest: undefined,
  };
}

function mergeLatestMessages(
  state: AgentV2MessagesState,
  action: Extract<AgentV2MessagesStateAction, { kind: 'latestMessagesReceived' }>,
): AgentV2MessagesState {
  if (state.thread?.id !== action.thread.id || state.thread.revision > action.thread.revision
    || state.isLoading || state.isLoadingOlderMessages || selectIsAgentV2RunActive(state)
    || state.threadMutation.phase !== 'idle') return state;

  const knownSourceIds = new Set(state.messages.map(({ id }) => state.sourceIdByMessageId[id]));
  const entries = normalizeHydrationEntries(action).filter(({ sourceId }) => !knownSourceIds.has(sourceId));
  const thread = areDeepEqual(state.thread, action.thread) ? state.thread : action.thread;
  const loadedOperatorMessageAt = action.thread.support?.lastOperatorMessageAt;
  if (!entries.length) {
    return thread === state.thread && loadedOperatorMessageAt === state.loadedOperatorMessageAt
      ? state : { ...state, thread, loadedOperatorMessageAt };
  }

  return {
    ...state,
    thread,
    loadedOperatorMessageAt,
    messages: insertLatestEntries(state, entries, action.sourceIds),
    sourceIdByMessageId: { ...state.sourceIdByMessageId,
      ...Object.fromEntries(entries.map(({ message, sourceId }) => [message.id, sourceId])) },
  };
}

// Each new message goes before the shown message the server lists next; the rest go after the last saved message,
// ahead of local messages the server has not confirmed yet
function insertLatestEntries(
  state: AgentV2MessagesState,
  entries: AgentV2NormalizedMessageEntry[],
  sourceIds: string[],
) {
  const messageIndexBySourceId = new Map<string, number>();
  let tailIndex = 0;
  state.messages.forEach(({ id }, index) => {
    const sourceId = state.sourceIdByMessageId[id];
    if (sourceId === undefined) return;
    messageIndexBySourceId.set(sourceId, index);
    tailIndex = index + 1;
  });

  const entryBySourceId = new Map(entries.map((entry) => [entry.sourceId, entry]));
  const insertionsByIndex = new Map<number, AgentMessage[]>();
  let anchorIndex = tailIndex;
  for (let i = sourceIds.length - 1; i >= 0; i--) {
    const knownIndex = messageIndexBySourceId.get(sourceIds[i]);
    const entry = entryBySourceId.get(sourceIds[i]);
    if (knownIndex !== undefined) {
      anchorIndex = knownIndex;
    } else if (entry) {
      entryBySourceId.delete(sourceIds[i]);
      insertionsByIndex.set(anchorIndex, [entry.message, ...insertionsByIndex.get(anchorIndex) ?? []]);
    }
  }
  if (entryBySourceId.size) {
    insertionsByIndex.set(tailIndex, [
      ...insertionsByIndex.get(tailIndex) ?? [],
      ...[...entryBySourceId.values()].map(({ message }) => message),
    ]);
  }

  const messages: AgentMessage[] = [];
  for (let i = 0; i <= state.messages.length; i++) {
    messages.push(...insertionsByIndex.get(i) ?? []);
    if (i < state.messages.length) messages.push(state.messages[i]);
  }
  return messages;
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
  // A stopped answer waiting for an older page is not loaded, and stays for that page. A loaded copy may carry another
  // id than the record, so records match by source.
  const loadedSourceIds = new Set(state.messages.map(({ id }) => state.sourceIdByMessageId[id]));
  const retainedSourceIds = new Set(messages.map(({ id }) => state.sourceIdByMessageId[id]));
  const stoppedAnswers = state.stoppedAnswers?.filter(({ sourceId }) => (
    retainedSourceIds.has(sourceId) || !loadedSourceIds.has(sourceId)
  ));
  return {
    ...state,
    messages,
    sourceIdByMessageId,
    stoppedAnswers: stoppedAnswers?.length ? stoppedAnswers : undefined,
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
  let hasChanged = false;
  const messages = state.messages.map((message) => {
    const delta = deltasByMessageId.get(message.id);
    if (!delta) return message;

    const text = `${message.text}${delta}`;
    hasVisibleText ||= Boolean(text.trim());
    hasChanged = true;
    return { ...message, text, isTyping: undefined };
  });
  if (!hasChanged) return state;

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
    // An answer the agent finished without a client tool is still stored as complete
    ...(action.finishReason === 'complete' || action.finishReason === 'tool_unavailable' ? { isComplete: true } : {}),
  }));
  const operationBinding = getRunOperationBinding(state.run);
  // An interrupted local operation keeps its indicator until the controller reports the run's outcome
  if (!isRunUpdateCurrent(state.run, action.clientRunId)
    || (action.finishReason === 'run_interrupted' && operationBinding.operationId !== undefined)) return updated;
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
  const isSupportRequest = !action.hasRunId && getRunOperationBinding(state.run).operationKind === 'supportRequest';
  const cause: AgentV2MessageError = {
    code: action.code,
    retryable: action.retryable && !isSupportRequest,
    ...(action.resetAtIso ? { resetAt: action.resetAtIso } : {}),
  };
  const admissionFailure = !action.hasRunId && action.messageId === undefined
    ? buildAdmissionFailure(action, cause)
    : undefined;
  if (isSupportRequest) {
    const heldAdmissionFailure = selectIsAgentV2AdmissionFailureHeld(state) ? state.admissionFailure : undefined;
    return {
      ...nextState,
      admissionFailure: heldAdmissionFailure ?? admissionFailure,
      ...(action.code === 'rate_limited' && action.resetAt ? {
        userRateLimit: {
          ...state.userRateLimit,
          kind: 'rateLimit',
          resetAt: Math.max(state.userRateLimit?.resetAt ?? 0, action.resetAt),
        },
      } : {}),
      error: heldAdmissionFailure ? {
        text: action.errorText, timestamp: action.timestamp, cause,
        optimisticMessageId: action.optimisticMessageId,
      } : undefined,
      isLoading: false,
      run: { phase: 'idle' },
    };
  }
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
    ...(error.retryable ? { clientRunId: action.clientRunId } : {}),
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

// A later question that goes leaves the questions a wallet switch failed where they are, with their failure, without
// Retry, as on Android
function settleFailedQueue(state: AgentV2MessagesState): AgentV2MessagesState {
  const { failedQueue } = state;
  if (!failedQueue) return state;
  return {
    ...state,
    messages: [...state.messages, ...failedQueue.messages, failedQueue.failure],
    failedQueue: undefined,
  };
}

/**
 * A run a limit held, as one that failed before the server took it, goes again only for the account it was asked for,
 * so once another account is active its failure and its limit stay without Retry
 */
function dropHeldLimitRun(state: AgentV2MessagesState): AgentV2MessagesState {
  const { admissionFailure, quotaRetry, userRateLimit } = state;
  let nextState = state;
  if (admissionFailure?.clientRunId) {
    const { clientRunId, ...failure } = admissionFailure;
    nextState = { ...nextState, admissionFailure: failure };
  }
  if (quotaRetry?.clientRunId) {
    const { clientRunId, ...retry } = quotaRetry;
    nextState = { ...nextState, quotaRetry: retry };
  }
  if (userRateLimit?.clientRunId) {
    const { clientRunId, ...limit } = userRateLimit;
    nextState = { ...nextState, userRateLimit: limit };
  }
  return nextState;
}

// A stopped answer keeps what it has shown, without the suggestions that follow a finished answer. One that has shown
// nothing goes. The operation of a run the chat started keeps input blocked until it settles; a run without one ends.
function stopRun(state: AgentV2MessagesState, messageId?: number): AgentV2MessagesState {
  const terminalState = terminalizeStreamingMessages(state);
  const nextState = getRunOperationId(state.run) === undefined
    ? { ...terminalState, run: { phase: 'idle' as const } }
    : clearRunActivity(terminalState);
  const answer = nextState.messages.find(({ id }) => id === messageId);
  if (!answer) return nextState;
  if (!hasAnswerContent(answer)) {
    return { ...nextState, messages: nextState.messages.filter((message) => message !== answer) };
  }

  const shownAnswer = omitFollowups(answer);
  const messages = nextState.messages.map((message) => (message === answer ? shownAnswer : message));
  const sourceId = nextState.sourceIdByMessageId[answer.id];
  if (!sourceId || !answer.text.trim()) return { ...nextState, messages };

  const previousMessage = messages[messages.indexOf(shownAnswer) - 1];
  return {
    ...nextState,
    messages,
    stoppedAnswers: [
      ...(nextState.stoppedAnswers ?? []).filter((stopped) => stopped.sourceId !== sourceId),
      {
        message: shownAnswer,
        sourceId,
        previousSourceId: previousMessage && nextState.sourceIdByMessageId[previousMessage.id],
      },
    ],
  };
}

/**
 * Keeps each stopped answer as it was shown where the server has less of its text or leaves it out, as it does for an
 * answer stopped before the server saved what it streamed. An answer the server holds as much of is the server's.
 * An answer left out goes after the message it followed, and waits for the page that holds that message to load.
 */
function keepStoppedAnswers(
  messages: AgentMessage[],
  sourceIdByMessageId: Record<number, string>,
  stoppedAnswers: AgentV2StoppedAnswer[] = [],
) {
  let keptMessages = messages;
  let keptSourceIds = sourceIdByMessageId;
  const stillStoppedAnswers: AgentV2StoppedAnswer[] = [];
  stoppedAnswers.forEach((stopped) => {
    const saved = keptMessages.find(({ id }) => keptSourceIds[id] === stopped.sourceId);
    if (saved && saved.text.trim().length >= stopped.message.text.trim().length) return;

    stillStoppedAnswers.push(stopped);
    if (saved) {
      const shown = { ...stopped.message, id: saved.id };
      keptMessages = keptMessages.map((message) => (message === saved ? shown : message));
      return;
    }

    const previousIndex = stopped.previousSourceId === undefined
      ? undefined
      : keptMessages.findIndex(({ id }) => keptSourceIds[id] === stopped.previousSourceId);
    // The message it followed is on an older page, which it waits for
    if (previousIndex === -1) return;

    const index = previousIndex === undefined ? keptMessages.length : previousIndex + 1;
    keptMessages = [...keptMessages.slice(0, index), stopped.message, ...keptMessages.slice(index)];
    keptSourceIds = { ...keptSourceIds, [stopped.message.id]: stopped.sourceId };
  });

  return {
    messages: keptMessages,
    sourceIdByMessageId: keptSourceIds,
    stoppedAnswers: stillStoppedAnswers.length ? stillStoppedAnswers : undefined,
  };
}

function hasAnswerContent({ text, semanticContent, tables, actions }: AgentMessage) {
  return Boolean(text.trim() || semanticContent || tables?.length || actions?.length);
}

function omitFollowups({ followups, ...message }: AgentMessage): AgentMessage {
  return message;
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
  if ((state.run.phase !== 'admitting' && state.run.phase !== 'streaming') || !state.run.activity) return state;
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
  const index = state.messages.findIndex((message) => message.id === messageId);
  if (index === -1) return state;

  const message = update(state.messages[index]);
  if (message === state.messages[index]) return state;

  const messages = [...state.messages];
  messages[index] = message;
  return { ...state, messages };
}

// An update that leaves the run as it was keeps the state, so the chat does not render again for it
function withRun(state: AgentV2MessagesState, run: AgentV2RunState): AgentV2MessagesState {
  return run === state.run ? state : { ...state, run };
}

function reconcileHydratedMessages(
  currentMessages: AgentMessage[],
  hydratedMessages: AgentMessage[],
  sourceIdByMessageId: AgentV2MessagesState['sourceIdByMessageId'] | undefined,
  hasNewerContent: boolean,
  isCachedHistory: boolean,
) {
  const currentById = new Map(currentMessages.map((message) => [message.id, message]));
  const hydratedMessageIds = new Set(hydratedMessages.map(({ id }) => id));
  const reconciledMessages = hydratedMessages.map((message) => {
    const current = currentById.get(message.id);
    if (hasNewerContent && current) return current;
    // An answer still streaming takes the rest of its text from the stream, which the stored copy may already hold.
    // The stored copy keeps its time.
    if (current?.isStreaming) return { ...current, timestamp: message.timestamp };
    const semanticContent = message.semanticContent ?? current?.semanticContent;
    // A cached history's actions may be outdated, so the server's replace them
    const actions = isCachedHistory ? message.actions : current?.actions ?? message.actions;
    const actionPresentations = isCachedHistory
      ? keepCachedActionPresentations(message, current)
      : current?.actionPresentations ?? message.actionPresentations;
    if (!semanticContent && !actions && !actionPresentations) return message;
    return {
      ...message,
      ...(semanticContent ? { semanticContent } : {}),
      ...(actions ? { actions } : {}),
      ...(actionPresentations ? { actionPresentations } : {}),
    };
  });
  const liveOnlyMessages = currentMessages.filter((message) => (
    !hydratedMessageIds.has(message.id) && (hasNewerContent || message.isStreaming || message.isTyping
      || (sourceIdByMessageId && message.isOutgoing && !sourceIdByMessageId[message.id]))
  ));
  return [...reconciledMessages, ...liveOnlyMessages];
}

function isLiveMessage({ isStreaming, isTyping }: AgentMessage) {
  return Boolean(isStreaming || isTyping);
}

/** The server's presentations, with the cached one of each action the server has as the cache had it */
function keepCachedActionPresentations(message: AgentMessage, cached?: AgentMessage) {
  const cachedPresentations = cached?.actionPresentations;
  if (!cachedPresentations || !message.actions) return message.actionPresentations;
  const keptPresentations = message.actions.flatMap((action) => {
    const presentation = cachedPresentations[action.id];
    const cachedAction = cached.actions?.find(({ id }) => id === action.id);
    return presentation && cachedAction && areDeepEqual(cachedAction, action) ? [[action.id, presentation]] : [];
  });
  if (!keptPresentations.length) return message.actionPresentations;
  return { ...message.actionPresentations, ...Object.fromEntries(keptPresentations) };
}

function normalizeHydrationEntries(
  action: { entries: AgentV2NormalizedMessageEntry[] },
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
