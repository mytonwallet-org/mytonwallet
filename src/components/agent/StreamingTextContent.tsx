import React, {
  type ElementRef, memo, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type { TextRevealPhase } from '../../util/agent/TextRevealController';
import type { AnswerTableProps } from './AnswerMessageContent';

import { markAnswerLinks } from '../../util/agent/answerLinkMarkers';
import { closeStreamingInlineMarkdown, segmentStreamingMarkdown } from '../../util/agent/streamingMarkdown';
import buildClassName from '../../util/buildClassName';
import renderMarkdown from '../../util/renderMarkdown';
import { copyClickedAgentCode } from './helpers/copyAgentText';

import useLang from '../../hooks/useLang';
import useSyncEffect from '../../hooks/useSyncEffect';

import AnswerMessageContent from './AnswerMessageContent';

import styles from './StreamingText.module.scss';

// The markup `renderMarkdown` opens with for a text that opens with a heading
const LEADING_HEADING_PATTERN = /^<h[1-6] class="agent-text-heading /;
// The closing tags `renderMarkdown` ends its markup with, after the last letter of the text
const TRAILING_CLOSING_TAGS_PATTERN = /(?:<\/[a-z][a-z0-9]*>)*$/;
const CLOSING_TAG_NAME_PATTERN = /<\/([a-z][a-z0-9]*)>/g;
// Characters that `renderMarkdown` writes as tags or entities rather than as they are
const MARKUP_CHARACTER_PATTERN = /[<>&]/;

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
  const lang = useLang();
  const codeCopyLabel = lang('Copy');
  // `text` is the revealed prefix, so a label is a link from its first revealed character
  const marked = useMemo(
    () => markAnswerLinks(text, links, tableReferences),
    [links, tableReferences, text],
  );
  const isTailCommitted = phase === 'complete' && shouldCommitMarkdownTail;
  const markdownSegments = useMemo(
    () => segmentStreamingMarkdown(marked.text, isTailCommitted),
    [isTailCommitted, marked],
  );

  return (
    <div
      ref={contentRef}
      className={styles.text}
      data-agent-streaming-text
      dir="auto"
      aria-busy={phase !== 'complete'}
      onClick={copyClickedAgentCode}
    >
      {tables?.length ? (
        <AnswerMessageContent
          text={marked.text}
          tables={tables}
          tableReferences={marked.tableReferences}
          areLinksEnabled={areLinksEnabled}
          isStreaming={!isTailCommitted}
        />
      ) : markdownSegments.blocks.map((block) => (
        <MemoizedMarkdownSegment
          key={block.offset}
          offset={block.offset}
          text={block.text}
          areLinksEnabled={areLinksEnabled}
          codeCopyLabel={codeCopyLabel}
        />
      ))}
      {!tables?.length && markdownSegments.tail && (
        <MemoizedMarkdownTail
          text={closeStreamingInlineMarkdown(markdownSegments.tail)}
          areLinksEnabled={areLinksEnabled}
          codeCopyLabel={codeCopyLabel}
        />
      )}
    </div>
  );
}

function MarkdownSegment({
  offset,
  text,
  areLinksEnabled,
  codeCopyLabel,
}: {
  offset?: number;
  text: string;
  areLinksEnabled: boolean;
  codeCopyLabel: string;
}) {
  // Teact sets the markup again whenever it gets another object, so the object lasts while the text is the same
  const markup = useMemo(
    () => ({ __html: renderMarkdown(text, { areLinksEnabled, codeCopyLabel }).html }),
    [areLinksEnabled, codeCopyLabel, text],
  );

  return (
    <div
      className={buildClassName(
        styles.markdownSegment,
        LEADING_HEADING_PATTERN.test(markup.__html) && styles.headingSegment,
      )}
      data-agent-markdown-offset={offset}
      dangerouslySetInnerHTML={markup}
    />
  );
}

const MemoizedMarkdownSegment = memo(MarkdownSegment);

/**
 * The tail of the text, which grows by a few letters on every frame of the reveal. Letters added at the end of the
 * markup are written into the shown nodes. Setting the tail's markup anew on every frame would create its nodes again
 * and make the browser style and lay them out from scratch. Any other change, as a new list item or a closed bold run,
 * replaces the markup.
 *
 * The tail writes while it renders. Teact renders it before it runs the layout effects of `useStreamingText`, so these
 * effects measure the letters that are shown.
 */
