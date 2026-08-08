import './enclave';

import type { GlobalState } from '../../types';

import { enclave } from '../../../enclave';
import { addActionHandler } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../enclave', () => ({
  enclave: { releaseSession: jest.fn() },
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => GlobalState;

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

function release(global: Partial<GlobalState>, enclaveToken: string) {
  return getHandler('releaseEnclaveSession')(global as GlobalState, {}, { enclaveToken });
}

describe('releaseEnclaveSession', () => {
  beforeEach(() => (enclave.releaseSession as jest.Mock).mockClear());

  // The token in the global state is only a copy; the reads live in the Enclave, so dropping the
  // copy without telling the Enclave would leave them spendable by anything that kept the token.
  it('tells the Enclave to end the session, not just the global state', () => {
    const result = release({ enclaveSession: { token: 'passcode:aa' } }, 'passcode:aa');

    expect(enclave.releaseSession).toHaveBeenCalledWith('passcode:aa');
    expect(result.enclaveSession).toBeUndefined();
  });

  it('keeps a session that expires by time', () => {
    const enclaveSession = { token: 'passcode:aa', validUntil: 1 };

    const result = release({ enclaveSession }, 'passcode:aa');

    expect(result.enclaveSession).toBe(enclaveSession);
  });

  it('keeps a session the released token does not own', () => {
    const enclaveSession = { token: 'passcode:bb' };

    const result = release({ enclaveSession }, 'passcode:aa');

    expect(result.enclaveSession).toBe(enclaveSession);
  });
});
