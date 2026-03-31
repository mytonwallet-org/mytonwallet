import { poseidon9 } from 'poseidon-bls12381';

import { CIRCOM_BIGINT_K, CIRCOM_BIGINT_N } from '../../../lib/zk-email-helpers/constants';
import { bigIntFromBuffer } from '../../../../util/casting';

export function calcPubkeyPoseidonHash(pubkeyBuffer: Buffer) {
  const limbs = splitModulusToBitLimbs(pubkeyBuffer);
  const merged = mergeLimbsPoseidonLargeStyle(limbs, CIRCOM_BIGINT_N);
  if (merged.length !== 9) throw new Error(`Expected merged arity 9 for k=${CIRCOM_BIGINT_K}`);

  return poseidon9(merged);
}

function splitModulusToBitLimbs(buffer: Buffer, k = CIRCOM_BIGINT_K, limbBits = CIRCOM_BIGINT_N) {
  const bigInt = bigIntFromBuffer(buffer);
  const mask = (1n << BigInt(limbBits)) - 1n;
  const limbs = [];

  let x = bigInt;

  for (let i = 0; i < k; i++) {
    limbs.push(x & mask);
    x >>= BigInt(limbBits);
  }

  return limbs; // little-endian limbs
}

function mergeLimbsPoseidonLargeStyle(limbs: bigint[], bitsPerChunk = CIRCOM_BIGINT_N) {
  const k = limbs.length;
  const half = Math.floor(k / 2) + (k % 2 === 1 ? 1 : 0);
  const merged = [];
  const shift = 1n << BigInt(bitsPerChunk);

  for (let i = 0; i < half; i++) {
    const leftIndex = 2 * i;
    const rightIndex = leftIndex + 1;
    if (rightIndex >= k) {
      merged.push(limbs[leftIndex]);
    } else {
      merged.push(limbs[leftIndex] + shift * limbs[rightIndex]);
    }
  }

  return merged;
}
