import type { ElementRef } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
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
import { getAgentV2ErrorText, getAgentV2NoticeTexts } from './agentV2Copy';

import { LangProvider, useLangForCode } from '../../hooks/useLang';

import AgentRunActivity from '../agent/AgentRunActivity';
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
  areFollowupsHeld?: boolean;
  /** The answer's menu is open over the chat's tint */
  isMenuOpen?: boolean;
  activity?: AgentRunActivityType;
  activityHandoff?: AgentRunActivityHandoff;
  textRevealPresentation?: TextRevealPresentation;
  onMouseDown: (e: React.MouseEvent) => void;
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
  areFollowupsHeld = false,
  isMenuOpen = false,
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
  const noticeContent = semanticContent?.kind === 'notice' ? semanticContent : undefined;
  const noticeText = noticeContent ? getAgentV2NoticeTexts(noticeContent, lang).join('\n\n')
    : semanticContent ? lang('$agent_error_invalid_response') : undefined;
  const incomingText = noticeText ?? text;
  const hasRichContent = Boolean(actions?.length || followups?.length);
  const hasActionButtons = Boolean(actions?.length);
  const shouldRenderIncomingBubble = Boolean(isTyping || incomingText || message.tableReferences?.length);
  const isTextRevealActive = textRevealPresentation?.status === 'active' && Boolean(incomingText);
  const areControlsVisible = hasRichContent && !isTextRevealActive;
  // Suggestions hang from the bubble, which has no tail over them, as on mobile; action buttons keep it
  const isTailless = areControlsVisible && isLatest && Boolean(followups?.length) && !hasActionButtons;
  // Suggestions that arrive while the chat is open grow into place; an answer from the history has them already
  const hadFollowupsAtMountRef = useRef(Boolean(followups?.length));
  // A failure of the answer tells its code in words; a failure of the chat brings words of its own
  const captionText = noFailureCaption ? undefined : error ? getAgentV2ErrorText(error.code, lang) : failureText;

  return (
    <LangProvider value={{ lang }}>
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
            className={buildClassName(
              styles.bubble,
              styles.incoming,
              isTailless && styles.tailless,
              shouldAnimateAppearance && styles.appearing,
            )}
          >
            {!isTyping && (
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
          </div>
        )}
        {/* The failure takes the activity's place at once rather than after it fades */}
        {isLatest && !captionText && (
          <AgentRunActivity activity={activity} isAnswerPlaceholder handoff={activityHandoff} />
        )}
        {areControlsVisible && (
          <AgentMessageControls
            followups={followups}
            isDisabled={isDisabled}
            shouldShowFollowups={isLatest && !areFollowupsHeld}
            shouldAnimateGrowth={shouldAnimateTextStreaming && !hadFollowupsAtMountRef.current}
            onGrowthFrame={onTextRevealProgress}
            onFollowup={(followup) => onFollowup?.(id, followup)}
          >
            {actions?.map((action) => {
              const presentation = actionPresentations?.[action.id];
              const requiresActivePresentation = action.kind === 'send';
              const isActionActive = presentation?.kind !== 'inactive'
                && (!requiresActivePresentation
                  || (presentation?.kind === 'send' && presentation.status === 'active'));

              return (
                <AgentV2ActionButton
                  key={action.id}
                  actionKind={action.kind}
                  label={action.title}
                  expiresAt={presentation?.kind === 'send' ? presentation.expiresAt : undefined}
                  isActive={isActionActive}
                  isDisabled={isDisabled || !onAction}
                  onClick={() => onAction?.(id, action)}
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
              onRetry={onRetry ? () => onRetry(id) : undefined}
            />
          </div>
        )}
      </div>
    </LangProvider>
  );
}

interface AgentV2ActionButtonProps {
  actionKind: AgentV2LiveAction['kind'];
  expiresAt?: string;
  isActive: boolean;
  isDisabled: boolean;
  label: string;
  onClick: NoneToVoidFunction;
}

function AgentV2ActionButton({
  actionKind,
  expiresAt,
  isActive,
  isDisabled,
  label,
  onClick,
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

  return (
    <button
      type="button"
      data-agent-action-kind={actionKind}
      className={buildClassName(
        styles.actionButton,
        v2styles.button,
        // A transfer to confirm stands out from the buttons that only open a screen
        actionKind === 'send' && v2styles.confirmButton,
      )}
      disabled={isDisabled}
      aria-disabled={isUnavailable || undefined}
      onClick={onClick}
    >
      {label}
    </button>
  );
}

function isActionExpired(expiresAt?: string) {
  return Boolean(expiresAt && Date.parse(expiresAt) <= Date.now());
}

function getIncomingMessageKey(presentation?: TextRevealPresentation) {
  if (!presentation) return 'static';
  if (presentation.status === 'error') return `${presentation.key}:error`;
  return presentation.key;
}

export default memo(AgentV2IncomingMessage);
