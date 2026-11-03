import type { FC } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AuthType } from '../../global/types';

import { pause } from '../../util/schedulers';
import { EnclaveError } from '../../enclave/errors';

import PasswordForm from './PasswordForm';

const mockAuthorizeOrThrow = jest.fn();
const mockIsAuthProvisioned = jest.fn();
const mockShowDialog = jest.fn();
const mockSetEnclaveSession = jest.fn();
const mockGlobal: { settings: { animationLevel: number }; authTypes?: AuthType[] } = {
  settings: { animationLevel: 0 },
};

jest.mock('../../enclave', () => ({
  enclave: {
    authorizeOrThrow: (...args: unknown[]) => mockAuthorizeOrThrow(...args),
    isAuthProvisioned: (...args: unknown[]) => mockIsAuthProvisioned(...args),
  },
}));
jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  getGlobal: () => mockGlobal,
  getActions: () => ({
    migrateLegacyAuth: jest.fn(),
    migrateLegacyBiometricAuth: jest.fn(),
    setEnclaveSession: mockSetEnclaveSession,
    enableBiometrics: jest.fn(),
    upgradeMultichainAccounts: jest.fn(),
    showDialog: mockShowDialog,
  }),
  withGlobal: () => (Component: unknown) => Component,
}));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../../util/biometrics', () => ({
  ...jest.requireActual('../../util/biometrics'),
  getDoesUsePinPad: () => false,
}));
jest.mock('../main/modals/LogOutModal', () => ({
  __esModule: true,
  default: () => undefined,
}));
// Style modules resolve to one stub, which answers every class name with the name itself here
jest.mock('../../../tests/staticFileMock.js', () => new Proxy({}, {
  get: (_target, key) => (key === '__esModule' ? false : key),
}));

// `withGlobal` is mocked to hand the component through, so the state it would map arrives as props
const PasswordFormWithState = PasswordForm as FC<Parameters<typeof PasswordForm>[0] & {
  isBiometricAuthEnabled: boolean;
}>;

const BIOMETRIC_PROMPT_DELAY_MS = 350;
const DATA_MISSING_DIALOG = {
  title: '$enclave_data_missing_title',
  buttons: { confirm: { action: 'exportLogs' }, cancel: { title: 'Close' } },
};

