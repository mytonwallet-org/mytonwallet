import type { AgentAnswerLinkV1, AgentAnswerTableReferenceV1 } from '../types';

import { isAgentLinkUrl } from '../../../../util/agent/agentLinkUrl';
import {
  AgentV2ContractError, array, boundedInteger, boundedString, fail, object,
} from '../wireReader';

const MAX_TEXT_OFFSET = 200_000;
const MAX_LINK_URL_LENGTH = 2_048;
export const MAX_MESSAGE_LINKS = 64;

export function decodeAnswerLink(value: unknown, path: string): AgentAnswerLinkV1 {
  const link = object(value, path);
  const url = boundedString(link.url, `${path}.url`, 1, MAX_LINK_URL_LENGTH);
  if (!isAgentLinkUrl(url)) fail(`${path}.url`);
  return {
    textOffset: boundedInteger(link.textOffset, `${path}.textOffset`, 0, MAX_TEXT_OFFSET),
    textLength: boundedInteger(link.textLength, `${path}.textLength`, 1, MAX_TEXT_OFFSET),
    url,
  };
}

/**
 * Keeps the links of a stored answer that lie over its text in order, apart from each other and from its
 * tables. A link that does not is dropped and its label stays text; a link never fails the message.
 */
export function decodeMessageLinks(content: Record<string, unknown>, path: string) {
  if (content.links === undefined) return;
  const text = String(content.text);
  const tableOffsets = (content.tableReferences as AgentAnswerTableReferenceV1[] | undefined ?? [])
    .map(({ textOffset }) => textOffset);
  const links: AgentAnswerLinkV1[] = [];
  for (const [index, value] of array(content.links, `${path}.links`, MAX_MESSAGE_LINKS).entries()) {
    try {
      const link = decodeAnswerLink(value, `${path}.links[${index}]`);
      if (!canPlaceAnswerLink(link, links.at(-1), text.length, tableOffsets)) fail(`${path}.links[${index}]`);
      links.push(link);
    } catch (error) {
      if (!(error instanceof AgentV2ContractError)) throw error;
    }
  }
  if (links.length) content.links = links;
  else delete content.links;
}

/** Whether `link` follows `previous` without overlap, ends within the text and does not contain a table */
export function canPlaceAnswerLink(
  link: AgentAnswerLinkV1,
  previous: AgentAnswerLinkV1 | undefined,
  textLength: number,
  tableOffsets: readonly number[],
) {
  const end = link.textOffset + link.textLength;
  return link.textOffset >= (previous ? previous.textOffset + previous.textLength : 0)
    && end <= textLength
    && !tableOffsets.some((offset) => offset > link.textOffset && offset < end);
}
