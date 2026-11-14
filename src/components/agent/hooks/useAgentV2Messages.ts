import { useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type {
  AgentAnswerFeedbackV2,
  AgentNewsFeedDiscussionNamingV2,
  AgentNewsFeedLocaleV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentThreadDigestCardV2,
  AgentThreadNewsCardV2,
  AgentThreadSummaryV2,
  AgentV2LiveAction,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ClientUpdate,
  AgentV2ComposerStatus,
  AgentV2HostContextSnapshot,
  AgentV2InactiveAction,
  AgentV2IncompatibleHistoryMessage,
  AgentV2MutationResult,
  AgentV2ResolvedAction,
  AgentV2SupportRequestSource,
} from '../../../api/agentV2/types';
import type { AgentHint, AgentMessage } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';
import type { AgentProblemReportOutcome } from '../AgentConversationShell';
import type { AgentRunActivityType } from '../AgentRunActivity';
import type { AgentV2HydrationController } from './agentV2HydrationController';
import type { AgentV2RunController, AgentV2StarterHintEntryPoint } from './agentV2RunController';
import type { AgentV2SendAction, AgentV2StreamController } from './agentV2StreamController';
import type { TextRevealPresentations } from './textRevealPresentation';

import { selectAgentV2HostContext } from '../../../global/agentV2/buildHostContext';
import { buildAgentBuiltinDapps } from '../../../global/agentV2/builtinDapps';
import { getIsAgentV2SupportActive, getIsAgentV2SupportEntryVisible } from '../../../global/agentV2/uiCapabilities';
import { selectCurrentAccountState } from '../../../global/selectors';
import { isAgentLinkUrl } from '../../../util/agent/agentLinkUrl';
import {
  agentThreadListListeners,
  agentV2BackgroundQueueListeners,
  dropAgentV2BackgroundQueue,
  forgetRecentAgentChat,
  getAgentV2LocalState,
  getRecentAgentChat,
  holdAgentV2BackgroundQueue,
  isAgentV2QueueHeld,
  keepAgentV2QueueInBackground,
  keepRecentAgentChat,
  releaseDrainedAgentV2Queues,
  takeAgentV2BackgroundQueue,
} from '../../../util/agent/agentV2LocalState';
import {
  cancelAgentV2ActiveRunReplays,
  subscribeToAgentV2RuntimeReady,
  subscribeToAgentV2Updates,
} from '../../../util/agentV2Updates';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { getIsSupportedChain } from '../../../util/chain';
import {
  isSelfDeeplink, parseDeeplinkTransferParams, processDeeplink,
} from '../../../util/deeplink';
import { SELF_PROTOCOL } from '../../../util/deeplink/constants';
import { logDebugError } from '../../../util/logs';
import { openUrl } from '../../../util/openUrl';
import { callApi } from '../../../api';
import { getAgentV2ActionAvailability } from '../../../api/agentV2/actionAvailability';
import { getSecretPhraseWordList, removeSecretPhrases } from '../../../api/agentV2/secretPhrase';
import { isAgentV2ComposerBlocked } from '../../agentV2/agentComposerStatus';
import { markAgentThreadSupportSeen } from '../../agentV2/agentThreadReadState';
import { getAgentV2ErrorText, mapAgentV2StarterHints } from '../../agentV2/agentV2Copy';
import { buildAgentV2HydrationError } from '../../agentV2/hydrationError';
import { loadAgentV2StarterHints } from '../../agentV2/useAgentSuggestions';
import { findSiteByUrl, openSite } from '../../explore/helpers/utils';
import { buildAgentV2SendAuthorityKey } from '../helpers/sendActionAuthority';
import { createAgentV2HydrationController } from './agentV2HydrationController';
import {
  type AgentV2MessagesState,
  type AgentV2MessagesStateAction,
  ANALYZING_REQUEST_ACTIVITY,
  findAgentV2MessageId,
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  restoreAgentV2MessagesState,
  selectAgentV2Activity,
  selectAgentV2CachedChat,
  selectAgentV2ComposerStatusForState,
  selectCanRequestAgentV2Support,
  selectIsAgentV2AdmissionFailureHeld,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
  selectIsAgentV2SendDisabled,
  selectIsAgentV2SendQueued,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

import useEffectWithPrevDeps from '../../../hooks/useEffectWithPrevDeps';
import useInterval from '../../../hooks/useInterval';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

/** The rating requests of one answer that have not all settled yet */
interface AgentV2FeedbackRequests {
  /** The request that settles the rating; the SDK sends an answer's requests in order, so it settles last */
  latest: { feedback?: AgentAnswerFeedbackV2 };
  /** The rating the server keeps after the requests settled so far */
  saved?: AgentAnswerFeedbackV2;
}

interface AgentV2Controllers {
  hydration: AgentV2HydrationController;
  run: AgentV2RunController;
  stream: AgentV2StreamController;
}

/**
 * The thread a chat shows: a known one, the profile's default one, the profile's empty one for a new chat, or the
 * discussion of a MyPulse news item or daily digest, which the server keeps one of per item.
 * A chat keeps the thread it resolved; showing another thread takes another chat.
 */
export type AgentV2ChatTarget =
  | {
    kind: 'thread';
    threadId: string;
    /** The feed's copy of the news of a discussion that holds its post alone, which it shows from its first frame */
    preview?: AgentThreadNewsCardV2;
    /** The feed's copy of the digest of a discussion, whose post it shows from its first frame */
    digestPreview?: AgentThreadDigestCardV2;
    /** A news or digest discussion, which loads before consent */
    isNews?: boolean;
    /** The language the news discussion was opened in, which its shared links name */
    newsLocale?: AgentNewsFeedLocaleV2;
  }
  | { kind: 'default' }
  | { kind: 'new' }
  | ({
    kind: 'digest';
    digest: { id: string };
    /** The feed's copy of the digest, whose post the discussion shows from its first frame */
    digestPreview?: AgentThreadDigestCardV2;
  } & AgentV2DeferredDiscussion)
  | ({
    kind: 'news';
    news: { eventId: number; locale: AgentNewsFeedLocaleV2 };
    /** The feed's copy of the news, which a discussion that holds its post alone shows from its first frame */
    preview?: AgentThreadNewsCardV2;
  } & AgentV2DeferredDiscussion);

/** A news or digest discussion of the feed that has none yet creates its thread with the first question */
interface AgentV2DeferredDiscussion {
  shouldDeferCreation?: boolean;
  discussionNaming?: AgentNewsFeedDiscussionNamingV2;
  threadResolution?: AgentV2DiscussionThreadResolution;
}

/** The thread a discussion is creating with its first question, which the question waits for */
export interface AgentV2DiscussionThreadResolution {
  promise: AgentV2ThreadResolution;
  localState: ReturnType<typeof getAgentV2LocalState>;
  /** The question as it shows, for a chat of the same discussion that opens while it waits */
  getOpeningQuestion: () => AgentMessage | undefined;
  takeOpeningQuestion?: () => {
    text: string;
    question: AgentMessage;
    followupText?: string;
    accountId?: string;
    hasAccountChanged: boolean;
  } | undefined;
}

type AgentV2DiscussionTarget = Extract<AgentV2ChatTarget, { kind: 'news' | 'digest' }>;

interface UseAgentV2MessagesProps {
  isActive?: boolean;
  lang: LangFn;
  /** Without a target the chat follows the default thread and every update, as the single-chat host did */
  target?: AgentV2ChatTarget;
  /**
   * The list's copy of the target thread. It tells a news or digest discussion before the history loads, and such a
   * discussion shows no cached history
   */
  initialThread?: AgentThreadSummaryV2;
  /** A question for a new chat: it shows at once and is sent once the chat's thread is ready */
  initialMessage?: string;
  /** The starter hint `initialMessage` is the title of */
  initialHintEntryPoint?: AgentV2StarterHintEntryPoint;
  shouldRequestSupport?: boolean;
  onInitialMessageSent?: NoneToVoidFunction;
  onThreadResolved?: (threadId: string) => void;
  onThreadNotFound?: NoneToVoidFunction;
  /** Problem reports need the user's consent, so a news discussion opened before it checks them once it comes */
  hasConsent?: boolean;
  isUnreadStateUnknown?: boolean;
}

export interface UseAgentV2MessagesResult {
  messages: AgentMessage[];
  thread?: AgentThreadSummaryV2;
  support?: AgentThreadSummaryV2['support'];
  /** The news the chat discusses */
  news?: AgentThreadNewsCardV2;
  /** The digest the chat discusses, as its thread or, until the thread comes, the feed tells it */
  digest?: AgentThreadDigestCardV2;
  /** A news discussion shows its post while the thread's history is loading */
  isOpeningNews: boolean;
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  /** The messages are the device's copy of the history, which shows until the history loads and offers nothing to do */
  isHistoryCached: boolean;
  /** The chat opened with the history it had when it was last shown, so it has no history to wait for */
  isOpenedWithCachedHistory: boolean;
  /** The question the chat opened with is on screen and not sent yet */
  hasPendingQuestion: boolean;
  /** Suggestions, edits and answering again wait: an answer is being produced, a question queued, or worse */
  isInputDisabled: boolean;
  /** No question can be sent, nor queued, as while the chat loads or is cleared, or a limit holds */
  isSendDisabled: boolean;
  /** A question sent now is queued behind the answer being produced */
  isSendQueued: boolean;
  /** The queued question that went last, a new object each time one goes */
  sentQueuedMessage?: { id: number };
  /** The questions queued, and those a wallet switch failed with their failure, which end the messages */
  queuedMessageCount: number;
  /** The failure of the questions a wallet switch failed, whose Retry works while an answer is being produced */
  failedQueueFailureId?: number;
  isRunActive: boolean;
  /**
   * An answer is being produced in the chat, from the question's sending on, which `stopRun` stops at once. Stop stays
   * while a stop sends the next queued question, and stops it once its run has started.
   */
  canStopRun: boolean;
  stopRun: NoneToVoidFunction;
  textRevealPresentations: TextRevealPresentations;
  clearChat: NoneToVoidFunction;
  /** Holds queued questions, cancels opening work and returns the thread already known or being created for deletion */
  cancelPendingRequests: () => Promise<string | undefined>;
  /** Present while the server takes problem reports */
  reportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  /** Sets or withdraws a rating, resolving to a live check of a saved reaction for its landing toast */
  rateMessage: (messageId: number, feedback?: AgentAnswerFeedbackV2) => Promise<(() => boolean) | undefined>;
  consumeTextRevealSession: (messageId: number, key: string) => void;
  settleTextRevealSession: (messageId: number, key: string) => void;
  activity?: AgentRunActivityType;
  hasOlderMessages: boolean;
  isLoadingOlderMessages: boolean;
  loadOlderMessages: () => Promise<void>;
  /** The chat's history did not load, which `retryHistory` reads again */
  historyFailure?: { text: string; isRetrying: boolean };
  retryHistory: NoneToVoidFunction;
  isConsentAccepted?: boolean;
  /** Reads the consent again, after a chat without it asked for it, and loads the chat once it is given */
  checkConsentAgain: NoneToVoidFunction;
  composerStatus?: AgentV2ComposerStatus;
  prepareSend: () => Promise<boolean>;
  sendMessage: (text: string, editMessageId?: number) => void;
  sendHint: (hint: AgentHint) => void;
  requestSupport: (source: AgentV2SupportRequestSource) => boolean;
  isSupportRequestVisible: boolean;
  canRequestSupport: boolean;
  sendFollowup: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  retryMessage: (messageId: number) => void;
  /** A finished answer the server stores, other than a news post, can be answered again with `retryMessage` */
  isMessageRegenerable: (messageId: number) => boolean;
  /**
   * A question the server stores, unlike one that waits or failed to go, can be edited with `sendMessage`, while support
   * doesn't have the chat
   */
  isMessageEditable: (messageId: number) => boolean;
  retryAdmission: NoneToVoidFunction;
  refreshExpiredComposerStatus: NoneToVoidFunction;
  activateAction: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
}

const ERROR_MESSAGE_ID = -1;
const NEWS_POST_MESSAGE_ID = -2;
const SUPPORT_ERROR_MESSAGE_ID = -3;
const SUPPORT_POLLING_INTERVAL_MS = 15_000;

// The chats on screen. Across the phone breakpoint the outgoing layout can unmount its chat after the incoming layout
// has mounted its own, so the chat stays active until the last of them goes.
let shownChatCount = 0;

export default function useAgentV2Messages({
  isActive,
  lang,
  target,
  initialThread,
  initialMessage,
  initialHintEntryPoint,
  shouldRequestSupport = false,
  onInitialMessageSent,
  onThreadResolved,
  onThreadNotFound,
  hasConsent,
  isUnreadStateUnknown = false,
}: UseAgentV2MessagesProps): UseAgentV2MessagesResult {
  const {
    openReceiveModal,
    setSwapAmountOut,
    showError,
    startSwap,
    startTransfer,
  } = getActions();
  // A chat shown recently opens with the history it had, as on iOS, and loads it again in place. A news discussion does
  // so once the user has allowed the Agent, since a chat shown keeps the wallet's state on the server up to date.
  const [state, setState] = useState(() => {
    const cachedChat = !isUnreadStateUnknown && target?.kind === 'thread' && !target.preview
      ? getRecentAgentChat(target.threadId) : undefined;
    return cachedChat && (!(cachedChat.thread.news || cachedChat.thread.digest) || hasConsent)
      ? restoreAgentV2MessagesState(cachedChat)
      : INITIAL_AGENT_V2_MESSAGES_STATE;
  });
  const isOpenedWithCachedHistory = useRef(Boolean(state.isShowingCachedHistory)).current;
  // Each time the chat comes on screen it picks its starter hints anew, and the previous pick is gone at once
  const hintsShowingIdRef = useLastingRef(0);
  useSyncEffect(() => {
    if (isActive) hintsShowingIdRef.current += 1;
  }, [hintsShowingIdRef, isActive]);
  const [textRevealPresentations, setTextRevealPresentations] = useState<TextRevealPresentations>({});
  // Reports are taken until the server says otherwise
  const [isProblemReportAvailable, setIsProblemReportAvailable] = useState(true);
  const problemReportAvailabilityRef = useRef<Promise<boolean>>();
  const [sentQueuedMessage, setSentQueuedMessage] = useState<{ id: number }>();
  // What the controllers read lasts past unmount, for a chat left with questions queued that goes on sending them
  const stateRef = useLastingRef(state);
  const [localState] = useState(getAgentV2LocalState);
  const hasActualConsentRef = useLastingRef(Boolean(hasConsent));
  if (hasConsent) hasActualConsentRef.current = true;
  const hasLoadedSendStatusRef = useLastingRef(false);
  const sendStatusRequestRef = useLastingRef<Promise<void> | undefined>(undefined);
  const [isSendStatusLoading, setIsSendStatusLoading] = useState(false);
  const [prepareSend] = useState(() => prepareDiscussionSend);
  // Keyed by the answer's server id, which a cleared chat cannot hand over to another answer
  const feedbackRequestsRef = useLastingRef(new Map<string, AgentV2FeedbackRequests>());
  const langRef = useLastingRef(lang);
  const wasActiveRef = useRef(isActive);
  const controllersRef = useLastingRef<AgentV2Controllers | undefined>(undefined);
  // The target is read once: a chat stays on the thread it resolved, so a runtime restart cannot move it
  const targetRef = useLastingRef(target);
  const observedThreadResolutionRef = useLastingRef(findThreadResolution(target, localState));
  const isObservingPendingThreadRef = useLastingRef(Boolean(observedThreadResolutionRef.current
    || (target?.kind === 'thread' && localState.backgroundQueues.get(target.threadId)?.hasOpeningQuestion())));
  const resolvedThreadIdRef = useLastingRef(target?.kind === 'thread' ? target.threadId : undefined);
  // Hydrations that overlap, such as the first one and a runtime restart, share one thread creation
  const resolvingThreadIdRef = useLastingRef<AgentV2ThreadResolution | undefined>(undefined);
  // The creation this chat started for its discussion's first question, which others of the discussion follow
  const ownThreadResolutionRef = useLastingRef<AgentV2DiscussionThreadResolution | undefined>(undefined);
  const isUnmountedRef = useLastingRef(false);
  // In-flight requests retain this state after Teact clears the component's refs on unmount
  const deletionState = useRef({ isRequested: false }).current;
  // Once the chat has unmounted and let go of its controllers, what they still finish changes nothing
  const disposalState = useRef({ isDisposed: false }).current;
  // The server's card is available before the history has loaded
  const createdNewsRef = useLastingRef<AgentThreadNewsCardV2 | undefined>(undefined);
  const newsPostRef = useRef<{ messageId: number; timestamp: number }>();
  const onThreadResolvedRef = useLastingRef(onThreadResolved);
  onThreadResolvedRef.current = onThreadResolved;
  const handleThreadNotFound = useLastCallback(() => {
    const threadId = stateRef.current.thread?.id ?? resolvedThreadIdRef.current;
    if (threadId) {
      forgetRecentAgentChat(threadId);
      dropAgentV2BackgroundQueue(threadId);
    }
    onThreadNotFound?.();
  });
  const onInitialMessageSentRef = useLastingRef(onInitialMessageSent);
  onInitialMessageSentRef.current = onInitialMessageSent;
  const [sendPendingQuestion] = useState(() => sendOpeningQuestion);
  const [failOpeningQuestion] = useState(() => failPendingOpeningQuestion);
  // The controllers go on dispatching after unmount, while a left chat's queue is sent
  const [dispatch] = useState(() => (action: AgentV2MessagesStateAction) => {
    if (deletionState.isRequested || disposalState.isDisposed) return;
    const wasRunActive = selectIsAgentV2RunActive(stateRef.current);
    const hasPendingHeaderSupportRun = isHeaderSupportPendingRef.current && stateRef.current.run.phase !== 'idle'
      && stateRef.current.run.operationKind === 'supportRequest';
    const previousThread = stateRef.current.thread;
    stateRef.current = reduceAgentV2MessagesState(stateRef.current, action);
    // History carries the rating the server keeps; a rating still being saved shows over it
    if (action.kind === 'hydrationSucceeded' || action.kind === 'historyPageSucceeded') {
      stateRef.current = applyPendingFeedback(stateRef.current, feedbackRequestsRef.current);
    }
    if (action.kind === 'runStarted' || action.kind === 'runSettled') {
      if (hasPendingHeaderSupportRun && !controllersRef.current?.run.hasPendingAdmission()) {
        isHeaderSupportPendingRef.current = false;
      }
      const target = targetRef.current;
      const question = pendingQuestionRef.current;
      if (getIsDiscussionTarget(target) && target.threadResolution?.takeOpeningQuestion === takeOpeningQuestion
        && ((question && stateRef.current.sourceIdByMessageId[question.id])
          || (!initialMessageRef.current && !stateRef.current.queuedMessages.length
            && !controllersRef.current?.run.hasPendingAdmission()))) {
        delete target.threadResolution.takeOpeningQuestion;
        forgetPendingDiscussionThread(target, target.threadResolution);
      }
      // The discussion's entry goes once the opening question's run is admitted or has ended, whatever waits after it
      const sentQuestion = sentOpeningQuestionRef.current;
      const ownResolution = ownThreadResolutionRef.current;
      if (sentQuestion && ownResolution && getIsDiscussionTarget(target)
        && (action.kind === 'runSettled' || stateRef.current.sourceIdByMessageId[sentQuestion.id])) {
        forgetPendingDiscussionThread(target, ownResolution);
      }
    }
    if (action.kind === 'hydrationSucceeded' && isObservingPendingThreadRef.current
      && !getIsObservingOpeningQuestion()
      && stateRef.current.messages.some(({ isOutgoing }) => isOutgoing)) {
      const backgroundQueue = localState.backgroundQueues.get(action.thread.id);
      if (!backgroundQueue || backgroundQueue.isDone()) isObservingPendingThreadRef.current = false;
    }
    setState(stateRef.current);
    const support = stateRef.current.thread?.support;
    if (wasRunActive && !selectIsAgentV2RunActive(stateRef.current)
      && getIsAgentV2SupportActive(stateRef.current.thread)) {
      void controllersRef.current?.hydration.refreshLatestMessages();
    }
    // A live summary announces a reply or a closure before its messages load; closure also ends polling
    if (action.kind === 'threadChanged' && previousThread?.id === action.thread.id
      && (support?.state !== previousThread.support?.state
        || support?.lastOperatorMessageAt !== previousThread.support?.lastOperatorMessageAt)) {
      controllersRef.current?.hydration.requestLatestRefresh();
    }
    controllersRef.current?.hydration.resumeLatestRefresh();
    if (isUnmountedRef.current) {
      if (action.kind === 'errorSet' && action.error.isHistoryFailure) failOpeningQuestion(action.error);
      if (action.kind === 'hydrationSucceeded') sendPendingQuestion();
      if (action.kind === 'runSettled') agentV2BackgroundQueueListeners.forEach((listener) => listener());
      releaseDrainedAgentV2Queues();
    }
  });
  langRef.current = lang;
  const [hideSecretPhrases] = useState(() => redactQuestion);
  const isChatVisible = useLastCallback(() => Boolean(
    isActive && !deletionState.isRequested && document.visibilityState === 'visible',
  ));

  if (!controllersRef.current) {
    const stream = createAgentV2StreamController({
      cancelFrame: (frameId) => window.cancelAnimationFrame(frameId),
      dispatch,
      getActionPresentation: (messageId, actionId) => callApi(
        'getAgentV2ActionPresentation',
        messageId,
        actionId,
      ),
      getState: () => stateRef.current,
      now: Date.now,
      requestFrame: (callback) => window.requestAnimationFrame(callback),
      setTextRevealPresentations,
    });
    const hydration = createAgentV2HydrationController({
      buildHistoryError: (error) => buildAgentV2HydrationError(error, langRef.current),
      dispatch,
      resolveThreadId,
      onThreadNotFound: handleThreadNotFound,
      ...(canReadCachedHistory(targetRef.current, initialThread) && {
        getCachedMessages: (threadId: string) => callApi('getAgentV2CachedMessages', threadId),
      }),
      getStarterHints: () => (
        getIsNewsTarget(targetRef.current) || createdNewsRef.current
        || stateRef.current.thread?.news || stateRef.current.thread?.digest
          ? Promise.resolve(undefined)
          : loadAgentV2StarterHints()
      ),
      getHintsShowingId: () => hintsShowingIdRef.current,
      getMessages: (threadId, cursor) => cursor
        ? callApi('getAgentV2Messages', threadId, cursor)
        : callApi('getAgentV2Messages', threadId),
      getState: () => stateRef.current,
      isConsentAccepted: () => stateRef.current.isConsentAccepted === true,
      isChatVisible,
      loadAvailability: () => callApi('getAgentV2Availability'),
      loadUserQuota: () => callApi('getAgentV2UserQuota'),
      now: Date.now,
      releaseStaleThreadClearOperation: (thread, shouldMatchRevision) => {
        run.releaseStaleThreadClearOperation(thread, shouldMatchRevision);
      },
      reportIncompatibleMessages: reportIncompatibleHistoryMessages,
      stream,
    });
    const run = createAgentV2RunController({
      buildConnectionError: () => langRef.current('Agent connection was interrupted.'),
      clearThread: (threadId, expectedRevision) => callApi(
        'clearAgentV2Thread',
        threadId,
        expectedRevision,
      ),
      dispatch,
      getErrorText: (code) => getAgentV2ErrorText(code, langRef.current),
      getSupportRequestText,
      getState: () => stateRef.current,
      getActiveAccountId: () => selectAgentV2HostContext(getGlobal()).activeAccountId,
      isQueueHeld: () => {
        const threadId = stateRef.current.thread?.id;
        return Boolean(threadId && isAgentV2QueueHeld(threadId));
      },
      hydrate: hydration.hydrate,
      now: Date.now,
      retryRun: (clientRunId) => callApi('retryAgentV2Run', clientRunId),
      resetHistory: hydration.resetHistory,
      startRun: async (command, isStopped) => {
        // A chat being deleted never sends its opening question, nor does one whose thread another chat deletes
        if (deletionState.isRequested) return undefined;
        const hostContext = selectAgentV2HostContext(getGlobal());
        const synchronized = await synchronizeHostContext(hostContext);
        if (synchronized === undefined || deletionState.isRequested || isStopped()
          || isAgentV2QueueHeld(command.threadId!)) return undefined;
        return callApi('startAgentV2Run', command);
      },
      stopRun: (threadId) => callApi('stopAgentV2Run', threadId),
      onQueuedMessageSent: (id) => setSentQueuedMessage({ id }),
      stream,
      hideSecretPhrases,
    });
    controllersRef.current = { hydration, run, stream };
  }
  const controllers = controllersRef.current;
  const cancelPendingRequests = useLastCallback(() => {
    const threadId = stateRef.current.thread?.id ?? resolvedThreadIdRef.current;
    if (threadId) {
      forgetRecentAgentChat(threadId);
      holdAgentV2BackgroundQueue(threadId);
      // Queued questions keep their controllers until the server confirms deletion
      if (stateRef.current.queuedMessages.length || stateRef.current.failedQueue) return Promise.resolve(threadId);
    }
    deletionState.isRequested = true;
    // Deleting any chat of a discussion cancels the question its thread is being created for, which the chat that
    // asked it keeps, so the discussion opens afresh
    const chatTarget = targetRef.current;
    if (getIsDiscussionTarget(chatTarget)) {
      const threadResolution = observedThreadResolutionRef.current ?? findThreadResolution(chatTarget, localState);
      if (threadResolution) {
        threadResolution.takeOpeningQuestion?.();
        forgetPendingDiscussionThread(chatTarget, threadResolution);
      }
    }
    controllers.hydration.dispose();
    controllers.run.dispose();
    controllers.stream.dispose();
    return resolvedThreadIdRef.current
      ? Promise.resolve(resolvedThreadIdRef.current)
      : resolvingThreadIdRef.current?.then((result) => (result?.ok ? result.value : undefined))
        ?? Promise.resolve(undefined);
  });
  const isInitialSupportRequest = useRef(shouldRequestSupport && !getIsNewsTarget(target)).current;
  const initialMessageRef = useLastingRef(observedThreadResolutionRef.current ? undefined
    : (isInitialSupportRequest ? getSupportRequestText() : initialMessage?.trim()));
  const initialHintEntryPointRef = useLastingRef(observedThreadResolutionRef.current || isInitialSupportRequest
    ? undefined : initialHintEntryPoint);
  const pendingFollowupTextRef = useLastingRef<string | undefined>(undefined);
  const openingQuestionAccountRef = useLastingRef<{
    accountId?: string; hasChanged: boolean;
  } | undefined>(undefined);
  const isHeaderSupportPendingRef = useLastingRef(false);
  // The question is the sent message's placeholder, so the message that takes its place keeps its id and time
  const [pendingQuestion, setPendingQuestion] = useState<AgentMessage | undefined>(() => {
    const text = initialMessageRef.current;
    return text ? {
      id: controllers.stream.createLocalMessageId(),
      text: hideSecretPhrases(text),
      isOutgoing: true,
      timestamp: Date.now(),
    } : undefined;
  });
  const pendingQuestionRef = useLastingRef(pendingQuestion);
  // The opening question being sent, which the discussion's other chats show until its run is admitted
  const sentOpeningQuestionRef = useLastingRef<AgentMessage | undefined>(undefined);
  // The question of the chat creating the thread shows here until it is sent, failed or taken over
  const [observedQuestion] = useState(() => {
    const question = observedThreadResolutionRef.current?.getOpeningQuestion();
    return question && { ...question, id: controllers.stream.createLocalMessageId() };
  });
  const chatTarget = targetRef.current;
  const isDeferredDiscussion = getIsDeferredDiscussion(chatTarget);
  const isUncreatedDiscussion = isDeferredDiscussion && !resolvedThreadIdRef.current;
  const namingFollowups = useMemo(() => (isUncreatedDiscussion && getIsDiscussionTarget(chatTarget)
    ? chatTarget.discussionNaming?.followups.map((text, index) => ({
      id: String(index), kind: 'suggested_prompt' as const, text,
    }))
    : undefined), [chatTarget, isUncreatedDiscussion]);
  const preview = chatTarget?.kind === 'news' || chatTarget?.kind === 'thread' ? chatTarget.preview : undefined;
  const createdNews = createdNewsRef.current;
  const authoritativeNews = state.thread?.news ?? createdNews ?? preview;
  const news = useMemo(() => {
    if (!authoritativeNews) return undefined;
    const matchingCreatedNews = createdNews?.eventId === authoritativeNews.eventId ? createdNews : undefined;
    const matchingPreview = preview?.eventId === authoritativeNews.eventId ? preview : undefined;
    return {
      ...authoritativeNews,
      // The feed's picture, decoded already, stays through the card's flight into the chat and after, whatever
      // address or none the thread's card gives it
      imageUrl: matchingPreview?.imageUrl ?? authoritativeNews.imageUrl,
      body: authoritativeNews.body ?? matchingCreatedNews?.body ?? matchingPreview?.body,
      sources: authoritativeNews.sources ?? matchingCreatedNews?.sources ?? matchingPreview?.sources,
    };
  }, [authoritativeNews, createdNews, preview]);
  const isNewsThread = getIsNewsTarget(chatTarget) || Boolean(news || state.thread?.digest);
  const starterHints = state.starterHintsShowingId === hintsShowingIdRef.current ? state.starterHints : undefined;
  const hints = useMemo(() => starterHints && mapAgentV2StarterHints(starterHints.items, lang), [lang, starterHints]);
  if (news && !newsPostRef.current) {
    newsPostRef.current = {
      messageId: NEWS_POST_MESSAGE_ID, timestamp: Date.parse(news.publishedAt),
    };
  }
  const digestPreview = chatTarget?.kind === 'digest' || chatTarget?.kind === 'thread'
    ? chatTarget.digestPreview
    : undefined;
  const digest = news ? undefined : state.thread?.digest ?? digestPreview;
  if (!news && digest && !newsPostRef.current) {
    newsPostRef.current = {
      messageId: NEWS_POST_MESSAGE_ID, timestamp: Date.parse(digest.windowEnd),
    };
  }
  const isOpeningNews = Boolean((preview || digestPreview) && (!state.thread || state.isLoading));

  const isChatShown = Boolean(isActive && state.isConsentAccepted);
  useEffect(() => {
    if (!isChatShown) return undefined;

    shownChatCount += 1;
    updateChatActivity();
    const unsubscribe = subscribeToAgentV2RuntimeReady(updateChatActivity);
    return () => {
      unsubscribe();
      shownChatCount -= 1;
      updateChatActivity();
    };
  }, [isChatShown]);

  // The status keeps its object while it says the same, so that what shows it renders again only when it changes
  const composerStatusRef = useRef<AgentV2ComposerStatus>();
  const nextComposerStatus = selectAgentV2ComposerStatusForState(state);
  if (!areDeepEqual(composerStatusRef.current, nextComposerStatus)) composerStatusRef.current = nextComposerStatus;
  const composerStatus = composerStatusRef.current;
  const isComposerBlocked = isAgentV2ComposerBlocked(composerStatus);
  const isAdmissionFailureHeld = selectIsAgentV2AdmissionFailureHeld(state);
  const isObservedQuestionShown = Boolean(observedQuestion && !pendingQuestion
    && observedThreadResolutionRef.current?.takeOpeningQuestion
    && !state.queuedMessages.length && !state.failedQueue);
  const messages = useMemo(() => {
    const shownQuestion = pendingQuestion ?? (isObservedQuestionShown
      && !state.messages.some(({ isOutgoing }) => isOutgoing) ? observedQuestion : undefined);
    const shownMessages = shownQuestion ? [...state.messages, shownQuestion] : state.messages;
    const lastAdmittedUserMessageIndex = shownMessages.reduce((lastIndex, { id, isOutgoing }, index) => (
      isOutgoing && state.sourceIdByMessageId[id] ? index : lastIndex
    ), -1);
    const supportFailure = state.admissionFailure && state.error?.optimisticMessageId !== undefined
      ? buildLiveFailureMessage(undefined, state.error, shownMessages, SUPPORT_ERROR_MESSAGE_ID) : undefined;
    const liveFailure = buildLiveFailureMessage(
      state.admissionFailure, supportFailure ? undefined : state.error, shownMessages,
    );
    // Questions a wallet switch failed and their failure come last, then the queued questions, as on Android: after
    // whatever the answer being produced adds. Their Retry shows while the failure ends the chat.
    const trailingMessages = [
      ...(liveFailure ? [liveFailure] : []),
      ...(supportFailure ? [supportFailure] : []),
      ...(state.failedQueue ? [
        ...state.failedQueue.messages,
        { ...state.failedQueue.failure, isRetryAvailable: !state.queuedMessages.length },
      ] : []),
      ...state.queuedMessages,
    ];
    return keepRetryOnLatestFailure(
      trailingMessages.length ? [...shownMessages, ...trailingMessages] : shownMessages,
      lastAdmittedUserMessageIndex,
      isAdmissionFailureHeld ? ERROR_MESSAGE_ID : undefined,
    );
  }, [
    isAdmissionFailureHeld, isObservedQuestionShown, observedQuestion, pendingQuestion, state.admissionFailure,
    state.error, state.failedQueue, state.messages, state.queuedMessages,
    state.sourceIdByMessageId,
  ]);
  const visibleMessages = useMemo(() => {
    const post = newsPostRef.current;
    if (!news && digest && post && !state.nextCursor) {
      // A digest's post is the thread's first message, which the feed's copy of the digest stands in for until it comes
      const postMessage = messages.find(({ isNewsPost }) => isNewsPost);
      return [{
        ...postMessage,
        id: post.messageId,
        text: postMessage?.text ?? '',
        isOutgoing: false,
        isNewsPost: true,
        followups: postMessage ? postMessage.followups : namingFollowups,
        timestamp: postMessage?.timestamp ?? post.timestamp,
      }, ...messages.filter((message) => message !== postMessage)];
    }
    if (!news || !post || state.nextCursor) return messages;
    const firstOutgoingMessage = messages.find(({ isOutgoing }) => isOutgoing);
    const postMessage = messages.find(({ isNewsPost }) => isNewsPost)
      ?? (firstOutgoingMessage !== pendingQuestion && firstOutgoingMessage !== observedQuestion
        && firstOutgoingMessage?.text === news.headline ? firstOutgoingMessage : undefined);
    return [{
      ...postMessage,
      // The same list item hosts the preview, the saved post and the local fallback after a clear
      id: post.messageId,
      text: postMessage?.text ?? `**${news.headline}**\n\n${news.body ?? news.excerpt ?? ''}`,
      isOutgoing: false,
      isNewsPost: true,
      followups: postMessage?.isNewsPost ? postMessage.followups : namingFollowups,
      timestamp: post.timestamp,
    }, ...messages.filter((message) => message !== postMessage)];
  }, [digest, messages, namingFollowups, news, observedQuestion, pendingQuestion, state.nextCursor]);

  useEffect(() => {
    isUnmountedRef.current = false;
    const chatTarget = targetRef.current;
    // Runs of other threads carry on in the SDK; a bound chat leaves their updates to the chats that show them
    const isUpdateForThisChat = (update: AgentV2ClientUpdate) => {
      if (!targetRef.current || update.threadId === undefined) return true;
      return update.threadId === (stateRef.current.thread?.id ?? resolvedThreadIdRef.current);
    };
    const unsubscribe = subscribeToAgentV2Updates((update) => {
      if (!isUpdateForThisChat(update)) return;
      if (controllers.run.isCancelledRunUpdate(update)) return;
      const openingAccount = openingQuestionAccountRef.current;
      if (update.kind === 'walletAuthorityChanged' && openingAccount
        && openingAccount.accountId !== selectAgentV2HostContext(getGlobal()).activeAccountId) {
        openingAccount.hasChanged = true;
      }
      controllers.stream.handleUpdate(update);
      if (update.kind !== 'runtimeReady' || !isDeferredDiscussion || initialMessageRef.current
        || resolvedThreadIdRef.current) controllers.hydration.handleUpdate(update);
      controllers.run.handleUpdate(update);
      if (update.kind === 'walletAuthorityChanged') sendPendingQuestion();
      if (isObservingPendingThreadRef.current && update.kind === 'runStarted') {
        void controllers.hydration.hydrate(true, true);
      }
    });
    agentV2BackgroundQueueListeners.add(refreshObservedThread);

    function refreshObservedThread() {
      const observedThreadId = resolvedThreadIdRef.current;
      if (!isObservingPendingThreadRef.current || !observedThreadId
        || !localState.backgroundQueues.get(observedThreadId)?.isDone()) return;
      isObservingPendingThreadRef.current = false;
      void controllers.hydration.hydrate(true, true);
    }

    return () => {
      isUnmountedRef.current = true;
      const cachedChat = deletionState.isRequested ? undefined : selectAgentV2CachedChat(stateRef.current);
      const leftThreadId = stateRef.current.thread?.id ?? resolvedThreadIdRef.current;
      // A chat left while it answers loads afresh, as the answer's updates come again on top of the history it reads
      if (cachedChat) {
        keepRecentAgentChat(cachedChat);
      } else if (leftThreadId) {
        forgetRecentAgentChat(leftThreadId);
      }
      const dispose = () => {
        if (disposalState.isDisposed) return;
        disposalState.isDisposed = true;
        // A disposed chat sends its opening question no more, so its discussion opens afresh
        const ownResolution = ownThreadResolutionRef.current;
        if (ownResolution?.takeOpeningQuestion && getIsDiscussionTarget(chatTarget)) {
          forgetPendingDiscussionThread(chatTarget, ownResolution);
        }
        unsubscribe();
        agentV2BackgroundQueueListeners.delete(refreshObservedThread);
        controllers.hydration.dispose();
        controllers.run.dispose();
        controllers.stream.dispose();
      };
      // A chat left with questions queued keeps sending them in the background, as on mobile, until they have been
      // answered or the chat opens again and takes them over. Questions a wallet switch failed wait for it, as on
      // Android, to show last with their failure.
      const historyFailure = stateRef.current.error;
      if (historyFailure?.isHistoryFailure) failOpeningQuestion(historyFailure);
      const { queuedMessages, failedQueue } = stateRef.current;
      // An opening request stays with the chat until admission, as other chats of the discussion follow it until then
      const hasPendingQuestion = isDeferredDiscussion
        && Boolean(initialMessageRef.current || isHeaderSupportPendingRef.current
          || (sentOpeningQuestionRef.current && controllers.run.hasPendingAdmission()));
      if (!deletionState.isRequested && (queuedMessages.length || failedQueue || hasPendingQuestion)) {
        if (leftThreadId) {
          keepQueueInBackground(leftThreadId);
          return;
        }
        if (hasPendingQuestion && resolvingThreadIdRef.current) {
          void resolvingThreadIdRef.current.then((result) => {
            if (result?.ok) keepQueueInBackground(result.value);
            else dispose();
          });
          return;
        }
      }
      dispose();

      function keepQueueInBackground(threadId: string) {
        if (deletionState.isRequested || disposalState.isDisposed || localState !== getAgentV2LocalState()) {
          dispose();
          return;
        }
        keepAgentV2QueueInBackground(threadId, {
          resume: () => {
            sendPendingQuestion();
            controllers.run.sendQueuedMessage();
          },
          take: () => {
            // A pending admission has no run updates for the receiving chat to follow yet
            if (initialMessageRef.current || isHeaderSupportPendingRef.current
              || controllers.run.hasPendingAdmission()) return undefined;
            const left = {
              queuedMessages: stateRef.current.queuedMessages,
              failedQueue: stateRef.current.failedQueue,
              heldRun: controllers.run.getHeldLimitRun(),
            };
            dispatch({ kind: 'queuedMessagesTaken' });
            return left;
          },
          isDone: () => !initialMessageRef.current && !isHeaderSupportPendingRef.current
            && !selectIsAgentV2SendQueued(stateRef.current),
          hasOpeningQuestion: () => isHeaderSupportPendingRef.current || (getIsDiscussionTarget(chatTarget)
            && Boolean(chatTarget.threadResolution?.takeOpeningQuestion)),
          hasFailures: () => Boolean(stateRef.current.failedQueue),
          dispose,
        });
        agentV2BackgroundQueueListeners.forEach((listener) => listener());
        releaseDrainedAgentV2Queues();
      }
    };
  }, [
    controllers, deletionState, disposalState, dispatch, failOpeningQuestion, isDeferredDiscussion, isUnmountedRef,
    resolvedThreadIdRef,
    initialMessageRef, isHeaderSupportPendingRef, isObservingPendingThreadRef, localState,
    openingQuestionAccountRef, ownThreadResolutionRef,
    resolvingThreadIdRef, sendPendingQuestion, sentOpeningQuestionRef,
    stateRef, targetRef,
  ]);

  // A chat that opens again takes over the questions it left queued, and those a wallet switch failed, once its history
  // has loaded, by when the answer still running has been replayed to it and holds them back
  const threadId = state.thread?.id;
  const isHistoryLoaded = Boolean(state.hasHydratedHistory && !state.isLoading && !state.isShowingCachedHistory);
  useEffect(() => {
    if (!threadId || !isHistoryLoaded) return undefined;
    function restoreLeftQueue() {
      if (isUnmountedRef.current) return;
      if (isObservingPendingThreadRef.current && observedThreadResolutionRef.current?.takeOpeningQuestion
        && !localState.backgroundQueues.get(threadId!)?.hasFailures()) return;
      const left = takeAgentV2BackgroundQueue(threadId!);
      if (!left) return;
      const backgroundQueue = localState.backgroundQueues.get(threadId!);
      if (isObservingPendingThreadRef.current && (!backgroundQueue || backgroundQueue.isDone())) {
        isObservingPendingThreadRef.current = false;
        void controllers.hydration.hydrate(true, true);
      }
      if (left.heldRun) controllers.run.restoreHeldLimitRun(left.heldRun);
      // The messages take ids of this chat's own
      const adopt = (message: AgentMessage) => ({ ...message, id: controllers.stream.createLocalMessageId() });
      dispatch({
        kind: 'leftQueueRestored',
        queuedMessages: left.queuedMessages.map(adopt),
        failedQueue: left.failedQueue && {
          messages: left.failedQueue.messages.map(adopt),
          failure: adopt(left.failedQueue.failure),
        },
      });
      controllers.run.sendQueuedMessage();
    }
    agentV2BackgroundQueueListeners.add(restoreLeftQueue);
    restoreLeftQueue();
    return () => {
      agentV2BackgroundQueueListeners.delete(restoreLeftQueue);
    };
  }, [controllers, dispatch, isHistoryLoaded, isObservingPendingThreadRef, isUnmountedRef, localState,
    observedThreadResolutionRef, state.run.phase, threadId]);

  // A queue held while the chat loads goes on once it has loaded
  useEffect(() => {
    if (!state.isLoading) controllers.run.sendQueuedMessage();
  }, [controllers, state.isLoading]);

  useEffect(() => {
    if (!isActive || !stateRef.current.isShowingCachedHistory) return;
    void controllers.hydration.hydrate(true, true);
  }, [controllers, isActive, stateRef]);

  useEffect(() => {
    if (!isActive || deletionState.isRequested || state.isConsentAccepted !== undefined) return undefined;

    let isCurrent = true;
    const resolveConsent = (isAccepted: boolean) => {
      // A news discussion reads its thread and post without consent, so it loads as an allowed chat does; what it
      // would send asks for consent first
      hasActualConsentRef.current = isAccepted;
      const canLoad = isAccepted || getIsNewsTarget(targetRef.current);
      dispatch({ kind: 'consentResolved', isAccepted: canLoad });
      // A bound chat that opens again during its thread's answer keeps the answer its updates replayed
      if (isDeferredDiscussion && !initialMessageRef.current && !resolvedThreadIdRef.current
        && !isObservingPendingThreadRef.current) {
        dispatch({ kind: 'hydrationFailed' });
        if (isAccepted) void prepareSend();
      } else if (canLoad) {
        void controllers.hydration.hydrate(Boolean(targetRef.current));
      }
    };
    // The chat list has read the consent already
    if (hasConsent) {
      resolveConsent(true);
      return undefined;
    }

    // Asked again once the SDK is ready: before that the question has no answer
    const checkConsent = () => {
      void callApi('getAgentV2Consent').then((isAccepted) => {
        if (!isCurrent || deletionState.isRequested || typeof isAccepted !== 'boolean') return;
        resolveConsent(isAccepted);
      });
    };
    dispatch({ kind: 'consentLoadingStarted' });
    const unsubscribe = subscribeToAgentV2RuntimeReady(checkConsent);
    checkConsent();
    return () => {
      isCurrent = false;
      unsubscribe();
    };
  }, [controllers, deletionState, dispatch, hasActualConsentRef, hasConsent, initialMessageRef, isActive,
    isDeferredDiscussion,
    isObservingPendingThreadRef, prepareSend, resolvedThreadIdRef, state.isConsentAccepted, targetRef]);

  useEffect(() => {
    if (isActive && hasConsent && isDeferredDiscussion && !resolvedThreadIdRef.current) void prepareSend();
  }, [hasConsent, isActive, isDeferredDiscussion, prepareSend, resolvedThreadIdRef]);

  const checkConsentAgain = useLastCallback(() => {
    dispatch({ kind: 'consentReset' });
  });

  useEffect(() => {
    if (isActive) controllers.hydration.pickStarterHints();
  }, [controllers, isActive]);

  useEffect(() => {
    const wasActive = wasActiveRef.current;
    wasActiveRef.current = isActive;
    if (!isActive || wasActive || state.isConsentAccepted !== true || !state.error) return;
    void controllers.hydration.hydrate();
  }, [controllers, isActive, state.error, state.isConsentAccepted]);

  const { loadedOperatorMessageAt } = state;
  const canEditMessages = !getIsAgentV2SupportActive(state.thread);
  const markSupportSeen = useLastCallback(() => {
    // A summary from the chat list or an older page announces a reply before it loads, so only loaded history counts
    const { thread, loadedOperatorMessageAt: operatorMessageAt } = stateRef.current;
    if (isChatVisible() && thread && operatorMessageAt) {
      markAgentThreadSupportSeen(thread.id, operatorMessageAt);
    }
  });
  const refreshSupportHistory = useLastCallback(() => {
    if (getIsAgentV2SupportActive(stateRef.current.thread)) {
      void controllers.hydration.refreshLatestMessages();
    } else {
      controllers.hydration.resumeLatestRefresh();
    }
  });
  useInterval(refreshSupportHistory, isActive && !canEditMessages ? SUPPORT_POLLING_INTERVAL_MS : undefined, true);
  useEffect(() => {
    markSupportSeen();
  }, [isActive, loadedOperatorMessageAt, markSupportSeen, threadId]);
  useEffectWithPrevDeps(([wasActive]) => {
    if (isActive && wasActive === false) refreshSupportHistory();
  }, [isActive, refreshSupportHistory]);
  useEffect(() => {
    if (!isActive) return undefined;
    const handleReturn = () => {
      markSupportSeen();
      refreshSupportHistory();
    };
    const handleList = (threads: AgentThreadSummaryV2[]) => {
      const current = stateRef.current.thread;
      const listed = threads.find(({ id }) => id === current?.id);
      if (current && listed && listed.revision >= current.revision
        && (listed.support?.state !== current.support?.state
          || listed.support?.lastOperatorMessageAt !== current.support?.lastOperatorMessageAt)) {
        void controllers.hydration.refreshLatestMessages();
      }
    };
    document.addEventListener('visibilitychange', handleReturn);
    window.addEventListener('focus', handleReturn);
    agentThreadListListeners.add(handleList);
    return () => {
      document.removeEventListener('visibilitychange', handleReturn);
      window.removeEventListener('focus', handleReturn);
      agentThreadListListeners.delete(handleList);
      controllers.hydration.cancelLatestRefresh();
    };
  }, [controllers, isActive, markSupportSeen, refreshSupportHistory, stateRef]);
  const requestProblemReportAvailability = useLastCallback(() => {
    const availability = callApi('getAgentV2ProblemReportAvailability').then(Boolean);
    problemReportAvailabilityRef.current = availability;
    void availability.then((isAvailable) => {
      if (problemReportAvailabilityRef.current === availability) setIsProblemReportAvailable(isAvailable);
    });
    return availability;
  });
  useEffect(() => {
    if (!isActive || hasConsent === false) return;
    void requestProblemReportAvailability();
  }, [hasConsent, isActive, requestProblemReportAvailability]);

  const activateAction = useLastCallback((
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => {
    const sourceId = controllers.stream.getSourceId(messageId);
    if (!sourceId || stateRef.current.isHistoryCached) return;
    if (action.kind === 'send') {
      void activateSendAction(messageId, sourceId, action);
      return;
    }
    const authorityKey = buildAgentV2ActionAuthorityKey(selectAgentV2HostContext(getGlobal()));
    const generation = controllers.stream.getActionPresentationGeneration();
    void callApi('resolveAgentV2Action', sourceId, action.id).then((resolved) => {
      if (!resolved || generation !== controllers.stream.getActionPresentationGeneration()) return;
      const currentAuthorityKey = buildAgentV2ActionAuthorityKey(selectAgentV2HostContext(getGlobal()));
      if (currentAuthorityKey !== authorityKey) return;
      if (resolved.kind === 'inactive') {
        showActionUnavailable(sourceId, action.id, resolved, generation);
        return;
      }
      dispatchResolvedAction(resolved);
    });
  });

  const reportProblem = useLastCallback(async (
    messageId: number | undefined,
    comment: string,
  ): Promise<AgentProblemReportOutcome> => {
    if (isDeferredDiscussion && !resolvedThreadIdRef.current) return 'failed';
    // The connection error bubble has no stored message and reports the conversation. An answer that lost its stored
    // message since the form opened is not reported as the conversation in its place.
    const isFailureMessage = messageId === ERROR_MESSAGE_ID || messageId === SUPPORT_ERROR_MESSAGE_ID;
    const sourceId = messageId === undefined || isFailureMessage
      ? undefined
      : controllers.stream.getSourceId(messageId);
    if (messageId !== undefined && !isFailureMessage && !sourceId) return 'failed';
    // A report sent while the chat creates its thread, or before the server says whether it takes reports, waits
    const [reportedThreadId, isAvailable] = await Promise.all([
      waitForThreadId(),
      problemReportAvailabilityRef.current ?? requestProblemReportAvailability(),
    ]);
    if (!reportedThreadId || !isAvailable) return 'failed';
    const result = await callApi('reportAgentV2Problem', reportedThreadId, {
      ...(sourceId ? { messageId: sourceId } : {}),
      ...(comment ? { comment } : {}),
    });
    if (result?.ok) return 'sent';
    // A server that has switched reports off refuses them, and asking again takes the report items away
    void requestProblemReportAvailability();
    return result?.error.code === 'rate_limited' ? 'rateLimited' : 'failed';
  });

  const rateMessage = useLastCallback(async (messageId: number, feedback?: AgentAnswerFeedbackV2) => {
    const { thread, messages: currentMessages, isHistoryCached } = stateRef.current;
    const message = currentMessages.find(({ id }) => id === messageId);
    const sourceId = controllers.stream.getSourceId(messageId);
    if (!thread || !sourceId || !message?.isComplete || isHistoryCached) return;
    const request = { feedback };
    const requests = feedbackRequestsRef.current.get(sourceId) ?? { latest: request, saved: message.feedback };
    requests.latest = request;
    feedbackRequestsRef.current.set(sourceId, requests);
    dispatch({ kind: 'messageFeedbackChanged', messageId, feedback });
    const result = await callApi('setAgentV2MessageFeedback', thread.id, sourceId, feedback);
    if (result?.ok) requests.saved = result.value.feedback;
    if (requests.latest !== request) return;
    feedbackRequestsRef.current.delete(sourceId);
    // A cleared chat no longer shows the answer
    const currentMessageId = findAgentV2MessageId(stateRef.current, sourceId);
    if (currentMessageId === undefined) return;
    dispatch({ kind: 'messageFeedbackChanged', messageId: currentMessageId, feedback: requests.saved });
    if (!result?.ok) showError({ error: '$agent_feedback_failed' });
    if (!result?.ok || !feedback || requests.saved !== feedback) return;

    return getIsCurrentFeedback;

    function getIsCurrentFeedback() {
      const current = stateRef.current;
      if (!current) return false;

      const ratedMessageId = findAgentV2MessageId(current, sourceId!);
      return current.messages.some(({ id, feedback: currentFeedback }) => (
        id === ratedMessageId && currentFeedback === feedback
      ));
    }
  });

  const refreshExpiredComposerStatus = useLastCallback(() => {
    dispatch({ kind: 'composerStatusExpired' });
    // The queue waits while a limit holds, and goes on once it has reset
    controllers.run.sendQueuedMessage();
  });

  const retryMessage = useLastCallback((messageId: number) => {
    const { admissionFailure, failedQueue } = stateRef.current;
    if (messageId === failedQueue?.failure.id) {
      controllers.run.retryFailedQueue();
      return;
    }
    if (messageId === ERROR_MESSAGE_ID
      || (messageId === admissionFailure?.retryMessageId && admissionFailure.clientRunId)) {
      controllers.run.retryAdmission();
      return;
    }
    controllers.run.retryMessage(messageId);
  });

  const sendMessage = useLastCallback((text: string, editMessageId?: number) => {
    if (getIsObservingOpeningQuestion() || (isDeferredDiscussion && initialMessageRef.current)) return false;
    if (!isDeferredDiscussion || stateRef.current.hasHydratedHistory) {
      return controllers.run.sendOrQueueMessage(text, editMessageId);
    }
    if (stateRef.current.isConsentAccepted !== true || !getCanSendDiscussion()) return false;
    const trimmed = text.trim();
    if (!trimmed || deletionState.isRequested) return false;
    initialMessageRef.current = trimmed;
    initialHintEntryPointRef.current = undefined;
    openingQuestionAccountRef.current = {
      accountId: selectAgentV2HostContext(getGlobal()).activeAccountId, hasChanged: false,
    };
    const question: AgentMessage = {
      id: controllers.stream.createLocalMessageId(),
      text: hideSecretPhrases(trimmed),
      isOutgoing: true,
      timestamp: Date.now(),
    };
    pendingQuestionRef.current = question;
    setPendingQuestion(question);
    void controllers.hydration.hydrate(true);
    return true;
  });

  const requestSupport = useLastCallback((source: AgentV2SupportRequestSource) => {
    const current = stateRef.current;
    if (source !== 'header' || !getIsDeferredDiscussion(targetRef.current) || current.hasHydratedHistory) {
      return controllers.run.requestSupport(source);
    }
    if (!getCanCreateDiscussionThreadForSupport() || !selectCanRequestAgentV2Support(current, undefined, true)) {
      return false;
    }
    const openingAccount = {
      accountId: selectAgentV2HostContext(getGlobal()).activeAccountId, hasChanged: false,
    };
    openingQuestionAccountRef.current = openingAccount;
    isHeaderSupportPendingRef.current = true;
    void controllers.hydration.hydrate(true).then((isHydrated) => {
      const target = targetRef.current;
      const resolution = ownThreadResolutionRef.current;
      if (getIsDiscussionTarget(target) && resolution) {
        delete resolution.takeOpeningQuestion;
        forgetPendingDiscussionThread(target, resolution);
      }
      if (!isHydrated || !isHeaderSupportPendingRef.current || openingAccount.hasChanged
        || openingAccount.accountId !== selectAgentV2HostContext(getGlobal()).activeAccountId
        || deletionState.isRequested || disposalState.isDisposed
        || localState !== getAgentV2LocalState()) return;
      controllers.run.requestSupport(source);
    }).finally(() => {
      if (openingQuestionAccountRef.current === openingAccount) openingQuestionAccountRef.current = undefined;
      if (!controllers.run.hasPendingAdmission()) isHeaderSupportPendingRef.current = false;
      releaseDrainedAgentV2Queues();
    });
    return true;
  });

  const sendFollowup = useLastCallback((messageId: number, followup: AgentPublicFollowUpV2) => {
    if (getIsObservingOpeningQuestion() || (isDeferredDiscussion && initialMessageRef.current)) return;
    if (isDeferredDiscussion && !stateRef.current.hasHydratedHistory) {
      if (stateRef.current.isConsentAccepted !== true || !getCanSendDiscussion()) return;
      pendingFollowupTextRef.current = followup.text;
      sendMessage(followup.text);
      return;
    }
    const sourceMessageId = messageId === NEWS_POST_MESSAGE_ID
      ? stateRef.current.messages.find(({ isNewsPost }) => isNewsPost)?.id
      : messageId;
    if (sourceMessageId === undefined) return;
    controllers.run.sendFollowup(sourceMessageId, followup);
  });

  const isMessageRegenerable = useLastCallback((messageId: number) => {
    const current = stateRef.current;
    const message = current.messages.find(({ id }) => id === messageId);
    return Boolean(
      !getIsAgentV2SupportActive(current.thread)
      && !current.isHistoryCached
      && message && !message.isOutgoing && !message.isNewsPost && !message.operator && !message.supportEvent
      && !message.isTyping && !message.isStreaming
      && current.sourceIdByMessageId[messageId],
    );
  });

  const isMessageEditable = useLastCallback((messageId: number) => {
    const current = stateRef.current;
    const message = current.messages.find(({ id }) => id === messageId);
    return canEditMessages && !current.isHistoryCached
      && Boolean(message?.isOutgoing && current.sourceIdByMessageId[messageId]);
  });

  // A chat that shows its cached history is complete while that history loads again
  const isInitialLoadComplete = state.isConsentAccepted === true
    && (!state.isLoading || Boolean(state.isShowingCachedHistory));

  // The failure stays, saying it is being retried, until the history loads or fails again
  const [retriedHistoryFailure, setRetriedHistoryFailure] = useState<string | undefined>();
  const retryHistory = useLastCallback(() => {
    const error = stateRef.current.error;
    if (!error?.isHistoryFailure) return;

    if (isDeferredDiscussion && initialMessageRef.current) {
      openingQuestionAccountRef.current = {
        accountId: selectAgentV2HostContext(getGlobal()).activeAccountId, hasChanged: false,
      };
    }
    setRetriedHistoryFailure(error.text);
    void controllers.hydration.hydrate();
  });

  useEffect(() => {
    if (!state.isLoading) setRetriedHistoryFailure(undefined);
  }, [state.isLoading]);

  const historyFailure = useMemo(() => (state.error?.isHistoryFailure
    ? { text: state.error.text, isRetrying: false }
    : (retriedHistoryFailure && state.isLoading ? { text: retriedHistoryFailure, isRetrying: true } : undefined)
  ), [retriedHistoryFailure, state.error, state.isLoading]);
  const isThreadRequired = (!state.thread && !isDeferredDiscussion)
    || getIsObservingOpeningQuestion()
    || (isDeferredDiscussion && !state.hasHydratedHistory && (state.isConsentAccepted !== true || isSendStatusLoading
      || (hasActualConsentRef.current && !hasLoadedSendStatusRef.current)
      || (Boolean(pendingQuestion) && !state.hasHydratedHistory)));
  const isInputDisabled = isThreadRequired || selectIsAgentV2InputDisabled(state, isComposerBlocked);
  const isSendDisabled = isThreadRequired || selectIsAgentV2SendDisabled(state, isComposerBlocked);
  const canCreateThreadForSupport = getCanCreateDiscussionThreadForSupport();
  const canRequestSupport = (!isDeferredDiscussion || state.hasHydratedHistory || canCreateThreadForSupport)
    && selectCanRequestAgentV2Support(state, undefined, canCreateThreadForSupport);
  // The Agent is taken to be analyzing the question while the chat gets its thread ready
  const isQuestionWaiting = Boolean(pendingQuestion) && !isInitialLoadComplete;

  useEffect(() => {
    if (isActive) sendPendingQuestion();
  }, [
    canRequestSupport, isActive, isInitialLoadComplete, isInputDisabled, pendingQuestion, sendPendingQuestion,
    state.messages, state.thread,
  ]);

  return {
    messages: visibleMessages,
    thread: state.thread,
    support: state.thread?.support,
    news,
    digest,
    isOpeningNews,
    hints: isNewsThread ? undefined : hints,
    activity: selectAgentV2Activity(state) ?? (isQuestionWaiting ? ANALYZING_REQUEST_ACTIVITY : undefined),
    isInitialLoadComplete,
    isHistoryCached: state.isHistoryCached,
    isOpenedWithCachedHistory,
    hasPendingQuestion: Boolean(pendingQuestion),
    isInputDisabled,
    isSendDisabled,
    isSendQueued: selectIsAgentV2SendQueued(state),
    sentQueuedMessage,
    queuedMessageCount: state.queuedMessages.length + (state.failedQueue ? state.failedQueue.messages.length + 1 : 0),
    failedQueueFailureId: state.failedQueue?.failure.id,
    isRunActive: selectIsAgentV2RunActive(state) || isQuestionWaiting,
    canStopRun: controllers.run.canStopRun(),
    stopRun: controllers.run.stopRun,
    textRevealPresentations,
    hasOlderMessages: Boolean(state.nextCursor),
    isLoadingOlderMessages: state.isLoadingOlderMessages,
    loadOlderMessages: controllers.hydration.loadOlderMessages,
    historyFailure,
    retryHistory,
    isConsentAccepted: state.isConsentAccepted,
    checkConsentAgain,
    composerStatus,
    prepareSend,
    sendMessage,
    sendHint: controllers.run.sendHint,
    requestSupport,
    isSupportRequestVisible: getIsAgentV2SupportEntryVisible(state.thread ?? initialThread),
    canRequestSupport,
    sendFollowup,
    clearChat: controllers.run.clearChat,
    cancelPendingRequests,
    reportProblem: !isUncreatedDiscussion && hasConsent !== false && isProblemReportAvailable
      ? reportProblem
      : undefined,
    rateMessage,
    retryMessage,
    isMessageRegenerable,
    isMessageEditable,
    retryAdmission: controllers.run.retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession: controllers.stream.consumeTextRevealSession,
    settleTextRevealSession: controllers.stream.settleTextRevealSession,
  };

  async function prepareDiscussionSend() {
    if (!getIsDeferredDiscussion(targetRef.current) || stateRef.current.thread) {
      return !getIsComposerBlocked();
    }
    if (deletionState.isRequested || disposalState.isDisposed || localState !== getAgentV2LocalState()) return false;
    if (!hasLoadedSendStatusRef.current) {
      if (!sendStatusRequestRef.current) {
        setIsSendStatusLoading(true);
        sendStatusRequestRef.current = loadDiscussionSendStatus().finally(() => {
          sendStatusRequestRef.current = undefined;
          if (!isUnmountedRef.current) setIsSendStatusLoading(false);
        });
      }
      await sendStatusRequestRef.current;
    }
    return getCanSendDiscussion();
  }

  async function loadDiscussionSendStatus() {
    if (!hasActualConsentRef.current) {
      const isAccepted = await callApi('getAgentV2Consent').catch(() => undefined);
      if (isAccepted !== true) return;
      hasActualConsentRef.current = true;
    }
    await Promise.all([
      callApi('getAgentV2Availability').catch(() => undefined),
      callApi('getAgentV2UserQuota').catch(() => undefined),
    ]);
    if (deletionState.isRequested || disposalState.isDisposed || localState !== getAgentV2LocalState()) return;
    hasLoadedSendStatusRef.current = true;
  }

  function getCanCreateDiscussionThreadForSupport() {
    return getIsDeferredDiscussion(targetRef.current) && !stateRef.current.thread && !stateRef.current.isLoading
      && hasActualConsentRef.current && hasLoadedSendStatusRef.current && !sendStatusRequestRef.current
      && !initialMessageRef.current && !getIsObservingOpeningQuestion()
      && !deletionState.isRequested && !disposalState.isDisposed && localState === getAgentV2LocalState();
  }

  function getCanSendDiscussion() {
    return hasActualConsentRef.current && hasLoadedSendStatusRef.current && !sendStatusRequestRef.current
      && !deletionState.isRequested && !disposalState.isDisposed && localState === getAgentV2LocalState()
      && !stateRef.current.isLoading && !getIsComposerBlocked();
  }

  function getIsComposerBlocked() {
    const current = stateRef.current;
    return isAgentV2ComposerBlocked(selectAgentV2ComposerStatusForState(current));
  }

  function getIsObservingOpeningQuestion() {
    if (isObservingPendingThreadRef.current && observedThreadResolutionRef.current?.takeOpeningQuestion) return true;
    const threadId = stateRef.current.thread?.id ?? resolvedThreadIdRef.current;
    return Boolean(threadId && localState.backgroundQueues.get(threadId)?.hasOpeningQuestion());
  }

  function sendOpeningQuestion() {
    const current = stateRef.current;
    const text = initialMessageRef.current;
    const question = pendingQuestionRef.current;
    const thread = current.thread;
    const isDeferredDiscussion = getIsDeferredDiscussion(targetRef.current);
    const isComposerBlocked = isAgentV2ComposerBlocked(selectAgentV2ComposerStatusForState(current));
    if (deletionState.isRequested || disposalState.isDisposed || localState !== getAgentV2LocalState()
      || !question || !text || !thread || current.isConsentAccepted !== true
      || (current.isLoading && !current.isShowingCachedHistory)
      || (isDeferredDiscussion && !current.hasHydratedHistory)
      || isAgentV2QueueHeld(thread.id)) return false;
    const openingAccount = openingQuestionAccountRef.current;
    if (openingAccount && (openingAccount.hasChanged
      || openingAccount.accountId !== selectAgentV2HostContext(getGlobal()).activeAccountId)) {
      failOpeningQuestion(undefined);
      return false;
    }
    if (isUnmountedRef.current && isDeferredDiscussion && (isComposerBlocked || selectIsAgentV2RunActive(current))) {
      takeOpeningQuestion();
      dispatch({ kind: 'messageQueued', message: question });
      controllersRef.current!.run.sendQueuedMessage();
      agentV2BackgroundQueueListeners.forEach((listener) => listener());
      return true;
    }
    if (!isInitialSupportRequest && selectIsAgentV2InputDisabled(current, isComposerBlocked)) return false;
    const post = current.messages.find(({ isNewsPost }) => isNewsPost);
    const followup = pendingFollowupTextRef.current
      ? post?.followups?.find(({ text: savedText }) => savedText === pendingFollowupTextRef.current)
      : undefined;
    const isSent = isInitialSupportRequest
      ? controllersRef.current!.run.requestSupport('starterHint', question)
      : (post && followup
        ? controllersRef.current!.run.sendFollowup(post.id, followup, question)
        : controllersRef.current!.run.sendMessage(text, undefined, question, initialHintEntryPointRef.current));
    if (!isSent) return false;
    sentOpeningQuestionRef.current = question;
    initialMessageRef.current = undefined;
    initialHintEntryPointRef.current = undefined;
    pendingFollowupTextRef.current = undefined;
    pendingQuestionRef.current = undefined;
    openingQuestionAccountRef.current = undefined;
    if (!isUnmountedRef.current) {
      setPendingQuestion(undefined);
      onInitialMessageSentRef.current?.();
    }
    return true;
  }

  function failPendingOpeningQuestion(error: AgentV2MessagesState['error']) {
    const question = pendingQuestionRef.current;
    if (!question || !resolvedThreadIdRef.current || !getIsDeferredDiscussion(targetRef.current)) return;
    takeOpeningQuestion();
    dispatch({ kind: 'messageQueued', message: question });
    dispatch({
      kind: 'queuedMessagesFailed',
      failure: {
        id: controllersRef.current!.stream.createLocalMessageId(),
        text: '',
        isOutgoing: false,
        timestamp: error?.timestamp ?? Date.now(),
        ...(error ? { failureText: error.text } : { error: { code: 'internal_error' as const, retryable: true } }),
      },
    });
    agentV2BackgroundQueueListeners.forEach((listener) => listener());
  }

  function redactQuestion(text: string) {
    return removeSecretPhrases(text, getSecretPhraseWordList(), langRef.current('$agent_secret_words_removed'));
  }

  function getSupportRequestText() {
    return langRef.current('$agent_support_request_message');
  }

  function resolveThreadId(): Promise<AgentV2MutationResult<string> | undefined> {
    if (deletionState.isRequested) return Promise.resolve(undefined);
    const resolvedThreadId = resolvedThreadIdRef.current;
    if (resolvedThreadId) return Promise.resolve({ ok: true, value: resolvedThreadId });
    if (!targetRef.current) return requestThreadId();

    if (!resolvingThreadIdRef.current) {
      const chatTarget = targetRef.current;
      const observedResolution = observedThreadResolutionRef.current ?? findThreadResolution(chatTarget, localState);
      if (observedResolution) isObservingPendingThreadRef.current = true;
      const resolution: AgentV2ThreadResolution = (
        observedResolution ? observeThreadResolution(observedResolution) : requestThreadId()
      )
        .then((result) => {
          if (!result?.ok && getIsDiscussionTarget(chatTarget) && chatTarget.threadResolution?.promise === resolution) {
            forgetPendingDiscussionThread(chatTarget, chatTarget.threadResolution);
            delete chatTarget.threadResolution;
          }
          return result;
        }).finally(() => {
          resolvingThreadIdRef.current = undefined;
        });
      resolvingThreadIdRef.current = resolution;
      if (!observedResolution && getIsDiscussionTarget(chatTarget) && chatTarget.shouldDeferCreation) {
        chatTarget.threadResolution = { promise: resolution, localState, getOpeningQuestion, takeOpeningQuestion };
        ownThreadResolutionRef.current = chatTarget.threadResolution;
        localState.pendingDiscussionThreads.set(buildDiscussionKey(chatTarget), chatTarget.threadResolution);
      }
    }
    return resolvingThreadIdRef.current;
  }

  async function observeThreadResolution(resolution: AgentV2DiscussionThreadResolution) {
    const result = await resolution.promise;
    if (deletionState.isRequested) return result;
    if (disposalState.isDisposed || localState !== getAgentV2LocalState()) return undefined;
    if (!result?.ok) {
      observedThreadResolutionRef.current = undefined;
      if (isUnmountedRef.current) return result;
      const pending = resolution.takeOpeningQuestion?.();
      if (!pending) return result;
      initialMessageRef.current = pending.text;
      initialHintEntryPointRef.current = undefined;
      pendingFollowupTextRef.current = pending.followupText;
      pendingQuestionRef.current = { ...pending.question, id: controllers.stream.createLocalMessageId() };
      openingQuestionAccountRef.current = { accountId: pending.accountId, hasChanged: pending.hasAccountChanged };
      isObservingPendingThreadRef.current = false;
      setPendingQuestion(pendingQuestionRef.current);
      return result;
    }
    resolvedThreadIdRef.current = result.value;
    onThreadResolvedRef.current?.(result.value);
    return result;
  }

  function takeOpeningQuestion() {
    if (isHeaderSupportPendingRef.current) {
      isHeaderSupportPendingRef.current = false;
      releaseDrainedAgentV2Queues();
    }
    const text = initialMessageRef.current;
    const question = pendingQuestionRef.current;
    if (!text || !question || deletionState.isRequested || localState !== getAgentV2LocalState()) return undefined;
    const followupText = pendingFollowupTextRef.current;
    const openingAccount = openingQuestionAccountRef.current;
    initialMessageRef.current = undefined;
    initialHintEntryPointRef.current = undefined;
    pendingFollowupTextRef.current = undefined;
    pendingQuestionRef.current = undefined;
    openingQuestionAccountRef.current = undefined;
    const target = targetRef.current;
    if (getIsDiscussionTarget(target) && target.threadResolution?.takeOpeningQuestion === takeOpeningQuestion) {
      delete target.threadResolution.takeOpeningQuestion;
      forgetPendingDiscussionThread(target, target.threadResolution);
    }
    if (!isUnmountedRef.current) setPendingQuestion(undefined);
    return {
      text, question, followupText,
      accountId: openingAccount?.accountId, hasAccountChanged: openingAccount?.hasChanged ?? false,
    };
  }

  function getOpeningQuestion() {
    return initialMessageRef.current ? pendingQuestionRef.current : sentOpeningQuestionRef.current;
  }

  function waitForThreadId() {
    const threadId = stateRef.current.thread?.id;
    if (threadId) return Promise.resolve(threadId);
    return resolveThreadId().then((result) => (result?.ok ? result.value : undefined));
  }

  async function requestThreadId(): Promise<AgentV2MutationResult<string> | undefined> {
    const chatTarget = targetRef.current;
    const notifyThreadResolved = onThreadResolvedRef.current;
    const result = await resolveTargetThread(chatTarget).catch(() => undefined);
    if (!result?.ok) return result;
    const threadId = result.value.thread.id;
    if (deletionState.isRequested) return { ok: true, value: threadId };
    if (localState !== getAgentV2LocalState()) return undefined;
    createdNewsRef.current = result.value.thread.news;
    if (chatTarget) {
      resolvedThreadIdRef.current = threadId;
      if (!isUnmountedRef.current) {
        if (getIsDiscussionTarget(chatTarget)) {
          dispatch({ kind: 'threadChanged', thread: result.value.thread });
        }
      }
      // An in-flight creation can resolve its original selection after the chat has closed
      notifyThreadResolved?.(threadId);
    }
    return { ok: true, value: threadId };
  }

  function resolveTargetThread(chatTarget?: AgentV2ChatTarget) {
    switch (chatTarget?.kind) {
      case 'new':
        return callApi('createAgentV2Thread');
      case 'news':
        return callApi('createAgentV2Thread', { news: chatTarget.news });
      case 'digest':
        return callApi('createAgentV2Thread', { digest: chatTarget.digest });
      default:
        return callApi('getAgentV2DefaultThread');
    }
  }

  async function activateSendAction(messageId: number, sourceId: string, action: AgentV2SendAction) {
    const lifecycleGeneration = controllers.stream.getActionLifecycleGeneration();
    let presentationGeneration = controllers.stream.getActionPresentationGeneration();
    const presentation = stateRef.current.messages
      .find((message) => message.id === messageId)
      ?.actionPresentations?.[action.id];
    if (!isActiveSendPresentation(presentation)) {
      showActionUnavailable(
        sourceId, action.id, presentation?.kind === 'inactive' ? presentation : { kind: 'inactive' },
      );
      return;
    }

    const initialHostContext = selectAgentV2HostContext(getGlobal());
    const initialAuthorityKey = buildAgentV2SendAuthorityKey(initialHostContext);
    if (!initialAuthorityKey) {
      showActionUnavailable(sourceId, action.id, { kind: 'inactive' });
      return;
    }

    try {
      const hasAuthorityChanged = await synchronizeHostContext(initialHostContext);
      const synchronizedAuthorityKey = buildAgentV2SendAuthorityKey(selectAgentV2HostContext(getGlobal()));
      const synchronizedGeneration = controllers.stream.getActionPresentationGeneration();
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      if (
        hasAuthorityChanged === undefined
        || synchronizedAuthorityKey !== initialAuthorityKey
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, synchronizedGeneration);
        return;
      }
      presentationGeneration = synchronizedGeneration;

      const resolved = await callApi('resolveAgentV2Action', sourceId, action.id);
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      const currentHostContext = selectAgentV2HostContext(getGlobal());
      const hasCurrentAuthorityChanged = await synchronizeHostContext(currentHostContext);
      const currentAuthorityKey = buildAgentV2SendAuthorityKey(selectAgentV2HostContext(getGlobal()));
      const currentGeneration = controllers.stream.getActionPresentationGeneration();
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      if (
        hasCurrentAuthorityChanged === undefined
        || currentAuthorityKey !== initialAuthorityKey
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, currentGeneration);
        return;
      }
      presentationGeneration = currentGeneration;
      const currentMessage = stateRef.current.messages.find((message) => message.id === messageId);
      if (!currentMessage?.actions?.some(({ id }) => id === action.id)) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, presentationGeneration);
        return;
      }
      if (resolved?.kind !== 'sendForm') {
        showActionUnavailable(
          sourceId, action.id, resolved?.kind === 'inactive' ? resolved : { kind: 'inactive' }, presentationGeneration,
        );
        return;
      }

      dispatchResolvedAction(resolved);
    } catch {
      controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, presentationGeneration);
    }
  }

  function showActionUnavailable(
    sourceId: string,
    actionId: string,
    inactive: AgentV2InactiveAction,
    generation?: number,
  ) {
    controllers.stream.setActionPresentation(sourceId, actionId, inactive, generation);
    showError({
      error: inactive.reason === 'viewOnlyWallet'
        ? '$action_not_available_view_mode'
        : 'This action is no longer available.',
    });
  }

  function dispatchResolvedAction(resolved: AgentV2ResolvedAction) {
    switch (resolved.kind) {
      case 'openReceive':
        if (getIsSupportedChain(resolved.chain)) openReceiveModal({ chain: resolved.chain });
        return;
      case 'openStaking': {
        void processDeeplink(buildStakingDeeplink(resolved));
        return;
      }
      case 'openSwap':
        if (isSelfDeeplink(resolved.url)) {
          const global = getGlobal();
          if (!getAgentV2ActionAvailability(selectAgentV2HostContext(global)).canPrepareSwap) return;
          const tokensBySlug = global.swapTokenInfo?.bySlug;
          if ((resolved.tokenInSlug && !tokensBySlug?.[resolved.tokenInSlug])
            || (resolved.tokenOutSlug && !tokensBySlug?.[resolved.tokenOutSlug])) {
            showError({ error: '$unknown_swap_token' });
            return;
          }
          startSwap({
            tokenInSlug: resolved.tokenInSlug,
            tokenOutSlug: resolved.tokenOutSlug,
            amountIn: resolved.amountSide === 'source' ? resolved.amount : undefined,
          });
          if (resolved.amountSide === 'destination' && resolved.amount) {
            setSwapAmountOut({ amount: resolved.amount });
          }
        } else if (isSafeHttpsUrl(resolved.url)) {
          void openUrl(resolved.url);
        }
        return;
      case 'sendForm': {
        if (resolved.url === 'mtw://send') {
          startTransfer({ shouldRequireFreshAuth: true });
          return;
        }
        const url = new URL(resolved.url);
        if (url.protocol !== 'mtw:' || url.hostname !== 'send') return;
        const global = getGlobal();
        const params = parseDeeplinkTransferParams(resolved.url, global);
        if (!params) return;
        const { error, ...transferParams } = params;
        // The runtime already matched the asset; the parser sees no held tokens until balances load
        const requestedTokenSlug = error === '$dont_have_required_token' && !selectCurrentAccountState(global)?.balances
          ? url.searchParams.get('token') ?? undefined
          : undefined;
        if (error && !requestedTokenSlug) {
          showError({ error });
          return;
        }
        const tokenSlug = requestedTokenSlug || transferParams.tokenSlug;
        // As the Max button does before the fee is known: the form takes the fee off once it has it
        const maxAmount = resolved.isMaxAmount && tokenSlug
          ? selectCurrentAccountState(global)?.balances?.bySlug[tokenSlug]
          : undefined;
        startTransfer({
          ...transferParams,
          tokenSlug,
          ...(maxAmount ? { amount: maxAmount } : {}),
          shouldRequireFreshAuth: true,
        });
        return;
      }
      case 'openDapp': {
        const global = getGlobal();
        // A stored button to a screen of the app, such as Multisend, opens it as an answer link does
        if ((resolved.url.startsWith(SELF_PROTOCOL) && isAgentLinkUrl(resolved.url))
          || buildAgentBuiltinDapps(global).some(({ url }) => url === resolved.url)) {
          void processDeeplink(resolved.url);
          return;
        }
        const site = findSiteByUrl(global.exploreData?.sites, resolved.url);
        if (!site || (global.restrictions.isLimitedRegion && site.canBeRestricted)) return;
        openSite(site.url, site.isExternal, site.name);
        return;
      }
      case 'inactive':
        return;
      default:
        assertUnreachable(resolved);
    }
  }
}

