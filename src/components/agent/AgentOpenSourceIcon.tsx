import React, { memo } from '../../lib/teact/teact';

import styles from './AgentMenuIcon.module.scss';

/** The outlined arrow out of a ring of "Open Source", drawn as "Report a Problem" and the wallet's outlined menu icons */
function AgentOpenSourceIcon() {
  return (
    <svg className={styles.icon} viewBox="0 0 768 768" aria-hidden>
      <circle className={styles.ring} cx="384" cy="384" r="276" />
      <path className={styles.bar} d="M296 472 472 296M330 296h142v142" />
    </svg>
  );
}

export default memo(AgentOpenSourceIcon);
