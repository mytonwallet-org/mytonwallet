import type {
  AgentSemanticContentV1,
  AgentStarterHintIdV2,
  AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { AgentV2StarterHint } from '../../api/agentV2/types';
import type { AgentHint } from '../../global/types';
import type { LangFn } from '../../util/langProvider';

import { formatAgentTime } from '../agent/helpers/agentDateFormat';

const HINT_KEYS: Record<AgentStarterHintIdV2, [string, string?]> = {
  'agent.capabilities': ['$agent_hint_capabilities_title'],
  'learn.swap': ['$agent_hint_swap_title', '$agent_hint_swap_prompt'],
  'learn.staking': ['$agent_hint_staking_title', '$agent_hint_staking_prompt'],
  'learn.security': ['$agent_hint_security_title', '$agent_hint_security_prompt'],
  'receive.tokens': ['$agent_hint_receive_title', '$agent_hint_receive_prompt'],
  'wallet.assets': ['$agent_hint_assets_title'],
  'wallet.total': ['$agent_hint_total_title'],
  'wallet.spending': ['$agent_hint_spending_title'],
  'wallet.last_transfer': ['$agent_hint_last_transfer_title'],
  'wallet.fund': ['$agent_hint_fund_title'],
  'market.today': ['$agent_hint_market_today_title'],
  'news.today': ['$agent_hint_news_today_title'],
  'market.bitcoin': ['$agent_hint_bitcoin_title'],
  'market.price': ['$agent_hint_price_title'],
  'staking.yield': ['$agent_hint_staking_yield_title'],
  'staking.options': ['$agent_hint_staking_options_title'],
  'learn.multisend': ['$agent_hint_multisend_title'],
  'action.swap': ['$agent_hint_action_swap_title'],
  'action.send': ['$agent_hint_action_send_title'],
  'action.stake': ['$agent_hint_action_stake_title'],
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

export function mapAgentV2StarterHints(items: readonly AgentV2StarterHint[], lang: LangFn): AgentHint[] {
  const langCode = lang.code ?? 'en';
  return items.map(({ id }) => ({ id, langCode, ...getAgentV2HintCopy(id, lang) }));
}

export function getAgentV2NoticeTexts(content: AgentSemanticContentV1, lang: LangFn): string[] {
  return [lang(NOTICE_KEYS[content.code])];
}

export function getAgentV2ErrorText(code: AgentV2ErrorCode, lang: LangFn, resetAt?: string | number): string {
  switch (code) {
    case 'client_update_required':
      return lang('$agent_error_update_required');
    case 'device_token_missing':
    case 'device_token_invalid':
      return lang('$agent_error_session');
    case 'user_quota_exhausted': {
      const resetTimestamp = typeof resetAt === 'string' ? Date.parse(resetAt) : resetAt;
      if (resetTimestamp !== undefined && resetTimestamp > Date.now()) {
        return lang('$agent_daily_limit_resets_at', formatAgentTime(lang.code ?? 'en', resetTimestamp)) as string;
      }
      return lang('$agent_daily_limit_reached');
    }
    case 'support_escalation_rate_limited':
      return lang('$agent_support_rate_limited');
    case 'rate_limited':
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
    case 'recording_too_large':
      return lang('$agent_error_recording_too_large');
    case 'audio_unreadable':
      return lang('$agent_error_audio_unreadable');
    case 'transcription_unavailable':
      return lang('$agent_error_transcription_unavailable');
    case 'news_unavailable':
      return lang('$agent_news_unavailable');
    case 'digest_unavailable':
      return lang('$agent_digest_unavailable');
    case 'market_data_unavailable':
      return lang('$agent_error_generic');
    case 'network_error':
      return lang('$agent_connection_lost');
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
