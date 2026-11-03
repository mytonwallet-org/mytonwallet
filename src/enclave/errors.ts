/**
 * The ways a call into the Enclave can fail, named so that the caller can act on them: some of these
 * mean "ask for the passcode again", others mean the storage is in a state no retry will change.
 * Collapsing them into a bare `Error` leaves the UI with one message for every cause.
 */
export type EnclaveErrorCode =
  | 'auth_already_configured'
  | 'auth_setup_in_progress'
  | 'auth_not_configured'
  | 'wrong_passcode'
  | 'session_expired'
  | 'unknown_token'
  | 'master_key_missing'
  | 'secret_missing';

export class EnclaveError extends Error {
  constructor(readonly code: EnclaveErrorCode, message: string) {
    super(message);
    this.name = 'EnclaveError';
  }
}

const ENCLAVE_ERROR_CODES: ReadonlySet<string> = new Set(Object.keys({
  auth_already_configured: true,
  auth_setup_in_progress: true,
  auth_not_configured: true,
  wrong_passcode: true,
  session_expired: true,
  unknown_token: true,
  master_key_missing: true,
  secret_missing: true,
} satisfies Record<EnclaveErrorCode, true>));

/**
 * Read off the property rather than through `instanceof`: an error that crossed the worker bridge is
 * rebuilt as a plain `Error` with the code copied and the class lost, and an enclave that ever answers
 * from the other side would silently stop matching. Membership is what separates a code the enclave
 * minted from a `code` any platform error may carry - an `ENOENT` or an `UNAVAILABLE` from a native
 * bridge would otherwise reach support looking like a verdict the enclave had reached.
 */
export function getEnclaveErrorCode(err: unknown): EnclaveErrorCode | undefined {
  const code = (err as { code?: unknown } | undefined)?.code;

  return typeof code === 'string' && ENCLAVE_ERROR_CODES.has(code) ? code as EnclaveErrorCode : undefined;
}
