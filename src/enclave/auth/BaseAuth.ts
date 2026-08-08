import type { AuthType, EnclaveSession } from '../../global/types';
import type { SimpleStorage } from '../types';

import { hexFromByteArray } from '../../util/casting';
import { randomBytes } from '../../util/random';
import { EnclaveError } from '../errors';
import { deriveKeyFromPasscode, deriveKeyFromRandom } from './deriveKey';

const LONG_SESSION_DURATION = 5 * 60 * 1000; // 5 min

interface SessionWithKey extends EnclaveSession {
  key: CryptoKey;
  encryptOnlyKey: CryptoKey;
  remainingUsages: number;
}

export type KeyMaterial = ArrayBuffer | [string, string];

export default abstract class BaseAuth {
  readonly abstract type: AuthType;

  #session?: SessionWithKey;
  #sessionTimeout?: number;

  constructor(protected storage: SimpleStorage) {
  }

  abstract setup(passcode?: string, isLong?: boolean, usageCount?: number): Promise<EnclaveSession>;

  abstract authorize(isLong?: boolean, passcode?: string, usageCount?: number): Promise<EnclaveSession>;

  abstract destroy(): Promise<void>;

  getKey(token: string, isEncryptOnly = false): CryptoKey {
    const session = this.#session;
    // A token that lost its session and a token replaced by a newer one lead to the same place: ask
    // for the passcode again. `unknown_token` is left for a token that maps to no configured auth
    if (!session || session.token !== token) {
      throw new EnclaveError('session_expired', 'Enclave: no active session for this token');
    }

    // Encrypt-only keys do not expire
    if (isEncryptOnly) {
      return session.encryptOnlyKey;
    }

    const isExpired = session.validUntil !== undefined
      ? Date.now() >= session.validUntil
      : session.remainingUsages <= 0;

    if (isExpired) {
      this.#clearSession();
      throw new EnclaveError('session_expired', 'Enclave: the session has expired');
    }

    // This session has a usage counter, so spend one use, and clear the session if no reads are left
    if (session.validUntil === undefined) {
      session.remainingUsages -= 1;
      if (session.remainingUsages <= 0) {
        this.#clearSession();
      }
    }

    return session.key;
  }

  clearSession(token?: string) {
    if (token && this.#session?.token !== token) return;
    this.#clearSession();
  }

  /**
   * Hands back the reads an operation asked for and did not take. A flow has to name its budget
   * before it starts, so it names the largest it might need; a usage counter has no expiry of its
   * own, so whatever it overshot by would otherwise stay a live permission to read the private key
   * until the next authorization or the app lock. A session measured in time is left alone - it is
   * granted for a span rather than for a count, and giving it back early is what locking is for.
   */
  releaseSession(token: string) {
    const session = this.#session;
    if (!session || session.token !== token || session.validUntil !== undefined) return;

    this.#clearSession();
  }

  protected async setupSession(keyMaterial: KeyMaterial, isLong?: boolean, usageCount = 1) {
    this.#clearSession();

    const token = `${this.type}:${hexFromByteArray(randomBytes(16))}`;
    const validUntil = isLong ? Date.now() + LONG_SESSION_DURATION : undefined;
    const [key, encryptOnlyKey] = await Promise.all([
      this.#deriveKey(keyMaterial),
      this.#deriveKey(keyMaterial, ['encrypt']),
    ]);

    this.#session = { token, validUntil, key, encryptOnlyKey, remainingUsages: usageCount };

    // Start the lock timer now, so a long session still locks on time even if the key is never used
    if (validUntil !== undefined) {
      this.#sessionTimeout = self.setTimeout(() => this.#clearSession(), validUntil - Date.now());
    }

    return { token, validUntil };
  }

  #deriveKey(keyMaterial: KeyMaterial, keyUsages?: KeyUsage[]) {
    if (Array.isArray(keyMaterial)) {
      const [passcode, salt] = keyMaterial;

      return deriveKeyFromPasscode(passcode, salt, keyUsages);
    } else {
      return deriveKeyFromRandom(keyMaterial, keyUsages);
    }
  }

  #clearSession() {
    this.#session = undefined;

    if (this.#sessionTimeout) {
      self.clearTimeout(this.#sessionTimeout);
      this.#sessionTimeout = undefined;
    }
  }
}
