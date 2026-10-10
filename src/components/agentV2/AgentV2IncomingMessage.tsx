import type { ElementRef } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useState,
} from '../../lib/teact/teact';

import type {
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentV2LiveAction,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { AgentRunActivityType } from '../agent/AgentRunActivity';
import type { TextRevealPresentation } from '../agent/hooks/textRevealPresentation';

import buildClassName from '../../util/buildClassName';
import { getAgentV2NoticeTexts } from './agentV2Copy';

import { LangProvider, useLangForCode } from '../../hooks/useLang';

import AgentRunActivity from '../agent/AgentRunActivity';
import AgentMessageControls from './AgentMessageControls';
import { AgentRunFailure } from './AgentStatusNotice';
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
  activity?: AgentRunActivityType;
  textRevealPresentation?: TextRevealPresentation;
  onMouseDown: (e: React.MouseEvent) => void;
  onContextMenu: (e: React.MouseEvent) => void;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  onAction?: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
  onRetry?: (messageId: number) => void;
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
  activity,
  textRevealPresentation,
  onMouseDown,
  onContextMenu,
  onFollowup,
  onAction,
  onRetry,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const {
    id, text, shouldCommitMarkdownTail, isTyping, isStreaming, semanticContent,
    actions, actionPresentations, followups, error, responseLanguage,
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
  const areRichContentVisible = hasRichContent && !isTextRevealActive;
  const hasPartialResponse = Boolean(incomingText.trim() || hasRichContent || message.tableReferences?.length);

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
        )}
      >
        {shouldRenderIncomingBubble && (
          <div className={buildClassName(styles.bubble, styles.incoming, shouldAnimateAppearance && styles.appearing)}>
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
        {isLatest && <AgentRunActivity activity={activity} isAnswerPlaceholder />}
        {areRichContentVisible && (
          <AgentMessageControls
            followups={followups}
            isDisabled={isDisabled}
            shouldShowFollowups={isLatest}
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
        {error && (
          <div className={styles.failure}>
            <AgentRunFailure
              error={error}
              hasPartialResponse={hasPartialResponse}
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

  return (
    <button
      type="button"
      data-agent-action-kind={actionKind}
      className={buildClassName(styles.actionButton, v2styles.button)}
      disabled={isDisabled || !isActive || isExpired}
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
