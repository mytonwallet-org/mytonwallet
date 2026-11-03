import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './AgentSearchGlyph.module.scss';

function AgentSearchGlyph({ className }: { className?: string }) {
  return <span className={buildClassName(styles.icon, className)} aria-hidden />;
}

export default memo(AgentSearchGlyph);
