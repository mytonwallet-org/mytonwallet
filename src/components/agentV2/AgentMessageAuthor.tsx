import React, { memo } from '../../lib/teact/teact';

import type { AgentMessage } from '../../global/types';

import { APP_NAME } from '../../config';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import AgentMark from '../agent/AgentMark';

import styles from './AgentSupport.module.scss';

interface OwnProps {
  /** The operator who wrote the answer; without one, the answer is the agent's */
  operator?: AgentMessage['operator'];
}

/**
 * The author over an answer once an operator has joined the chat: the operator's photo, name and support badge, or
 * the agent's mark and name, so that the user tells the two apart, as in the design
 */
function AgentMessageAuthor({ operator }: OwnProps) {
  const lang = useLang();

  if (!operator) {
    return (
      <div className={styles.author}>
        <span className={buildClassName(styles.avatar, styles.avatarAgent)} aria-hidden>
          <AgentMark className={styles.agentMark} />
        </span>
        <span className={styles.authorName}>{lang('Agent')}</span>
      </div>
    );
  }

  return (
    <div className={styles.author}>
      <span className={buildClassName(styles.avatar, styles.avatarOperator)} aria-hidden>
        {operator.avatarUrl
          ? <img className={styles.avatarImage} src={operator.avatarUrl} alt="" draggable={false} />
          : getInitial(operator.name)}
      </span>
      <span className={styles.authorName}>{operator.name}</span>
      <span className={styles.badge}>{lang('$agent_support_badge', { app_name: APP_NAME })}</span>
    </div>
  );
}

export default memo(AgentMessageAuthor);

function getInitial(name: string) {
  return Array.from(name.trim())[0]?.toUpperCase() ?? '';
}
