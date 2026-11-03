import React, {
  memo, useEffect, useMemo, useRef,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  AgentPublicFollowUpV2, AgentThreadSummaryV2, AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { AgentV2ComposerStatus } from '../../api/agentV2/types';
import type { AgentMessage, AnimationLevel } from '../../global/types';
import type {
  AgentConversationComposerHeightContext,
  AgentConversationComposerProps,
  AgentConversationHeader,
  AgentConversationHistory,
  AgentConversationMessageContext,
  AgentConversationSessionStore,
} from '../agent/AgentConversationShell';
import type { AgentRunActivityType } from '../agent/AgentRunActivity';
import type { AgentV2ChatTarget } from '../agent/hooks/useAgentV2Messages';
import type { AgentThreadUnreadStart } from './agentThreadReadState';

import { findAgentThreadFirstUnreadMessage } from './agentThreadReadState';
import { updateAgentV2InputBarSpacing } from './inputBarSpacing';
import useRegenerationDissolve from './useRegenerationDissolve';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';
import useAgentV2Messages from '../agent/hooks/useAgentV2Messages';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentRunActivity, {
  createAgentRunActivityHandoff,
  getAgentRunActivityLangKey,
} from '../agent/AgentRunActivity';
import MessageBubble from '../agent/MessageBubble';
import AgentNewsPost from './AgentNewsPost';
import { AgentComposerStatus } from './AgentStatusNotice';
import AgentV2Composer from './AgentV2Composer';
import { AgentV2ConsentScreen } from './AgentV2Conversation';

interface OwnProps {
  isActive: boolean;
  /** The chat selection that owns the opening question */
  chatKey?: number;
  /** The thread to show among several; without it the chat is the single default one */
  target?: AgentV2ChatTarget;
  /** Shown at once and sent once the chat is ready, as when a question typed under the chat list opens a new chat */
  initialMessage?: string;
  /** What the chat list knows of the thread, shown in the header until its history loads */
  initialThread?: AgentThreadSummaryV2;
  /** Where the messages the user has not seen start; the chat opens there, under the "New" line */
  unreadStart?: AgentThreadUnreadStart;
  /** Keeps the draft and the place in the conversation for the chat's next mount */
  session?: AgentConversationSessionStore;
  onInitialMessageSent?: (chatKey: number) => void;
  /** Tells where the unread messages start, counted from the chat's first message, so its next mount opens there */
  onUnreadStartResolved?: (chatKey: number, unreadStart: number) => void;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
  /** Shows the Back button, which goes back to the chat list the chat opened over */
  onBack?: NoneToVoidFunction;
  onThreadResolved?: (chatKey: number, threadId: string) => void;
  /** The thread as its history brings it, which the chat shows from the start when it mounts again */
  onThreadLoaded?: (thread: AgentThreadSummaryV2) => void;
  onThreadNotFound?: NoneToVoidFunction;
  /** What the Agent is doing in the chat's thread, as a localization key, or nothing once it is not answering */
  onAnswerChange?: (threadId: string, activityLangKey: string | undefined) => void;
  /** Asks to delete the chat's thread, from the chat menu */
  onDelete?: (
    thread: AgentThreadSummaryV2 | undefined, cancelPendingRequests: () => Promise<string | undefined>,
  ) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

const ANALYZING_REQUEST_ACTIVITY: AgentRunActivityType = { kind: 'analyzingRequest' };
const WRITING_ACTIVITY_LANG_KEY = '$agent_activity_writing';
// The limits whose status a request's failure stands for
const STATUS_KIND_BY_ERROR_CODE: Partial<Record<AgentV2ErrorCode, AgentV2ComposerStatus['kind']>> = {
  agent_capacity_exhausted: 'capacity',
  user_quota_exhausted: 'userQuota',
  rate_limited: 'rateLimit',
};

export function AgentV2Classic({
  isActive,
  chatKey,
  target,
  initialMessage,
  initialThread,
  unreadStart,
  session,
  animationLevel,
  onInitialMessageSent,
  onUnreadStartResolved,
  onScroll,
  onBack,
  onThreadResolved,
  onThreadLoaded,
  onThreadNotFound,
  onAnswerChange,
  onDelete,
}: OwnProps & StateProps) {
  const { switchToWallet } = getActions();
  const lang = useLang();
  const requestLiveTailRef = useRef<NoneToVoidFunction>();
  const handleInitialMessageSent = useLastCallback(() => onInitialMessageSent?.(chatKey!));
  // Creation can resolve its original selection after this screen unmounts. Teact clears a component's refs on
  // unmount, and `useLastCallback` keeps its callback in a ref, so this callback is memoized instead.
  const handleThreadResolved = useMemo(
    () => (threadId: string) => onThreadResolved?.(chatKey!, threadId), [chatKey, onThreadResolved],
  );
  const {
    messages: loadedMessages,
    thread: loadedThread,
    news: loadedNews,
    isOpeningNews,
    hints,
    activity,
    isInitialLoadComplete,
    hasPendingQuestion,
    isInputDisabled,
    isRunActive,
    isConsentAccepted,
    textRevealPresentations,
    hasOlderMessages,
    isLoadingOlderMessages,
    loadOlderMessages,
    historyFailure,
    retryHistory,
    sendMessage,
    sendHint,
    sendFollowup,
    cancelPendingRequests,
    reportProblem,
    rateMessage,
    acceptConsent,
    composerStatus,
    retryMessage,
    isMessageRegenerable,
    retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession,
    settleTextRevealSession,
  } = useAgentV2Messages({
    isActive, lang, target, initialMessage,
    onInitialMessageSent: handleInitialMessageSent, onThreadResolved: handleThreadResolved, onThreadNotFound,
  });
  const {
    messages, regeneratingMessageId, dissolvingMessageIds, markRegenerating, releaseMessages,
  } = useRegenerationDissolve(loadedMessages, isRunActive);
  const thread = loadedThread ?? initialThread;
  const news = loadedNews ?? initialThread?.news;
  // The "New" line takes its place once the history loads and keeps it while the chat is open
  const firstUnreadRef = useRef<ReturnType<typeof findAgentThreadFirstUnreadMessage> | false>();
  if (firstUnreadRef.current === undefined && unreadStart !== undefined && isInitialLoadComplete && loadedThread) {
    firstUnreadRef.current = findAgentThreadFirstUnreadMessage(loadedMessages, loadedThread.messageCount, unreadStart)
      ?? false;
  }
  const firstUnread = firstUnreadRef.current || undefined;
  const firstOutgoingMessage = messages.find(({ isOutgoing }) => isOutgoing);

  const lastMessage = messages[messages.length - 1];
  // Chats open once consent is given, so the composer waits at its place while the chat checks it, as on mobile
  const isInputVisible = isConsentAccepted !== false;
  const visibleComposerStatus = isInputVisible ? composerStatus : undefined;
  // While a limit holds, no request can be retried, and the limit the latest request ran into tells its failure in
  // place of the failure's own caption
  const isLimitHolding = visibleComposerStatus?.mode === 'blocked';
  const statusFailedMessage = isLimitHolding
    ? getStatusFailedMessage(lastMessage, visibleComposerStatus)
    : undefined;
  // Once the answer message exists, it hosts the run indicator in place of its bubble
  const isActivityInFooter = !lastMessage || lastMessage.isOutgoing;
  const answerLangKey = isRunActive
    ? (lastMessage?.isStreaming && !lastMessage.isOutgoing
      ? WRITING_ACTIVITY_LANG_KEY
      : getAgentRunActivityLangKey(activity ?? ANALYZING_REQUEST_ACTIVITY))
    : undefined;
  const loadedThreadId = loadedThread?.id;

  useEffect(() => {
    if (loadedThreadId) onAnswerChange?.(loadedThreadId, answerLangKey);
  }, [answerLangKey, loadedThreadId, onAnswerChange]);

  useEffect(() => {
    if (loadedThread) onThreadLoaded?.(loadedThread);
  }, [loadedThread, onThreadLoaded]);

  const firstUnreadPosition = firstUnread?.position;
  useEffect(() => {
    if (firstUnreadPosition !== undefined && firstUnreadPosition !== unreadStart) {
      onUnreadStartResolved?.(chatKey!, firstUnreadPosition);
    }
  }, [chatKey, firstUnreadPosition, onUnreadStartResolved, unreadStart]);

  const handleFollowup = useLastCallback((messageId: number, followup: AgentPublicFollowUpV2) => {
    requestLiveTailRef.current?.();
    sendFollowup(messageId, followup);
  });

  // The answer and the messages after it turn to dust once the server takes the regeneration
  const handleRegenerate = useLastCallback((messageId: number) => {
    markRegenerating(messageId);
    retryMessage(messageId);
  });

  // The run's indicator moves from the chat's end into the answer's message as the message starts, its top going on
  // spinning and its step blurring into the next
  const activityHandoff = useMemo(createAgentRunActivityHandoff, []);

  const renderMessage = useLastCallback((
    message: AgentMessage,
    context: AgentConversationMessageContext,
  ) => {
    requestLiveTailRef.current = context.onRequestLiveTail;
    const isLatest = message.id === lastMessage?.id;
    const isRegenerating = message.id === regeneratingMessageId;
    // Answering again needs the same free composer as a follow-up does
    const canRegenerate = !isInputDisabled && !isRunActive && isMessageRegenerable(message.id);
    if (message.isNewsPost && news) {
      return (
        <AgentNewsPost
          key={message.id}
          news={news}
          message={message}
          isDisabled={isInputDisabled}
          shouldShowFollowups={isLatest && !isRunActive}
          shouldAnimateFollowups={context.shouldAnimateTextStreaming}
          onFollowup={handleFollowup}
          onFollowupsGrowthFrame={context.onTextRevealProgress}
        />
      );
    }

    return (
      <MessageBubble
        key={message.id}
        message={message}
        isDisabled={isInputDisabled}
        shouldAnimateTextStreaming={context.shouldAnimateTextStreaming}
        isLatest={isLatest}
        areFollowupsHeld={isRunActive}
        // The answer being answered again keeps its place until it turns to dust; the activity comes after it
        isRegenerating={isRegenerating}
        activity={isLatest && !isRegenerating ? activity : undefined}
        activityHandoff={activityHandoff}
        textRevealPresentation={context.textRevealPresentation}
        isJustAdded={context.isJustAdded}
        onEdit={context.onEditMessage}
        onFollowup={handleFollowup}
        onAction={activateAction}
        onRetry={message.isRetryAvailable && !isLimitHolding ? handleRegenerate : undefined}
        noFailureCaption={message.id === statusFailedMessage?.id}
        onRegenerate={canRegenerate ? handleRegenerate : undefined}
        onRate={rateMessage}
        onReport={context.onReportMessage}
        onTextRevealSessionConsumed={consumeTextRevealSession}
        onTextRevealSessionSettled={settleTextRevealSession}
        onTextRevealProgress={context.onTextRevealProgress}
        onTextRevealComplete={context.onTextRevealProgress}
      />
    );
  });

  const handleComposerHeightChange = useLastCallback((
    height: number,
    context: AgentConversationComposerHeightContext,
  ) => {
    updateAgentV2InputBarSpacing(
      context.messagesElement,
      height,
      context.getIsAtBottom,
      context.messagesElement.parentElement ?? context.messagesElement,
      context.onTextRevealProgress,
    );
  });

  // A question a limit kept from starting offers Retry once the limit has reset, unless a failure under it does
  const canRetryAdmission = visibleComposerStatus?.mode === 'informational'
    && Boolean(visibleComposerStatus.clientRunId)
    && !getIsFailure(lastMessage);
  // Retry turns the failure under the question to dust, as Retry under a failed answer does
  const [isStatusRetried, markStatusRetried, unmarkStatusRetried] = useFlag();
  const handleRetryAdmission = useLastCallback(() => {
    markStatusRetried();
    retryAdmission();
  });
  // A retry that ends without the server taking it leaves the status in place
  useEffect(() => {
    if (!isRunActive) unmarkStatusRetried();
  }, [isRunActive, unmarkStatusRetried]);
  // The chat ends with the limit, as in the design, which takes the place of the activity once no answer is running
  const currentChatStatus = useMemo(() => (visibleComposerStatus && !isRunActive ? (
    <AgentComposerStatus
      key="status"
      status={visibleComposerStatus}
      isRetryDisabled={isInputDisabled}
      onRetry={canRetryAdmission ? handleRetryAdmission : undefined}
      onExpired={refreshExpiredComposerStatus}
    />
  ) : undefined), [
    canRetryAdmission, handleRetryAdmission, isInputDisabled, isRunActive, refreshExpiredComposerStatus,
    visibleComposerStatus,
  ]);
  const previousChatStatus = usePrevious2(currentChatStatus);
  // The retried status stays for the list to turn it to dust, and goes once the list lets it go
  const isStatusDissolving = isStatusRetried && !currentChatStatus && Boolean(previousChatStatus);
  const chatStatus = isStatusDissolving ? previousChatStatus : currentChatStatus;
  const handleDissolveStart = useLastCallback(() => {
    releaseMessages();
    unmarkStatusRetried();
  });

  const renderComposer = useLastCallback((props: AgentConversationComposerProps) => (
    <AgentV2Composer
      {...props}
      isActive={isActive}
      isDimmed={isLimitHolding}
    />
  ));
  const conversation = useMemo(() => ({
    messages,
    hints,
    // A news discussion shows its post, and a new chat its question, while the server is still preparing the thread
    isInitialLoadComplete: isInitialLoadComplete || isOpeningNews || hasPendingQuestion,
    // A new chat has no history to wait for
    hasHistoryPlaceholder: target?.kind === 'thread',
    unreadMessageId: firstUnread?.messageId,
    loadFailure: historyFailure && { ...historyFailure, onRetry: retryHistory },
    isRunActive,
    textRevealPresentations,
    dissolvingMessageIds,
    isFooterDissolving: isStatusDissolving,
    onDissolveStart: handleDissolveStart,
    renderMessage,
  }), [
    dissolvingMessageIds, firstUnread, handleDissolveStart, hasPendingQuestion, historyFailure, hints,
    isInitialLoadComplete, isOpeningNews, isRunActive, isStatusDissolving, messages, renderMessage, retryHistory,
    target, textRevealPresentations,
  ]);
  const composer = useMemo(() => ({
    isDisabled: isInputDisabled,
    shouldHide: !isInputVisible,
    onSendMessage: sendMessage,
    onSendHint: sendHint,
    onHeightChange: handleComposerHeightChange,
    render: renderComposer,
  }), [handleComposerHeightChange, isInputDisabled, isInputVisible, renderComposer, sendHint, sendMessage]);
  const history = useMemo<AgentConversationHistory>(() => ({
    hasOlderMessages,
    isLoading: isLoadingOlderMessages,
    mode: 'continuous',
    loadOlderMessages,
  }), [hasOlderMessages, isLoadingOlderMessages, loadOlderMessages]);
  const slots = useMemo(() => ({
    body: isConsentAccepted === false
      ? <AgentV2ConsentScreen onAccept={acceptConsent} />
      : undefined,
    messageListFooter: chatStatus
      ?? (isActivityInFooter
        ? <AgentRunActivity key="activity" activity={activity} handoff={activityHandoff} />
        : undefined),
    bottomStickDependency: chatStatus ?? activity,
  }), [acceptConsent, activity, activityHandoff, chatStatus, isActivityInFooter, isConsentAccepted]);
  // The server keeps a thread nameless until it holds a message; the question shows until then, as on mobile
  const isNamedThread = Boolean(thread?.messageCount);
  const firstQuestion = firstOutgoingMessage?.text ?? initialMessage ?? news?.headline;
  const hasMessages = messages.length > 0;
  // A chat whose thread is known or on its way has the menu
  const hasMenu = Boolean(target || thread) || hasMessages || isOpeningNews;
  // The consent screen keeps the plain "Agent" header. Chats open once consent is given, so the chat's own header
  // shows while the chat checks it.
  const header = useMemo<AgentConversationHeader | undefined>(() => (target ? {
    // A known thread whose history has not loaded yet has a name that is not known yet either
    // An empty name is no name, so the header keeps the question rather than going blank
    title: isConsentAccepted === false ? lang('Agent') : ((isNamedThread ? thread?.title : undefined) || firstQuestion)
      ?? (target.kind === 'thread' && !thread ? '' : lang('New Chat')),
    icon: isConsentAccepted !== false && isNamedThread ? thread?.icon : undefined,
    hasBackButton: Boolean(onBack),
    hasMenu,
  } : undefined), [firstQuestion, hasMenu, isConsentAccepted, isNamedThread, lang, onBack, target, thread]);
  const handleDelete = useLastCallback(() => {
    onDelete!(thread, cancelPendingRequests);
  });
  const canDelete = Boolean(onDelete && hasMenu);
  const actions = useMemo(() => ({
    onBack: onBack ?? switchToWallet,
    onReportProblem: reportProblem,
    onScroll,
    onDelete: canDelete ? handleDelete : undefined,
  }), [canDelete, handleDelete, onBack, onScroll, reportProblem, switchToWallet]);

  return (
    <AgentConversationShell
      isActive={isActive}
      animationLevel={animationLevel}
      conversation={conversation}
      composer={composer}
      history={history}
      slots={slots}
      header={header}
      actions={actions}
      session={session}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    animationLevel: global.settings.animationLevel,
  };
})(AgentV2Classic));

function getIsFailure(message: AgentMessage | undefined) {
  return Boolean(message && !message.isOutgoing && (message.error || message.failureText));
}

function getStatusFailedMessage(lastMessage: AgentMessage | undefined, status: AgentV2ComposerStatus) {
  const code = lastMessage?.error?.code;
  return code && STATUS_KIND_BY_ERROR_CODE[code] === status.kind ? lastMessage : undefined;
}
