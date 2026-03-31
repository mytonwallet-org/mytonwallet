import { poseidon2, poseidon9 } from 'poseidon-bls12381';

import { bigIntFromHex } from '../../../../util/casting';
import { bytesToFields, padString } from '../fields';

const TARGET_MAX_BYTES = 256;

export function calcTargetHash2(target: string, saltHex: string) {
  const targetPadded = padString(target, TARGET_MAX_BYTES);
  const targetFields = bytesToFields(targetPadded);
  const targetHash = poseidon9(targetFields);
  const saltBigInt = bigIntFromHex(saltHex);

  return poseidon2([targetHash, saltBigInt]);
}
