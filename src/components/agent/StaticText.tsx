import React, { memo, useMemo } from '../../lib/teact/teact';

import renderMarkdown from '../../util/renderMarkdown';

import styles from './StreamingText.module.scss';

interface OwnProps {
  text: string;
}

function StaticText({ text }: OwnProps) {
  const html = useMemo(() => renderMarkdown(text).html, [text]);

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
