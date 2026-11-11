import { MARKDOWN_BOLD_PATTERN, MARKDOWN_ITALIC_PATTERN } from '../renderMarkdown';

const FENCE_PATTERN = /^\s*(`{3,}|~{3,})/;
const LIST_ITEM_PATTERN = /^\s*(?:[-+*]|\d+[.)])\s+/;

interface MarkdownBlock {
  offset: number;
  text: string;
}

interface MarkdownSegments {
  blocks: MarkdownBlock[];
  tail: string;
}

interface MarkdownLine {
  start: number;
  end: number;
  content: string;
}

export function segmentStreamingMarkdown(
  text: string,
  shouldCommitTail = false,
): MarkdownSegments {
  const lines = splitMarkdownLines(text);
  const blocks: MarkdownBlock[] = [];
  let blockStart = 0;
  let fenceMarker: string | undefined;

  lines.forEach((line, index) => {
    const fenceMatch = line.content.match(FENCE_PATTERN);
    if (fenceMatch) {
      const marker = fenceMatch[1];
      if (!fenceMarker) {
        fenceMarker = marker;
      } else if (marker[0] === fenceMarker[0] && marker.length >= fenceMarker.length) {
        fenceMarker = undefined;
      }
      return;
    }

    if (fenceMarker || line.content.trim() || getIsLooseListContinuation(lines, index)) {
      return;
    }

    appendMarkdownBlock(blocks, text, blockStart, line.start);
    blockStart = line.end;
  });

  if (shouldCommitTail) {
    appendMarkdownBlock(blocks, text, blockStart, text.length);
    return { blocks, tail: '' };
  }

  return {
    blocks,
    tail: text.slice(blockStart),
  };
}

/** Holds back the markup that the last paragraph of a growing text has opened, as a streamed answer shows it */
export function closeStreamingMarkdownTail(text: string): string {
  const { tail } = segmentStreamingMarkdown(text);
  return text.slice(0, text.length - tail.length) + closeStreamingInlineMarkdown(tail);
}

const OPEN_BOLD_PATTERN = /\*\*\S/u;
const OPEN_ITALIC_PATTERN = /(^|[^\w*])\*\S/u;
// A link whose label or address is still coming in, at the end of the text
const OPEN_LINK_PATTERN = /(?<!!)\[([^\]\n]*)(?:\](?:\([^)\s]*)?)?$/u;
// The hashes of a heading whose text has not come in yet, on the last line
const OPEN_HEADING_PATTERN = /(?:^|\n)[^\S\n]*#{1,6}$/u;
// The marker of a list item whose text has not come in yet, on the last line
const OPEN_LIST_ITEM_PATTERN = /(?:^|\n)[^\S\n]*(?:[-+*]|\d{1,9}[.)])$/u;

/**
 * Closes the inline code, bold and italics a growing paragraph has opened but not yet closed, and shows a link that is
 * still coming in as its label, so that the paragraph never shows its markup while it grows. Asterisks with nothing
 * after them yet may be half a marker, and hashes or a list item's marker alone on the last line, or a code block's
 * fence with no code under it yet, open what has no text yet, so they wait for the next text.
 */
export function closeStreamingInlineMarkdown(text: string): string {
  const lines = text.split('\n');
  const fenceIndexes = lines.flatMap((line, index) => (FENCE_PATTERN.test(line) ? [index] : []));
  if (fenceIndexes.length % 2) {
    // A code block streams as code, which shows its text as it is
    const openingIndex = fenceIndexes[fenceIndexes.length - 1];
    if (lines.slice(openingIndex + 1).some((line) => line.trim())) return text;

    return closeStreamingInlineMarkdown(lines.slice(0, openingIndex).join('\n'));
  }

  const trailingSpace = text.match(/\s*$/)![0];
  const isLastLineOpen = !trailingSpace.includes('\n');
  let body = text.slice(0, text.length - trailingSpace.length);
  const codeSpans = body.split('`');
  if (codeSpans.length % 2 === 0) {
    // Inside an open code span
    if (codeSpans[codeSpans.length - 1]) return `${body}\`${trailingSpace}`;

    const shown = body.slice(0, -1);
    return (isLastLineOpen ? removeOpenListItem(shown) : shown) + trailingSpace;
  }

  body = body.replace(/\*+$/u, '').trimEnd();
  if (isLastLineOpen) {
    body = removeOpenListItem(body.replace(OPEN_HEADING_PATTERN, ''));
  }
  // The emphasis of the last line, with code spans standing in as plain text, is what can still be open
  const lastLine = body.split('`').map((part, index) => (index % 2 ? 'c' : part)).join('').split('\n').pop()!;
  let line = lastLine;
  const linkMatch = lastLine.match(OPEN_LINK_PATTERN);
  if (linkMatch && body.endsWith(linkMatch[0])) {
    body = body.slice(0, body.length - linkMatch[0].length) + linkMatch[1];
    line = lastLine.slice(0, lastLine.length - linkMatch[0].length) + linkMatch[1];
  }

  // The emphasis is matched as `renderMarkdown` draws it
  const boldClosing = OPEN_BOLD_PATTERN.test(line.replace(MARKDOWN_BOLD_PATTERN, '<$1>')) ? '**' : '';
  const formatted = `${line}${boldClosing}`
    .replace(MARKDOWN_BOLD_PATTERN, '<$1>')
    .replace(MARKDOWN_ITALIC_PATTERN, '$1<$2>');
  const italicClosing = OPEN_ITALIC_PATTERN.test(formatted) ? '*' : '';

  return body + italicClosing + boldClosing + trailingSpace;
}

// A list item's marker with nothing after it yet ends the text without the space that followed it
function removeOpenListItem(text: string) {
  const trimmed = text.trimEnd();
  return OPEN_LIST_ITEM_PATTERN.test(trimmed) ? trimmed.replace(OPEN_LIST_ITEM_PATTERN, '') : text;
}

function splitMarkdownLines(text: string) {
  const lines: MarkdownLine[] = [];
  let start = 0;

  while (start < text.length) {
    const newlineIndex = text.indexOf('\n', start);
    const end = newlineIndex >= 0 ? newlineIndex + 1 : text.length;
    const contentEnd = newlineIndex >= 0 && text[newlineIndex - 1] === '\r'
      ? newlineIndex - 1
      : newlineIndex >= 0 ? newlineIndex : text.length;

    lines.push({
      start,
      end,
      content: text.slice(start, contentEnd),
    });
    start = end;
  }

  return lines;
}

function getIsLooseListContinuation(lines: MarkdownLine[], blankLineIndex: number) {
  const previousLine = getNearestNonEmptyLine(lines, blankLineIndex, -1);
  const nextLine = getNearestNonEmptyLine(lines, blankLineIndex, 1);

  return Boolean(
    previousLine
    && nextLine
    && LIST_ITEM_PATTERN.test(previousLine.content)
    && LIST_ITEM_PATTERN.test(nextLine.content),
  );
}

function getNearestNonEmptyLine(lines: MarkdownLine[], startIndex: number, direction: -1 | 1) {
  for (
    let index = startIndex + direction;
    index >= 0 && index < lines.length;
    index += direction
  ) {
    if (lines[index].content.trim()) {
      return lines[index];
    }
  }

  return undefined;
}

function appendMarkdownBlock(
  blocks: MarkdownBlock[],
  text: string,
  start: number,
  end: number,
) {
  const blockText = text.slice(start, end);
  if (!blockText.trim()) return;

  blocks.push({
    offset: start,
    text: blockText,
  });
}
