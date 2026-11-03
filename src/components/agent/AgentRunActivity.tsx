import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentRunActivityCodeV1,
  AgentToolName,
  AgentWalletSemanticOperationV2,
} from '../../api/agentV2/protocol/types';
import type { AgentSpinningTopHandoff } from './helpers/agentSpinningTop';

import buildClassName from '../../util/buildClassName';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import AgentSpinningTop from './AgentSpinningTop';

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
// Each step stays at least this long before the next replaces it, as on mobile
const MIN_STEP_DURATION = 1200;
const STEP_LEAVE_DURATION = 250;
// An indicator that comes this soon after another one left takes its place
const HANDOFF_WINDOW_MS = 300;

/**
 * What a run's indicator hands to the one that takes its place, as the answer's message takes it from the chat's
 * end: its step, which goes on or blurs into the step that comes with the move, and its top, which goes on spinning
 */
export interface AgentRunActivityHandoff {
  langKey?: string;
  shownAt?: number;
  mountedCount: number;
  leftAt?: number;
  top: AgentSpinningTopHandoff;
}

export function createAgentRunActivityHandoff(): AgentRunActivityHandoff {
  return { mountedCount: 0, top: {} };
}

interface OwnProps {
  /** The indicator fades out with its last phase once the activity is gone */
  activity?: AgentRunActivityType;
  /**
   * Stands in for the answer bubble inside its message. It takes the bubble's place without an entrance
   * and, once the bubble arrives, fades out on top of it instead of being pushed below.
   */
  isAnswerPlaceholder?: boolean;
  /** Shared with the indicator that takes this one's place */
  handoff?: AgentRunActivityHandoff;
}

function AgentRunActivity({ activity, isAnswerPlaceholder = false, handoff }: OwnProps) {
  const lang = useLang();
  const renderedActivity = useCurrentOrPrev(activity, true);
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen: Boolean(activity),
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_DURATION,
  });
  const [handedOffStep] = useState(() => (activity ? takeHandoff(handoff) : undefined));
  const {
    currentKey, leavingKey, hasChanged, shownAt,
  } = useActivitySteps(renderedActivity && getAgentRunActivityLangKey(renderedActivity), handedOffStep);

  useLayoutEffect(() => {
    if (!handoff) return undefined;

    handoff.mountedCount += 1;
    return () => {
      handoff.mountedCount -= 1;
      handoff.leftAt = performance.now();
    };
  }, [handoff]);

  useLayoutEffect(() => {
    if (!handoff) return;

    handoff.langKey = activity ? currentKey : undefined;
    handoff.shownAt = shownAt;
  });

  if (!shouldRender || !currentKey) return undefined;

  return (
    <div
      ref={ref}
      className={buildClassName(styles.root, isAnswerPlaceholder && styles.answerPlaceholder)}
      data-agent-run-activity
      role="status"
      aria-live="polite"
      aria-atomic="true"
    >
      <AgentSpinningTop
        className={styles.icon}
        markClassName={styles.iconMark}
        isTouchInteractive
        handoff={handoff?.top}
      />
      {/* A new step comes into focus while the previous one blurs away above it, as on mobile */}
      <span className={buildClassName(styles.steps, !isAnswerPlaceholder && styles.stepsFocusing)}>
        {leavingKey && (
          <span key={`leaving-${leavingKey}`} className={buildClassName(styles.step, styles.stepLeaving)} aria-hidden>
            <span className={styles.text}>{lang(leavingKey)}</span>
          </span>
        )}
        <span key={currentKey} className={buildClassName(styles.step, hasChanged && styles.stepEntering)}>
          <span className={styles.text} data-agent-activity-step>{lang(currentKey)}</span>
        </span>
      </span>
    </div>
  );
}

export function getAgentRunActivityLangKey(activity: AgentRunActivityType) {
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

// The step of an indicator that is still on screen, or has just left it
function takeHandoff(handoff?: AgentRunActivityHandoff) {
  if (!handoff?.langKey || handoff.shownAt === undefined) return undefined;
  const isRecent = handoff.mountedCount > 0
    || (handoff.leftAt !== undefined && performance.now() - handoff.leftAt < HANDOFF_WINDOW_MS);
  return isRecent ? { langKey: handoff.langKey, shownAt: handoff.shownAt } : undefined;
}

function useActivitySteps(langKey?: string, handedOffStep?: { langKey: string; shownAt: number }) {
  // The step handed over goes on, or blurs away as the step that came with the move comes into focus
  const isHandedOffStepLeaving = Boolean(handedOffStep && langKey && handedOffStep.langKey !== langKey);
  const [steps, setSteps] = useState<{ currentKey?: string; leavingKey?: string; hasChanged: boolean }>(() => (
    isHandedOffStepLeaving
      ? { currentKey: langKey, leavingKey: handedOffStep?.langKey, hasChanged: true }
      : { currentKey: langKey ?? handedOffStep?.langKey, hasChanged: false }
  ));
  const shownAtRef = useRef(handedOffStep && !isHandedOffStepLeaving ? handedOffStep.shownAt : Date.now());
  const { currentKey, leavingKey } = steps;

  useEffect(() => {
    if (!langKey || langKey === currentKey) return undefined;

    // The first step shows at once
    if (!currentKey) {
      shownAtRef.current = Date.now();
      setSteps({ currentKey: langKey, hasChanged: false });
      return undefined;
    }

    // A step that comes too soon waits for the shown one's turn to end, and a later step takes its place meanwhile
    const delay = Math.max(0, shownAtRef.current + MIN_STEP_DURATION - Date.now());
    const timer = window.setTimeout(() => {
      shownAtRef.current = Date.now();
      setSteps({ currentKey: langKey, leavingKey: currentKey, hasChanged: true });
    }, delay);

    return () => window.clearTimeout(timer);
  }, [currentKey, langKey]);

  useEffect(() => {
    if (!leavingKey) return undefined;

    const timer = window.setTimeout(() => {
      setSteps((current) => ({ ...current, leavingKey: undefined }));
    }, STEP_LEAVE_DURATION);

    return () => window.clearTimeout(timer);
  }, [leavingKey]);

  return { ...steps, currentKey: currentKey ?? langKey, shownAt: shownAtRef.current };
}
