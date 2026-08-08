import type { ElementRef } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useState,
} from '../../lib/teact/teact';

import type { ActionButton } from '../../util/renderMarkdown';
import type { TextRevealPresentation } from './hooks/useAgentMessages';

import buildClassName from '../../util/buildClassName';
import { getTranslation } from '../../util/langProvider';

import useLastCallback from '../../hooks/useLastCallback';

import LoadingDots from '../ui/LoadingDots';
import StaticText from './StaticText';
import StreamingText from './StreamingText';

import styles from './MessageBubble.module.scss';

interface OwnProps {
  messageId: number;
  text: string;
  isTyping?: boolean;
  isStreaming?: boolean;
  shouldAnimateTextStreaming: boolean;
  textRevealPresentation?: TextRevealPresentation;
  buttons: ActionButton[];
  contentRef: ElementRef<HTMLDivElement>;
  onMouseDown: (e: React.MouseEvent) => void;
  onContextMenu: (e: React.MouseEvent) => void;
  onActionClick: (url: string) => void;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onTextRevealProgress?: NoneToVoidFunction;
  onTextRevealComplete?: NoneToVoidFunction;
}

const STREAMING_SHELL_ANIMATION_NAME = 'expand-incoming-streaming-shell';

function IncomingMessage({
  messageId,
  text,
  isTyping = false,
  isStreaming = false,
  shouldAnimateTextStreaming,
  textRevealPresentation,
  buttons,
  contentRef,
  onMouseDown,
  onContextMenu,
  onActionClick,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const activeTextRevealPresentation = textRevealPresentation?.status === 'active'
    ? textRevealPresentation
    : undefined;
  const isRevealActive = Boolean(activeTextRevealPresentation);
  const isRevealSettled = textRevealPresentation?.status === 'settled';
  const [shouldRevealFromStart] = useState(
    Boolean(activeTextRevealPresentation?.shouldRevealFromStart),
  );
  const [hasStreamingShellStarted, setHasStreamingShellStarted] = useState(false);
  const [shouldAnimateStreamingShell, setShouldAnimateStreamingShell] = useState(false);
  const [areActionButtonsReady, setAreActionButtonsReady] = useState(
    !isRevealActive || !shouldAnimateTextStreaming,
  );
  const hasImmediateStreamingShell = Boolean(
    isRevealActive
    && !shouldAnimateTextStreaming
    && !isTyping
    && text,
  );
  const isStreamingShellActive = isRevealSettled
    || hasStreamingShellStarted
    || hasImmediateStreamingShell;
  const areActionButtonsVisible = buttons.length > 0
    && (!isRevealActive || !shouldAnimateTextStreaming || areActionButtonsReady);
  const isWaitingForStreamingReveal = Boolean(
    isRevealActive
    && shouldAnimateTextStreaming
    && !isTyping
    && text
    && !isStreamingShellActive,
  );

  useEffect(() => {
    if (!activeTextRevealPresentation?.shouldRevealFromStart) return;

    onTextRevealSessionConsumed?.(messageId, activeTextRevealPresentation.key);
  }, [
    activeTextRevealPresentation, messageId, onTextRevealSessionConsumed,
  ]);

  const handleTextRevealComplete = useLastCallback(() => {
    setAreActionButtonsReady(true);
    onTextRevealComplete?.();

    if (activeTextRevealPresentation) {
      onTextRevealSessionSettled?.(messageId, activeTextRevealPresentation.key);
    }
  });

  const handleTextRevealStart = useLastCallback(() => {
    if (!isRevealActive || isStreamingShellActive) return;

    setHasStreamingShellStarted(true);
    setShouldAnimateStreamingShell(shouldAnimateTextStreaming);
  });

  const handleStreamingShellAnimationEnd = useLastCallback((e: React.AnimationEvent<HTMLDivElement>) => {
    if (
      e.target !== e.currentTarget
      || !e.animationName.includes(STREAMING_SHELL_ANIMATION_NAME)
    ) {
      return;
    }

    setShouldAnimateStreamingShell(false);
  });

  return (
    <div
      ref={contentRef}
      onMouseDown={onMouseDown}
      onContextMenu={onContextMenu}
      className={buildClassName(styles.wrapper, isStreamingShellActive && styles.wrapperExpanded)}
      data-agent-streaming-shell={isStreamingShellActive || undefined}
    >
      <div
        className={buildClassName(
          styles.bubble,
          styles.incoming,
          areActionButtonsVisible && styles.hasButtons,
          isStreamingShellActive && styles.incomingStreamingShell,
          shouldAnimateStreamingShell && styles.incomingStreamingShellAnimated,
        )}
        data-agent-streaming-waiting={isWaitingForStreamingReveal || undefined}
        data-agent-streaming-shell-animated={shouldAnimateStreamingShell || undefined}
        onAnimationEnd={handleStreamingShellAnimationEnd}
      >
        {isTyping || isWaitingForStreamingReveal ? (
          <div role="status" aria-label={getTranslation('Loading...')}>
            <LoadingDots className={styles.loadingDots} isActive />
          </div>
        ) : undefined}
        {!isTyping && (
          isRevealActive ? (
            <StreamingText
              text={text}
              isStreaming={Boolean(isStreaming)}
              isHidden={isWaitingForStreamingReveal}
              shouldAnimate={shouldAnimateTextStreaming}
              revealSessionKey={activeTextRevealPresentation.key}
              shouldRevealFromStart={shouldRevealFromStart}
              onRevealStart={handleTextRevealStart}
              onRevealProgress={onTextRevealProgress}
              onRevealComplete={handleTextRevealComplete}
            />
          ) : (
            <StaticText text={text} />
          )
        )}
      </div>
      {areActionButtonsVisible && (
        <div className={styles.buttons}>
          {buttons.map((button) => (
            <button
              key={button.url}
              type="button"
              className={styles.actionButton}
              onClick={() => onActionClick(button.url)}
            >
              {button.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export default memo(IncomingMessage);
