import {
  base64FromArrayBuffer,
  bufferFromBase64,
  bufferFromHex,
  bufferFromString,
  hexFromByteArray,
  stringFromArrayBuffer,
} from '../util/casting';

export async function encrypt(plaintext: string | ArrayBuffer, key: CryptoKey) {
  const plaintextBuffer = typeof plaintext === 'string' ? bufferFromString(plaintext) : plaintext;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertextAb = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plaintextBuffer);
  const ciphertextBase64 = base64FromArrayBuffer(ciphertextAb);
  const ivHex = hexFromByteArray(iv);
  const encrypted = `${ivHex}:${ciphertextBase64}`;

  return encrypted;
}

export async function decrypt(encrypted: string, key: CryptoKey): Promise<string>;
export async function decrypt(encrypted: string, key: CryptoKey, asArrayBuffer: true): Promise<ArrayBuffer>;
export async function decrypt(encrypted: string, key: CryptoKey, asArrayBuffer = false) {
  const [ivHex, encryptedBase64] = encrypted.split(':');
  const iv = bufferFromHex(ivHex);
  const ciphertextBuffer = bufferFromBase64(encryptedBase64);
  const plaintextAb = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertextBuffer);

  return asArrayBuffer ? plaintextAb : stringFromArrayBuffer(plaintextAb);
}
