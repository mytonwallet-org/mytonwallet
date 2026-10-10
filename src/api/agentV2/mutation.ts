import type { AgentV2OperationResult } from './types';

import { safeAgentV2OperationError } from './errors';

export async function runSafeAgentV2Operation<T>(
  operation: () => Promise<T>,
): Promise<AgentV2OperationResult<T>> {
  try {
    return { ok: true, value: await operation() };
  } catch (error) {
    return { ok: false, error: safeAgentV2OperationError(error) };
  }
}
