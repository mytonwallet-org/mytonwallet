import type {
  AgentAnswerLinkV1,
  AgentAnswerTableReferenceV1,
  AgentAnswerTableV1,
} from '../../../api/agentV2/protocol/types';

import { getAnswerLinkCopyText, markAnswerLinks } from '../../../util/agent/answerLinkMarkers';

export function getAnswerMessageCopyText(
  text: string,
  tables?: AgentAnswerTableV1[],
  tableReferences?: AgentAnswerTableReferenceV1[],
  links?: AgentAnswerLinkV1[],
) {
  const marked = markAnswerLinks(text, links, tableReferences);
  return buildAnswerMessageBlocks(marked.text, tables, marked.tableReferences).map((block) => {
    if ('text' in block) return getAnswerLinkCopyText(block.text);
    const { headers, rows, notes } = block.table.content;
    const tableText = rows.length ? [headers, ...rows].map((row) => row.join('\t')).join('\n') : '';
    const content = [...notes, tableText].filter(Boolean).join('\n\n');
    return `\n\n${content}\n\n`;
  }).join('');
}

export function buildAnswerMessageBlocks(
  text: string,
  tables?: AgentAnswerTableV1[],
  tableReferences?: AgentAnswerTableReferenceV1[],
) {
  const blocks: Array<{ key: string; text: string } | { key: string; table: AgentAnswerTableV1 }> = [];
  let offset = 0;
  for (const reference of tableReferences ?? []) {
    if (reference.textOffset > text.length) break;
    const table = tables?.find(({ id }) => id === reference.tableId);
    if (!table) continue;
    blocks.push({ key: `before-${table.id}`, text: text.slice(offset, reference.textOffset) });
    blocks.push({ key: table.id, table });
    offset = reference.textOffset;
  }
  blocks.push({ key: 'tail', text: text.slice(offset) });
  return blocks;
}
