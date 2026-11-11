import React, { memo, useMemo } from '../../lib/teact/teact';

import type {
  AgentAnswerLinkV1,
  AgentAnswerTableReferenceV1,
  AgentAnswerTableV1,
} from '../../api/agentV2/protocol/types';

import { closeStreamingMarkdownTail } from '../../util/agent/streamingMarkdown';
import renderMarkdown from '../../util/renderMarkdown';
import { buildAnswerMessageBlocks } from './helpers/answerMessage';

import useLang from '../../hooks/useLang';

export interface AnswerTableProps {
  tables?: AgentAnswerTableV1[];
  tableReferences?: AgentAnswerTableReferenceV1[];
  links?: AgentAnswerLinkV1[];
}

interface OwnProps extends AnswerTableProps {
  text: string;
  areLinksEnabled: boolean;
  isStreaming?: boolean;
}

function AnswerMessageContent({
  text, tables, tableReferences, areLinksEnabled, isStreaming = false,
}: OwnProps) {
  const lang = useLang();
  const codeCopyLabel = lang('Copy');
  const blocks = useMemo(() => {
    const answerBlocks = buildAnswerMessageBlocks(text, tables, tableReferences);
    const lastBlock = answerBlocks[answerBlocks.length - 1];
    if (!isStreaming || !('text' in lastBlock)) return answerBlocks;

    // The text after the last table is the one still coming in
    return [...answerBlocks.slice(0, -1), { ...lastBlock, text: closeStreamingMarkdownTail(lastBlock.text) }];
  }, [isStreaming, text, tables, tableReferences]);

  return blocks.map((block) => 'table' in block ? (
    <div key={block.key} data-agent-answer-table={block.table.id}>
      <AnswerTable table={block.table} />
    </div>
  ) : (
    <MarkdownBlock key={block.key} text={block.text} areLinksEnabled={areLinksEnabled} codeCopyLabel={codeCopyLabel} />
  ));
}

function MarkdownBlock({ text, areLinksEnabled, codeCopyLabel }: {
  text: string;
  areLinksEnabled: boolean;
  codeCopyLabel: string;
}) {
  // Teact sets the markup again whenever it gets another object, so the object lasts while the text is the same
  const markup = useMemo(
    () => ({ __html: renderMarkdown(text, { areLinksEnabled, codeCopyLabel }).html }),
    [text, areLinksEnabled, codeCopyLabel],
  );
  return <div data-agent-answer-prose dangerouslySetInnerHTML={markup} />;
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
