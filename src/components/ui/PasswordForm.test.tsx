import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { enclave } from '../../enclave';
import { EnclaveError } from '../../enclave/errors';

import PasswordForm, { triggerPasswordFormHandleBiometrics } from './PasswordForm';

const mockActions: Record<string, jest.Mock> = {};

jest.mock('../../global', () => {
  const getActions = () => new Proxy(mockActions, {
    get: (actions, name: string) => (actions[name] ??= jest.fn()),
  });

  return {
    ...jest.requireActual('../../global'),
    getActions,
    getPromiseActions: getActions,
    withGlobal: () => (Component: unknown) => Component,
  };
});
jest.mock('../../enclave', () => ({ enclave: { authorizeOrThrow: jest.fn() } }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));
jest.mock('./AnimatedIconWithPreview', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../main/modals/LogOutModal', () => ({ __esModule: true, default: () => undefined }));

describe('PasswordForm', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('keeps the user on the form until the password check ends', async () => {
    const resolveCheck = deferAuthorize();
    const onCancel = jest.fn();
    const onAuthorize = jest.fn();

    TeactDOM.render(
      <PasswordForm isActive cancelLabel="Back" submitLabel="Confirm" onCancel={onCancel} onAuthorize={onAuthorize} />,
      root,
    );
    await pause(20);
    await submitPassword(root, 'Confirm');
    clickButton(root, 'Back');

    expect(onCancel).not.toHaveBeenCalled();

    resolveCheck({ token: 'token' });
    await pause(20);
    clickButton(root, 'Back');

    expect(onAuthorize).toHaveBeenCalledWith('token');
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('releases the session of a check that ends after the form has closed', async () => {
    const resolveCheck = deferAuthorize();
    const onAuthorize = jest.fn();

    TeactDOM.render(<PasswordForm isActive submitLabel="Confirm" onAuthorize={onAuthorize} />, root);
    await pause(20);
    await submitPassword(root, 'Confirm');

    TeactDOM.render(<PasswordForm isActive={false} submitLabel="Confirm" onAuthorize={onAuthorize} />, root);
    await pause(20);
    resolveCheck({ token: 'token' });
    await pause(20);

    expect(onAuthorize).not.toHaveBeenCalled();
    expect(mockActions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'token' });
  });

  it('releases the session of a check that ends after the form is removed', async () => {
    const resolveCheck = deferAuthorize();
    const onAuthorize = jest.fn();

    TeactDOM.render(<PasswordForm isActive submitLabel="Confirm" onAuthorize={onAuthorize} />, root);
    await pause(20);
    await submitPassword(root, 'Confirm');

    TeactDOM.render(undefined, root);
    await pause(20);
    resolveCheck({ token: 'token' });
    await pause(20);

    expect(onAuthorize).not.toHaveBeenCalled();
    expect(mockActions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'token' });
  });

  it('lets the user leave the form when the password check fails', async () => {
    jest.mocked(enclave.authorizeOrThrow).mockRejectedValueOnce(new Error('Check failed'));
    const onCancel = jest.fn();
    const onError = jest.fn();

    TeactDOM.render(
      <PasswordForm
        isActive
        cancelLabel="Back"
        submitLabel="Confirm"
        onCancel={onCancel}
        onAuthorize={jest.fn()}
        onError={onError}
      />,
      root,
    );
    await pause(20);
    await submitPassword(root, 'Confirm');
    clickButton(root, 'Back');

    expect(onError).toHaveBeenCalledWith('Something went wrong.');
    expect(root.textContent).toContain('Something went wrong.');
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('turns biometrics back on after a migration that ends after the form has closed', async () => {
    let finishBiometricsSetup!: NoneToVoidFunction;
    mockActions.enableBiometrics = jest.fn(() => new Promise<void>((resolve) => {
      finishBiometricsSetup = resolve;
    }));
    const onAuthorize = jest.fn();
    // State props go straight to the form, as `withGlobal` is mocked
    const migrationProps = { shouldMigrate: true, hasLegacyBiometrics: true };
    const renderForm = (isActive: boolean) => TeactDOM.render(
      <PasswordForm isActive={isActive} submitLabel="Confirm" onAuthorize={onAuthorize} {...migrationProps} />,
      root,
    );

    renderForm(true);
    await pause(20);
    await submitPassword(root, 'Confirm');

    renderForm(false);
    await pause(20);
    void mockActions.migrateLegacyAuth.mock.calls[0][0].onSuccess('token');

    expect(mockActions.enableBiometrics).toHaveBeenCalledTimes(1);
    expect(mockActions.releaseEnclaveSession).not.toHaveBeenCalled();

    finishBiometricsSetup();
    await pause(0);

    expect(mockActions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'token' });
    expect(onAuthorize).not.toHaveBeenCalled();
  });

  it('drops a failure of a check that ends after the form has closed', async () => {
    const resolveCheck = deferAuthorize();
    const onError = jest.fn();

    TeactDOM.render(<PasswordForm isActive submitLabel="Confirm" onAuthorize={jest.fn()} onError={onError} />, root);
    await pause(20);
    await submitPassword(root, 'Confirm');

    TeactDOM.render(
      <PasswordForm isActive={false} submitLabel="Confirm" onAuthorize={jest.fn()} onError={onError} />,
      root,
    );
    await pause(20);
    resolveCheck(new EnclaveError('wrong_passcode', 'Wrong passcode'));
    await pause(20);

    expect(onError).not.toHaveBeenCalledWith('Wrong password, please try again.');
    expect(root.textContent).not.toContain('Wrong password');
  });

  it('keeps a newer check running when an older one ends', async () => {
    const resolveOlderCheck = deferAuthorize();
    const resolveNewerCheck = deferAuthorize();
    const onCancel = jest.fn();
    const onAuthorize = jest.fn();
    const renderForm = (isActive: boolean) => TeactDOM.render(
      <PasswordForm
        isActive={isActive}
        cancelLabel="Back"
        submitLabel="Confirm"
        onCancel={onCancel}
        onAuthorize={onAuthorize}
      />,
      root,
    );

    renderForm(true);
    await pause(20);
    await submitPassword(root, 'Confirm');

    renderForm(false);
    await pause(20);
    renderForm(true);
    await pause(20);
    await submitPassword(root, 'Confirm');

    resolveOlderCheck({ token: 'older' });
    await pause(20);
    clickButton(root, 'Back');

    expect(onCancel).not.toHaveBeenCalled();
    expect(mockActions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'older' });

    resolveNewerCheck({ token: 'newer' });
    await pause(20);

    expect(onAuthorize).toHaveBeenCalledTimes(1);
    expect(onAuthorize).toHaveBeenCalledWith('newer');
  });

  it('authorizes on a form that stays inactive, like the manually locked app', async () => {
    jest.mocked(enclave.authorizeOrThrow).mockResolvedValue({ token: 'token', validUntil: undefined });
    const onAuthorize = jest.fn();

    TeactDOM.render(<PasswordForm isActive={false} submitLabel="Unlock" onAuthorize={onAuthorize} />, root);
    await pause(20);
    await submitPassword(root, 'Unlock');

    expect(onAuthorize).toHaveBeenCalledWith('token');
  });

  it('leaves the lock screen biometrics signal to the unlock form', async () => {
    jest.mocked(enclave.authorizeOrThrow).mockResolvedValue({ token: 'token', validUntil: undefined });
    // State props go straight to the form, as `withGlobal` is mocked
    const biometricsProps = { isBiometricAuthEnabled: true };
    const renderForm = (operationType: 'transfer' | 'unlock') => TeactDOM.render(
      <PasswordForm isActive={false} operationType={operationType} onAuthorize={jest.fn()} {...biometricsProps} />,
      root,
    );

    renderForm('transfer');
    await pause(20);
    triggerPasswordFormHandleBiometrics();
    await pause(20);

    expect(enclave.authorizeOrThrow).not.toHaveBeenCalled();

    TeactDOM.render(undefined, root);
    renderForm('unlock');
    await pause(20);
    triggerPasswordFormHandleBiometrics();
    await pause(20);

    expect(enclave.authorizeOrThrow).toHaveBeenCalledTimes(1);
  });
});

// Makes the next `enclave.authorizeOrThrow` call wait until the returned callback answers it
function deferAuthorize() {
  let settleCheck: (outcome: { token: string } | Error) => void;
  jest.mocked(enclave.authorizeOrThrow).mockReturnValueOnce(new Promise((resolve, reject) => {
    settleCheck = (outcome) => (
      outcome instanceof Error ? reject(outcome) : resolve({ validUntil: undefined, ...outcome })
    );
  }));

  return (outcome: { token: string } | Error) => settleCheck(outcome);
}

async function submitPassword(root: HTMLElement, submitLabel: string) {
  const input = root.querySelector('input')!;
  input.value = 'password';
  input.dispatchEvent(new Event('input', { bubbles: true }));
  await pause(20);

  clickButton(root, submitLabel);
  await pause(20);
}

function clickButton(root: HTMLElement, label: string) {
  Array.from(root.querySelectorAll('button')).find((button) => button.textContent === label)!.click();
}
