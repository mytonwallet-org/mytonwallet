import { hexFromArrayBuffer } from '../../util/casting';
import { randomBase64 } from '../../util/random';
import { deriveBitsFromPasscode } from './deriveKey';

import BaseAuth from './BaseAuth';

const SALT_BYTES = 16;
const STORAGE_KEY_SALT = 'PasscodeAuth:salt';
const STORAGE_KEY_VERIFIER_SALT = 'PasscodeAuth:verifierSalt';
const STORAGE_KEY_VERIFIER = 'PasscodeAuth:verifier';

export default class PasscodeAuth extends BaseAuth {
  readonly type = 'passcode';

  async setup(passcode: string) {
    const salt = randomBase64(SALT_BYTES);
    const verifierSalt = randomBase64(SALT_BYTES);
    const verifier = await generateVerifier(passcode, verifierSalt);

    await Promise.all([
      this.storage.setItem(STORAGE_KEY_SALT, salt),
      this.storage.setItem(STORAGE_KEY_VERIFIER_SALT, verifierSalt),
      this.storage.setItem(STORAGE_KEY_VERIFIER, verifier),
    ]);

    return this.setupSession([passcode, salt]);
  }

  async authorize(isLong: boolean, passcode: string, usageCount?: number) {
    const [salt, verifierSalt, storedVerifier] = await Promise.all([
      this.storage.getItem(STORAGE_KEY_SALT),
      this.storage.getItem(STORAGE_KEY_VERIFIER_SALT),
      this.storage.getItem(STORAGE_KEY_VERIFIER),
    ]);
    if (!salt || !verifierSalt || !storedVerifier) throw new Error('PasscodeAuth: Missing salt or verifier');

    const verifier = await generateVerifier(passcode, verifierSalt);
    if (verifier !== storedVerifier) throw new Error('PasscodeAuth: Invalid passcode');

    return this.setupSession([passcode, salt], isLong, usageCount);
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
async function generateVerifier(passcode: string, verifierSalt: string): Promise<string> {
  const verifierAb = await deriveBitsFromPasscode(passcode, verifierSalt);

  return hexFromArrayBuffer(verifierAb);
}
