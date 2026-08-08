import React, {
  type ElementRef, memo, useMemo,
} from '../../lib/teact/teact';

import type { TextRevealPhase } from '../../util/agent/TextRevealController';

import { segmentStreamingMarkdown } from '../../util/agent/streamingMarkdown';
import renderMarkdown from '../../util/renderMarkdown';

import styles from './StreamingText.module.scss';

interface OwnProps {
  contentRef: ElementRef<HTMLDivElement>;
  text: string;
  phase: TextRevealPhase;
}

function StreamingTextContent({
  contentRef,
  text,
  phase,
}: OwnProps) {
  const markdownSegments = useMemo(
    () => segmentStreamingMarkdown(text, phase === 'complete'),
    [phase, text],
  );

  return (
    <div
      ref={contentRef}
      className={styles.text}
      data-agent-streaming-text
      dir="auto"
      aria-busy={phase !== 'complete'}
    >
      {markdownSegments.blocks.map((block) => (
        <MemoizedMarkdownSegment
          key={block.offset}
          offset={block.offset}
          text={block.text}
        />
      ))}
      {markdownSegments.tail && (
        <MarkdownSegment text={markdownSegments.tail} />
      )}
    </div>
  );
}

function MarkdownSegment({
  offset,
  text,
}: {
  offset?: number;
  text: string;
}) {
  const html = useMemo(() => renderMarkdown(text).html, [text]);

  return (
    <div
      className={styles.markdownSegment}
      data-agent-markdown-offset={offset}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}

const MemoizedMarkdownSegment = memo(MarkdownSegment);

export default memo(StreamingTextContent);
