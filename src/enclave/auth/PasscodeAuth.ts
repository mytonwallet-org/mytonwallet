import { hexFromArrayBuffer } from '../../util/casting';
import { randomBase64 } from '../../util/random';
import { EnclaveError } from '../errors';
import { deriveBitsFromPasscode, LEGACY_PBKDF2_ITERATIONS, PBKDF2_ITERATIONS } from './deriveKey';

import BaseAuth from './BaseAuth';

const SALT_BYTES = 16;
const STORAGE_KEY_SALT = 'PasscodeAuth:salt';
const STORAGE_KEY_VERIFIER_SALT = 'PasscodeAuth:verifierSalt';
const STORAGE_KEY_VERIFIER = 'PasscodeAuth:verifier';
const VERIFIER_ITERATIONS_SEPARATOR = ':';
const VERIFIER_PATTERN = /^[0-9a-f]{64}$/;
const SUPPORTED_ITERATIONS = [LEGACY_PBKDF2_ITERATIONS, PBKDF2_ITERATIONS];
// A count has to be readable for a whole release before any build writes it: a build rolled back
// past the one that wrote it answers the right passcode with `wrong_passcode`
const SETUP_ITERATIONS = LEGACY_PBKDF2_ITERATIONS;

export default class PasscodeAuth extends BaseAuth {
  readonly type = 'passcode';

  async setup(passcode: string) {
    const salt = randomBase64(SALT_BYTES);
    const verifierSalt = randomBase64(SALT_BYTES);
    const verifier = await generateVerifier(passcode, verifierSalt, SETUP_ITERATIONS);

    await Promise.all([
      this.storage.setItem(STORAGE_KEY_SALT, salt),
      this.storage.setItem(STORAGE_KEY_VERIFIER_SALT, verifierSalt),
      this.storage.setItem(STORAGE_KEY_VERIFIER, formatStoredVerifier(SETUP_ITERATIONS, verifier)),
    ]);

    return this.setupSession([passcode, salt, SETUP_ITERATIONS]);
  }

  async authorize(isLong: boolean, passcode: string, usageCount?: number) {
    const [salt, verifierSalt, storedVerifier] = await Promise.all([
      this.storage.getItem(STORAGE_KEY_SALT),
      this.storage.getItem(STORAGE_KEY_VERIFIER_SALT),
      this.storage.getItem(STORAGE_KEY_VERIFIER),
    ]);
    if (!salt || !verifierSalt || !storedVerifier) {
      throw new EnclaveError('auth_not_configured', 'PasscodeAuth: Missing salt or verifier');
    }

    const expected = parseStoredVerifier(storedVerifier);
    const verifier = await generateVerifier(passcode, verifierSalt, expected.iterations);
    if (verifier !== expected.verifier) throw new EnclaveError('wrong_passcode', 'PasscodeAuth: Invalid passcode');

    return this.setupSession([passcode, salt, expected.iterations], isLong, usageCount);
  }

  async destroy() {
    this.clearSession();
    await Promise.all([
      this.storage.removeItem(STORAGE_KEY_SALT),
      this.storage.removeItem(STORAGE_KEY_VERIFIER_SALT),
      this.storage.removeItem(STORAGE_KEY_VERIFIER),
    ]);
  }
}

// The verifier is derived with PBKDF2, so every offline passcode guess costs a full derivation.
// Its salt must stay distinct from the session-key salt: with the same salt, the stored verifier
// would equal the KEK bits, letting anyone with storage access decrypt the master key directly.
async function generateVerifier(passcode: string, verifierSalt: string, iterations: number): Promise<string> {
  const verifierAb = await deriveBitsFromPasscode(passcode, verifierSalt, iterations);

  return hexFromArrayBuffer(verifierAb);
}

// The count lives in the verifier's own record, so a write cut short cannot pair one setup's count
// with another setup's verifier. A record that names no count was derived with the legacy one.
function formatStoredVerifier(iterations: number, verifier: string) {
  return iterations === LEGACY_PBKDF2_ITERATIONS
    ? verifier
    : `${iterations}${VERIFIER_ITERATIONS_SEPARATOR}${verifier}`;
}

function parseStoredVerifier(storedVerifier: string) {
  const separatorIndex = storedVerifier.indexOf(VERIFIER_ITERATIONS_SEPARATOR);
  if (separatorIndex === -1) {
    return { iterations: LEGACY_PBKDF2_ITERATIONS, verifier: storedVerifier };
  }

  const recorded = storedVerifier.slice(0, separatorIndex);
  const iterations = SUPPORTED_ITERATIONS.find((supported) => String(supported) === recorded);
  if (!iterations) {
    throw new EnclaveError('auth_not_configured', 'PasscodeAuth: Unsupported iteration count');
  }

  const verifier = storedVerifier.slice(separatorIndex + 1);
  if (!VERIFIER_PATTERN.test(verifier)) {
    throw new EnclaveError('auth_not_configured', 'PasscodeAuth: Malformed verifier');
  }

  return { iterations, verifier };
}
