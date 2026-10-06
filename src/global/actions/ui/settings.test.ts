import './settings';

import type { GlobalState } from '../../types';

import { addActionHandler } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../lib/teact/teactn', () => ({
  addCallback: jest.fn(),
}));

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
}));

jest.mock('../../../enclave', () => ({
  enclave: {},
}));

jest.mock('../../../util/langProvider', () => ({
  setLanguage: jest.fn(),
}));

jest.mock('../../../util/switchTheme', () => jest.fn());

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => GlobalState;

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

function setIsAutoConfirmEnabled(global: Partial<GlobalState>, isEnabled: boolean) {
  return getHandler('setIsAutoConfirmEnabled')(global as GlobalState, {}, { isEnabled });
}

describe('setIsAutoConfirmEnabled', () => {
  // The cache is saved as JSON, which drops `undefined`, and on load the settings are filled from
  // `INITIAL_STATE`, where the setting is on. Anything but an explicit `false` turns it back on.
  it('stores an explicit `false` when turned off', () => {
    const result = setIsAutoConfirmEnabled({
      settings: { isAutoConfirmEnabled: true } as GlobalState['settings'],
      enclaveSession: { token: 'passcode:aa', validUntil: 1 },
    }, false);

    expect(result.settings.isAutoConfirmEnabled).toBe(false);
    expect(result.enclaveSession).toBeUndefined();
  });

  it('keeps the session when turned on', () => {
    const enclaveSession = { token: 'passcode:aa', validUntil: 1 };

    const result = setIsAutoConfirmEnabled({
      settings: { isAutoConfirmEnabled: false } as GlobalState['settings'],
      enclaveSession,
    }, true);

    expect(result.settings.isAutoConfirmEnabled).toBe(true);
    expect(result.enclaveSession).toBe(enclaveSession);
  });
});
