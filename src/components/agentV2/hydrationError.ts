import type { AgentV2OperationError } from '../../api/agentV2/types';
import type { LangFn } from '../../util/langProvider';

import { getAgentV2ErrorText } from './agentV2Copy';

export interface AgentV2HydrationError {
  code: AgentV2OperationError['code'];
  message: string;
  isRetryable: boolean;
}

export function buildAgentV2HydrationError(
  error: AgentV2OperationError | undefined,
  lang: LangFn,
): AgentV2HydrationError {
  const code = error?.code ?? 'network_error';
  return {
    code,
    message: getHistoryErrorText(code, lang),
    isRetryable: error?.retryable ?? true,
  };
}

function getHistoryErrorText(code: AgentV2OperationError['code'], lang: LangFn) {
  switch (code) {
    case 'tool_scope_mismatch':
    case 'tool_result_already_submitted':
    case 'wallet_context_changed':
    case 'tool_timeout':
    case 'tool_failed':
    case 'tool_result_too_large':
    case 'invalid_request':
      // Here these codes come from the history request, so they mean the chat failed to load, not a wallet operation
      return lang('Failed to load chat');
    default:
      return getAgentV2ErrorText(code, lang);
  }
}
