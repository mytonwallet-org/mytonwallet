import { useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type {
  AgentAnswerFeedbackV2,
  AgentHintsResponseV2,
  AgentNewsFeedLocaleV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
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
} from '../../../api/agentV2/types';
import type { AgentHint, AgentMessage } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';
import type { AgentProblemReportOutcome } from '../AgentConversationShell';
import type { AgentRunActivityType } from '../AgentRunActivity';
import type { AgentV2HydrationController } from './agentV2HydrationController';
import type { AgentV2RunController } from './agentV2RunController';
import type { AgentV2SendAction, AgentV2StreamController } from './agentV2StreamController';
import type { TextRevealPresentations } from './textRevealPresentation';

import { buildAgentV2HostContext } from '../../../global/agentV2/buildHostContext';
import { buildAgentBuiltinDapps } from '../../../global/agentV2/builtinDapps';
import { selectCurrentAccountState } from '../../../global/selectors';
import { isAgentLinkUrl } from '../../../util/agent/agentLinkUrl';
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
import {
  isAgentV2ComposerBlocked,
  selectAgentV2ComposerStatus,
} from '../../agentV2/agentComposerStatus';
import {
  getAgentV2ErrorText,
  getAgentV2HintCopy,
} from '../../agentV2/agentV2Copy';
import { buildAgentV2HydrationError } from '../../agentV2/hydrationError';
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
  selectAgentV2Activity,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

import useLastCallback from '../../../hooks/useLastCallback';

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
 * discussion of a MyPulse news item, which the server keeps one of per news item.
 * A chat keeps the thread it resolved; showing another thread takes another chat.
 */
export type AgentV2ChatTarget =
  | {
    kind: 'thread';
    threadId: string;
    /** The feed's copy of the news of a discussion that holds its post alone, which it shows from its first frame */
    preview?: AgentThreadNewsCardV2;
  }
  | { kind: 'default' }
  | { kind: 'new' }
  | {
    kind: 'news';
    news: { eventId: number; locale: AgentNewsFeedLocaleV2 };
    /** The feed's copy of the news, which a discussion that holds its post alone shows from its first frame */
    preview?: AgentThreadNewsCardV2;
  };

interface UseAgentV2MessagesProps {
  isActive?: boolean;
  lang: LangFn;
  /** Without a target the chat follows the default thread and every update, as the single-chat host did */
  target?: AgentV2ChatTarget;
  /** A question for a new chat: it shows at once and is sent once the chat's thread is ready */
  initialMessage?: string;
  onInitialMessageSent?: NoneToVoidFunction;
  onThreadResolved?: (threadId: string) => void;
  onThreadNotFound?: NoneToVoidFunction;
}

export interface UseAgentV2MessagesResult {
  messages: AgentMessage[];
  thread?: AgentThreadSummaryV2;
  /** The news the chat discusses */
  news?: AgentThreadNewsCardV2;
  /** A news discussion shows its post while the thread's history is loading */
  isOpeningNews: boolean;
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  /** The question the chat opened with is on screen and not sent yet */
  hasPendingQuestion: boolean;
  isInputDisabled: boolean;
  isRunActive: boolean;
  textRevealPresentations: TextRevealPresentations;
  clearChat: NoneToVoidFunction;
  /** Cancels this chat's work and returns only the thread already known or being created for deletion */
  cancelPendingRequests: () => Promise<string | undefined>;
  /** Present while the server takes problem reports */
  reportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  /** Sets the user's rating of a complete answer, or withdraws it without `feedback` */
  rateMessage: (messageId: number, feedback?: AgentAnswerFeedbackV2) => void;
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
  composerStatus?: AgentV2ComposerStatus;
  sendMessage: (text: string, editMessageId?: number) => void;
  sendHint: (hint: AgentHint) => void;
  sendFollowup: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  acceptConsent: NoneToVoidFunction;
  retryMessage: (messageId: number) => void;
  /** A finished answer the server stores, other than a news post, can be answered again with `retryMessage` */
  isMessageRegenerable: (messageId: number) => boolean;
  retryAdmission: NoneToVoidFunction;
  refreshExpiredComposerStatus: NoneToVoidFunction;
  activateAction: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
}

const ERROR_MESSAGE_ID = -1;
const NEWS_POST_MESSAGE_ID = -2;

// The chats on screen. Across the phone breakpoint the outgoing layout can unmount its chat after the incoming layout
// has mounted its own, so the chat stays active until the last of them goes.
let shownChatCount = 0;

export default function useAgentV2Messages({
  isActive,
  lang,
  target,
  initialMessage,
  onInitialMessageSent,
  onThreadResolved,
  onThreadNotFound,
}: UseAgentV2MessagesProps): UseAgentV2MessagesResult {
  const {
    openReceiveModal,
    setSwapAmountOut,
    showError,
    startSwap,
    startTransfer,
  } = getActions();
  const langCode = lang.code ?? 'en';
  const [state, setState] = useState(INITIAL_AGENT_V2_MESSAGES_STATE);
  const [textRevealPresentations, setTextRevealPresentations] = useState<TextRevealPresentations>({});
  const [isProblemReportAvailable, setIsProblemReportAvailable] = useState(false);
  const stateRef = useRef(state);
  // Keyed by the answer's server id, which a cleared chat cannot hand over to another answer
  const feedbackRequestsRef = useRef(new Map<string, AgentV2FeedbackRequests>());
  const langRef = useRef(lang);
  const wasActiveRef = useRef(isActive);
  const controllersRef = useRef<AgentV2Controllers>();
  // The target is read once: a chat stays on the thread it resolved, so a runtime restart cannot move it
  const targetRef = useRef(target);
  const resolvedThreadIdRef = useRef(target?.kind === 'thread' ? target.threadId : undefined);
  // Hydrations that overlap, such as the first one and a runtime restart, share one thread creation
  const resolvingThreadIdRef = useRef<Promise<AgentV2MutationResult<string> | undefined>>();
  const isUnmountedRef = useRef(false);
  // In-flight requests retain this state after Teact clears the component's refs on unmount
  const deletionState = useRef({ isRequested: false }).current;
  // The server's card is available before the history has loaded
  const createdNewsRef = useRef<AgentThreadNewsCardV2>();
  const newsPostRef = useRef<{ messageId: number; timestamp: number }>();
  const onThreadResolvedRef = useRef(onThreadResolved);
  onThreadResolvedRef.current = onThreadResolved;
  const handleThreadNotFound = useLastCallback(() => onThreadNotFound?.());
  const handleInitialMessageSent = useLastCallback(() => onInitialMessageSent?.());
  const dispatch = useLastCallback((action: AgentV2MessagesStateAction) => {
    if (deletionState.isRequested) return;
    stateRef.current = reduceAgentV2MessagesState(stateRef.current, action);
    // History carries the rating the server keeps; a rating still being saved shows over it
    if (action.kind === 'hydrationSucceeded' || action.kind === 'historyPageSucceeded') {
      stateRef.current = applyPendingFeedback(stateRef.current, feedbackRequestsRef.current);
    }
    setState(stateRef.current);
  });
  langRef.current = lang;
  const hideSecretPhrases = useLastCallback((text: string) => removeSecretPhrases(
    text, getSecretPhraseWordList(), langRef.current('$agent_secret_words_removed'),
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
      getHints: (currentLangCode) => (
        targetRef.current?.kind === 'news' || createdNewsRef.current || stateRef.current.thread?.news
          ? Promise.resolve(undefined)
          : callApi('getAgentV2Hints', currentLangCode)
      ),
      getLangCode: () => langRef.current.code ?? 'en',
      getMessages: (threadId, cursor) => cursor
        ? callApi('getAgentV2Messages', threadId, cursor)
        : callApi('getAgentV2Messages', threadId),
      getState: () => stateRef.current,
      isConsentAccepted: () => stateRef.current.isConsentAccepted === true,
      loadAvailability: () => callApi('getAgentV2Availability'),
      loadUserQuota: () => callApi('getAgentV2UserQuota'),
      mapHints: (response, currentLangCode) => mapHints(response, currentLangCode, langRef.current),
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
      getState: () => stateRef.current,
      hydrate: hydration.hydrate,
      now: Date.now,
      retryRun: (clientRunId) => callApi('retryAgentV2Run', clientRunId),
      resetHistory: hydration.resetHistory,
      startRun: async (command) => {
        // A chat being deleted never sends its opening question
        if (deletionState.isRequested) return undefined;
        const hostContext = buildAgentV2HostContext(getGlobal());
        const synchronized = await synchronizeHostContext(hostContext);
        if (synchronized === undefined || deletionState.isRequested) return undefined;
        return callApi('startAgentV2Run', command);
      },
      stream,
      hideSecretPhrases,
    });
    controllersRef.current = { hydration, run, stream };
  }
  const controllers = controllersRef.current;
  const cancelPendingRequests = useLastCallback(() => {
    deletionState.isRequested = true;
    controllers.hydration.dispose();
    controllers.run.dispose();
    controllers.stream.dispose();
    return resolvedThreadIdRef.current
      ? Promise.resolve(resolvedThreadIdRef.current)
      : resolvingThreadIdRef.current?.then((result) => (result?.ok ? result.value : undefined))
        ?? Promise.resolve(undefined);
  });
  const initialMessageRef = useRef(initialMessage?.trim());
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
  const chatTarget = targetRef.current;
  const preview = chatTarget?.kind === 'news' || chatTarget?.kind === 'thread' ? chatTarget.preview : undefined;
  const createdNews = createdNewsRef.current;
  const authoritativeNews = state.thread?.news ?? createdNews ?? preview;
  const news = useMemo(() => {
    if (!authoritativeNews) return undefined;
    const matchingCreatedNews = createdNews?.eventId === authoritativeNews.eventId ? createdNews : undefined;
    const matchingPreview = preview?.eventId === authoritativeNews.eventId ? preview : undefined;
    return {
      ...authoritativeNews,
      body: authoritativeNews.body ?? matchingCreatedNews?.body ?? matchingPreview?.body,
      sources: authoritativeNews.sources ?? matchingCreatedNews?.sources ?? matchingPreview?.sources,
    };
  }, [authoritativeNews, createdNews, preview]);
  const isNewsThread = chatTarget?.kind === 'news' || Boolean(news);
  if (news && !newsPostRef.current) {
    newsPostRef.current = {
      messageId: NEWS_POST_MESSAGE_ID, timestamp: Date.parse(news.publishedAt),
    };
  }
  const isOpeningNews = Boolean(preview && (!state.thread || state.isLoading));

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
  const nextComposerStatus = selectAgentV2ComposerStatus(
    state.availability,
    state.userQuota,
    state.quotaRetry,
    state.userRateLimit,
  );
  if (!areDeepEqual(composerStatusRef.current, nextComposerStatus)) composerStatusRef.current = nextComposerStatus;
  const composerStatus = composerStatusRef.current;
  const isComposerBlocked = isAgentV2ComposerBlocked(composerStatus);
  const messages = useMemo(() => {
    const stateMessages = pendingQuestion ? [...state.messages, pendingQuestion] : state.messages;
    const lastAdmittedUserMessageIndex = stateMessages.reduce((lastIndex, { id, isOutgoing }, index) => (
      isOutgoing && state.sourceIdByMessageId[id] ? index : lastIndex
    ), -1);
    const liveFailure = buildLiveFailureMessage(state.admissionFailure, state.error, stateMessages);
    return keepRetryOnLatestFailure(
      liveFailure ? [...stateMessages, liveFailure] : stateMessages,
      lastAdmittedUserMessageIndex,
    );
  }, [pendingQuestion, state.admissionFailure, state.error, state.messages, state.sourceIdByMessageId]);
  const visibleMessages = useMemo(() => {
    const post = newsPostRef.current;
    if (!news || !post || state.nextCursor) return messages;
    const firstOutgoingMessage = messages.find(({ isOutgoing }) => isOutgoing);
    const postMessage = messages.find(({ isNewsPost }) => isNewsPost)
      ?? (firstOutgoingMessage?.text === news.headline ? firstOutgoingMessage : undefined);
    return [{
      ...postMessage,
      // The same list item hosts the preview, the saved post and the local fallback after a clear
      id: post.messageId,
      text: postMessage?.text ?? `**${news.headline}**\n\n${news.body ?? news.excerpt ?? ''}`,
      isOutgoing: false,
      isNewsPost: true,
      followups: postMessage?.isNewsPost ? postMessage.followups : undefined,
      timestamp: post.timestamp,
    }, ...messages.filter((message) => message !== postMessage)];
  }, [messages, news, state.nextCursor]);

  useEffect(() => {
    isUnmountedRef.current = false;
    const unsubscribe = subscribeToAgentV2Updates((update) => {
      if (!isUpdateForThisChat(update)) return;
      if (controllers.run.isCancelledRunUpdate(update)) return;
      controllers.stream.handleUpdate(update);
      controllers.hydration.handleUpdate(update);
      controllers.run.handleUpdate(update);
    });

    return () => {
      isUnmountedRef.current = true;
      unsubscribe();
      controllers.hydration.dispose();
      controllers.run.dispose();
      controllers.stream.dispose();
    };
  }, [controllers]);

  useEffect(() => {
    if (!isActive || deletionState.isRequested || state.isConsentAccepted !== undefined) return;

    dispatch({ kind: 'consentLoadingStarted' });
    void callApi('getAgentV2Consent').then((isAccepted) => {
      if (deletionState.isRequested) return;
      const isConsentAccepted = Boolean(isAccepted);
      dispatch({ kind: 'consentResolved', isAccepted: isConsentAccepted });
      // A bound chat that opens again during its thread's answer keeps the answer its updates replayed
      if (isConsentAccepted) void controllers.hydration.hydrate(Boolean(targetRef.current));
    });
  }, [controllers, deletionState, dispatch, isActive, state.isConsentAccepted]);

  useEffect(() => {
    const wasActive = wasActiveRef.current;
    wasActiveRef.current = isActive;
    if (!isActive || wasActive || state.isConsentAccepted !== true || !state.error) return;
    void controllers.hydration.hydrate();
  }, [controllers, isActive, state.error, state.isConsentAccepted]);

  useEffect(() => {
    if (
      !isActive
      || isNewsThread
      || state.isConsentAccepted !== true
      || !state.thread
      || state.hintsLangCode === langCode
    ) return;
    void controllers.hydration.refreshHints();
  }, [controllers, isActive, isNewsThread, langCode, state.hintsLangCode, state.isConsentAccepted, state.thread]);

  const threadId = state.thread?.id;
  useEffect(() => {
    if (!isActive || !threadId) return undefined;

    let isCurrent = true;
    void callApi('getAgentV2ProblemReportAvailability').then((isAvailable) => {
      if (isCurrent) setIsProblemReportAvailable(Boolean(isAvailable));
    });
    return () => {
      isCurrent = false;
    };
  }, [isActive, threadId]);

  const acceptConsent = useLastCallback(() => {
    if (deletionState.isRequested) return;
    void callApi('acceptAgentV2Consent').then((isConsentAccepted) => {
      if (isConsentAccepted !== true || deletionState.isRequested) return;
      dispatch({ kind: 'consentAccepted' });
      void controllers.hydration.hydrate(Boolean(targetRef.current));
    });
  });

  const activateAction = useLastCallback((
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => {
    const sourceId = controllers.stream.getSourceId(messageId);
    if (!sourceId) return;
    if (action.kind === 'send') {
      void activateSendAction(messageId, sourceId, action);
      return;
    }
    const authorityKey = buildAgentV2ActionAuthorityKey(buildAgentV2HostContext(getGlobal()));
    const generation = controllers.stream.getActionPresentationGeneration();
    void callApi('resolveAgentV2Action', sourceId, action.id).then((resolved) => {
      if (!resolved || generation !== controllers.stream.getActionPresentationGeneration()) return;
      const currentAuthorityKey = buildAgentV2ActionAuthorityKey(buildAgentV2HostContext(getGlobal()));
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
    const { thread } = stateRef.current;
    if (!thread) return 'failed';
    // The connection error bubble has no stored message and reports the conversation. An answer that lost its stored
    // message since the form opened is not reported as the conversation in its place.
    const sourceId = messageId === undefined || messageId === ERROR_MESSAGE_ID
      ? undefined
      : controllers.stream.getSourceId(messageId);
    if (messageId !== undefined && messageId !== ERROR_MESSAGE_ID && !sourceId) return 'failed';
    const result = await callApi('reportAgentV2Problem', thread.id, {
      ...(sourceId ? { messageId: sourceId } : {}),
      ...(comment ? { comment } : {}),
    });
    if (result?.ok) return 'sent';
    // A server that has switched reports off refuses them, and asking again takes the report items away
    void callApi('getAgentV2ProblemReportAvailability').then((isAvailable) => {
      setIsProblemReportAvailable(Boolean(isAvailable));
    });
    return result?.error.code === 'rate_limited' ? 'rateLimited' : 'failed';
  });

  const rateMessage = useLastCallback(async (messageId: number, feedback?: AgentAnswerFeedbackV2) => {
    const { thread, messages: currentMessages } = stateRef.current;
    const message = currentMessages.find(({ id }) => id === messageId);
    const sourceId = controllers.stream.getSourceId(messageId);
    if (!thread || !sourceId || !message?.isComplete) return;
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
  });

  const refreshExpiredComposerStatus = useLastCallback(() => {
    dispatch({ kind: 'composerStatusExpired' });
  });

  const retryMessage = useLastCallback((messageId: number) => {
    const admissionFailure = stateRef.current.admissionFailure;
    if (messageId === ERROR_MESSAGE_ID
      || (messageId === admissionFailure?.retryMessageId && admissionFailure.clientRunId)) {
      controllers.run.retryAdmission();
      return;
    }
    controllers.run.retryMessage(messageId);
  });

  const sendFollowup = useLastCallback((messageId: number, followup: AgentPublicFollowUpV2) => {
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
      message && !message.isOutgoing && !message.isNewsPost && !message.isTyping && !message.isStreaming
      && current.sourceIdByMessageId[messageId],
    );
  });

  const isInitialLoadComplete = state.isConsentAccepted === true && !state.isLoading;

  // The failure stays, saying it is being retried, until the history loads or fails again
  const [retriedHistoryFailure, setRetriedHistoryFailure] = useState<string | undefined>();
  const retryHistory = useLastCallback(() => {
    const error = stateRef.current.error;
    if (!error?.isHistoryFailure) return;

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
  const isInputDisabled = !state.thread || selectIsAgentV2InputDisabled(state, isComposerBlocked);
  // The Agent is taken to be analyzing the question while the chat gets its thread ready
  const isQuestionWaiting = Boolean(pendingQuestion) && !isInitialLoadComplete;

  useEffect(() => {
    const text = initialMessageRef.current;
    if (!isActive || deletionState.isRequested
      || !pendingQuestion || !text || !isInitialLoadComplete || isInputDisabled) return;
    if (!controllers.run.sendMessage(text, undefined, pendingQuestion)) return;
    initialMessageRef.current = undefined;
    setPendingQuestion(undefined);
    handleInitialMessageSent();
  }, [controllers, deletionState, handleInitialMessageSent, isActive,
    isInitialLoadComplete, isInputDisabled, pendingQuestion]);

  return {
    messages: visibleMessages,
    thread: state.thread,
    news,
    isOpeningNews,
    hints: isNewsThread ? undefined : state.hints,
    activity: selectAgentV2Activity(state) ?? (isQuestionWaiting ? ANALYZING_REQUEST_ACTIVITY : undefined),
    isInitialLoadComplete,
    hasPendingQuestion: Boolean(pendingQuestion),
    isInputDisabled,
    isRunActive: selectIsAgentV2RunActive(state) || isQuestionWaiting,
    textRevealPresentations,
    hasOlderMessages: Boolean(state.nextCursor),
    isLoadingOlderMessages: state.isLoadingOlderMessages,
    loadOlderMessages: controllers.hydration.loadOlderMessages,
    historyFailure,
    retryHistory,
    isConsentAccepted: state.isConsentAccepted,
    composerStatus,
    sendMessage: controllers.run.sendMessage,
    sendHint: controllers.run.sendHint,
    sendFollowup,
    clearChat: controllers.run.clearChat,
    cancelPendingRequests,
    reportProblem: isProblemReportAvailable ? reportProblem : undefined,
    rateMessage,
    acceptConsent,
    retryMessage,
    isMessageRegenerable,
    retryAdmission: controllers.run.retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession: controllers.stream.consumeTextRevealSession,
    settleTextRevealSession: controllers.stream.settleTextRevealSession,
  };

  function resolveThreadId(): Promise<AgentV2MutationResult<string> | undefined> {
    if (deletionState.isRequested) return Promise.resolve(undefined);
    const resolvedThreadId = resolvedThreadIdRef.current;
    if (resolvedThreadId) return Promise.resolve({ ok: true, value: resolvedThreadId });
    if (!targetRef.current) return requestThreadId();

    resolvingThreadIdRef.current ??= requestThreadId().finally(() => {
      resolvingThreadIdRef.current = undefined;
    });
    return resolvingThreadIdRef.current;
  }

  async function requestThreadId(): Promise<AgentV2MutationResult<string> | undefined> {
    const chatTarget = targetRef.current;
    const notifyThreadResolved = onThreadResolvedRef.current;
    const result = await resolveTargetThread(chatTarget).catch(() => undefined);
    if (!result?.ok) return result;
    const threadId = result.value.thread.id;
    if (deletionState.isRequested) return { ok: true, value: threadId };
    createdNewsRef.current = result.value.thread.news;
    if (chatTarget) {
      resolvedThreadIdRef.current = threadId;
      if (!isUnmountedRef.current) {
        if (chatTarget.kind === 'news') dispatch({ kind: 'threadChanged', thread: result.value.thread });
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
      default:
        return callApi('getAgentV2DefaultThread');
    }
  }

  /** Runs of other threads carry on in the SDK; a bound chat leaves their updates to the chats that show them */
  function isUpdateForThisChat(update: AgentV2ClientUpdate) {
    if (!targetRef.current || update.threadId === undefined) return true;
    return update.threadId === (stateRef.current.thread?.id ?? resolvedThreadIdRef.current);
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

    const initialHostContext = buildAgentV2HostContext(getGlobal());
    const initialAuthorityKey = buildAgentV2SendAuthorityKey(initialHostContext);
    if (!initialAuthorityKey) {
      showActionUnavailable(sourceId, action.id, { kind: 'inactive' });
      return;
    }

    try {
      const hasAuthorityChanged = await synchronizeHostContext(initialHostContext);
      const synchronizedAuthorityKey = buildAgentV2SendAuthorityKey(buildAgentV2HostContext(getGlobal()));
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
      const currentHostContext = buildAgentV2HostContext(getGlobal());
      const hasCurrentAuthorityChanged = await synchronizeHostContext(currentHostContext);
      const currentAuthorityKey = buildAgentV2SendAuthorityKey(buildAgentV2HostContext(getGlobal()));
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
          if (!getAgentV2ActionAvailability(buildAgentV2HostContext(global)).canPrepareSwap) return;
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

function mapHints(
  response: AgentHintsResponseV2,
  langCode: AgentHint['langCode'],
  lang: UseAgentV2MessagesProps['lang'],
): AgentHint[] {
  return response.items.map((hint) => {
    const copy = getAgentV2HintCopy(hint.id, lang);
    return {
      id: hint.id,
      langCode,
      title: copy.title,
      subtitle: copy.subtitle,
      prompt: copy.prompt,
    };
  });
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
): AgentMessage | undefined {
  if (admissionFailure && admissionFailure.retryMessageId === undefined) {
    return {
      id: ERROR_MESSAGE_ID,
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
    id: ERROR_MESSAGE_ID,
    text: '',
    isOutgoing: false,
    timestamp: error.timestamp,
    ...(error.cause ? { error: error.cause } : { failureText: error.text }),
  };
}

/**
 * Failures stay in the history as captions. Only the latest one offers Retry, and only while no question has been
 * asked after it.
 */
function keepRetryOnLatestFailure(messages: AgentMessage[], lastAdmittedUserMessageIndex: number) {
  let latestFailureIndex = messages.length - 1;
  while (latestFailureIndex >= 0 && !messages[latestFailureIndex].error && !messages[latestFailureIndex].failureText) {
    latestFailureIndex--;
  }

  return messages.map((message, index) => (
    message.isRetryAvailable && (index !== latestFailureIndex || index < lastAdmittedUserMessageIndex)
      ? { ...message, isRetryAvailable: undefined }
      : message
  ));
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

// While a chat is active, the runtime keeps the wallet's state on the server up to date for its answers
function updateChatActivity() {
  void callApi('setAgentV2ChatActive', shownChatCount > 0).catch(() => undefined);
}
