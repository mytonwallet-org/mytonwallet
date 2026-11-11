import React, { memo } from '../../lib/teact/teact';

import type { AgentMessage } from '../../global/types';

import formatAgentChatDate from '../agent/helpers/formatAgentChatDate';

import useLang from '../../hooks/useLang';

import AgentSupportIcon from './AgentSupportIcon';

import styles from './AgentSupport.module.scss';

interface OwnProps {
  event: NonNullable<AgentMessage['supportEvent']>;
  timestamp: number;
}

/** A line in the middle of the chat about its handover to support, with the time it happened, as in the design */
function AgentSupportEventLine({ event, timestamp }: OwnProps) {
  const lang = useLang();
  const { time } = formatAgentChatDate(lang, timestamp);

  return (
    <div className={styles.eventLine} role="status">
      <AgentSupportIcon className={styles.eventIcon} />
      <span className={styles.eventText}>{getEventText(event, lang)}</span>
      <span className={styles.eventTime}>{time}</span>
    </div>
  );
}

export default memo(AgentSupportEventLine);

function getEventText(event: NonNullable<AgentMessage['supportEvent']>, lang: ReturnType<typeof useLang>) {
  if (event.code === 'support_requested') return lang('$agent_support_requested');
  if (event.code === 'operator_joined') {
    return lang('$agent_support_operator_joined', { name: event.operatorName ?? lang('$agent_support_label') });
  }

  return event.reason === 'inactivity'
    ? lang('$agent_support_closed_inactivity')
    : lang('$agent_support_closed_operator');
}
