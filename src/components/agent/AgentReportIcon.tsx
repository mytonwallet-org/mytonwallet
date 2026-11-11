import React, { memo } from '../../lib/teact/teact';

import styles from './AgentMenuIcon.module.scss';

/** The outlined exclamation mark of "Report a Problem", drawn as the wallet's outlined menu icons are */
function AgentReportIcon() {
  return (
    <svg className={styles.icon} viewBox="0 0 768 768" aria-hidden>
      <circle className={styles.ring} cx="384" cy="384" r="276" />
      <path className={styles.bar} d="M384 236v176" />
      <circle className={styles.dot} cx="384" cy="518" r="34" />
    </svg>
  );
}

export default memo(AgentReportIcon);
