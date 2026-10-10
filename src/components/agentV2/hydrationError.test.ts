import type { AgentV2OperationError } from '../../api/agentV2/types';
import type { LangFn } from '../../util/langProvider';

import { buildAgentV2HydrationError } from './hydrationError';

const lang = ((key: string) => ({
  $agent_connection_interrupted: 'Connection message',
  $agent_error_generic: 'Request message',
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
      message: 'Request message',
      isRetryable: false,
    });
  });
});
