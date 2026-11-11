import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  AgentPublicFollowUpV2, AgentThreadSummaryV2, AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { AgentV2ComposerStatus } from '../../api/agentV2/types';
import type { AgentMessage, AnimationLevel } from '../../global/types';
import type { LangFn } from '../../hooks/useLang';
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

import { getIsAgentV2ThreadStarted } from '../../api/agentV2/threadStarted';
import getCanAnimate from '../agent/helpers/getCanAnimate';
import { findAgentThreadFirstUnreadMessage, getAgentThreadUnreadStart } from './agentThreadReadState';
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
import AgentSupportEventLine from './AgentSupportEventLine';
import AgentV2Composer from './AgentV2Composer';

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
  isUnreadStateUnknown?: boolean;
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
  /** The user has allowed the Agent, as the chat list learns it */
  hasConsent?: boolean;
  /**
   * Asks for the Agent's consent before `action`, which runs once the user allows it. A news discussion opened before
   * consent sends, dictates and takes its suggestions through it; the `field` a question was sent from gets its focus
   * back if the user closes the sheet, and `onDecline` runs then.
   */
  onRequestConsent?: (action: NoneToVoidFunction, field?: HTMLElement, onDecline?: NoneToVoidFunction) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

const ANALYZING_REQUEST_ACTIVITY: AgentRunActivityType = { kind: 'analyzingRequest' };
// A Stop while the Agent thinks keeps its indicator this long, while the top grows, is knocked and shrinks back
const STOPPED_ACTIVITY_DURATION_MS = 1600;
const WRITING_ACTIVITY_LANG_KEY = '$agent_activity_writing';
const NO_MESSAGES: AgentMessage[] = [];
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
  isUnreadStateUnknown = false,
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
  hasConsent,
  onRequestConsent,
}: OwnProps & StateProps) {
  const { switchToWallet } = getActions();
  const lang = useLang();
  const requestLiveTailRef = useRef<AgentConversationMessageContext['onRequestLiveTail']>();
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
    isHistoryCached,
    isOpenedWithCachedHistory,
    hasPendingQuestion,
    isInputDisabled,
    isRunActive,
    canStopRun,
    stopRun,
    isConsentAccepted,
    checkConsentAgain,
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
    composerStatus,
    retryMessage,
    isMessageRegenerable,
    retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession,
    settleTextRevealSession,
    support,
    canEditMessages,
  } = useAgentV2Messages({
    isActive, lang, target, initialThread, initialMessage, hasConsent, isUnreadStateUnknown,
    onInitialMessageSent: handleInitialMessageSent, onThreadResolved: handleThreadResolved, onThreadNotFound,
  });
  const {
    messages, regeneratingMessageId, dissolvingMessageIds, markRegenerating, releaseMessages,
  } = useRegenerationDissolve(loadedMessages, isRunActive);
  const thread = loadedThread ?? initialThread;
  // What the chat's list row says it holds, read once, so that its placeholder keeps one shape until the history comes
  const [historyPlaceholderLayout] = useState(() => (initialThread ? {
    messageCount: initialThread.messageCount, isNews: Boolean(initialThread.news),
  } : undefined));
  const isWithSupport = support?.state === 'waiting' || support?.state === 'operator';
  // Once an operator has joined, every answer in the chat names its author, the agent's before it too, as in the design
  const supportOperator = useMemo(() => findLatestOperator(messages), [messages]);
  const news = loadedNews ?? initialThread?.news;
  // The "New" line takes its place once the history loads and keeps it while the chat is open
  const firstUnreadRef = useRef<ReturnType<typeof findAgentThreadFirstUnreadMessage> | false>();
  // The device's copy of the history places no "New" line and is not the thread as loaded
  const isUnreadStateReady = !isHistoryCached && (!isUnreadStateUnknown || (isInitialLoadComplete && !historyFailure));
  if (firstUnreadRef.current === undefined && isInitialLoadComplete && loadedThread && isUnreadStateReady) {
    const resolvedUnreadStart = isUnreadStateUnknown ? getAgentThreadUnreadStart(loadedThread) : unreadStart;
    if (resolvedUnreadStart !== undefined) {
      firstUnreadRef.current = findAgentThreadFirstUnreadMessage(
        loadedMessages, loadedThread.messageCount, resolvedUnreadStart,
      ) ?? false;
    }
  }
  const firstUnread = firstUnreadRef.current || undefined;
  const firstOutgoingMessage = messages.find(({ isOutgoing }) => isOutgoing);

  const lastMessage = messages[messages.length - 1];
  // Chats open once consent is given, so the composer waits at its place while the chat checks it, as on mobile. A news
  // discussion opens before it, and asks for it before it sends, dictates or takes a suggestion.
  const isInputVisible = isConsentAccepted !== false;
  const isAwaitingConsent = !hasConsent && Boolean(onRequestConsent);
  const visibleComposerStatus = isInputVisible ? composerStatus : undefined;
  // While a limit holds, no request can be retried, and the limit the latest request ran into tells its failure in
  // place of the failure's own caption
  const isLimitHolding = visibleComposerStatus?.mode === 'blocked';
  const statusFailedMessage = isLimitHolding
    ? getStatusFailedMessage(lastMessage, visibleComposerStatus)
    : undefined;
  // Once the answer message exists, it hosts the run indicator in place of its bubble
  const isActivityInFooter = !lastMessage || lastMessage.isOutgoing;
  // The indicator a Stop while the Agent thinks keeps for a moment at the chat's end, where it shows the Stop
  const [stoppedActivity, setStoppedActivity] = useState<AgentRunActivityType>();
  const stoppedActivityTimeoutRef = useRef<number>();
  const handleStop = useLastCallback(() => {
    // Before any of the answer has come, the Agent is still thinking
    const isThinking = isRunActive && (!lastMessage || lastMessage.isOutgoing || !lastMessage.text);
    if (isThinking && getCanAnimate()) {
      setStoppedActivity(activity ?? ANALYZING_REQUEST_ACTIVITY);
      window.clearTimeout(stoppedActivityTimeoutRef.current);
      stoppedActivityTimeoutRef.current = window.setTimeout(
        () => setStoppedActivity(undefined), STOPPED_ACTIVITY_DURATION_MS,
      );
    }
    stopRun();
  });
  // A new run takes the chat's end at once
  useEffect(() => {
    if (!isRunActive) return;
    window.clearTimeout(stoppedActivityTimeoutRef.current);
    setStoppedActivity(undefined);
  }, [isRunActive]);
  useEffect(() => () => window.clearTimeout(stoppedActivityTimeoutRef.current), []);
  const answerLangKey = isRunActive
    ? (lastMessage?.isStreaming && !lastMessage.isOutgoing
      ? WRITING_ACTIVITY_LANG_KEY
      : getAgentRunActivityLangKey(activity ?? ANALYZING_REQUEST_ACTIVITY))
    : undefined;
  const loadedThreadId = loadedThread?.id;
  const handleConsentDecline = useLastCallback(() => onBack?.());

  // A chat other than a news discussion opens once the user allows the Agent: it asks at once, and closing the sheet
  // leaves the chat, as on mobile
  useEffect(() => {
    if (!isActive || isConsentAccepted !== false) return;
    onRequestConsent?.(checkConsentAgain, undefined, handleConsentDecline);
  }, [checkConsentAgain, handleConsentDecline, isActive, isConsentAccepted, onRequestConsent]);

  useEffect(() => {
    if (loadedThreadId) onAnswerChange?.(loadedThreadId, answerLangKey);
  }, [answerLangKey, loadedThreadId, onAnswerChange]);

  useEffect(() => {
    if (loadedThread && isUnreadStateReady) onThreadLoaded?.(loadedThread);
  }, [isUnreadStateReady, loadedThread, onThreadLoaded]);

  const firstUnreadPosition = firstUnread?.position;
  useEffect(() => {
    if (firstUnreadPosition !== undefined && firstUnreadPosition !== unreadStart) {
      onUnreadStartResolved?.(chatKey!, firstUnreadPosition);
    }
  }, [chatKey, firstUnreadPosition, onUnreadStartResolved, unreadStart]);

  const handleFollowup = useLastCallback((messageId: number, followup: AgentPublicFollowUpV2) => {
    if (isAwaitingConsent) onRequestConsent(send);
    else send();

    function send() {
      requestLiveTailRef.current?.(followup.id);
      sendFollowup(messageId, followup);
    }
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
    if (message.supportEvent) {
      return <AgentSupportEventLine key={message.id} event={message.supportEvent} timestamp={message.timestamp} />;
    }
    // A digest's discussion opens with the digest's post, which its thread describes
    const digest = thread?.digest;
    if (message.isNewsPost && (news || digest)) {
      return (
        <AgentNewsPost
          key={message.id}
          {...(news ? { news } : { digest: digest! })}
          message={message}
          isDisabled={isInputDisabled}
          shouldShowFollowups={isLatest && !isRunActive}
          hasLoadFailed={Boolean(historyFailure)}
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
        hasAuthor={Boolean(supportOperator)}
        // A suggestion tapped while support has the chat would go to the operator, so none is offered then. The
        // device's copy of the history left with a failure offers none either: the chat takes none until it loads.
        areFollowupsHeld={isRunActive || isWithSupport || (isHistoryCached && Boolean(historyFailure))}
        // The device's copy of the history shows its suggestions as the history does, out of reach until it loads
        areFollowupsInactive={isHistoryCached}
        // The answer being answered again keeps its place until it turns to dust; the activity comes after it
        isRegenerating={isRegenerating}
        activity={isLatest && !isRegenerating ? activity : undefined}
        activityHandoff={activityHandoff}
        textRevealPresentation={context.textRevealPresentation}
        isJustAdded={context.isJustAdded}
        // Support reads every message as it was sent, so none is edited while support has the chat
        onEdit={canEditMessages ? context.onEditMessage : undefined}
        onFollowup={handleFollowup}
        onAction={activateAction}
        onRetry={message.isRetryAvailable && !isLimitHolding && !isWithSupport ? handleRegenerate : undefined}
        noFailureCaption={message.id === statusFailedMessage?.id}
        onRegenerate={canRegenerate ? handleRegenerate : undefined}
        onRate={isHistoryCached ? undefined : rateMessage}
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
      placeholder={isWithSupport ? lang('$agent_support_placeholder') : undefined}
    />
  ));
  // The device's copy of the history stands in for it only in a chat that opens at its end. One that opens at its first
  // unread message, may do so as its list row is the device's copy too, or opens where it was left before it mounted
  // again waits for the history, which alone places it there, and after a failed load shows the failure as without
  // the copy.
  const isCachedHistoryHidden = isHistoryCached
    && (unreadStart !== undefined || isUnreadStateUnknown || Boolean(session?.initial));
  const conversation = useMemo(() => ({
    messages: isCachedHistoryHidden ? NO_MESSAGES : messages,
    hints,
    // A news discussion shows its post, a new chat its question, and a thread the device's copy of its history, while
    // the server is still preparing them
    isInitialLoadComplete: isInitialLoadComplete || isOpeningNews || hasPendingQuestion
      || (isHistoryCached && !isCachedHistoryHidden),
    hasOpeningQuestion: hasPendingQuestion,
    // A new chat has no history to wait for, nor does a chat that opens with the history it had
    hasHistoryPlaceholder: target?.kind === 'thread' && !isOpenedWithCachedHistory,
    // The placeholder takes the shape of what the chat's list row says it holds
    historyPlaceholderLayout,
    unreadMessageId: firstUnread?.messageId,
    loadFailure: historyFailure && { ...historyFailure, onRetry: retryHistory },
    isRunActive,
    textRevealPresentations,
    dissolvingMessageIds,
    isFooterDissolving: isStatusDissolving,
    onDissolveStart: handleDissolveStart,
    renderMessage,
  }), [
    dissolvingMessageIds, firstUnread, handleDissolveStart, hasPendingQuestion, historyFailure,
    historyPlaceholderLayout, hints, isCachedHistoryHidden, isHistoryCached, isInitialLoadComplete,
    isOpenedWithCachedHistory, isOpeningNews, isRunActive, isStatusDissolving, messages, renderMessage, retryHistory,
    target, textRevealPresentations,
  ]);
  const composer = useMemo(() => ({
    isDisabled: isInputDisabled,
    shouldHide: !isInputVisible,
    canStop: canStopRun,
    onStop: handleStop,
    onSendMessage: sendMessage,
    onSendHint: sendHint,
    onHeightChange: handleComposerHeightChange,
    onRequestConsent: isAwaitingConsent ? onRequestConsent : undefined,
    render: renderComposer,
  }), [
    canStopRun, handleComposerHeightChange, isAwaitingConsent, isInputDisabled, isInputVisible, onRequestConsent,
    handleStop, renderComposer, sendHint, sendMessage,
  ]);
  const history = useMemo<AgentConversationHistory>(() => ({
    hasOlderMessages,
    isLoading: isLoadingOlderMessages,
    mode: 'continuous',
    loadOlderMessages,
  }), [hasOlderMessages, isLoadingOlderMessages, loadOlderMessages]);
  const slots = useMemo(() => ({
    messageListFooter: chatStatus
      ?? (isActivityInFooter
        ? (
          <AgentRunActivity
            key="activity"
            activity={stoppedActivity ?? activity}
            isStopped={Boolean(stoppedActivity)}
            handoff={activityHandoff}
          />
        )
        : undefined),
    bottomStickDependency: chatStatus ?? activity,
  }), [activity, activityHandoff, chatStatus, isActivityInFooter, stoppedActivity]);
  // The server keeps a thread nameless until it holds a message; the question shows until then, as on mobile
  const isNamedThread = Boolean(thread?.messageCount);
  const firstQuestion = firstOutgoingMessage?.text ?? initialMessage ?? news?.headline;
  const hasMessages = messages.length > 0;
  // A chat whose thread is known or on its way has the menu
  const hasMenu = Boolean(target || thread) || hasMessages || isOpeningNews;
  // Chats open once consent is given, so the chat's own header shows while the chat checks it
  const header = useMemo<AgentConversationHeader | undefined>(() => (target ? {
    // A known thread whose history has not loaded yet has a name that is not known yet either.
    // An empty name is no name, so the header keeps the question rather than going blank.
    title: ((isNamedThread ? thread?.title : undefined) || firstQuestion)
      ?? (target.kind === 'thread' && !thread ? '' : lang('New Chat')),
    icon: isNamedThread ? thread?.icon : undefined,
    subtitle: isWithSupport ? getSupportSubtitle(lang, support.state, supportOperator?.name) : undefined,
    hasBackButton: Boolean(onBack),
    hasMenu,
  } : undefined), [
    firstQuestion, hasMenu, isNamedThread, isWithSupport, lang, onBack, support, supportOperator, target, thread,
  ]);
  const handleDelete = useLastCallback(() => {
    onDelete!(thread, cancelPendingRequests);
  });
  // A news discussion the user hasn't written in, before consent or after it, is left out of the chat list and has
  // nothing to delete; a question sent here counts at once
  const isUntouchedNews = Boolean(news || thread?.digest || target?.kind === 'digest'
    || (target?.kind === 'thread' && target.isNews)) && !firstOutgoingMessage
    && !(thread && getIsAgentV2ThreadStarted(thread));
  const canDelete = Boolean(onDelete && hasMenu && !isUntouchedNews);
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
      // An operator answers in seconds or minutes, if at all, so the chat scrolls as a messenger does
      noLiveTail={isWithSupport}
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

function findLatestOperator(messages: AgentMessage[]) {
  for (let index = messages.length - 1; index >= 0; index--) {
    const { operator, supportEvent } = messages[index];
    if (operator) return operator;
    if (supportEvent?.code === 'operator_joined' && supportEvent.operatorName) {
      return { name: supportEvent.operatorName };
    }
  }
  return undefined;
}

function getSupportSubtitle(lang: LangFn, state: 'waiting' | 'operator' | 'closed', operatorName?: string): string {
  if (state === 'operator' && operatorName) {
    return lang('$agent_support_with_operator', { name: operatorName }) as string;
  }
  return state === 'operator' ? lang('$agent_support_label') : lang('$agent_support_waiting');
}
