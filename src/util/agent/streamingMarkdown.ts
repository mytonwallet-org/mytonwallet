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
