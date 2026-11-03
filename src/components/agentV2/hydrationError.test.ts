import type { AgentV2OperationError } from '../../api/agentV2/types';
import type { LangFn } from '../../util/langProvider';

import { buildAgentV2HydrationError } from './hydrationError';

const lang = ((key: string) => ({
  $agent_connection_lost: 'Connection message',
  $agent_error_generic: 'Request message',
  'Failed to load chat': 'History message',
}[key] ?? key)) as LangFn;

describe('Agent V2 hydration errors', () => {
  it('maps worker and network failures to a connection error', () => {
    expect(buildAgentV2HydrationError(undefined, lang)).toEqual({
      code: 'network_error',
      message: 'Connection message',
      isRetryable: true,
    });
    expect(buildAgentV2HydrationError({
      code: 'network_error',
      retryable: true,
    }, lang)).toEqual({
      code: 'network_error',
      message: 'Connection message',
      isRetryable: true,
    });
  });

  it('preserves backend failure categories without exposing the server message', () => {
    const error: AgentV2OperationError = {
      code: 'invalid_request',
      retryable: false,
    };

    expect(buildAgentV2HydrationError(error, lang)).toEqual({
      code: 'invalid_request',
      message: 'History message',
      isRetryable: false,
    });
  });

  it.each<AgentV2OperationError['code']>([
    'tool_failed', 'tool_timeout', 'wallet_context_changed', 'tool_scope_mismatch',
    'tool_result_already_submitted', 'tool_result_too_large',
  ])('describes %s as a failed history read and keeps Retry available', (code) => {
    expect(buildAgentV2HydrationError({ code, retryable: true }, lang)).toEqual({
      code,
      message: 'History message',
      isRetryable: true,
    });
  });

  it.each<{ code: AgentV2OperationError['code']; message: string }>([
    { code: 'client_update_required', message: '$agent_error_update_required' },
    { code: 'device_token_invalid', message: '$agent_error_session' },
    { code: 'invalid_event', message: '$agent_error_invalid_response' },
    { code: 'news_unavailable', message: '$agent_news_unavailable' },
    { code: 'rate_limited', message: '$agent_error_limit' },
    { code: 'user_quota_exhausted', message: '$agent_daily_limit_reached' },
    { code: 'provider_timeout', message: '$agent_capacity_limit_unknown' },
    { code: 'provider_unavailable', message: '$agent_capacity_limit_unknown' },
    { code: 'provider_error', message: 'Request message' },
    { code: 'internal_error', message: 'Request message' },
  ])('keeps actionable guidance for $code', ({ code, message }) => {
    expect(buildAgentV2HydrationError({ code, retryable: false }, lang)).toEqual({
      code,
      message,
      isRetryable: false,
    });
  });
});
