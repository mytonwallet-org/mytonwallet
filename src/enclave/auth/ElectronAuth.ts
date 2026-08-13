import { base64FromBuffer, bufferFromBase64 } from '../../util/casting';
import { logDebugError } from '../../util/logs';
import { randomBytes } from '../../util/random';

import BaseAuth from './BaseAuth';

const KEY_MATERIAL_BYTES = 32;
const STORAGE_KEY = 'ElectronAuth:encryptedKeyMaterial';

export default class ElectronAuth extends BaseAuth {
  readonly type = 'biometric';

  /**
   * Touch ID hardware is deliberately not required: `authorize` reads the key material back through
   * `decryptPassword`, whose prompt asks for user presence - biometry where it exists, the macOS
   * account password elsewhere. What setup has to prove is that the prompt can be answered at all,
   * and the only oracle for that is the prompt itself: a Mac with no login password fails presence
   * evaluation even though `safeStorage` happily encrypts, which would strand the account behind an
   * `authorize` that can never succeed. So where Touch ID cannot vouch for the prompt, setup decrypts
   * the freshly encrypted key material once, before anything is stored - turning a permanent
   * stranding into an immediate, retryable refusal. Where Touch ID answers the prompt no probe runs:
   * the OS requires a login password before enrolling biometry, so the fallback is guaranteed.
   */
  async setup(_passcode?: string, isLong?: boolean, usageCount?: number) {
    const { electron } = window;
    if (
      !electron?.encryptPassword || !electron.decryptPassword
      || await electron.getIsEncryptionSupported?.() === false
    ) {
      throw new Error('ElectronAuth: encryption is not supported');
    }

    const keyMaterial = Buffer.from(randomBytes(KEY_MATERIAL_BYTES));
    const keyMaterialBase64 = base64FromBuffer(keyMaterial);
    const encryptedKeyMaterial = await electron.encryptPassword(keyMaterialBase64); // TODO → `encrypt`

    if (!await electron.getIsTouchIdSupported?.()) {
      const probed = await electron.decryptPassword(encryptedKeyMaterial);
      if (probed !== keyMaterialBase64) {
        logDebugError('ElectronAuth', 'User presence is not available');
        // The i18n key, since the settings path shows this message as is
        throw new Error('Biometric setup failed.');
      }
    }

    await this.#storeEncryptedKeyMaterial(encryptedKeyMaterial);

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async authorize(isLong?: boolean, _passcode?: string, usageCount?: number) {
    const { electron } = window;
    if (!electron?.decryptPassword) {
      throw new Error('ElectronAuth: encryption is not supported');
    }

    const encryptedKeyMaterial = await this.#loadEncryptedKeyMaterial();
    if (!encryptedKeyMaterial) {
      throw new Error('ElectronAuth: no key material is stored');
    }

    // The prompt reports refusal and plain cancellation alike as an absent value rather than a throw
    const keyMaterialBase64 = await electron.decryptPassword(encryptedKeyMaterial);
    if (!keyMaterialBase64) {
      throw new Error('ElectronAuth: user presence was not confirmed');
    }

    const keyMaterial = bufferFromBase64(keyMaterialBase64);

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async destroy() {
    this.clearSession();
    await this.storage.removeItem(STORAGE_KEY);
  }

  #storeEncryptedKeyMaterial(encryptedKeyMaterial: string) {
    return this.storage.setItem(STORAGE_KEY, encryptedKeyMaterial);
  }

  #loadEncryptedKeyMaterial() {
    return this.storage.getItem(STORAGE_KEY);
  }
}
