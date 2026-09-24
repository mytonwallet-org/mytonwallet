import type { ContractInfo } from '../types';

import { KnownContracts } from '../constants';

/**
 * Identifies a contract by the hash of its code. `codeHash` is the hash of the code cell, which is what toncenter
 * returns; `codeHashOld` is the sha256 of the BOC bytes, the form the older `KnownContracts` entries were collected in.
 */
export function findKnownContract(codeHash?: string, codeHashOld?: string): ContractInfo | undefined {
  return Object.values(KnownContracts).find((info) => (
    (!!codeHash && info.hash === codeHash) || (!!codeHashOld && info.oldHash === codeHashOld)
  ));
}
