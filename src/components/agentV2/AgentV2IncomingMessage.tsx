import type { ElementRef } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentV2LiveAction,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { AgentRunActivityHandoff, AgentRunActivityType } from '../agent/AgentRunActivity';
import type { TextRevealPresentation } from '../agent/hooks/textRevealPresentation';

import buildClassName from '../../util/buildClassName';
import { startTypingAnswerMorph } from '../agent/helpers/typingAnswerMorph';
import { getAgentV2ErrorText, getAgentV2NoticeTexts } from './agentV2Copy';
import useAgentFeedbackBadge from './useAgentFeedbackBadge';

import useForceUpdate from '../../hooks/useForceUpdate';
import useLang, { LangProvider, useLangForCode } from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useTimeout from '../../hooks/useTimeout';

import AgentRunActivity from '../agent/AgentRunActivity';
import AgentFeedbackBadge from './AgentFeedbackBadge';
import AgentMessageControls from './AgentMessageControls';
import { AgentFailureCaption } from './AgentStatusNotice';
import { AgentV2AssistantText } from './AgentV2Conversation';

import styles from '../agent/MessageBubble.module.scss';
import v2styles from './AgentV2IncomingMessage.module.scss';

interface OwnProps {
  message: AgentMessage;
  contentRef: ElementRef<HTMLDivElement>;
  isDisabled: boolean;
  shouldAnimateTextStreaming: boolean;
  shouldAnimateAppearance?: boolean;
  isLatest?: boolean;
  /** Shows the run's activity in place of the bubble, as the answer being produced */
  isActivityHost?: boolean;
  areFollowupsHeld?: boolean;
  /** The suggestions keep the look they have when they can be pressed, and a press does nothing */
  areFollowupsInactive?: boolean;
  /** The answer's menu is open over the chat's tint */
  isMenuOpen?: boolean;
  /** The cloud of reactions is open over the answer, whose rating reaches its corner once the cloud has gone */
  isFeedbackCloudOpen?: boolean;
  activity?: AgentRunActivityType;
  activityHandoff?: AgentRunActivityHandoff;
  textRevealPresentation?: TextRevealPresentation;
  onMouseDown: (e: React.MouseEvent) => void;
  /** Opens the answer's menu, from the bubble or from its reaction's emoji */
  onContextMenu: (e: React.MouseEvent) => void;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  onAction?: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
  onRetry?: (messageId: number) => void;
  /** The chat's status tells the failure in place of its caption */
  noFailureCaption?: boolean;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onTextRevealProgress?: NoneToVoidFunction;
  onTextRevealComplete?: NoneToVoidFunction;
}

/** `setTimeout` stores its delay in a 32-bit signed integer. */
const MAX_TIMEOUT_DELAY = 2 ** 31 - 1;