// The device keeps the history of a thread the chat opens by its id; a news or digest discussion opens with its post
function canReadCachedHistory(target?: AgentV2ChatTarget, thread?: AgentThreadSummaryV2) {
  return target?.kind === 'thread' && !target.isNews && !target.preview && !thread?.news && !thread?.digest;
}

function getIsDiscussionTarget(target?: AgentV2ChatTarget): target is AgentV2DiscussionTarget {
  return target?.kind === 'news' || target?.kind === 'digest';
}

/**
 * The thread creation a chat of a discussion follows: its target's own, or, for a discussion opened again from the
 * feed, the one still waiting to send the first question of the same news or digest. The feed marks the discussion
 * once its thread is created, before the question is sent, so a discussion opened then follows it too.
 */
function findThreadResolution(
  target: AgentV2ChatTarget | undefined, localState: AgentV2DiscussionThreadResolution['localState'],
) {
  if (!getIsDiscussionTarget(target)) return undefined;
  if (target.threadResolution?.localState === localState) return target.threadResolution;
  return localState.pendingDiscussionThreads.get(buildDiscussionKey(target));
}

function forgetPendingDiscussionThread(
  target: AgentV2DiscussionTarget, resolution: AgentV2DiscussionThreadResolution,
) {
  const key = buildDiscussionKey(target);
  const { pendingDiscussionThreads } = resolution.localState;
  if (pendingDiscussionThreads.get(key) === resolution) pendingDiscussionThreads.delete(key);
}