describe('PasswordForm unlock', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    mockGlobal.authTypes = ['passcode'];
    mockIsAuthProvisioned.mockResolvedValue(false);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.clearAllMocks();
  });

  function renderForm(isBiometricAuthEnabled: boolean, onAuthorize = jest.fn()) {
    TeactDOM.render(
      <PasswordFormWithState
        isActive
        noAnimatedIcon
        operationType="unlock"
        isBiometricAuthEnabled={isBiometricAuthEnabled}
        onAuthorize={onAuthorize}
      />,
      root,
    );
  }

  async function submitPassword(password: string) {
    renderForm(false);
    await pause(20);

    const input = root.querySelector('input')!;
    input.value = password;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    await pause(20);
    [...root.querySelectorAll('button')].find((button) => button.textContent === 'Send')!.click();
    await pause(20);
  }

  function isLogOutOffered() {
    return !root.querySelector('.logOutWrapper')!.classList.contains('logOutWrapperHidden');
  }

  it('says the wallet data is missing when the storage has nothing to check the password against', async () => {
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'PasscodeAuth: Missing salt or verifier'),
    );

    await submitPassword('123456');

    expect(mockShowDialog).toHaveBeenCalledWith(expect.objectContaining(DATA_MISSING_DIALOG));
    expect(root.textContent).not.toContain('Wrong password');
  });

  // The dialog sends a user who has the secret words to exit and import them again
  it('offers to exit all wallets once the data is known to be missing', async () => {
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'PasscodeAuth: Missing salt or verifier'),
    );

    await submitPassword('123456');

    expect(isLogOutOffered()).toBe(true);
  });

  it('asks for the password again when the verifier refuses it', async () => {
    mockAuthorizeOrThrow.mockRejectedValue(new EnclaveError('wrong_passcode', 'PasscodeAuth: Invalid passcode'));

    await submitPassword('000000');

    expect(root.textContent).toContain('Wrong password, please try again.');
    expect(mockShowDialog).not.toHaveBeenCalled();
    expect(isLogOutOffered()).toBe(false);
  });

  // A profile that only ever set up biometrics has no passcode to lose, so a typed one is just wrong
  it('answers a passcode typed into a biometric-only profile as a wrong one', async () => {
    mockGlobal.authTypes = ['biometric'];
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'Enclave: no passcode auth is configured'),
    );

    await submitPassword('123456');

    expect(root.textContent).toContain('Wrong password, please try again.');
    expect(mockShowDialog).not.toHaveBeenCalled();
  });

  it('unlocks with the session the enclave issues', async () => {
    mockAuthorizeOrThrow.mockResolvedValue({ token: 'passcode:issued' });

    await submitPassword('123456');

    expect(mockSetEnclaveSession).toHaveBeenCalledWith({ token: 'passcode:issued' });
  });

  it('says the wallet data is missing on the biometric route too', async () => {
    mockGlobal.authTypes = ['biometric'];
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'ElectronAuth: no key material is stored'),
    );

    renderForm(true);
    await pause(BIOMETRIC_PROMPT_DELAY_MS);

    expect(mockAuthorizeOrThrow).toHaveBeenCalledWith('biometric', undefined, undefined, undefined);
    expect(mockShowDialog).toHaveBeenCalledWith(expect.objectContaining(DATA_MISSING_DIALOG));
  });

  // Turning biometrics off swaps the method in the enclave first and saves the recorded one seconds later
  it('does not call the data lost when the key still opens with the password', async () => {
    mockGlobal.authTypes = ['biometric'];
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'Enclave: no biometric auth is configured'),
    );
    mockIsAuthProvisioned.mockImplementation((authType: AuthType) => Promise.resolve(authType === 'passcode'));

    renderForm(true);
    await pause(BIOMETRIC_PROMPT_DELAY_MS);

    expect(mockIsAuthProvisioned).toHaveBeenCalledWith('passcode');
    expect(mockShowDialog).not.toHaveBeenCalled();
    expect(isLogOutOffered()).toBe(false);
  });

  it('does not call the data lost when the key still opens with biometrics', async () => {
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'Enclave: no passcode auth is configured'),
    );
    mockIsAuthProvisioned.mockImplementation((authType: AuthType) => Promise.resolve(authType === 'biometric'));

    await submitPassword('123456');

    expect(mockShowDialog).not.toHaveBeenCalled();
    expect(isLogOutOffered()).toBe(false);
  });

  it('does not call the data lost when the other method cannot be checked', async () => {
    mockGlobal.authTypes = ['biometric'];
    mockAuthorizeOrThrow.mockRejectedValue(
      new EnclaveError('auth_not_configured', 'Enclave: no biometric auth is configured'),
    );
    mockIsAuthProvisioned.mockRejectedValue(new Error('Internal error opening backing store'));

    renderForm(true);
    await pause(BIOMETRIC_PROMPT_DELAY_MS);

    expect(mockShowDialog).not.toHaveBeenCalled();
    expect(isLogOutOffered()).toBe(false);
    expect([...root.querySelectorAll('button')].some((button) => button.textContent === 'Try Again')).toBe(true);
  });

  it('keeps the prompt wording and a retry for a refused biometric prompt', async () => {
    mockGlobal.authTypes = ['biometric'];
    mockAuthorizeOrThrow.mockRejectedValue(
      Object.assign(new Error('The operation was cancelled'), { name: 'NotAllowedError' }),
    );

    renderForm(true);
    await pause(BIOMETRIC_PROMPT_DELAY_MS);

    expect(root.textContent).toContain('Biometric confirmation failed');
    expect([...root.querySelectorAll('button')].some((button) => button.textContent === 'Try Again')).toBe(true);
  });
});
