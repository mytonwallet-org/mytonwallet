import type { AgentUserQuotaV2 } from '../../api/agentV2/protocol/types';
import type {
  AgentV2AvailabilityState,
  AgentV2ComposerStatus,
  AgentV2RateLimitState,
} from '../../api/agentV2/types';

interface AgentV2QuotaRetry {
  clientRunId?: string;
  resetAt?: number;
}

export function selectAgentV2ComposerStatus(
  availability?: AgentV2AvailabilityState,
  quota?: AgentUserQuotaV2,
  quotaRetry?: AgentV2QuotaRetry,
  rateLimit?: AgentV2RateLimitState,
  now = Date.now(),
): AgentV2ComposerStatus | undefined {
  if (
    availability?.state === 'capacity_exhausted'
    && availability.resetAt !== undefined
    && availability.resetAt > now
  ) {
    return { kind: 'capacity', mode: 'blocked', resetAt: availability.resetAt };
  }

  const quotaResetAt = quotaRetry?.resetAt ?? (quota ? Date.parse(quota.resetAt) : undefined);
  if (quota && quota.remaining === 0 && quotaResetAt !== undefined && quotaResetAt > now) {
    return {
      kind: 'userQuota',
      mode: 'blocked',
      quota,
      resetAt: quotaResetAt,
      ...(quotaRetry?.clientRunId ? { clientRunId: quotaRetry.clientRunId } : {}),
    };
  }

  if (rateLimit && rateLimit.resetAt > now) {
    return {
      kind: 'rateLimit',
      mode: 'blocked',
      resetAt: rateLimit.resetAt,
      ...(rateLimit.clientRunId ? { clientRunId: rateLimit.clientRunId } : {}),
    };
  }

  if (availability?.state === 'capacity_exhausted') {
    return { kind: 'capacity', mode: 'degraded' };
  }

  if (quota && quotaRetry && quotaResetAt !== undefined) {
    return {
      kind: 'userQuota',
      mode: 'informational',
      quota,
      resetAt: quotaResetAt,
      ...(quotaRetry.clientRunId ? { clientRunId: quotaRetry.clientRunId } : {}),
    };
  }

  if (rateLimit) {
    return {
      kind: 'rateLimit',
      mode: 'informational',
      resetAt: rateLimit.resetAt,
      ...(rateLimit.clientRunId ? { clientRunId: rateLimit.clientRunId } : {}),
    };
  }

  return undefined;
}

export function isAgentV2ComposerBlocked(status: AgentV2ComposerStatus | undefined) {
  return status?.mode === 'blocked';
}
