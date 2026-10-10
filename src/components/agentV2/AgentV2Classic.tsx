import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage, AnimationLevel } from '../../global/types';
import type {
  AgentConversationComposerHeightContext,
  AgentConversationComposerProps,
  AgentConversationHistory,
  AgentConversationMessageContext,
} from '../agent/AgentConversationShell';

import { AGENT_V2_QUOTA_STATUS_ENABLED } from '../../config';
import { updateAgentV2InputBarSpacing } from './inputBarSpacing';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentV2Messages from '../agent/hooks/useAgentV2Messages';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentInputBar from '../agent/AgentInputBar';
import AgentRunActivity from '../agent/AgentRunActivity';
import MessageBubble from '../agent/MessageBubble';
import { AgentComposerStatus, AgentQuotaStatus } from './AgentStatusNotice';
import { AgentV2ConsentScreen } from './AgentV2Conversation';

interface OwnProps {
  isActive: boolean;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

export function AgentV2Classic({
  isActive,
  animationLevel,
  onScroll,
}: OwnProps & StateProps) {
  const { switchToWallet } = getActions();
  const lang = useLang();
  const requestLiveTailRef = useRef<NoneToVoidFunction>();
  const {
    messages,
    hints,
    activity,
    isInitialLoadComplete,
    isInputDisabled,
    isRunActive,
    isConsentAccepted,
    textRevealPresentations,
    hasOlderMessages,
    isLoadingOlderMessages,
    loadOlderMessages,
    sendMessage,
    sendHint,
    sendFollowup,
    clearChat,
    reportProblem,
    acceptConsent,
    composerStatus,
    userQuota,
    retryMessage,
    retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession,
    settleTextRevealSession,
  } = useAgentV2Messages({ isActive, lang });

  const lastMessage = messages[messages.length - 1];
  // Once the answer message exists, it hosts the run indicator in place of its bubble
  const isActivityInFooter = !lastMessage || lastMessage.isOutgoing;

  const handleFollowup = useLastCallback((messageId: number, followup: AgentPublicFollowUpV2) => {
    requestLiveTailRef.current?.();
    sendFollowup(messageId, followup);
  });

  const renderMessage = useLastCallback((
    message: AgentMessage,
    context: AgentConversationMessageContext,
  ) => {
    requestLiveTailRef.current = context.onRequestLiveTail;
    const isLatest = message.id === lastMessage?.id;

    return (
      <MessageBubble
        key={message.id}
        message={message}
        isDisabled={isInputDisabled}
        shouldAnimateTextStreaming={context.shouldAnimateTextStreaming}
        isLatest={isLatest}
        activity={isLatest ? activity : undefined}
        textRevealPresentation={context.textRevealPresentation}
        isJustAdded={context.isJustAdded}
        onEdit={context.onEditMessage}
        onFollowup={handleFollowup}
        onAction={activateAction}
        onRetry={message.isRetryAvailable ? retryMessage : undefined}
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

  const isInputVisible = isConsentAccepted === true;
  const visibleComposerStatus = isInputVisible ? composerStatus : undefined;
  const canRetryAdmission = visibleComposerStatus?.kind === 'rateLimit'
    || (visibleComposerStatus?.kind === 'userQuota' && Boolean(visibleComposerStatus.clientRunId));
  const statusSlot = visibleComposerStatus ? (
    <AgentComposerStatus
      status={visibleComposerStatus}
      isRetryDisabled={isInputDisabled}
      onRetry={canRetryAdmission ? retryAdmission : undefined}
      onExpired={refreshExpiredComposerStatus}
    />
  ) : undefined;

  const renderComposer = useLastCallback((props: AgentConversationComposerProps) => (
    <AgentInputBar
      {...props}
      userQuota={AGENT_V2_QUOTA_STATUS_ENABLED ? userQuota : undefined}
      quotaStatus={AGENT_V2_QUOTA_STATUS_ENABLED && userQuota
        ? <AgentQuotaStatus quota={userQuota} />
        : undefined}
      statusNotice={statusSlot}
    />
  ));
  const conversation = useMemo(() => ({
    messages,
    hints,
    isInitialLoadComplete,
    isRunActive,
    textRevealPresentations,
    renderMessage,
  }), [hints, isInitialLoadComplete, isRunActive, messages, renderMessage, textRevealPresentations]);
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
    body: isConsentAccepted === false ? <AgentV2ConsentScreen onAccept={acceptConsent} /> : undefined,
    messageListFooter: isActivityInFooter ? <AgentRunActivity key="activity" activity={activity} /> : undefined,
    bottomStickDependency: activity,
  }), [acceptConsent, activity, isActivityInFooter, isConsentAccepted]);
  const actions = useMemo(() => ({
    onBack: switchToWallet,
    onClearChat: clearChat,
    onReportProblem: reportProblem,
    onScroll,
  }), [clearChat, onScroll, reportProblem, switchToWallet]);

  return (
    <AgentConversationShell
      isActive={isActive}
      animationLevel={animationLevel}
      conversation={conversation}
      composer={composer}
      history={history}
      slots={slots}
      actions={actions}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    animationLevel: global.settings.animationLevel,
  };
})(AgentV2Classic));
