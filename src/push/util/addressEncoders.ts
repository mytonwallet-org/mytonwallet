import { Address } from '@ton/core';

import { base64UrlFromBigInt, bigIntFromBuffer, bigIntLeFromBigInt } from '../../util/casting';

const HEAD_BYTES = 72 / 8;

// Used in v1
export function calcAddressHead(address: string) {
  const head = Address.parse(address).hash.subarray(0, HEAD_BYTES);

  // base64url
  return head
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

// Used in v2
export async function calcAddressWithCheckIdSha256HeadBase64(checkId: number, address: string) {
  const checkIdBuffer = Buffer.from(checkId.toString(16).padStart(8, '0'), 'hex');
  const addressBuffer = Address.parse(address).hash;
  const combined = Buffer.concat([checkIdBuffer, addressBuffer]);
  const sha256 = Buffer.from(await window.crypto.subtle.digest('SHA-256', combined));
  const head = sha256.subarray(0, HEAD_BYTES);

  // base64url
  return head
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

// User in v3
export function calcAddressHashBase64(address: string) {
  return Address.parse(address).hash.toString('base64');
}

// Used in JWT
export async function calcAddressSha256HeadBigInt(address: string, headBytes = 1n) {
  const body = Address.parse(address).hash;
  const hash = await crypto.subtle.digest('SHA-256', body);
  const hashBigInt = bigIntFromBuffer(Buffer.from(hash));

  return hashBigInt >> (headBytes * 8n);
}

export async function calcAddressSha256HeadBase64(address: string, headBytes = 1n) {
  const headBigInt = await calcAddressSha256HeadBigInt(address, headBytes);
  // Circom reads in LE, so we prepare to reverse it
  const headBigIntLe = bigIntLeFromBigInt(headBigInt);

  return base64UrlFromBigInt(headBigIntLe);
}
