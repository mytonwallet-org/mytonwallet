import React, { memo, useMemo } from '../../lib/teact/teact';

import type {
  AgentAnswerLinkV1,
  AgentAnswerTableReferenceV1,
  AgentAnswerTableV1,
} from '../../api/agentV2/protocol/types';

import renderMarkdown from '../../util/renderMarkdown';
import { buildAnswerMessageBlocks } from './helpers/answerMessage';

export interface AnswerTableProps {
  tables?: AgentAnswerTableV1[];
  tableReferences?: AgentAnswerTableReferenceV1[];
  links?: AgentAnswerLinkV1[];
}

interface OwnProps extends AnswerTableProps {
  text: string;
  areLinksEnabled: boolean;
}

function AnswerMessageContent({ text, tables, tableReferences, areLinksEnabled }: OwnProps) {
  const blocks = useMemo(
    () => buildAnswerMessageBlocks(text, tables, tableReferences),
    [text, tables, tableReferences],
  );

  return blocks.map((block) => 'table' in block ? (
    <div key={block.key} data-agent-answer-table={block.table.id}>
      <AnswerTable table={block.table} />
    </div>
  ) : (
    <MarkdownBlock key={block.key} text={block.text} areLinksEnabled={areLinksEnabled} />
  ));
}

function MarkdownBlock({ text, areLinksEnabled }: { text: string; areLinksEnabled: boolean }) {
  const html = useMemo(() => renderMarkdown(text, { areLinksEnabled }).html, [text, areLinksEnabled]);
  return <div data-agent-answer-prose dangerouslySetInnerHTML={{ __html: html }} />;
}

function AnswerTable({ table }: { table: AgentAnswerTableV1 }) {
  const { headers, rows, notes } = table.content;
  return (
    <>
      {notes.map((note, index) => (
        <p key={index}>{note}</p>
      ))}
      {rows.length ? (
        <table>
          <thead>
            <tr>
              {headers.map((header, index) => (
                <th key={index} scope="col">{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>{rows.map((row, index) => (
            <tr key={index}>{row.map((cell, column) => (
              <td key={column}>{cell}</td>
            ))}
            </tr>
          ))}
          </tbody>
        </table>
      ) : undefined}
    </>
  );
}

export default memo(AnswerMessageContent);
