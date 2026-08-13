/**
 * The ways a call into the Enclave can fail, named so that the caller can act on them: some of these
 * mean "ask for the passcode again", others mean the storage is in a state no retry will change.
 * Collapsing them into a bare `Error` leaves the UI with one message for every cause.
 */
export type EnclaveErrorCode =
  | 'auth_already_configured'
  | 'auth_setup_in_progress'
  | 'auth_not_configured'
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
