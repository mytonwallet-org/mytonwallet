import { bufferFromBase64, bufferFromString } from '../../util/casting';

const PBKDF2_ITERATIONS = 100000;

export async function deriveKeyFromRandom(
  keyMaterialAb: ArrayBuffer,
  keyUsages: KeyUsage[] = ['encrypt', 'decrypt'],
) {
  return crypto.subtle.importKey(
    'raw',
    keyMaterialAb,
    { name: 'AES-GCM', length: 256 },
    false,
    keyUsages,
  );
}

export async function deriveKeyFromPasscode(
  passcode: string,
  saltBase64: string,
  keyUsages: KeyUsage[] = ['encrypt', 'decrypt'],
) {
  const imported = await importPasscode(passcode);
  const salt = bufferFromBase64(saltBase64);
  const key = await crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', iterations: PBKDF2_ITERATIONS, salt },
    imported,
    { name: 'AES-GCM', length: 256 },
    false,
    keyUsages,
  );

  return key;
}

export async function deriveBitsFromPasscode(passcode: string, saltBase64: string) {
  const imported = await importPasscode(passcode);
  const salt = bufferFromBase64(saltBase64);

  return crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', iterations: PBKDF2_ITERATIONS, salt },
    imported,
    256,
  );
}

function importPasscode(passcode: string) {
  return crypto.subtle.importKey(
    'raw',
    bufferFromString(passcode),
    { name: 'PBKDF2' },
    false,
    ['deriveKey', 'deriveBits'],
  );
}
