import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './AgentNews.module.scss';

interface OwnProps {
  className?: string;
}

/** The News mark: a white pulse line on the Agent gradient, as on mobile */
function AgentNewsIcon({ className }: OwnProps) {
  return (
    <span className={buildClassName(styles.icon, className)} aria-hidden>
      <svg className={styles.iconPulse} viewBox="0 0 32 32">
        <path d="M6 17h4l2.5-7L17 23l3.5-9.5L22.5 17H26" />
      </svg>
    </span>
  );
}

export default memo(AgentNewsIcon);