function buildDiscussionKey(target: AgentV2DiscussionTarget) {
  return target.kind === 'news' ? `news:${target.news.eventId}:${target.news.locale}` : `digest:${target.digest.id}`;
}

function getIsDeferredDiscussion(target?: AgentV2ChatTarget) {
  return getIsDiscussionTarget(target) && Boolean(target.shouldDeferCreation);
}

function getIsNewsTarget(target?: AgentV2ChatTarget) {
  return getIsDiscussionTarget(target) || (target?.kind === 'thread' && Boolean(target.isNews));
}

function buildAgentV2ActionAuthorityKey(host: AgentV2HostContextSnapshot) {
  const activeAccount = host.accounts.find(({ accountId }) => accountId === host.activeAccountId);
  const activeNetwork = host.activeNetwork;
  return JSON.stringify({
    accountId: host.activeAccountId,
    accountType: activeAccount?.accountType,
    state: activeAccount?.state,
    isViewOnly: activeAccount?.isViewOnly,
    network: activeNetwork,
    isTestnet: host.isTestnet,
    address: activeNetwork ? activeAccount?.addresses[activeNetwork] : undefined,
    chains: activeAccount ? [...activeAccount.chains].sort() : undefined,
  });
}

function buildStakingDeeplink({
  productId,
  tokenSlug,
  amount,
}: Extract<AgentV2ResolvedAction, { kind: 'openStaking' }> | Omit<
  Extract<AgentV2ResolvedAction, { kind: 'openStaking' }>, 'kind'
>) {
  const searchParams = new URLSearchParams({ product: productId, asset: tokenSlug });
  if (amount) searchParams.set('amount', amount.kind === 'all' ? 'all' : amount.value);
  return `${SELF_PROTOCOL}stake?${searchParams}`;
}

