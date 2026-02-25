import { getActions } from '../../global';

import { AUTO_CONFIRM_DURATION_MINUTES } from '../../config';
import { MINUTE } from '../dateFormat';
import { setReliableTimeout } from '../setReliableTimeout';
import { createSignal } from '../signals';
interface EncryptedPasswordData {
  ciphertext: ArrayBuffer;
  iv: Uint8Array;
}

const [
  getEncryptedPasswordSignal,
  setEncryptedPasswordSignal,
] = createSignal<EncryptedPasswordData | undefined>(undefined);

let encryptionKey: CryptoKey;

const isMainStore = true;

let clearTimeout: NoneToVoidFunction | undefined;

function resetTimeout() {
  if (!isMainStore) return;

  clearTimeout?.();
  clearTimeout = setReliableTimeout(() => {
    getActions().setInMemoryPassword({ password: undefined });
  }, AUTO_CONFIRM_DURATION_MINUTES * MINUTE);
}

async function initEncryptionKey(): Promise<CryptoKey> {
  if (encryptionKey) return encryptionKey;

  encryptionKey = await window.crypto.subtle.generateKey(
    {
      name: 'AES-GCM',
      length: 256,
    },
    false,
    ['encrypt', 'decrypt'],
  );

  return encryptionKey;
}

void initEncryptionKey();

async function encryptPassword(password: string): Promise<EncryptedPasswordData> {
  const key = await initEncryptionKey();

  const encoder = new TextEncoder();
  const passwordData = encoder.encode(password);

  const iv = window.crypto.getRandomValues(new Uint8Array(12));

  const ciphertext = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
    },
    key,
    passwordData,
  );

  return { ciphertext, iv };
}

async function decryptPassword(encryptedData: EncryptedPasswordData): Promise<string> {
  const key = await initEncryptionKey();

  const decryptedData = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: encryptedData.iv,
    },
    key,
    encryptedData.ciphertext,
  );

  const decoder = new TextDecoder();
  return decoder.decode(decryptedData);
}

export function getHasInMemoryPassword() {
  return getEncryptedPasswordSignal() !== undefined;
}

export async function getInMemoryPassword() {
  const encryptedData = getEncryptedPasswordSignal();
  if (!encryptedData) return undefined;

  try {
    return await decryptPassword(encryptedData);
  } catch (error) {
    return undefined;
  }
}

export function setInMemoryPasswordSignal(password?: string) {
  resetTimeout();

  if (password === undefined) {
    setEncryptedPasswordSignal(undefined);
    return;
  }

  void encryptPassword(password).then((encrypted) => {
    setEncryptedPasswordSignal(encrypted);
  });
}
