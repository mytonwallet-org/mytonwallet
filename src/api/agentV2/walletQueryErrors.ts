import type { AgenticWalletToolErrorCode } from './protocol/types';

import { ApiServerError } from '../errors';
import { classifyAgentV2Error } from './errors';

export class WalletQueryProjectionError extends Error {
  constructor(
    readonly code: AgenticWalletToolErrorCode,
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
  }
}

export function isWalletSourceError(error: unknown) {
  return error instanceof ApiServerError || isRetryableWalletSourceError(error);
}

export function isRetryableWalletSourceError(error: unknown) {
  if (error instanceof ApiServerError) {
    return error.statusCode === undefined
      || error.statusCode === 408
      || error.statusCode === 429
      || error.statusCode >= 500;
  }
  if (classifyAgentV2Error(error).kind === 'network') return true;
  if (!error || typeof error !== 'object') return false;
  const code = 'code' in error ? error.code : undefined;
  return code === 'NETWORK_ERROR' || code === 'TIMEOUT' || code === 'SERVER_ERROR';
}

export function invalid(message: string) {
  return new WalletQueryProjectionError('invalid_arguments', message, false);
}

export function unavailable(message: string) {
  return new WalletQueryProjectionError('stale_data_unavailable', message, true);
}
