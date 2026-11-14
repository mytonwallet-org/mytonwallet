import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AgentV2ErrorCode } from '../../api/agentV2/protocol/types';
import type { AgentV2ComposerStatus } from '../../api/agentV2/types';
import type { LangFn } from '../../util/langProvider';
import type {
  AgentDictationFailure,
  AgentDictationNotice as AgentDictationNoticeState,
} from '../agent/hooks/useAgentV2Dictation';

import buildClassName from '../../util/buildClassName';
import { getAgentV2ErrorText } from './agentV2Copy';

import useForceUpdate from '../../hooks/useForceUpdate';
import useLang from '../../hooks/useLang';

import styles from './AgentStatusNotice.module.scss';

interface AgentFailureCaptionProps {
  text: string;
  isRetryDisabled?: boolean;
  onRetry?: NoneToVoidFunction;
}

/** A failed request reads as one caption under the last message, with Retry at its end while it can be retried */
export const AgentFailureCaption = memo(({ text, isRetryDisabled, onRetry }: AgentFailureCaptionProps) => {
  const lang = useLang();

  return (
    <p className={styles.failureCaption}>
      <span>{text}</span>
      {onRetry && (
        <button
          type="button"
          className={styles.failureRetry}
          aria-label={lang('$agent_retry_request')}
          disabled={isRetryDisabled}
          onClick={onRetry}
        >
          {lang('Retry')}
        </button>
      )}
    </p>
  );
});

interface AgentComposerStatusProps {
  status: AgentV2ComposerStatus;
  isRetryDisabled?: boolean;
  /** Retries the question the limit kept from starting, once the limit no longer holds */
  onRetry?: NoneToVoidFunction;
  onExpired?: NoneToVoidFunction;
}

// The limit's line and the failure that follows it cross-fade over this time, as one line turning into the other
const STATUS_CROSSFADE_DURATION = 250;

// What a question kept from starting by a limit failed with
const ERROR_CODE_BY_STATUS_KIND: Record<AgentV2ComposerStatus['kind'], AgentV2ErrorCode> = {
  capacity: 'agent_capacity_exhausted',
  userQuota: 'user_quota_exhausted',
  rateLimit: 'rate_limited',
};

/**
 * A limit that holds, or an Agent that may be unstable, as the chat's last line, without Retry. Once a limit has
 * reset, the question it kept from starting reads as a failed request, with Retry while it can be retried.
 */
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

  const kind = status.mode !== 'informational' ? 'limit' : onRetry ? 'failure' : undefined;
  const content = kind === 'failure' ? (
    <div className={styles.chatFailure}>
      <AgentFailureCaption
        text={getAgentV2ErrorText(
          ERROR_CODE_BY_STATUS_KIND[status.kind], lang, 'resetAt' in status ? status.resetAt : undefined,
        )}
        isRetryDisabled={isRetryDisabled}
        onRetry={onRetry}
      />
    </div>
  ) : kind === 'limit' ? (
    <AgentStatusLine
      className={styles.chatStatus}
      title={getComposerStatusTitle(lang, status)}
      // The last second stays until the limit's end is confirmed, so that the line changes once
      body={getComposerStatusBody(lang, status, remainingMs === 0 ? 1 : remainingMs)}
      isStatus
      isBodyQuiet
    />
  ) : undefined;
  const leaving = useLeavingStatus(kind, content);

  if (!content) return undefined;

  return (
    <div className={styles.chatStatusSlot} data-agent-list-footer>
      {leaving && (
        <div key={`leaving-${leaving.key}`} className={styles.chatStatusLeaving} aria-hidden>
          {leaving.content}
        </div>
      )}
      <div key={kind} className={leaving && styles.chatStatusEntering}>
        {content}
      </div>
    </div>
  );
});

/**
 * The line a limit's status leaves for another, as the limit's own for the failure it kept from starting, while it
 * fades out over the one that comes
 */
function useLeavingStatus(kind: string | undefined, content: TeactNode) {
  const forceUpdate = useForceUpdate();
  const shownRef = useRef({ kind, content });
  const leavingRef = useRef<{ key: number; content: TeactNode }>();

  const shown = shownRef.current;
  if (kind !== shown.kind) {
    leavingRef.current = shown.kind && kind
      ? { key: (leavingRef.current?.key ?? 0) + 1, content: shown.content }
      : undefined;
  }
  shownRef.current = { kind, content };

  const leavingKey = leavingRef.current?.key;
  useEffect(() => {
    if (leavingKey === undefined) return undefined;

    const timer = window.setTimeout(() => {
      leavingRef.current = undefined;
      forceUpdate();
    }, STATUS_CROSSFADE_DURATION);
    return () => window.clearTimeout(timer);
  }, [forceUpdate, leavingKey]);

  return leavingRef.current;
}

interface AgentDictationNoticeProps {
  notice: AgentDictationNoticeState;
}

/**
 * The one dictation failure that stays on screen: the browser refused the microphone. A screen reader hears it from
 * `AgentDictationAnnouncement`: a status that comes into the page with its text already in it is not announced by
 * every screen reader, while an alert is.
 */
export const AgentDictationNotice = memo(({ notice }: AgentDictationNoticeProps) => {
  const lang = useLang();

  return <AgentStatusLine title={getDictationFailureText(lang, notice)} />;
});

interface AgentDictationAnnouncementProps {
  failure: AgentDictationFailure;
}

/**
 * Tells a screen reader why a dictation ended without text, while the microphone turns red, as on mobile. Keyed by
 * the failure count, so that a repeated failure is announced again.
 */
export const AgentDictationAnnouncement = memo(({ failure }: AgentDictationAnnouncementProps) => {
  const lang = useLang();

  return <span className="visually-hidden" role="alert">{getDictationFailureText(lang, failure)}</span>;
});

interface AgentStatusLineProps {
  className?: string;
  title: TeactNode;
  body?: TeactNode;
  /** Announces the line as the current status */
  isStatus?: boolean;
  /** Keeps a countdown in the body from being announced on every tick */
  isBodyQuiet?: boolean;
}

function AgentStatusLine({
  className, title, body, isStatus, isBodyQuiet,
}: AgentStatusLineProps) {
  return (
    <p className={buildClassName(styles.statusLine, className)} role={isStatus ? 'status' : undefined}>
      <strong className={buildClassName(styles.title, Boolean(body) && styles.titleWithBody)}>{title}</strong>
      {Boolean(body) && <span aria-live={isBodyQuiet ? 'off' : undefined}>{body}</span>}
    </p>
  );
}

function getDictationFailureText(lang: LangFn, failure: AgentDictationFailure) {
  switch (failure.kind) {
    case 'noSpeech':
      return lang('$agent_dictation_no_speech');
    case 'tooShort':
      return lang('$agent_dictation_too_short');
    case 'microphoneDenied':
      return lang('$agent_dictation_microphone_denied');
    case 'error':
      return getAgentV2ErrorText(failure.code, lang);
  }
}

function getComposerStatusTitle(lang: LangFn, status: AgentV2ComposerStatus) {
  if (status.kind === 'capacity') {
    return lang(status.mode === 'degraded'
      ? '$agent_capacity_degraded_title'
      : '$agent_capacity_limit_title');
  }
  if (status.kind === 'userQuota') return getAgentV2ErrorText('user_quota_exhausted', lang, status.resetAt);
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
  if (!remainingMs || status.kind === 'userQuota') return undefined;

  const formattedTime = formatRemainingTime(lang, remainingMs);
  if (status.kind === 'capacity') return lang('$agent_capacity_limit_known', formattedTime);
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
