import './transfer';

import type { GlobalState } from '../../types';
import { TransferState } from '../../types';

import { addActionHandler } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => GlobalState;

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

function confirm(shouldRequireFreshAuth: boolean) {
  const actions = { submitTransfer: jest.fn() };
  const global = {
    currentTransfer: { state: TransferState.Confirm, tokenSlug: 'toncoin', shouldRequireFreshAuth },
    enclaveSession: { token: 'passcode:aa', validUntil: Date.now() + 60_000 },
  } as unknown as GlobalState;

  const result = getHandler('submitTransferConfirm')(global, actions);

  return { result, actions };
}

describe('submitTransferConfirm', () => {
  it('sends with the Remember Passcode window', () => {
    const { result, actions } = confirm(false);

    expect(actions.submitTransfer).toHaveBeenCalledWith({ enclaveToken: 'passcode:aa' });
    expect(result.currentTransfer.state).toBe(TransferState.Confirm);
  });

  // The recipient and the amount of such a transfer were chosen outside the app
  it('asks for the passcode for a transfer opened from a deeplink, a QR code or the agent', () => {
    const { result, actions } = confirm(true);

    expect(actions.submitTransfer).not.toHaveBeenCalled();
    expect(result.currentTransfer.state).toBe(TransferState.Password);
  });
});
