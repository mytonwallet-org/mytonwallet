import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useStreamingText from './hooks/useStreamingText';

import StreamingTextContent from './StreamingTextContent';

import styles from './StreamingText.module.scss';

interface OwnProps {
  text: string;
  isStreaming: boolean;
  isHidden?: boolean;
  shouldAnimate: boolean;
  revealSessionKey?: string;
  shouldRevealFromStart?: boolean;
  onRevealStart?: NoneToVoidFunction;
  onRevealProgress?: NoneToVoidFunction;
  onRevealComplete?: NoneToVoidFunction;
}

function StreamingText({
  text,
  isStreaming,
  isHidden = false,
  shouldAnimate,
  revealSessionKey,
  shouldRevealFromStart = false,
  onRevealStart,
  onRevealProgress,
  onRevealComplete,
}: OwnProps) {
  const {
    containerRef,
    contentRef,
    revealEdgeLayerRef,
    visibleText,
    visualPhase,
  } = useStreamingText({
    text,
    isStreaming,
    shouldAnimate,
    revealSessionKey,
    shouldRevealFromStart,
    onRevealStart,
    onRevealProgress,
    onRevealComplete,
  });

  return (
    <div
      ref={containerRef}
      className={buildClassName(styles.container, isHidden && styles.containerHidden)}
      data-agent-streaming-container
    >
      <StreamingTextContent
        contentRef={contentRef}
        text={visibleText}
        phase={visualPhase}
      />
      <span
        ref={revealEdgeLayerRef}
        className={styles.revealEdgeLayer}
        data-agent-streaming-reveal-edge
        aria-hidden
      />
    </div>
  );
}

export default memo(StreamingText);
