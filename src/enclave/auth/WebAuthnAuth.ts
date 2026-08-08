import type { SecretMethod } from './webAuthn';

import * as webAuthn from './webAuthn';

import BaseAuth from './BaseAuth';

interface CredentialParams {
  credentialId: string;
  secretMethod: SecretMethod;
  transports: AuthenticatorTransport[];
}

const STORAGE_KEY = 'WebAuthnAuth:credentialParams';

export default class WebAuthnAuth extends BaseAuth {
  readonly type = 'biometric';

  async setup(_passcode?: string, isLong?: boolean, usageCount?: number) {
    try {
      const { credentialId, secretMethod, transports, secretArrayBuffer: keyMaterial } = await webAuthn.setup();

      const credentialParams = { credentialId, secretMethod, transports };
      await this.#storeCredentialParams(credentialParams);

      return this.setupSession(keyMaterial, isLong, usageCount);
    } catch (err: any) {
      if (err?.message?.includes('privacy-considerations-client')) {
        throw new Error('Biometric setup failed.');
      }
      throw err;
    }
  }

  async authorize(isLong?: boolean, _passcode?: string, usageCount?: number) {
    const credentialParams = await this.#loadCredentialParams();
    if (!credentialParams) {
      throw new Error('WebAuthnAuth: Missing or corrupted credential params');
    }
    const keyMaterial = await webAuthn.authorize(credentialParams);

    return this.setupSession(keyMaterial, isLong, usageCount);
  }

  async destroy() {
    this.clearSession();
    await this.storage.removeItem(STORAGE_KEY);
  }

  #storeCredentialParams(credentialParams: CredentialParams) {
    const credentialParamsJson = JSON.stringify(credentialParams);
    return this.storage.setItem(STORAGE_KEY, credentialParamsJson);
  }

  async #loadCredentialParams(): Promise<CredentialParams | undefined> {
    const credentialParamsJson = await this.storage.getItem(STORAGE_KEY);
    if (!credentialParamsJson) return undefined;

    try {
      return JSON.parse(credentialParamsJson) as CredentialParams;
    } catch {
      return undefined;
    }
  }
}
