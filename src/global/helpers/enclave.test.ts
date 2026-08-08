import type { GlobalState } from '../types';

import { dropEnclaveSessionHold, holdEnclaveSession, withEnclaveSessionRelease } from './enclave';

const global = {} as GlobalState;

function createActions() {
  return { releaseEnclaveSession: jest.fn() } as any;
}

describe('withEnclaveSessionRelease', () => {
  it('gives the session back once the flow is done with it', async () => {
    const actions = createActions();

    await withEnclaveSessionRelease(() => Promise.resolve())(global, actions, { enclaveToken: 'passcode:aa' });

    expect(actions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'passcode:aa' });
  });

  // A flow that dies halfway is exactly the one that leaves reads unspent, so the failure path is
  // where the release matters most - and the failure itself still has to reach the caller.
  it('gives the session back when the flow throws, and rethrows', async () => {
    const actions = createActions();
    const failing = withEnclaveSessionRelease(() => Promise.reject(new Error('nope')));

    await expect(failing(global, actions, { enclaveToken: 'passcode:aa' })).rejects.toThrow('nope');
    expect(actions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'passcode:aa' });
  });

  it('has nothing to give back when the flow authorized nothing', async () => {
    const actions = createActions();

    await withEnclaveSessionRelease(() => Promise.resolve())(global, actions, undefined);

    expect(actions.releaseEnclaveSession).not.toHaveBeenCalled();
  });

  // One password entry can serve two flows at once - the multichain upgrade rides along on the
  // operation the user asked for - and the first one to finish must leave the session standing.
  it('waits for the last flow on a shared session', async () => {
    const actions = createActions();
    const payload = { enclaveToken: 'passcode:aa' };
    const alongside = withEnclaveSessionRelease(() => Promise.resolve());

    holdEnclaveSession(payload.enclaveToken);
    await alongside(global, actions, payload);

    expect(actions.releaseEnclaveSession).not.toHaveBeenCalled();

    expect(dropEnclaveSessionHold(payload.enclaveToken)).toBe(true);
  });

  it('counts holds per token, not across them', async () => {
    const actions = createActions();

    holdEnclaveSession('passcode:bb');
    await withEnclaveSessionRelease(() => Promise.resolve())(global, actions, { enclaveToken: 'passcode:aa' });

    expect(actions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'passcode:aa' });

    dropEnclaveSessionHold('passcode:bb');
  });
});