function isActiveSendPresentation(
  presentation?: AgentV2ActionPresentation,
): presentation is Extract<AgentV2ActionPresentation, { kind: 'send' }> {
  return presentation?.kind === 'send'
    && (!presentation.expiresAt || Date.parse(presentation.expiresAt) > Date.now());
}

function reportIncompatibleHistoryMessages(
  threadId: string,
  messages: AgentV2IncompatibleHistoryMessage[],
) {
  messages.forEach((message) => {
    logDebugError(`Agent V2 ignored incompatible history message: ${JSON.stringify({
      threadId,
      ...message,
    })}`);
  });
}

async function synchronizeHostContext(hostContext: AgentV2HostContextSnapshot) {
  const result = await callApi('updateAgentV2HostContext', hostContext);
  if (!result?.ok) return undefined;
  if (result.value.authorityChanged && !result.value.preservesActiveRuns) cancelAgentV2ActiveRunReplays();
  return result.value.authorityChanged;
}

function isSafeHttpsUrl(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password;
  } catch {
    return false;
  }
}

function applyPendingFeedback(
  state: AgentV2MessagesState,
  requestsBySourceId: Map<string, AgentV2FeedbackRequests>,
) {
  let nextState = state;
  requestsBySourceId.forEach((requests, sourceId) => {
    const messageId = findAgentV2MessageId(nextState, sourceId);
    if (messageId === undefined) return;
    nextState = reduceAgentV2MessagesState(nextState, {
      kind: 'messageFeedbackChanged',
      messageId,
      feedback: requests.latest.feedback,
    });
  });
  return nextState;
}