function MarkdownTail({
  text,
  areLinksEnabled,
  codeCopyLabel,
}: {
  text: string;
  areLinksEnabled: boolean;
  codeCopyLabel: string;
}) {
  const ref = useRef<HTMLDivElement>();
  const html = useMemo(
    () => renderMarkdown(text, { areLinksEnabled, codeCopyLabel }).html,
    [areLinksEnabled, codeCopyLabel, text],
  );
  // Teact writes the markup once, as the tail mounts, and the tail updates it after that
  const [initialMarkup] = useState(() => ({ __html: html }));
  const shownHtmlRef = useRef(html);

  useSyncEffect(() => {
    const element = ref.current;
    if (!element || html === shownHtmlRef.current) return;

    if (!appendToShownMarkup(element, shownHtmlRef.current, html)) {
      element.innerHTML = html;
    }
    shownHtmlRef.current = html;
  }, [html]);

  return (
    <div
      ref={ref}
      className={buildClassName(
        styles.markdownSegment,
        LEADING_HEADING_PATTERN.test(html) && styles.headingSegment,
      )}
      dangerouslySetInnerHTML={initialMarkup}
    />
  );
}

const MemoizedMarkdownTail = memo(MarkdownTail);

export default memo(StreamingTextContent);

/**
 * Makes the nodes of `element`, built from `shownHtml`, match `html` when `html` only adds letters before the closing
 * tags at its end, and tells whether it did. The nodes come out as the browser would build them from `html`.
 *
 * The closing tags name the elements the letters go into, from the outermost one down. Letters that follow a letter
 * lengthen its text node, and letters that follow a tag, as after a bold run or a line break, start a text node of
 * their own. `renderMarkdown` leaves the space that ends the text after the closing tags, where it is a text node of
 * the element itself.
 */
function appendToShownMarkup(element: HTMLElement, shownHtml: string, html: string) {
  const shownMarkup = shownHtml.trimEnd();
  const markup = html.trimEnd();
  if (markup.length <= shownMarkup.length) return false;

  // The letters go before all the closing tags or between them, as after a bold run that is already closed
  const trailingTagNames = Array.from(
    shownMarkup.match(TRAILING_CLOSING_TAGS_PATTERN)![0].matchAll(CLOSING_TAG_NAME_PATTERN),
    ([, tagName]) => tagName,
  );
  let tagNames: string[] | undefined;
  let insertionIndex = 0;
  for (let count = trailingTagNames.length; count >= 0 && !tagNames; count--) {
    const names = trailingTagNames.slice(trailingTagNames.length - count);
    const closingTags = names.map((name) => `</${name}>`).join('');
    insertionIndex = shownMarkup.length - closingTags.length;
    if (markup.endsWith(closingTags) && markup.startsWith(shownMarkup.slice(0, insertionIndex))) {
      tagNames = names;
    }
  }
  if (!tagNames || !insertionIndex) return false;

  const appendedText = markup.slice(insertionIndex, markup.length - (shownMarkup.length - insertionIndex));
  if (MARKUP_CHARACTER_PATTERN.test(appendedText)) return false;

  const shownTrailingSpace = shownHtml.slice(shownMarkup.length);
  const trailingSpaceNode = shownTrailingSpace ? element.lastChild : undefined;
  if (trailingSpaceNode && (!(trailingSpaceNode instanceof Text) || trailingSpaceNode.data !== shownTrailingSpace)) {
    return false;
  }

  let container: Node = element;
  let lastNode = trailingSpaceNode ? trailingSpaceNode.previousSibling : element.lastChild;
  for (const tagName of [...tagNames].reverse()) {
    if (!(lastNode instanceof HTMLElement) || lastNode.tagName.toLowerCase() !== tagName) return false;

    container = lastNode;
    lastNode = lastNode.lastChild;
  }

  const isAfterLetter = shownMarkup[insertionIndex - 1] !== '>';
  if (isAfterLetter && !(lastNode instanceof Text)) return false;

  trailingSpaceNode?.remove();
  if (isAfterLetter) {
    (lastNode as Text).appendData(appendedText);
  } else {
    container.appendChild(document.createTextNode(appendedText));
  }
  const trailingSpace = html.slice(markup.length);
  if (trailingSpace) {
    element.appendChild(document.createTextNode(trailingSpace));
  }

  return true;
}
