/* eslint-disable */
// Generated from specs/schemas/agent-v2-public.schema.json. Do not edit.
import type { AgentActionKind, AgentClientFeature, AgentErrorCodeV2, AgentEventType, AgentRunActivityCodeV1 } from './public';

export const AGENT_EVENT_TYPES: readonly AgentEventType[] = [
  'run_start',
  'thread',
  'message_start',
  'text_delta',
  'text_draft',
  'table_data',
  'table_reference',
  'text_link',
  'message_content_end',
  'tool_call',
  'tool_status',
  'run_activity',
  'action',
  'followups',
  'semantic_content',
  'message_end',
  'error'
];

export const AGENT_ERROR_CODES: readonly AgentErrorCodeV2[] = [
  'invalid_request',
  'invalid_event',
  'client_update_required',
  'network_error',
  'device_token_missing',
  'device_token_invalid',
  'device_token_rate_limited',
  'idempotency_mismatch',
  'thread_revision_conflict',
  'thread_not_found',
  'thread_run_in_progress',
  'run_not_found',
  'run_interrupted',
  'run_replay_expired',
  'rate_limited',
  'user_quota_exhausted',
  'agent_capacity_exhausted',
  'tool_scope_mismatch',
  'tool_result_already_submitted',
  'wallet_context_changed',
  'tool_timeout',
  'tool_failed',
  'tool_result_too_large',
  'market_data_unavailable',
  'message_not_editable',
  'regenerate_target_invalid',
  'followup_reference_invalid',
  'provider_timeout',
  'provider_unavailable',
  'provider_error',
  'empty_response',
  'internal_error'
];

export const AGENT_RETRYABLE_ERROR_CODES: readonly AgentErrorCodeV2[] = [
  'network_error',
  'device_token_missing',
  'device_token_invalid',
  'device_token_rate_limited',
  'thread_revision_conflict',
  'thread_run_in_progress',
  'run_interrupted',
  'rate_limited',
  'user_quota_exhausted',
  'agent_capacity_exhausted',
  'wallet_context_changed',
  'tool_timeout',
  'tool_failed',
  'market_data_unavailable',
  'provider_timeout',
  'provider_unavailable',
  'provider_error',
  'empty_response',
  'internal_error'
];

export const AGENT_ACTION_KINDS: readonly AgentActionKind[] = [
  'send',
  'receive',
  'stake',
  'swap',
  'openDapp'
];

export const AGENT_CLIENT_FEATURES: readonly AgentClientFeature[] = [
  'followups',
  'walletDirectory',
  'sendRecipientWithoutAsset',
  'walletChainLookup'
];

export const AGENT_RUN_ACTIVITY_CODES: readonly AgentRunActivityCodeV1[] = [
  'web.searching',
  'web.reading_sources',
  'help.searching',
  'data.reading_market',
  'analysis.computing'
];
