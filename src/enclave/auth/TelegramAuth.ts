import { base64FromBuffer, bufferFromBase64 } from '../../util/casting';
import { randomBytes } from '../../util/random';
import { clearBiometricCredentials, setBiometricCredentials, verifyIdentity } from './telegram';

import BaseAuth from './BaseAuth';

const KEY_MATERIAL_BYTES = 32;

export default class TelegramAuth extends BaseAuth {
  readonly type = 'biometric';

  async setup(_passcode?: string, isLong?: boolean, usageCount?: number) {
    const keyMaterial = Buffer.from(randomBytes(KEY_MATERIAL_BYTES));
    const keyMaterialBase64 = base64FromBuffer(keyMaterial);
    await setBiometricCredentials(keyMaterialBase64); // TODO → `storeSecret`

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async authorize(isLong?: boolean, _passcode?: string, usageCount?: number) {
    const { token: keyMaterialBase64 } = await verifyIdentity();
    const keyMaterial = bufferFromBase64(keyMaterialBase64);

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async destroy() {
    this.clearSession();
    await clearBiometricCredentials();
  }
}