/**
 * The failure of the latest request that the chat keeps apart from its messages: an admission that failed, or a run
 * that failed outside an answer. A run's failure that its stored answer already tells is not told twice.
 */
function buildLiveFailureMessage(
  admissionFailure: AgentV2MessagesState['admissionFailure'],
  error: AgentV2MessagesState['error'],
  messages: AgentMessage[],
  messageId = ERROR_MESSAGE_ID,
): AgentMessage | undefined {
  if (admissionFailure && admissionFailure.retryMessageId === undefined) {
    return {
      id: messageId,
      text: '',
      isOutgoing: false,
      timestamp: admissionFailure.timestamp,
      error: admissionFailure.error,
      isRetryAvailable: Boolean(admissionFailure.clientRunId),
    };
  }
  // A history that failed to load has its own failure line with Retry, so it is not shown as a failed message
  if (!error || error.isHistoryFailure) return undefined;

  const lastMessage = messages[messages.length - 1];
  if (error.cause && lastMessage && !lastMessage.isOutgoing && lastMessage.error) return undefined;

  return {
    id: messageId,
    text: '',
    isOutgoing: false,
    timestamp: error.timestamp,
    ...(error.cause ? { error: error.cause } : { failureText: error.text }),
  };
}

/** Only the latest failure offers Retry, apart from a request held by a limit */
function keepRetryOnLatestFailure(
  messages: AgentMessage[], lastAdmittedUserMessageIndex: number, heldFailureId: number | undefined,
) {
  let latestFailureIndex = messages.length - 1;
  while (latestFailureIndex >= 0 && !messages[latestFailureIndex].error && !messages[latestFailureIndex].failureText) {
    latestFailureIndex--;
  }

  return messages.map((message, index) => (
    message.isRetryAvailable && message.id !== heldFailureId
    && (index !== latestFailureIndex || index < lastAdmittedUserMessageIndex)
      ? { ...message, isRetryAvailable: undefined }
      : message
  ));
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

type AgentV2ThreadResolution = Promise<AgentV2MutationResult<string> | undefined>;

/**
 * A ref whose value lasts once the chat unmounts, as Teact clears the component's own refs then, while a chat left with
 * questions queued goes on sending them
 */
function useLastingRef<T>(initial: T): { current: T } {
  return useState(() => ({ current: initial }))[0];
}

// While a chat is active, the runtime keeps the wallet's state on the server up to date for its answers
function updateChatActivity() {
  void callApi('setAgentV2ChatActive', shownChatCount > 0).catch(() => undefined);
}
