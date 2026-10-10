import React, { memo } from '../../lib/teact/teact';

import type { AnswerTableProps } from './AnswerMessageContent';

import useStreamingText from './hooks/useStreamingText';

import StreamingTextContent from './StreamingTextContent';

import styles from './StreamingText.module.scss';

interface OwnProps extends AnswerTableProps {
  text: string;
  isStreaming: boolean;
  shouldAnimate: boolean;
  revealSessionKey?: string;
  shouldRevealFromStart?: boolean;
  shouldCommitMarkdownTail: boolean;
  areLinksEnabled: boolean;
  onRevealProgress?: NoneToVoidFunction;
  onRevealComplete?: NoneToVoidFunction;
}

function StreamingText({
  text,
  tables,
  tableReferences,
  links,
  isStreaming,
  shouldAnimate,
  revealSessionKey,
  shouldRevealFromStart = false,
  shouldCommitMarkdownTail,
  areLinksEnabled,
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
    onRevealProgress,
    onRevealComplete,
  });

  return (
    <div
      ref={containerRef}
      className={styles.container}
      data-agent-streaming-container
    >
      <StreamingTextContent
        contentRef={contentRef}
        text={visibleText}
        tables={tables}
        tableReferences={tableReferences}
        links={links}
        phase={visualPhase}
        shouldCommitMarkdownTail={shouldCommitMarkdownTail}
        areLinksEnabled={areLinksEnabled}
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