function AgentV2IncomingMessage({
  message,
  contentRef,
  isDisabled,
  shouldAnimateTextStreaming,
  shouldAnimateAppearance = false,
  isLatest = false,
  isActivityHost = false,
  areFollowupsHeld = false,
  areFollowupsInactive = false,
  isMenuOpen = false,
  isFeedbackCloudOpen = false,
  activity,
  activityHandoff,
  textRevealPresentation,
  onMouseDown,
  onContextMenu,
  onFollowup,
  onAction,
  onRetry,
  noFailureCaption = false,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const {
    id, text, shouldCommitMarkdownTail, isTyping, isStreaming, semanticContent,
    actions, actionPresentations, followups, error, failureText, responseLanguage,
  } = message;
  const lang = useLangForCode(responseLanguage);
  // The reaction is the app's, and is told in its language
  const appLang = useLang();
  const noticeContent = semanticContent?.kind === 'notice' ? semanticContent : undefined;
  const noticeText = noticeContent ? getAgentV2NoticeTexts(noticeContent, lang).join('\n\n')
    : semanticContent ? lang('$agent_error_invalid_response') : undefined;
  const incomingText = noticeText ?? text;
  const hasRichContent = Boolean(actions?.length || followups?.length);
  const hasActionButtons = Boolean(actions?.length);
  const shouldRenderIncomingBubble = Boolean(isTyping || incomingText || message.tableReferences?.length);
  const isTextRevealActive = textRevealPresentation?.status === 'active' && Boolean(incomingText);
  const areControlsVisible = hasRichContent && !isTextRevealActive;
  // Suggestions hang from the bubble, which has no tail over them while they show, as on mobile; action buttons keep it
  const isTailless = areControlsVisible && isLatest && !areFollowupsHeld && Boolean(followups?.length)
    && !hasActionButtons;
  // Suggestions that arrive while the chat is open grow into place; an answer from the history has them already
  const hadFollowupsAtMountRef = useRef(Boolean(followups?.length));
  const forceUpdate = useForceUpdate();
  const quotaResetAt = error?.code === 'user_quota_exhausted' && typeof error.resetAt === 'string'
    ? error.resetAt : undefined;
  const quotaResetDelay = !noFailureCaption && quotaResetAt ? Date.parse(quotaResetAt) - Date.now() : 0;
  useTimeout(forceUpdate, quotaResetDelay > 0 ? quotaResetDelay : undefined);
  // A failure of the answer tells its code in words; a failure of the chat brings words of its own
  const captionText = noFailureCaption ? undefined
    : error ? getAgentV2ErrorText(error.code, lang, quotaResetAt) : failureText;
  const badge = useAgentFeedbackBadge(id, message.feedback, isFeedbackCloudOpen);
  const bubbleRef = useRef<HTMLDivElement>();
  // The run's indicator stands in for the bubble until the answer's first text, and the bubble grows out of it then,
  // as on iOS
  const isActivityPlaceholder = isActivityHost && !captionText && Boolean(activity) && !shouldRenderIncomingBubble;
  const isPreviousActivityPlaceholderRef = useRef(isActivityPlaceholder);

  useLayoutEffect(() => {
    const isPreviousActivityPlaceholder = isPreviousActivityPlaceholderRef.current;
    isPreviousActivityPlaceholderRef.current = isActivityPlaceholder;
    const row = contentRef.current?.querySelector<HTMLElement>('[data-agent-run-activity]');
    const bubble = bubbleRef.current;
    if (!isPreviousActivityPlaceholder || !shouldRenderIncomingBubble || !shouldAnimateTextStreaming) return;

    if (row && bubble) startTypingAnswerMorph(row, bubble);
  }, [contentRef, isActivityPlaceholder, shouldAnimateTextStreaming, shouldRenderIncomingBubble]);

  // Every component under the answer that takes its language renders again when the context gets another object
  const langContextValue = useMemo(() => ({ lang }), [lang]);

  const handleRetry = useLastCallback(() => onRetry?.(id));

  return (
    <LangProvider value={langContextValue}>
      <div
        ref={contentRef}
        lang={lang.code}
        onMouseDown={onMouseDown}
        onContextMenu={onContextMenu}
        className={buildClassName(
          styles.wrapper,
          hasRichContent && styles.wrapperRich,
          hasActionButtons && styles.wrapperRichActions,
          // Action buttons keep the width of the answer, and the failure is centered under them
          captionText && !hasActionButtons && styles.wrapperWithFailure,
          isMenuOpen && styles.wrapperMenuOpen,
        )}
      >
        {shouldRenderIncomingBubble && (
          <div
            ref={bubbleRef}
            className={buildClassName(
              styles.bubble,
              styles.incoming,
              message.operator && styles.incomingOperator,
              isTailless && styles.tailless,
              shouldAnimateAppearance && styles.appearing,
            )}
          >
            {/* An operator writes plain text, which the agent's Markdown rules would misread */}
            {message.operator && <span className={styles.operatorText}>{incomingText}</span>}
            {!isTyping && !message.operator && (
              <AgentV2AssistantText
                key={getIncomingMessageKey(textRevealPresentation)}
                messageId={id}
                text={incomingText}
                tables={message.tables}
                tableReferences={message.tableReferences}
                links={message.links}
                isStreaming={Boolean(isStreaming)}
                shouldAnimate={shouldAnimateTextStreaming}
                shouldCommitMarkdownTail={shouldCommitMarkdownTail}
                textRevealPresentation={textRevealPresentation}
                onTextRevealSessionConsumed={onTextRevealSessionConsumed}
                onTextRevealSessionSettled={onTextRevealSessionSettled}
                onRevealProgress={onTextRevealProgress}
                onRevealComplete={onTextRevealComplete}
              />
            )}
            {badge.feedback && (
              <AgentFeedbackBadge
                feedback={badge.feedback}
                replacedFeedback={badge.replacedFeedback}
                motion={badge.motion}
                isAwaitingFlight={badge.isAwaitingFlight}
                landingKey={badge.landingKey}
                label={appLang(badge.feedback === 'like' ? 'Liked' : 'Disliked')}
                onClick={onContextMenu}
              />
            )}
          </div>
        )}
        {/* The failure takes the activity's place at once rather than after it fades */}
        {isActivityHost && !captionText && (
          <AgentRunActivity activity={activity} isAnswerPlaceholder handoff={activityHandoff} />
        )}
        {areControlsVisible && (
          <AgentMessageControls
            followups={followups}
            isDisabled={isDisabled && !areFollowupsInactive}
            isInactive={areFollowupsInactive}
            shouldShowFollowups={isLatest && !areFollowupsHeld}
            shouldAnimateGrowth={shouldAnimateTextStreaming && !hadFollowupsAtMountRef.current}
            onGrowthFrame={onTextRevealProgress}
            onFollowup={(followup) => {
              if (!areFollowupsInactive) onFollowup?.(id, followup);
            }}
          >
            {actions?.map((action) => {
              const presentation = actionPresentations?.[action.id];
              const requiresActivePresentation = action.kind === 'send';
              const isActionActive = presentation?.kind !== 'inactive'
                && (!requiresActivePresentation
                  || (presentation?.kind === 'send' && presentation.status === 'active'));

              return (
                <MemoizedAgentV2ActionButton
                  key={action.id}
                  messageId={id}
                  action={action}
                  expiresAt={presentation?.kind === 'send' ? presentation.expiresAt : undefined}
                  isActive={isActionActive}
                  isDisabled={isDisabled || !onAction}
                  onAction={onAction}
                />
              );
            })}
          </AgentMessageControls>
        )}
        {captionText && (
          <div className={styles.failure}>
            <AgentFailureCaption
              text={captionText}
              isRetryDisabled={isDisabled}
              onRetry={onRetry ? handleRetry : undefined}
            />
          </div>
        )}
      </div>
    </LangProvider>
  );
}

interface AgentV2ActionButtonProps {
  messageId: number;
  action: AgentV2LiveAction | AgentPersistedActionV2;
  expiresAt?: string;
  isActive: boolean;
  isDisabled: boolean;
  onAction: OwnProps['onAction'];
}

function AgentV2ActionButton({
  messageId,
  action,
  expiresAt,
  isActive,
  isDisabled,
  onAction,
}: AgentV2ActionButtonProps) {
  const [isExpired, setIsExpired] = useState(() => isActionExpired(expiresAt));

  useEffect(() => {
    setIsExpired(isActionExpired(expiresAt));
    if (!expiresAt) return undefined;
    const timeout = Date.parse(expiresAt) - Date.now();
    // A delay above the 32-bit ceiling is truncated to its low bits, so it can land in the past and
    // fire at once, disabling a button that is nowhere near expiry. Such an expiry outlives any session.
    if (timeout <= 0 || timeout > MAX_TIMEOUT_DELAY) return undefined;
    const timer = window.setTimeout(() => setIsExpired(true), timeout);
    return () => window.clearTimeout(timer);
  }, [expiresAt]);

  // An unavailable action still takes a tap, which tells the user why it does not open
  const isUnavailable = !isActive || isExpired;

  const handleClick = useLastCallback(() => onAction?.(messageId, action));

  return (
    <button
      type="button"
      data-agent-action-kind={action.kind}
      className={buildClassName(
        styles.actionButton,
        v2styles.button,
        // A transfer to confirm stands out from the buttons that only open a screen
        action.kind === 'send' && v2styles.confirmButton,
      )}
      disabled={isDisabled}
      aria-disabled={isUnavailable || undefined}
      onClick={handleClick}
    >
      {action.title}
    </button>
  );
}

const MemoizedAgentV2ActionButton = memo(AgentV2ActionButton);

function isActionExpired(expiresAt?: string) {
  return Boolean(expiresAt && Date.parse(expiresAt) <= Date.now());
}

function getIncomingMessageKey(presentation?: TextRevealPresentation) {
  if (!presentation) return 'static';
  if (presentation.status === 'error') return `${presentation.key}:error`;
  return presentation.key;
}

export default memo(AgentV2IncomingMessage);
