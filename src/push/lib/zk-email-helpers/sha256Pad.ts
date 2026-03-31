/**
 * Extracted from https://www.npmjs.com/package/@zk-email/helpers
 */

import { assert, int64toBytes, int8toBytes, mergeUInt8Arrays } from './binary-format';

// Puts an end selector, a bunch of 0s, then the length, then fill the rest with 0s.
export function sha256Pad(message: Uint8Array, maxShaBytes: number): [Uint8Array, number] {
  const msgLen = message.length * 8; // bytes to bits
  const msgLenBytes = int64toBytes(msgLen);

  let res = mergeUInt8Arrays(message, int8toBytes(2 ** 7)); // Add the 1 on the end, length 505
  // while ((prehash_prepad_m.length * 8 + length_in_bytes.length * 8) % 512 !== 0) {
  while ((res.length * 8 + msgLenBytes.length * 8) % 512 !== 0) {
    res = mergeUInt8Arrays(res, int8toBytes(0));
  }

  res = mergeUInt8Arrays(res, msgLenBytes);
  assert((res.length * 8) % 512 === 0, 'Padding did not complete properly!');
  const messageLen = res.length;
  while (res.length < maxShaBytes) {
    res = mergeUInt8Arrays(res, int64toBytes(0));
  }

  assert(
    res.length === maxShaBytes,
    // eslint-disable-next-line @stylistic/max-len
    `Padding to max length did not complete properly! Your padded message is ${res.length} long but max is ${maxShaBytes}!`,
  );

  return [res, messageLen];
}
