import type { Curve } from 'ffjavascript';

import { hexFromByteArray } from '../../../util/casting';

type Writable<T> = { -readonly [P in keyof T]: T[P] };
type WritableArrayLike<T> = Writable<ArrayLike<T>>;

export async function calcProofBuffers(bigInts: any) {
  const { buildBls12381 } = await import('ffjavascript');
  const curve = await buildBls12381();
  const pi_aS = compressG1(curve, bigInts.pi_a);
  const pi_bS = compressG2(curve, bigInts.pi_b);
  const pi_cS = compressG1(curve, bigInts.pi_c);
  const pi_a = Buffer.from(pi_aS, 'hex');
  const pi_b = Buffer.from(pi_bS, 'hex');
  const pi_c = Buffer.from(pi_cS, 'hex');

  return { pi_a, pi_b, pi_c };
}

function compressG1(curve: Curve, p1Raw: bigint[]) {
  const p1 = curve.G1.fromObject(p1Raw);
  const byteArray = new Uint8Array(48);

  curve.G1.toRprCompressed(byteArray, 0, p1);

  return toBlst(byteArray);
}

function compressG2(curve: Curve, p2Raw: bigint[][]) {
  const p2 = curve.G2.fromObject(p2Raw);
  const byteArray = new Uint8Array(96);

  curve.G2.toRprCompressed(byteArray, 0, p2);

  return toBlst(byteArray);
}

function toBlst(byteArray: WritableArrayLike<number>) {
  if (byteArray[0] & 0x80) {
    byteArray[0] |= 32;
  }
  byteArray[0] |= 0x80;

  return hexFromByteArray(byteArray);
}
