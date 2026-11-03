import type { AuthType, MigrationErrorPresentation } from '../types';

import { getEnclaveErrorCode } from '../../enclave/errors';

const WRONG_PASSWORD = { kind: 'inline', text: 'Wrong password, please try again.' } as const;

/**
 * Only the verifier's own refusal is called a wrong password. A storage that has nothing left to check the
 * password against refuses every password alike, and a user told to retype would retype until logging out.
 */
export function presentAuthorizeFailure(
  err: unknown,
  authType: AuthType,
  /** The auth methods the app recorded as set up, which is what tells lost data from a method never set up */
  authTypes: AuthType[] | undefined,
  /** The other method still holds the key, or that could not be read, so the data is not shown as lost */
  mayOtherAuthUnlock: boolean,
): MigrationErrorPresentation {
  const code = getEnclaveErrorCode(err);

  if (code === 'auth_not_configured' && authTypes?.includes(authType) && !mayOtherAuthUnlock) {
    return {
      kind: 'dialog',
      titleKey: '$enclave_data_missing_title',
      messageKey: '$enclave_data_missing_message',
    };
  }

  // A passcode typed into a profile that never set one up is as wrong as a mistyped one
  if (code === 'wrong_passcode' || (code === 'auth_not_configured' && authType === 'passcode')) {
    return WRONG_PASSWORD;
  }

  return {
    kind: 'inline',
    text: authType === 'biometric' ? 'Biometric confirmation failed' : 'Something went wrong.',
  };
}
