import { EnclaveError } from '../../enclave/errors';
import { presentAuthorizeFailure } from './authorizeFailure';

const DATA_MISSING = {
  kind: 'dialog',
  titleKey: '$enclave_data_missing_title',
  messageKey: '$enclave_data_missing_message',
};

describe('presentAuthorizeFailure', () => {
  it.each(['passcode', 'biometric'] as const)('answers missing %s data with the dialog', (authType) => {
    const error = new EnclaveError('auth_not_configured', 'PasscodeAuth: Missing salt or verifier');

    expect(presentAuthorizeFailure(error, authType, [authType], false)).toEqual(DATA_MISSING);
  });

  it.each([
    ['biometric', 'Biometric confirmation failed'],
    ['passcode', 'Wrong password, please try again.'],
  ] as const)('does not call %s data lost while the other method still holds the key', (authType, text) => {
    const error = new EnclaveError('auth_not_configured', `Enclave: no ${authType} auth is configured`);

    expect(presentAuthorizeFailure(error, authType, [authType], true)).toEqual({ kind: 'inline', text });
  });

  it('answers a passcode typed into a biometric-only profile as a wrong one', () => {
    const error = new EnclaveError('auth_not_configured', 'Enclave: no passcode auth is configured');

    expect(presentAuthorizeFailure(error, 'passcode', ['biometric'], false))
      .toEqual({ kind: 'inline', text: 'Wrong password, please try again.' });
  });

  it('answers a refused passcode inline', () => {
    const error = new EnclaveError('wrong_passcode', 'PasscodeAuth: Invalid passcode');

    expect(presentAuthorizeFailure(error, 'passcode', ['passcode'], false))
      .toEqual({ kind: 'inline', text: 'Wrong password, please try again.' });
  });

  // The enclave answers across a message bridge, which rebuilds the error as a plain `Error`
  it('reads the code off an error that lost its class', () => {
    const rebuilt = Object.assign(new Error('Enclave: no passcode auth is configured'), {
      code: 'auth_not_configured',
    });

    expect(presentAuthorizeFailure(rebuilt, 'passcode', ['passcode'], false)).toEqual(DATA_MISSING);
  });

  it('does not call a passcode failure it cannot name a wrong password', () => {
    const error = Object.assign(new Error('Internal error opening backing store'), { name: 'UnknownError' });

    expect(presentAuthorizeFailure(error, 'passcode', ['passcode'], false))
      .toEqual({ kind: 'inline', text: 'Something went wrong.' });
  });

  it('keeps the prompt wording for a biometric failure it cannot name', () => {
    const error = Object.assign(new Error('The operation was cancelled'), { name: 'NotAllowedError' });

    expect(presentAuthorizeFailure(error, 'biometric', ['biometric'], false))
      .toEqual({ kind: 'inline', text: 'Biometric confirmation failed' });
  });
});
