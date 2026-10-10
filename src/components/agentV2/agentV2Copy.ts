import type {
  AgentSemanticContentV1,
  AgentStarterHintIdV2,
  AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { LangFn } from '../../util/langProvider';

const HINT_KEYS: Record<AgentStarterHintIdV2, [string, string?]> = {
  'agent.capabilities': ['$agent_hint_capabilities_title'],
  'learn.swap': ['$agent_hint_swap_title', '$agent_hint_swap_prompt'],
  'learn.staking': ['$agent_hint_staking_title', '$agent_hint_staking_prompt'],
  'learn.security': ['$agent_hint_security_title', '$agent_hint_security_prompt'],
  'receive.tokens': ['$agent_hint_receive_title', '$agent_hint_receive_prompt'],
};

const NOTICE_KEYS: Record<AgentSemanticContentV1['code'], string> = {
  agent_unavailable: '$agent_error_generic',
  content_over_budget: '$agent_notice_content_over_budget',
  web_search_no_results: '$agent_notice_web_search_no_results',
};

export function getAgentV2HintCopy(id: AgentStarterHintIdV2, lang: LangFn) {
  const [titleKey, subtitleKey] = HINT_KEYS[id];
  const title = lang(titleKey);
  return { title, subtitle: subtitleKey ? lang(subtitleKey) : '', prompt: title };
}

export function getAgentV2NoticeTexts(content: AgentSemanticContentV1, lang: LangFn): string[] {
  return [lang(NOTICE_KEYS[content.code])];
}

export function getAgentV2ErrorText(code: AgentV2ErrorCode, lang: LangFn) {
  switch (code) {
    case 'client_update_required':
      return lang('$agent_error_update_required');
    case 'device_token_missing':
    case 'device_token_invalid':
      return lang('$agent_error_session');
    case 'rate_limited':
    case 'user_quota_exhausted':
    case 'agent_capacity_exhausted':
    case 'device_token_rate_limited':
      return lang('$agent_error_limit');
    case 'tool_scope_mismatch':
    case 'tool_result_already_submitted':
    case 'wallet_context_changed':
    case 'tool_timeout':
    case 'tool_failed':
    case 'tool_result_too_large':
      return lang('$agent_error_tool');
    case 'market_data_unavailable':
      return lang('$agent_error_generic');
    case 'network_error':
      return lang('$agent_connection_interrupted');
    case 'provider_timeout':
    case 'provider_unavailable':
      return lang('$agent_capacity_limit_unknown');
    case 'thread_revision_conflict':
      return lang('$agent_error_conversation_updated');
    case 'invalid_event':
      return lang('$agent_error_invalid_response');
    case 'invalid_request':
    case 'idempotency_mismatch':
    case 'thread_not_found':
    case 'thread_run_in_progress':
    case 'run_not_found':
    case 'run_interrupted':
    case 'run_replay_expired':
    case 'message_not_editable':
    case 'regenerate_target_invalid':
    case 'followup_reference_invalid':
    case 'provider_error':
    case 'empty_response':
    case 'internal_error':
      return lang('$agent_error_generic');
    default:
      return assertUnreachable(code);
  }
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 copy code: ${String(value)}`);
}
