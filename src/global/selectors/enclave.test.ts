import type { GlobalState } from '../types';

import { selectIsEnclaveSessionValid } from './enclave';

function buildGlobal(enclaveSession?: GlobalState['enclaveSession']): GlobalState {
  return { enclaveSession } as GlobalState;
}

describe('selectIsEnclaveSessionValid', () => {
  it('rejects a missing session', () => {
    expect(selectIsEnclaveSessionValid(buildGlobal())).toBe(false);
  });

  it('accepts a time-based session that has not expired', () => {
    expect(selectIsEnclaveSessionValid(buildGlobal({
      token: 'passcode:aa',
      validUntil: Date.now() + 60_000,
    }))).toBe(true);
  });

  it('rejects an expired time-based session', () => {
    expect(selectIsEnclaveSessionValid(buildGlobal({
      token: 'passcode:aa',
      validUntil: Date.now() - 1,
    }))).toBe(false);
  });

  // The predicate answers "may a password prompt be skipped", which only the opt-in auto-confirm window
  // justifies. A usage-counted session (`isLong: false`, no `validUntil`) is live but not reusable: its
  // remaining usages live inside the Enclave and are spent silently, so global state cannot tell whether
  // the token still buys anything. Flows that hold such a token must carry it, not re-derive it here.
  it('rejects a usage-counted session', () => {
    expect(selectIsEnclaveSessionValid(buildGlobal({ token: 'passcode:aa' }))).toBe(false);
  });
});
