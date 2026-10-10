import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import type {
  AgentUserQuotaV2,
  AgentV2MessageError,
} from '../../api/agentV2/protocol/types';
import type { AgentV2ComposerStatus } from '../../api/agentV2/types';
import type { LangFn } from '../../util/langProvider';

import { getAgentV2ErrorText } from './agentV2Copy';

import useLang from '../../hooks/useLang';

import styles from './AgentStatusNotice.module.scss';

interface AgentComposerStatusProps {
  status: AgentV2ComposerStatus;
  isRetryDisabled?: boolean;
  onRetry?: NoneToVoidFunction;
  onExpired?: NoneToVoidFunction;
}

export const AgentComposerStatus = memo(({
  status,
  isRetryDisabled,
  onRetry,
  onExpired,
}: AgentComposerStatusProps) => {
  const lang = useLang();
  const [now, setNow] = useState(Date.now());
  const remainingMs = 'resetAt' in status ? Math.max(0, status.resetAt - now) : undefined;

  useEffect(() => {
    if (!('resetAt' in status)) return undefined;
    const delay = nextDisplayBoundary(status.resetAt - Date.now());
    const timer = window.setTimeout(() => setNow(Date.now()), delay);
    return () => window.clearTimeout(timer);
  }, [now, status]);

  useEffect(() => {
    if (remainingMs === 0) onExpired?.();
  }, [onExpired, remainingMs]);

  const title = getComposerStatusTitle(lang, status);
  const body = getComposerStatusBody(lang, status, remainingMs);

  return (
    <div
      className={status.mode === 'blocked' ? styles.composerStatus : styles.composerStatusNeutral}
      role="status"
    >
      <div className={styles.copy}>
        <strong>{title}</strong>
        {body && <span aria-live="off">{body}</span>}
      </div>
      {onRetry && (
        <button type="button" className={styles.retry} disabled={isRetryDisabled} onClick={onRetry}>
          {lang('$agent_retry_request')}
        </button>
      )}
    </div>
  );
});

interface AgentRunFailureProps {
  error: AgentV2MessageError;
  hasPartialResponse: boolean;
  isRetryDisabled?: boolean;
  onRetry?: NoneToVoidFunction;
}

export const AgentRunFailure = memo(({
  error,
  hasPartialResponse,
  isRetryDisabled,
  onRetry,
}: AgentRunFailureProps) => {
  const lang = useLang();

  return (
    <div className={styles.runFailure}>
      <div className={styles.copy}>
        <strong>
          {lang(hasPartialResponse ? '$agent_response_interrupted_title' : '$agent_response_failed_title')}
        </strong>
        <span>{getAgentV2ErrorText(error.code, lang)}</span>
      </div>
      {onRetry && (
        <button type="button" className={styles.retry} disabled={isRetryDisabled} onClick={onRetry}>
          {lang('$agent_retry_request')}
        </button>
      )}
    </div>
  );
});

export const AgentQuotaStatus = memo(({ quota }: { quota: AgentUserQuotaV2 }) => {
  const lang = useLang();
  const [now, setNow] = useState(Date.now());
  const resetAt = Date.parse(quota.resetAt);
  const remainingMs = Math.max(0, resetAt - now);

  useEffect(() => {
    const delay = nextDisplayBoundary(resetAt - Date.now());
    const timer = window.setTimeout(() => setNow(Date.now()), delay);
    return () => window.clearTimeout(timer);
  }, [now, resetAt]);

  return (
    <div className={styles.quotaStatus}>
      <strong>{lang('$agent_user_quota_meter', [quota.remaining, quota.limit])}</strong>
      <span>{lang('$agent_user_quota_reset', formatRemainingTime(lang, remainingMs))}</span>
    </div>
  );
});

function getComposerStatusTitle(lang: LangFn, status: AgentV2ComposerStatus) {
  if (status.kind === 'capacity') {
    return lang(status.mode === 'degraded'
      ? '$agent_capacity_degraded_title'
      : '$agent_capacity_limit_title');
  }
  if (status.kind === 'userQuota') return lang('$agent_user_quota_exhausted_title');
  return lang('$agent_rate_limit_title');
}

function getComposerStatusBody(
  lang: LangFn,
  status: AgentV2ComposerStatus,
  remainingMs?: number,
) {
  if (status.kind === 'capacity' && status.mode === 'degraded') {
    return lang('$agent_capacity_limit_unknown');
  }
  if (!remainingMs) return undefined;

  const formattedTime = formatRemainingTime(lang, remainingMs);
  if (status.kind === 'capacity') return lang('$agent_capacity_limit_known', formattedTime);
  if (status.kind === 'userQuota') {
    return lang('$agent_user_quota_exhausted_body', [status.quota.limit, formattedTime]);
  }
  return lang('$agent_rate_limit_body', formattedTime);
}

function nextDisplayBoundary(remainingMs: number) {
  if (remainingMs <= 0) return 60_000;
  const unit = remainingMs > 60_000 ? 60_000 : 1_000;
  const displayedUnits = Math.ceil(remainingMs / unit);
  return Math.max(1, remainingMs - (displayedUnits - 1) * unit + 1);
}

function formatRemainingTime(lang: LangFn, remainingMs: number) {
  if (remainingMs > 60 * 60_000) {
    return lang('$agent_time_hours', Math.ceil(remainingMs / (60 * 60_000)));
  }
  if (remainingMs > 60_000) {
    return lang('$agent_time_minutes', Math.ceil(remainingMs / 60_000));
  }
  return lang('$agent_time_seconds', Math.ceil(remainingMs / 1_000));
}
