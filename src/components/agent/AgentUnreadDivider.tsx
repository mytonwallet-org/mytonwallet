import React, { memo } from '../../lib/teact/teact';

import useLang from '../../hooks/useLang';

import styles from './Agent.module.scss';

/** The "New" line before the first message the user has not seen, as before the first unread news */
function AgentUnreadDivider() {
  const lang = useLang();

  return <div className={styles.unreadDivider}>{lang('$agent_news_new')}</div>;
}

export default memo(AgentUnreadDivider);
