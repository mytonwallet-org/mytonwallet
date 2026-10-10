import React, { memo, useMemo } from '../../lib/teact/teact';

import type { AnswerTableProps } from './AnswerMessageContent';

import { markAnswerLinks } from '../../util/agent/answerLinkMarkers';
import renderMarkdown from '../../util/renderMarkdown';

import AnswerMessageContent from './AnswerMessageContent';

import styles from './StreamingText.module.scss';

interface OwnProps extends AnswerTableProps {
  text: string;
  areLinksEnabled: boolean;
}

function StaticText({
  text,
  tables,
  tableReferences,
  links,
  areLinksEnabled,
}: OwnProps) {
  const marked = useMemo(
    () => markAnswerLinks(text, links, tableReferences),
    [links, tableReferences, text],
  );
  const html = useMemo(
    () => renderMarkdown(marked.text, { areLinksEnabled }).html,
    [areLinksEnabled, marked],
  );

  if (tables?.length) {
    return (
      <div className={styles.text} data-agent-static-text dir="auto">
        <AnswerMessageContent
          text={marked.text}
          tables={tables}
          tableReferences={marked.tableReferences}
          areLinksEnabled={areLinksEnabled}
        />
      </div>
    );
  }

  return (
    <div
      className={styles.text}
      data-agent-static-text
      dir="auto"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}

export default memo(StaticText);
