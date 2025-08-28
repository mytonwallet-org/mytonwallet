import * as bip39 from 'bip39';

import { type ApiAccountWithMnemonic, ApiCommonError } from '../types';

import { logDebugError } from '../../util/logs';
import { updateStoredAccount } from './accounts';

const PBKDF2_IMPORT_KEY_ARGS = [
  { name: 'PBKDF2' },
  false,
  ['deriveBits', 'deriveKey'],
] as const;

const PBKDF2_DERIVE_KEY_ARGS = {
  name: 'PBKDF2',
  iterations: 100000, // Higher is more secure but slower
  hash: 'SHA-256',
};

const PBKDF2_DERIVE_KEY_TYPE = { name: 'AES-GCM', length: 256 };

export function generateBip39Mnemonic() {
  return bip39.generateMnemonic(256).split(' ');
}

export function validateBip39Mnemonic(mnemonic: string[]) {
  return bip39.validateMnemonic(mnemonic.join(' '));
}

export async function tryMigratingMnemonicEncryption(accountId: string, mnemonic: string[], password: string) {
  const sensitiveData = [password, ...mnemonic];

  try {
    const mnemonicEncrypted = await encryptMnemonic(mnemonic, password);
    sensitiveData.push(mnemonicEncrypted);

    // This is a defensive approach against potential corrupted encryption reported by some users
    const decryptedMnemonic = await decryptMnemonic(mnemonicEncrypted, password)
      .catch(() => undefined);

    if (!password || !decryptedMnemonic) {
      return { error: ApiCommonError.DebugError };
    }

    await updateStoredAccount<ApiAccountWithMnemonic>(accountId, { mnemonicEncrypted });
  } catch (err) {
    logDebugError('tryMigratingMnemonicEncryption', removeSensitiveDataFromError(err, sensitiveData));
  }

  return undefined;
}

export async function encryptMnemonic(mnemonic: string[], password: string) {
  const plaintext = mnemonic.join(',');
  const salt = crypto.getRandomValues(new Uint8Array(16)); // generate a 128-bit salt
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    ...PBKDF2_IMPORT_KEY_ARGS,
  );
  const key = await crypto.subtle.deriveKey(
    {
      salt,
      ...PBKDF2_DERIVE_KEY_ARGS,
    },
    keyMaterial,
    PBKDF2_DERIVE_KEY_TYPE,
    false,
    ['encrypt'],
  );
  const iv = crypto.getRandomValues(new Uint8Array(12)); // get 96-bit random iv
  const ptUint8 = new TextEncoder().encode(plaintext); // encode plaintext as UTF-8
  const ctBuffer = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, ptUint8); // encrypt plaintext using key
  const ctArray = Array.from(new Uint8Array(ctBuffer)); // ciphertext as byte array
  const ctBase64 = btoa(String.fromCharCode(...ctArray)); // encode ciphertext as base64
  const ivHex = Array.from(iv).map((b) => (`00${b.toString(16)}`).slice(-2)).join(''); // iv as hex string
  const saltHex = Array.from(salt).map((b) => (`00${b.toString(16)}`).slice(-2)).join(''); // salt as hex string

  return `${saltHex}:${ivHex}:${ctBase64}`;
}

export async function decryptMnemonic(encrypted: string, password: string) {
  if (!encrypted.includes(':')) {
    return decryptMnemonicLegacy(encrypted, password);
  }

  const [saltHex, ivHex, encryptedData] = encrypted.split(':');
  const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const iv = new Uint8Array(ivHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    ...PBKDF2_IMPORT_KEY_ARGS,
  );
  const key = await crypto.subtle.deriveKey(
    { salt, ...PBKDF2_DERIVE_KEY_ARGS },
    keyMaterial,
    PBKDF2_DERIVE_KEY_TYPE,
    false,
    ['decrypt'],
  );
  const ctStr = atob(encryptedData); // decode base64 ciphertext
  const ctUint8 = new Uint8Array(ctStr.match(/[\s\S]/g)!.map((ch) => ch.charCodeAt(0))); // ciphertext as Uint8Array
  const plainBuffer = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ctUint8); // decrypt ciphertext using key
  const plaintext = new TextDecoder().decode(plainBuffer); // decode password from UTF-8

  return plaintext.split(',');
}

async function decryptMnemonicLegacy(encrypted: string, password: string) {
  const pwUtf8 = new TextEncoder().encode(password); // encode password as UTF-8
  const pwHash = await crypto.subtle.digest('SHA-256', pwUtf8); // hash the password
  const iv = encrypted.slice(0, 24).match(/.{2}/g)!.map((byte) => parseInt(byte, 16)); // get iv from ciphertext
  const alg = { name: 'AES-GCM', iv: new Uint8Array(iv) }; // specify algorithm to use
  const key = await crypto.subtle.importKey('raw', pwHash, alg, false, ['decrypt']); // use pw to generate key
  const ctStr = atob(encrypted.slice(24)); // decode base64 ciphertext
  const ctUint8 = new Uint8Array(ctStr.match(/[\s\S]/g)!.map((ch) => ch.charCodeAt(0))); // ciphertext as Uint8Array
  const plainBuffer = await crypto.subtle.decrypt(alg, key, ctUint8); // decrypt ciphertext using key
  const plaintext = new TextDecoder().decode(plainBuffer); // decode password from UTF-8

  return plaintext.split(',');
}

export async function getMnemonic(accountId: string, password: string, account: ApiAccountWithMnemonic) {
  const sensitiveData = [password];

  try {
    const { mnemonicEncrypted } = account;
    sensitiveData.push(mnemonicEncrypted);

    const mnemonic = await decryptMnemonic(mnemonicEncrypted, password);
    sensitiveData.push(...mnemonic);

    if (!mnemonicEncrypted.includes(':')) {
      await tryMigratingMnemonicEncryption(accountId, mnemonic, password);
    }

    return mnemonic;
  } catch (err) {
    logDebugError('getMnemonic', removeSensitiveDataFromError(err, sensitiveData));

    return undefined;
  }
}

function removeSensitiveDataFromError(error: unknown, sensitiveData: string[]) {
  const removeFromString = (text: string) => {
    for (const toRemove of sensitiveData) {
      if (toRemove) {
        text = text.replaceAll(toRemove, '(hidden)');
      }
    }
    return text;
  };

  if (typeof error === 'string') {
    return removeFromString(error);
  }

  if (error instanceof Error) {
    const message = removeFromString(error.message);
    return {
      name: error.name,
      message,
      stack: error.stack?.replaceAll(error.message, message),
    };
  }

  return error;
}
