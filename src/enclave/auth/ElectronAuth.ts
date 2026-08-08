import { base64FromBuffer, bufferFromBase64 } from '../../util/casting';
import { randomBytes } from '../../util/random';

import BaseAuth from './BaseAuth';

const KEY_MATERIAL_BYTES = 32;
const STORAGE_KEY = 'ElectronAuth:encryptedKeyMaterial';

export default class ElectronAuth extends BaseAuth {
  readonly type = 'biometric';

  async setup(_passcode?: string, isLong?: boolean, usageCount?: number) {
    const { electron } = window;
    if (!await getIsEncryptionSupported() || !electron?.encryptPassword) {
      throw new Error('ElectronAuth: encryption is not supported');
    }

    const keyMaterial = Buffer.from(randomBytes(KEY_MATERIAL_BYTES));
    const keyMaterialBase64 = base64FromBuffer(keyMaterial);
    const encryptedKeyMaterial = await electron.encryptPassword(keyMaterialBase64); // TODO → `encrypt`
    await this.#storeEncryptedKeyMaterial(encryptedKeyMaterial);

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async authorize(isLong?: boolean, _passcode?: string, usageCount?: number) {
    const { electron } = window;
    if (!electron?.decryptPassword) {
      throw new Error('ElectronAuth: encryption is not supported');
    }

    const encryptedKeyMaterial = (await this.#loadEncryptedKeyMaterial())!;
    const keyMaterialBase64 = (await electron.decryptPassword(encryptedKeyMaterial))!;
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

/**
 * `authorize` reads the key material back through `decryptPassword`, which always prompts for Touch ID, so setup may
 * only succeed where a Touch ID prompt is possible. Encryption availability alone is a weaker condition: on a Mac
 * without Touch ID it holds, setup passes and every later authorization fails, stranding an account that has no
 * passcode. `getIsTouchIdSupported` covers both conditions and is present in every shell able to load a remote
 * bundle, so it also carries shells that predate `getIsEncryptionSupported`.
 */
function getIsEncryptionSupported() {
  const { electron } = window;

  return electron?.getIsTouchIdSupported?.() ?? electron?.getIsEncryptionSupported?.();
}
