import React, { memo } from '../../lib/teact/teact';

import type {
  AgentRunActivityCodeV1,
  AgentToolName,
  AgentWalletSemanticOperationV2,
} from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentRunActivity.module.scss';

type AgentVisibleRunActivityCode = Exclude<AgentRunActivityCodeV1, 'analysis.computing'>;

export type AgentRunActivityType =
  | { kind: 'analyzingRequest' }
  | { kind: 'tool'; toolName: AgentToolName; operation?: AgentWalletSemanticOperationV2 }
  | { kind: 'server'; code: AgentVisibleRunActivityCode }
  | { kind: 'preparingResponse' };

const TOOL_ACTIVITY_LANG_KEY: Record<AgentToolName, string> = {
  'wallet.data.query': '$agent_activity_wallet',
  'wallet.directory.query': '$agent_activity_wallet',
};

const QUERY_ACTIVITY_LANG_KEY: Record<AgentWalletSemanticOperationV2, string> = {
  'account.inventory': '$agent_activity_wallet',
  'assets.search': '$agent_activity_assets',
  'positions.list': '$agent_activity_wallet',
  'portfolio.aggregate': '$agent_activity_portfolio',
  'transactions.list': '$agent_activity_transactions',
  'transactions.detail': '$agent_activity_transactions',
  'contacts.list': '$agent_activity_addresses',
  'value.series': '$agent_activity_portfolio',
};

const SERVER_ACTIVITY_LANG_KEY: Record<AgentVisibleRunActivityCode, string> = {
  'web.searching': '$agent_activity_web_searching',
  'web.reading_sources': '$agent_activity_web_reading_sources',
  'help.searching': '$agent_activity_help_searching',
  'data.reading_market': '$agent_activity_market_data',
};

const CLOSE_DURATION = 200;

interface OwnProps {
  /** The indicator fades out with its last phase once the activity is gone */
  activity?: AgentRunActivityType;
  /**
   * Stands in for the answer bubble inside its message. It takes the bubble's place without an entrance
   * and, once the bubble arrives, fades out on top of it instead of being pushed below.
   */
  isAnswerPlaceholder?: boolean;
}

function AgentRunActivity({ activity, isAnswerPlaceholder = false }: OwnProps) {
  const lang = useLang();
  const renderedActivity = useCurrentOrPrev(activity, true);
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen: Boolean(activity),
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_DURATION,
  });

  if (!shouldRender || !renderedActivity) return undefined;

  return (
    <div
      ref={ref}
      className={buildClassName(styles.root, isAnswerPlaceholder && styles.answerPlaceholder)}
      role="status"
      aria-live="polite"
      aria-atomic="true"
    >
      <i className={buildClassName(styles.icon, 'icon-agent')} aria-hidden />
      <span className={styles.text}>{lang(getActivityLangKey(renderedActivity))}</span>
    </div>
  );
}

function getActivityLangKey(activity: AgentRunActivityType) {
  if (activity.kind === 'server') return SERVER_ACTIVITY_LANG_KEY[activity.code];
  if (activity.kind === 'tool') {
    return activity.operation
      ? QUERY_ACTIVITY_LANG_KEY[activity.operation]
      : TOOL_ACTIVITY_LANG_KEY[activity.toolName];
  }
  return activity.kind === 'preparingResponse'
    ? '$agent_activity_preparing_response'
    : '$agent_activity_analyzing_request';
}

export default memo(AgentRunActivity);
