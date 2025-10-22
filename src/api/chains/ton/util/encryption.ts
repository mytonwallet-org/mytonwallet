// This JS library implements TON message comment encryption and decryption for Web
// Reference C++ code - SimpleEncryptionV2 - https://github.com/ton-blockchain/ton/blob/cc0eb453cb3bf69f92693160103d33112856c056/tonlib/tonlib/keys/SimpleEncryption.cpp#L110
// Dependencies:
// - TonWeb 0.0.60
// - aes-js - 3.1.2 - https://github.com/ricmoo/aes-js/releases/tag/v3.1.2 - for aes-cbc without padding
// - noble-ed25519 - 1.7.3 - // https://github.com/paulmillr/noble-ed25519/releases/tag/1.7.3 - for getSharedKey

import type { Address } from '@ton/core';

import aesjs from '../../../../lib/aes-js';
import { getSharedSecret } from '../../../../lib/noble-ed25519';
import { OpCode } from '../constants';
import { toBase64Address } from './tonCore';

async function hmacSha512(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const hmacAlgo = { name: 'HMAC', hash: 'SHA-512' };
  const hmacKey = await crypto.subtle.importKey('raw', key, hmacAlgo, false, ['sign']);
  const signature = await crypto.subtle.sign(hmacAlgo, hmacKey, data);
  const result = new Uint8Array(signature);
  if (result.length !== 512 / 8) throw new Error();
  return result;
}

function getAesCbcState(hash: Uint8Array) {
  if (hash.length < 48) throw new Error();
  const key = hash.slice(0, 32);
  const iv = hash.slice(32, 32 + 16);

  // Note that native crypto.subtle AES-CBC not suitable here because
  // even if the data IS a multiple of 16 bytes, padding will still be added
  // So we use aes-js

  return new aesjs.ModeOfOperation.cbc(key, iv);
}

function getRandomPrefix(dataLength: number, minPadding: number): Uint8Array {
  const prefixLength = ((minPadding + 15 + dataLength) & -16) - dataLength;
  const prefix = crypto.getRandomValues(new Uint8Array(prefixLength));
  prefix[0] = prefixLength;
  if ((prefixLength + dataLength) % 16 !== 0) throw new Error();
  return prefix;
}

function combineSecrets(a: Uint8Array, b: Uint8Array) {
  return hmacSha512(a, b);
}

async function encryptDataWithPrefix(data: Uint8Array, sharedSecret: Uint8Array, salt: Uint8Array) {
  if (data.length % 16 !== 0) throw new Error();
  const dataHash = await combineSecrets(salt, data);
  const msgKey = dataHash.slice(0, 16);

  const res = new Uint8Array(data.length + 16);
  res.set(msgKey, 0);

  const cbcStateSecret = await combineSecrets(sharedSecret, msgKey);
  const encrypted = getAesCbcState(cbcStateSecret).encrypt(data);
  res.set(encrypted, 16);

  return res;
}

async function encryptDataImpl(data: Uint8Array, sharedSecret: Uint8Array, salt: Uint8Array) {
  const prefix = getRandomPrefix(data.length, 16);
  const combined = new Uint8Array(prefix.length + data.length);
  combined.set(prefix, 0);
  combined.set(data, prefix.length);
  return encryptDataWithPrefix(combined, sharedSecret, salt);
}

export async function encryptData(
  data: Uint8Array, myPublicKey: Uint8Array, theirPublicKey: Uint8Array, privateKey: Uint8Array, salt: Uint8Array,
) {
  const sharedSecret = await getSharedSecret(privateKey, theirPublicKey);

  const encrypted = await encryptDataImpl(data, sharedSecret, salt);
  const prefixedEncrypted = new Uint8Array(myPublicKey.length + encrypted.length);
  for (let i = 0; i < myPublicKey.length; i++) {
    prefixedEncrypted[i] = theirPublicKey[i] ^ myPublicKey[i];
  }
  prefixedEncrypted.set(encrypted, myPublicKey.length);
  return prefixedEncrypted;
}

export async function encryptMessageComment(
  comment: string,
  myPublicKey: Uint8Array,
  theirPublicKey: Uint8Array,
  myPrivateKey: Uint8Array,
  senderAddress: Address | string,
) {
  if (!comment || !comment.length) throw new Error('empty comment');

  if (myPrivateKey.length === 64) {
    myPrivateKey = myPrivateKey.slice(0, 32); // convert nacl private key
  }

  const commentBytes = new TextEncoder().encode(comment);

  const salt = new TextEncoder().encode(toBase64Address(senderAddress, true));

  const encryptedBytes = await encryptData(commentBytes, myPublicKey, theirPublicKey, myPrivateKey, salt);

  const payload = new Uint8Array(encryptedBytes.length + 4);

  // https://docs.ton.org/v3/documentation/smart-contracts/message-management/internal-messages#encryption-algorithm
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32BE(OpCode.Encrypted);

  payload.set(buffer, 0);
  payload.set(encryptedBytes, 4);

  return payload;
}

async function doDecrypt(
  cbcStateSecret: Uint8Array, msgKey: Uint8Array, encryptedData: Uint8Array, salt: Uint8Array,
): Promise<Uint8Array> {
  const decryptedData = getAesCbcState(cbcStateSecret).decrypt(encryptedData);
  const dataHash = await combineSecrets(salt, decryptedData);
  const gotMsgKey = dataHash.slice(0, 16);
  if (msgKey.join(',') !== gotMsgKey.join(',')) {
    throw new Error('Failed to decrypt: hash mismatch');
  }
  const prefixLength = decryptedData[0];
  if (prefixLength > decryptedData.length || prefixLength < 16) {
    throw new Error('Failed to decrypt: invalid prefix size');
  }
  return decryptedData.slice(prefixLength);
}

async function decryptDataImpl(
  encryptedData: Uint8Array, sharedSecret: Uint8Array, salt: Uint8Array,
): Promise<Uint8Array> {
  if (encryptedData.length < 16) throw new Error('Failed to decrypt: data is too small');
  if (encryptedData.length % 16 !== 0) throw new Error('Failed to decrypt: data size is not divisible by 16');
  const msgKey = encryptedData.slice(0, 16);
  const data = encryptedData.slice(16);
  const cbcStateSecret = await combineSecrets(sharedSecret, msgKey);
  const res = await doDecrypt(cbcStateSecret, msgKey, data, salt);
  return res;
}

export async function decryptData(data: Uint8Array, publicKey: Uint8Array, privateKey: Uint8Array, salt: Uint8Array) {
  if (data.length < publicKey.length) {
    throw new Error('Failed to decrypt: data is too small');
  }
  const theirPublicKey = new Uint8Array(publicKey.length);
  for (let i = 0; i < publicKey.length; i++) {
    theirPublicKey[i] = data[i] ^ publicKey[i];
  }
  const sharedSecret = await getSharedSecret(privateKey, theirPublicKey);

  const decrypted = await decryptDataImpl(data.slice(publicKey.length), sharedSecret, salt);
  return decrypted;
}

export async function decryptMessageComment(
  encryptedData: Uint8Array, myPublicKey: Uint8Array, myPrivateKey: Uint8Array, senderAddress: Address | string,
) {
  if (myPrivateKey.length === 64) {
    myPrivateKey = myPrivateKey.slice(0, 32); // convert nacl private key
  }

  const salt = new TextEncoder().encode(toBase64Address(senderAddress, true));

  const decryptedBytes = await decryptData(encryptedData, myPublicKey, myPrivateKey, salt);
  return new TextDecoder().decode(decryptedBytes);
}
