import React, {
  type ElementRef, memo, useMemo,
} from '../../lib/teact/teact';

import type { TextRevealPhase } from '../../util/agent/TextRevealController';
import type { AnswerTableProps } from './AnswerMessageContent';

import { markAnswerLinks } from '../../util/agent/answerLinkMarkers';
import { segmentStreamingMarkdown } from '../../util/agent/streamingMarkdown';
import renderMarkdown from '../../util/renderMarkdown';

import AnswerMessageContent from './AnswerMessageContent';

import styles from './StreamingText.module.scss';

interface OwnProps extends AnswerTableProps {
  contentRef: ElementRef<HTMLDivElement>;
  text: string;
  phase: TextRevealPhase;
  shouldCommitMarkdownTail: boolean;
  areLinksEnabled: boolean;
}

function StreamingTextContent({
  contentRef,
  text,
  tables,
  tableReferences,
  links,
  phase,
  shouldCommitMarkdownTail,
  areLinksEnabled,
}: OwnProps) {
  // `text` is the revealed prefix, so a label is a link from its first revealed character
  const marked = useMemo(
    () => markAnswerLinks(text, links, tableReferences),
    [links, tableReferences, text],
  );
  const markdownSegments = useMemo(
    () => segmentStreamingMarkdown(marked.text, phase === 'complete' && shouldCommitMarkdownTail),
    [marked, phase, shouldCommitMarkdownTail],
  );

  return (
    <div
      ref={contentRef}
      className={styles.text}
      data-agent-streaming-text
      dir="auto"
      aria-busy={phase !== 'complete'}
    >
      {tables?.length ? (
        <AnswerMessageContent
          text={marked.text}
          tables={tables}
          tableReferences={marked.tableReferences}
          areLinksEnabled={areLinksEnabled}
        />
      ) : markdownSegments.blocks.map((block) => (
        <MemoizedMarkdownSegment
          key={block.offset}
          offset={block.offset}
          text={block.text}
          areLinksEnabled={areLinksEnabled}
        />
      ))}
      {!tables?.length && markdownSegments.tail && (
        <MarkdownSegment
          text={markdownSegments.tail}
          areLinksEnabled={areLinksEnabled}
        />
      )}
    </div>
  );
}

function MarkdownSegment({
  offset,
  text,
  areLinksEnabled,
}: {
  offset?: number;
  text: string;
  areLinksEnabled: boolean;
}) {
  const html = useMemo(
    () => renderMarkdown(text, { areLinksEnabled }).html,
    [areLinksEnabled, text],
  );

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
