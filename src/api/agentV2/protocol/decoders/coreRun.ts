import type {
  AgentAvailabilityResponseV2,
  AgentDeviceTokenIssueResponseV2,
  AgentErrorCodeV2,
  AgentFeatureCapabilitiesResponseV2,
  AgentProblemReportCapabilityV1,
  AgentRunCancelResponseV2,
  AgentThreadSummaryV2,
  AgentUserQuotaResponseV2,
  AgentUserQuotaV2,
  AgentWalletSnapshotAckV1,
} from '../types';

import {
  boolean,
  boundedInteger,
  fail,
  integer,
  object,
  oneOf,
  string,
  timestamp,
} from '../wireReader';
import {
  threadSummary,
} from './messages';
import {
  ERROR_CODES,
  protocol,
  RETRYABLE_ERROR_CODES,
  uuid,
  validateErrorTiming,
} from './readers';
import { walletQueryCapability } from './wallet';

export interface AgentV2DecodedApiError {
  protocolVersion: 3;
  error: {
    code: AgentErrorCodeV2;
    retryable: boolean;
    threadId?: string;
    runId?: string;
    currentThread?: AgentThreadSummaryV2;
    retryAfterMs?: number;
    resetAt?: string;
    quota?: AgentUserQuotaV2;
  };
}

export function decodeAgentV2ApiError(value: unknown): AgentV2DecodedApiError {
  const result = object(value, '$');
  protocol(result, '$');
  const error = object(result.error, '$.error');
  const code = oneOf<AgentErrorCodeV2>(error.code, ERROR_CODES, '$.error.code');
  const retryable = boolean(error.retryable, '$.error.retryable');
  if (retryable !== RETRYABLE_ERROR_CODES.has(code)) fail('$.error.retryable');
  const threadId = error.threadId === undefined ? undefined : uuid(error.threadId, '$.error.threadId');
  const runId = error.runId === undefined ? undefined : uuid(error.runId, '$.error.runId');
  const currentThread = error.currentThread === undefined
    ? undefined
    : threadSummary(error.currentThread, '$.error.currentThread');
  const retryAfterMs = error.retryAfterMs === undefined
    ? undefined
    : integer(error.retryAfterMs, '$.error.retryAfterMs', 1);
  const resetAt = error.resetAt === undefined ? undefined : timestamp(error.resetAt, '$.error.resetAt');
  const quota = error.quota === undefined ? undefined : userQuota(error.quota, '$.error.quota');
  if (code === 'user_quota_exhausted') {
    if (error.quota === undefined || error.resetAt === undefined) fail('$.error.quota');
  } else if (error.quota !== undefined) {
    fail('$.error.quota');
  }
  validateErrorTiming(code, error, '$.error');
  return {
    protocolVersion: 3,
    error: {
      code,
      retryable,
      ...(threadId !== undefined && { threadId }),
      ...(runId !== undefined && { runId }),
      ...(currentThread !== undefined && { currentThread }),
      ...(retryAfterMs !== undefined && { retryAfterMs }),
      ...(resetAt !== undefined && { resetAt }),
      ...(quota !== undefined && { quota }),
    },
  };
}

export function decodeAgentV2Availability(value: unknown): AgentAvailabilityResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const state = oneOf<'available' | 'capacity_exhausted'>(
    result.state,
    new Set(['available', 'capacity_exhausted']),
    '$.state',
  );
  if (state === 'available' && result.resetAt !== undefined) fail('$.resetAt');
  const resetAt = result.resetAt === undefined ? undefined : timestamp(result.resetAt, '$.resetAt');
  return state === 'available'
    ? { protocolVersion: 3, state }
    : { protocolVersion: 3, state, ...(resetAt !== undefined && { resetAt }) };
}

export function decodeAgentV2UserQuota(value: unknown): AgentUserQuotaResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return { protocolVersion: 3, quota: userQuota(result.quota, '$.quota') };
}

export function decodeAgentV2DeviceToken(value: unknown): AgentDeviceTokenIssueResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return {
    protocolVersion: 3,
    deviceId: uuid(result.deviceId, '$.deviceId'),
    deviceToken: string(result.deviceToken, '$.deviceToken'),
    expiresAt: timestamp(result.expiresAt, '$.expiresAt'),
  };
}

export function decodeAgentV2FeatureCapabilities(value: unknown): AgentFeatureCapabilitiesResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return {
    protocolVersion: 3,
    walletQuery: walletQueryCapability(result.walletQuery, '$.walletQuery'),
    problemReport: { status: problemReportStatus(result.problemReport) },
  };
}

// A server that does not state problem reports leaves them off without taking wallet reads down with them
function problemReportStatus(value: unknown): AgentProblemReportCapabilityV1['status'] {
  const status = value && typeof value === 'object' ? (value as { status?: unknown }).status : undefined;
  return status === 'available' ? 'available' : 'disabled';
}

export function decodeAgentV2RunCancel(value: unknown): AgentRunCancelResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const runId = uuid(result.runId, '$.runId');
  const state = oneOf<AgentRunCancelResponseV2['state']>(
    result.state,
    new Set(['completed', 'completed_with_tool_error', 'failed', 'cancelled', 'run_interrupted']),
    '$.state',
  );
  const lastSequence = integer(result.lastSequence, '$.lastSequence');
  const thread = threadSummary(result.thread, '$.thread');
  const duplicate = result.duplicate === undefined ? undefined : boolean(result.duplicate, '$.duplicate');
  return {
    protocolVersion: 3,
    runId,
    state,
    lastSequence,
    thread,
    ...(duplicate !== undefined && { duplicate }),
  };
}

function userQuota(value: unknown, path: string): AgentUserQuotaV2 {
  const result = object(value, path);
  const limit = boundedInteger(result.limit, `${path}.limit`, 1, 10_000);
  const used = boundedInteger(result.used, `${path}.used`, 0, 10_000);
  const remaining = boundedInteger(result.remaining, `${path}.remaining`, 0, 10_000);
  const resetAt = timestamp(result.resetAt, `${path}.resetAt`);
  if (used > limit || remaining !== limit - used) fail(`${path}.remaining`);
  return { limit, used, remaining, resetAt };
}

export function decodeAgentV2WalletSnapshotAck(value: unknown): AgentWalletSnapshotAckV1 {
  const result = object(object(value, '$').snapshotRef, '$.snapshotRef');
  return { snapshotRef: {
    instanceId: uuid(result.instanceId, '$.snapshotRef.instanceId'),
    sessionId: uuid(result.sessionId, '$.snapshotRef.sessionId'),
    revision: integer(result.revision, '$.snapshotRef.revision', 1),
    snapshotRevision: integer(result.snapshotRevision, '$.snapshotRef.snapshotRevision', 1),
  } };
}
