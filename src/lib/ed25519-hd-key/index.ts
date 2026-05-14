import { hmac } from '@noble/hashes/hmac';
import { sha512 } from '@noble/hashes/sha512';
import * as nacl from 'tweetnacl';

type Hex = string;
type Path = string;

type Keys = {
  key: Uint8Array;
  chainCode: Uint8Array;
};

function u8FromBufferSlice(buf: Buffer, start: number, end: number): Uint8Array {
  return new Uint8Array(buf.subarray(start, end));
}

const ED25519_CURVE = Buffer.from('ed25519 seed', 'utf8');
const HARDENED_OFFSET = 0x80000000;

const pathRegex = /^m(\/[0-9]+')+$/;
function replaceDerive(val: string) {
  return val.replace('\'', '');
}

function hmacSha512(key: Uint8Array, data: Uint8Array): Buffer {
  // Copy into plain Uint8Array so @noble/hashes accepts inputs under Jest/jsdom VM
  // (Node Buffer can fail `instanceof Uint8Array` across realm boundaries).
  return Buffer.from(hmac(sha512, Uint8Array.from(key), Uint8Array.from(data)));
}

export const getMasterKeyFromSeed = (seed: Hex): Keys => {
  const I = hmacSha512(ED25519_CURVE, Buffer.from(seed, 'hex'));
  return {
    key: u8FromBufferSlice(I, 0, 32),
    chainCode: u8FromBufferSlice(I, 32, 64),
  };
};

export const CKDPriv = ({ key, chainCode }: Keys, index: number): Keys => {
  const indexBuffer = new Uint8Array(4);
  new DataView(indexBuffer.buffer).setUint32(0, index, false);

  const data = new Uint8Array(1 + key.length + 4);
  data[0] = 0;
  data.set(key, 1);
  data.set(indexBuffer, 1 + key.length);

  const I = hmacSha512(chainCode, data);
  return {
    key: u8FromBufferSlice(I, 0, 32),
    chainCode: u8FromBufferSlice(I, 32, 64),
  };
};

export const getPublicKey = (privateKey: Buffer | Uint8Array, withZeroByte = true): Buffer => {
  const keyPair = nacl.sign.keyPair.fromSeed(new Uint8Array(privateKey));
  const signPk = keyPair.secretKey.subarray(32);
  const zero = Buffer.alloc(1, 0);
  return withZeroByte
    ? Buffer.concat([zero, Buffer.from(signPk)])
    : Buffer.from(signPk);
};

export const isValidPath = (path: string): boolean => {
  if (!pathRegex.test(path)) {
    return false;
  }
  return !path
    .split('/')
    .slice(1)
    .map(replaceDerive)

    .some(isNaN as any);
};

export const derivePath = (path: Path, seed: Hex, offset = HARDENED_OFFSET): Keys => {
  if (!isValidPath(path)) {
    throw new Error('Invalid derivation path');
  }

  const { key, chainCode } = getMasterKeyFromSeed(seed);
  const segments = path
    .split('/')
    .slice(1)
    .map(replaceDerive)
    .map((el) => parseInt(el, 10));

  return segments.reduce(
    (parentKeys, segment) => CKDPriv(parentKeys, segment + offset),
    { key, chainCode },
  );
};
