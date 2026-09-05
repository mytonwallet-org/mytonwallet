import type { ApiAnyDisplayError } from './types';
import { ApiCommonError } from './types';

export class ApiBaseError extends Error {
  constructor(message?: string, public displayError?: ApiAnyDisplayError) {
    super(message);
    this.name = this.constructor.name;
  }
}

export class ApiUserRejectsError extends ApiBaseError {
  constructor(message: string = 'Canceled by the user') {
    super(message);
  }
}

export class ApiServerError extends ApiBaseError {
  constructor(message: string, public statusCode?: number) {
    super(message, ApiCommonError.ServerError);
  }
}

const WALLET_DISCOVERY_RECOVERABLE_FETCH_ERRORS = new Set([
  'Failed to fetch', // Chromium
  'NetworkError when attempting to fetch resource.', // Firefox (console shows "TypeError: …")
  'Load failed', // Safari
]);

// Ethers reports upstream trouble as a plain `Error` carrying a `code`, so neither `instanceof` check below sees it.
// Only the three transport codes belong here: `SERVER_ERROR` (upstream answered non-2xx or unparseable), plus the
// network and timeout pair. Everything else ethers raises — `CALL_EXCEPTION` above all — is an answer about the
// chain rather than a failure to reach it, and swallowing those would hide a real verdict behind a default wallet.
const ETHERS_RECOVERABLE_TRANSPORT_CODES = new Set(['SERVER_ERROR', 'NETWORK_ERROR', 'TIMEOUT']);

function isEthersTransportError(err: unknown): boolean {
  // Duck-typed rather than `instanceof`: this module is shared with builds compiled without EVM (NO_EVM=1),
  // where importing ethers just to name its error class would pull the whole library into the bundle.
  return err instanceof Error
    && 'code' in err
    && typeof (err as { code: unknown }).code === 'string'
    && ETHERS_RECOVERABLE_TRANSPORT_CODES.has((err as { code: string }).code);
}

/**
 * Whether wallet discovery may continue with the default derivation path instead of aborting the whole import.
 *
 * Discovery is a best-effort scan for extra derivation variants, so an unreachable upstream must degrade it rather
 * than cancel it. The import fans out over every chain in a single `Promise.all`, which makes one unrecognised
 * transport error on one chain enough to reject the lot and fail the import everywhere.
 */
export function isWalletDiscoveryRecoverableTransportError(err: unknown): boolean {
  // Check for the error text to catch specific offline-import case.
  return err instanceof ApiServerError
    || (err instanceof TypeError && WALLET_DISCOVERY_RECOVERABLE_FETCH_ERRORS.has(err.message))
    || isEthersTransportError(err);
}

export class AbortOperationError extends ApiBaseError {
  constructor(message: string = 'Abort operation') {
    super(message);
  }
}

export class NotImplemented extends ApiBaseError {
  constructor(message: string = 'Not implemented') {
    super(message);
  }
}

export function maybeApiErrors(fn: AnyAsyncFunction) {
  return async (...args: any) => {
    try {
      return await fn(...args);
    } catch (err) {
      return handleServerError(err);
    }
  };
}

export function handleServerError(err: any) {
  if (err instanceof ApiServerError) {
    return { error: err.displayError! };
  }
  throw err;
}
