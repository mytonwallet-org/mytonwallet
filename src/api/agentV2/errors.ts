import type { AgentV2OperationError } from './types';

import { AgentV2CompatibilityError, AgentV2ContractError } from './protocol/wireReader';
import { AgentV2HttpError } from './identity';
import { AgentV2StreamProtocolError, AgentV2StreamTransportError } from './ndjson';

type AgentV2FailureKind = 'http' | 'compatibility' | 'protocol' | 'cancellation' | 'network' | 'unexpected';

export function classifyAgentV2Error(error: unknown): AgentV2OperationError & { kind: AgentV2FailureKind } {
  if (error instanceof AgentV2HttpError) {
    return { kind: 'http', code: error.code, retryable: error.retryable };
  }
  if (error instanceof AgentV2CompatibilityError) {
    return { kind: 'compatibility', code: 'client_update_required', retryable: false };
  }
  if (error instanceof AgentV2ContractError || error instanceof SyntaxError) {
    return { kind: 'protocol', code: 'invalid_event', retryable: false };
  }
  if (error instanceof AgentV2StreamProtocolError) {
    return { kind: 'protocol', code: 'invalid_event', retryable: error.retryable };
  }
  if (isCancellation(error) || (error instanceof AgentV2StreamTransportError && isCancellation(error.cause))) {
    return { kind: 'cancellation', code: 'run_interrupted', retryable: false };
  }
  if (error instanceof AgentV2StreamTransportError
    || (error instanceof DOMException && (error.name === 'NetworkError' || error.name === 'TimeoutError'))
    || (error instanceof TypeError
      && /failed to fetch|fetch failed|load failed|networkerror|offline/iu.test(error.message))) {
    return { kind: 'network', code: 'network_error', retryable: true };
  }
  return { kind: 'unexpected', code: 'internal_error', retryable: false };
}

export function safeAgentV2OperationError(error: unknown): AgentV2OperationError {
  const { code, retryable } = classifyAgentV2Error(error);
  return { code, retryable };
}

// Run admission retries only transient HTTP statuses, even if an application error permits a new operation.
export function isRetryableAgentV2RunError(error: unknown) {
  if (error instanceof AgentV2HttpError) {
    return error.status === 408 || error.status >= 500 || (error.status === 0 && error.retryable);
  }
  return classifyAgentV2Error(error).kind === 'network';
}

function isCancellation(error: unknown) {
  return error instanceof DOMException && error.name === 'AbortError';
}
