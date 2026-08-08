import type { BiometricRequestAccessParams } from '@twa-dev/types';

import { APP_NAME } from '../../config';
import { getTelegramApp } from '../../util/telegram';

function requestBiometricAccess(options: BiometricRequestAccessParams) {
  return new Promise((resolve, reject) => {
    getTelegramApp()!.BiometricManager.requestAccess(options, (accessGranted) => {
      if (accessGranted) {
        resolve(accessGranted);
      } else {
        reject(new Error('Access denied'));
      }
    });
  });
}

export async function setBiometricCredentials(password: string) {
  const biometricManager = getTelegramApp()!.BiometricManager;

  if (!biometricManager.isAccessGranted) {
    const isAccessGranted = await requestBiometricAccess({ reason: APP_NAME });
    if (!isAccessGranted) {
      throw new Error('Access to biometric data has not been granted');
    }
  }

  return new Promise<void>((resolve, reject) => {
    biometricManager.updateBiometricToken(password, (isUpdated) => {
      if (isUpdated) {
        resolve();
      } else {
        reject(new Error('Failed to update or save the biometric token'));
      }
    });
  });
}

export function clearBiometricCredentials() {
  const biometricManager = getTelegramApp()!.BiometricManager;

  return new Promise<void>((resolve, reject) => {
    biometricManager.updateBiometricToken('', (isUpdated) => {
      if (isUpdated) {
        resolve();
      } else {
        reject(new Error('Failed to clear the biometric token'));
      }
    });
  });
}

export async function verifyIdentity() {
  const biometricManager = getTelegramApp()!.BiometricManager;

  if (!biometricManager.isAccessGranted) {
    const isAccessGranted = await requestBiometricAccess({ reason: APP_NAME });
    if (!isAccessGranted) {
      throw new Error('Biometric access was denied. Please grant access to proceed.');
    }
  }

  return new Promise<{ success: boolean; token: string }>((resolve, reject) => {
    biometricManager.authenticate(
      { reason: '' },
      // @ts-ignore Wrong type signature https://github.com/twa-dev/types/pull/12
      (success: boolean, token: string) => {
        if (success) {
          resolve({ success, token });
        } else {
          reject(new Error('Biometric authentication failed. Please try again.'));
        }
      },
    );
  });
}
