import React, { memo, useMemo } from '../../lib/teact/teact';

import type { AnswerTableProps } from './AnswerMessageContent';

import { markAnswerLinks } from '../../util/agent/answerLinkMarkers';
import { copyClickedAgentCode } from './helpers/copyAgentText';
import renderFinishedMarkdown from './helpers/renderFinishedMarkdown';

import useLang from '../../hooks/useLang';

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
  const lang = useLang();
  const codeCopyLabel = lang('Copy');
  const marked = useMemo(
    () => markAnswerLinks(text, links, tableReferences),
    [links, tableReferences, text],
  );
  const html = useMemo(
    () => renderFinishedMarkdown(marked.text, areLinksEnabled, codeCopyLabel),
    [areLinksEnabled, codeCopyLabel, marked],
  );
  // Teact sets the markup again whenever it gets another object, so the object lasts while the markup is the same
  const markup = useMemo(() => ({ __html: html }), [html]);

  if (tables?.length) {
    return (
      <div className={styles.text} data-agent-static-text dir="auto" onClick={copyClickedAgentCode}>
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
      dangerouslySetInnerHTML={markup}
      onClick={copyClickedAgentCode}
    />
  );
}

export default memo(StaticText);
