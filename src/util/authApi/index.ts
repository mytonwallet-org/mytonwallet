import { NativeBiometric } from '@capgo/capacitor-native-biometric';

import type { AuthConfig, BiometricsSetupResult } from './types';
import type { CredentialCreationResult } from './webAuthn';

import {
  APP_NAME, IS_TELEGRAM_APP, NATIVE_BIOMETRICS_SERVER, NATIVE_BIOMETRICS_USERNAME,
} from '../../config';
import { logDebugError } from '../logs';
import { randomBytes } from '../random';
import {
  setBiometricCredentials as setTelegramBiometricCredentials,
  verifyIdentity as verifyTelegramBiometricsIdentity,
} from './telegram';
import webAuthn from './webAuthn';

const CREDENTIAL_SIZE = 32;

async function setupBiometrics({ credential }: { credential?: CredentialCreationResult }) {
  let result: BiometricsSetupResult | undefined;

  try {
    if (!credential) {
      const password = Buffer.from(randomBytes(CREDENTIAL_SIZE)).toString('hex');
      const encryptedPassword = await window.electron?.encryptPassword(password);
      if (!encryptedPassword) {
        return result;
      }

      result = {
        password,
        config: {
          kind: 'electron-safe-storage',
          encryptedPassword,
        },
      };
    } else {
      result = await webAuthn.verify(credential);
    }
  } catch (err) {
    logDebugError('setupBiometrics', err);
  }

  return result;
}

async function setupNativeBiometrics(password: string): Promise<BiometricsSetupResult> {
  if (IS_TELEGRAM_APP) {
    await setTelegramBiometricCredentials(password);

    return {
      password,
      config: { kind: 'native-biometrics' },
    };
  }

  await NativeBiometric.setCredentials({
    username: NATIVE_BIOMETRICS_USERNAME,
    password,
    server: NATIVE_BIOMETRICS_SERVER,
  });

  return {
    password,
    config: { kind: 'native-biometrics' },
  };
}

function removeNativeBiometrics() {
  if (IS_TELEGRAM_APP) {
    return setTelegramBiometricCredentials('');
  }

  return NativeBiometric.deleteCredentials({
    server: NATIVE_BIOMETRICS_SERVER,
  });
}

async function getPassword(config: AuthConfig) {
  let password: string | undefined;

  try {
    if (config.kind === 'webauthn') {
      password = await webAuthn.getPassword(config);
    } else if (config.kind === 'electron-safe-storage') {
      password = await window.electron?.decryptPassword(config.encryptedPassword);
    } else if (IS_TELEGRAM_APP && config.kind === 'native-biometrics') {
      const { success: isVerified, token } = await verifyTelegramBiometricsIdentity();

      if (!isVerified) return undefined;
      password = token;
    } else if (config.kind === 'native-biometrics') {
      const result = await NativeBiometric.verifyIdentityAndGetCredentials({
        title: APP_NAME,
        subtitle: '',
        isWeakAuthenticatorAllowed: true,
        maxAttempts: 1,
        server: NATIVE_BIOMETRICS_SERVER,
      })
        .then((credentials) => credentials.password)
        .catch((e) => {
          logDebugError('getPassword', e);
          return undefined;
        });

      if (!result) return undefined;

      password = result;
    } else {
      throw new Error('Unexpected auth kind');
    }
  } catch (err) {
    logDebugError('getPassword', err);
  }

  return password;
}

export default {
  setupBiometrics,
  setupNativeBiometrics,
  removeNativeBiometrics,
  getPassword,
  webAuthn,
};
