import './mfa';
import '../ui/mfa';

import type { GlobalState } from '../../types';

import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { updateSettings } from '../../reducers';

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
}));

describe('submitInstallMfa', () => {
  const ACCOUNT_ID = '0-mainnet';
  const INSTALL_REQUEST = {
    requestId: 'install-request',
    user: { id: '1', name: 'Telegram User' },
  };

  // The real handler lives in an action module this test does not load
  addActionHandler('releaseEnclaveSession', jest.fn());

  beforeEach(() => {
    const base = getGlobal();

    setGlobal({
      ...base,
      currentAccountId: ACCOUNT_ID,
      accounts: {
        ...base.accounts,
        byId: { [ACCOUNT_ID]: { type: 'mnemonic', title: 'Test', byChain: { ton: { address: 'UQ1' } } } },
      },
      settings: { ...base.settings, installMfa: INSTALL_REQUEST },
    } as unknown as GlobalState);
  });

  it.each([
    ['an install error', { error: 'Only V5R1 wallets supported!' }, 'Only V5R1 wallets supported!'],
    ['no API response', undefined, 'Unexpected'],
  ])('keeps the request and shows the error on %s', async (_, result, expectedError) => {
    (callApi as jest.Mock).mockResolvedValue(result);

    await submitInstallMfa();

    expect(getGlobal().settings.installMfa)
      .toEqual({ ...INSTALL_REQUEST, error: expectedError, failedAttemptCount: 1 });
    expect(getGlobal().accounts!.byId[ACCOUNT_ID].byChain.ton!.mfa).toBeUndefined();
  });

  it('counts every failure, including repeated identical ones and a cleared error in between', async () => {
    (callApi as jest.Mock).mockResolvedValue({ error: 'Server error' });

    await submitInstallMfa();
    getActions().clearInstallMfaError();
    await submitInstallMfa();
    await submitInstallMfa();

    expect(getGlobal().settings.installMfa)
      .toEqual({ ...INSTALL_REQUEST, error: 'Server error', failedAttemptCount: 3 });
  });

  it('clears the request once the extension is installed', async () => {
    (callApi as jest.Mock).mockResolvedValue('0:mfa-extension');

    await submitInstallMfa();

    expect(getGlobal().settings.installMfa).toBeUndefined();
  });

  it.each([
    ['an error that arrives after the user left the screen', { error: 'Server error' }, undefined],
    ['a success that arrives after the user started another request', '0:mfa-extension', { requestId: 'another' }],
  ])('ignores %s', async (_, result, requestAfterSubmit) => {
    let resolveInstall!: (value: unknown) => void;
    (callApi as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveInstall = resolve;
    }));

    const submission = submitInstallMfa();
    setGlobal(updateSettings(getGlobal(), { installMfa: requestAfterSubmit }));
    resolveInstall(result);
    await submission;

    expect(getGlobal().settings.installMfa).toEqual(requestAfterSubmit);
  });

  function submitInstallMfa() {
    return getActions().submitInstallMfa({ enclaveToken: 'enclave-token' }) as unknown as Promise<void>;
  }
});

describe('clearInstallMfaError', () => {
  it('does not create an install request on the disconnection screen', () => {
    setGlobal(updateSettings(getGlobal(), { installMfa: undefined }));

    getActions().clearInstallMfaError();

    expect(getGlobal().settings.installMfa).toBeUndefined();
  });
});
