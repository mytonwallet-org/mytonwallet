import type { AgentAnswerLinkV1, AgentAnswerTableReferenceV1 } from '../../api/agentV2/protocol/types';

import { isAgentLinkUrl } from './agentLinkUrl';

const LINK_START = '';
const URL_END = '';
const LINK_END = '';
const ASCII_ALPHANUMERIC = /[A-Za-z0-9]/u;
/** A backslash escape of ASCII punctuation, as the agent writes it and the server escapes link labels */
export const MARKDOWN_ESCAPE_PATTERN = /\\([\\|`*_{}[\]()<>#+.!~=-])/gu;

/** A marked label: its percent-encoded URL and the label, which `renderMarkdown` turns into a link */
export const ANSWER_LINK_MARKER_PATTERN = /([A-Za-z0-9%]*)([^]*)/gu;
/** A marker left without its pair, such as one Markdown parsing split from it */
export const STRAY_ANSWER_LINK_MARKER_PATTERN = /[A-Za-z0-9%]*|[-]/gu;

/**
 * Marks the labels of answer links in `text` with private-use markers, so they survive table splicing and
 * Markdown segmentation until `renderMarkdown` turns them into links. A label the text covers only in part, as
 * while it is revealed, is marked as far as the text goes. A link that overlaps an earlier one, contains a
 * table or may not be opened stays unmarked; `tableReferences` move with the text.
 */
export function markAnswerLinks(
  text: string,
  links?: AgentAnswerLinkV1[],
  tableReferences?: AgentAnswerTableReferenceV1[],
) {
  if (!links?.length) return { text, tableReferences };
  let marked = '';
  let offset = 0;
  const insertions: Array<{ start: number; length: number }> = [];
  for (const { textOffset, textLength, url } of links) {
    const end = textOffset + textLength;
    if (textOffset < offset || textLength < 1 || textOffset >= text.length || !isAgentLinkUrl(url)
      || tableReferences?.some((reference) => reference.textOffset > textOffset && reference.textOffset < end)) {
      continue;
    }
    const visibleEnd = Math.min(end, text.length);
    const opening = `${LINK_START}${encodeMarkerUrl(url)}${URL_END}`;
    marked += `${text.slice(offset, textOffset)}${opening}${text.slice(textOffset, visibleEnd)}${LINK_END}`;
    insertions.push({ start: textOffset, length: opening.length + LINK_END.length });
    offset = visibleEnd;
  }
  marked += text.slice(offset);
  return {
    text: marked,
    // A table at the start of a link stays before it
    tableReferences: tableReferences?.map((reference) => ({
      ...reference,
      textOffset: insertions.reduce(
        (moved, { start, length }) => (start < reference.textOffset ? moved + length : moved),
        reference.textOffset,
      ),
    })),
  };
}

/** The URL of a marker, or undefined when it does not decode to a link the app may open */
export function decodeMarkerUrl(encodedUrl: string) {
  try {
    const url = decodeURIComponent(encodedUrl);
    return isAgentLinkUrl(url) ? url : undefined;
  } catch {
    return undefined;
  }
}

/** Marked text with each label followed by its URL, for copying */
export function getAnswerLinkCopyText(text: string) {
  return text
    .replace(ANSWER_LINK_MARKER_PATTERN, (_match, encodedUrl: string, escapedLabel: string) => {
      const label = escapedLabel.replace(MARKDOWN_ESCAPE_PATTERN, '$1');
      const url = decodeMarkerUrl(encodedUrl);
      return url && label !== url ? `${label} (${url})` : label;
    })
    .replace(STRAY_ANSWER_LINK_MARKER_PATTERN, '');
}

/** Marked text with each label left as text, for content that shows no links, such as code */
export function removeAnswerLinkMarkers(text: string) {
  return text.replace(ANSWER_LINK_MARKER_PATTERN, '$2').replace(STRAY_ANSWER_LINK_MARKER_PATTERN, '');
}

// Only ASCII letters and digits stay as they are, so Markdown parsing never reads the URL
function encodeMarkerUrl(url: string) {
  let encoded = '';
  for (const byte of new TextEncoder().encode(url)) {
    const character = String.fromCharCode(byte);
    encoded += byte < 0x80 && ASCII_ALPHANUMERIC.test(character)
      ? character
      : `%${byte.toString(16).toUpperCase().padStart(2, '0')}`;
  }
  return encoded;
}
