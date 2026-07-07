import { ipcMain, safeStorage, systemPreferences } from 'electron';

import { ElectronAction } from './types';

import { NATIVE_BIOMETRICS_PROMPT_KEY } from '../config';
import { validateIpcSender } from './ipcSecurity';

const MAX_ENCRYPTED_PASSWORD_LENGTH = 8192;
const MAX_BIOMETRIC_PROMPT_LENGTH = 256;
const BASE64_REGEXP = /^[A-Za-z0-9+/]+={0,2}$/;

let biometricPrompt = NATIVE_BIOMETRICS_PROMPT_KEY;

export function setupSecrets() {
  ipcMain.handle(ElectronAction.GET_IS_TOUCH_ID_SUPPORTED, (event) => {
    validateIpcSender(event);

    return safeStorage.isEncryptionAvailable() && systemPreferences.canPromptTouchID();
  });
  ipcMain.handle(ElectronAction.ENCRYPT_PASSWORD, (event, password: unknown) => {
    validateIpcSender(event);

    if (typeof password !== 'string' || !password) {
      throw new Error('Invalid Electron password');
    }

    return safeStorage.encryptString(password).toString('base64');
  });
  ipcMain.handle(ElectronAction.DECRYPT_PASSWORD, async (event, encrypted: unknown) => {
    validateIpcSender(event);

    if (!checkIsEncryptedPasswordValid(encrypted)) {
      return undefined;
    }

    try {
      await systemPreferences.promptTouchID(biometricPrompt);
      return safeStorage.decryptString(Buffer.from(encrypted, 'base64'));
    } catch (err) {
      return undefined;
    }
  });
  ipcMain.handle(ElectronAction.SET_BIOMETRIC_PROMPT, (event, prompt: unknown) => {
    validateIpcSender(event);

    biometricPrompt = checkIsBiometricPromptValid(prompt) ? prompt : NATIVE_BIOMETRICS_PROMPT_KEY;
  });
}

function checkIsEncryptedPasswordValid(encrypted: unknown): encrypted is string {
  if (
    typeof encrypted !== 'string'
    || !encrypted
    || encrypted.length > MAX_ENCRYPTED_PASSWORD_LENGTH
    || encrypted.length % 4 !== 0
  ) {
    return false;
  }

  return BASE64_REGEXP.test(encrypted);
}

function checkIsBiometricPromptValid(prompt: unknown): prompt is string {
  return typeof prompt === 'string' && Boolean(prompt) && prompt.length <= MAX_BIOMETRIC_PROMPT_LENGTH;
}
