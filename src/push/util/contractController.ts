import type { OpenedContract } from '@ton/core';
import { Address } from '@ton/core';

import type { CheckInfo } from '../../api/chains/ton/contracts/PushEscrowJwt';
import type { ApiJwtCheck } from '../types';
import type { JwkRs256 } from './jwt/jwt';

import { NETWORK } from '../config';
import { bufferFromBase64Url } from '../../util/casting';
import { mapValues, pickTruthy } from '../../util/iteratees';
import { pause } from '../../util/schedulers';
import { getTonClient } from '../../api/chains/ton/util/tonCore';
import { collectWellKnownPubkeyHashes } from './jwt/wellKnownJwks';

import { PushEscrow } from '../../api/chains/ton/contracts/PushEscrow';
import { PushEscrowJwt } from '../../api/chains/ton/contracts/PushEscrowJwt';
import { PushEscrow as PushEscrowV3 } from '../../api/chains/ton/contracts/PushEscrowV3';
import { PushNftEscrow } from '../../api/chains/ton/contracts/PushNftEscrow';

export interface ContractVersion {
  isV1?: boolean;
  isV2?: boolean;
  isV3?: boolean;
  isNft?: boolean;
  isJwt?: boolean;
}

interface BaseCashCheckData {
  receiverAddress: string;
}

interface StandardCashCheckData extends BaseCashCheckData {
  authDate: string;
  chatInstance?: string;
  username?: string;
  signature: string;
}

interface JwtCashCheckData extends BaseCashCheckData {
  pubkeyIndex: number;
  publicSignals: {
    expiresAt: bigint;
    targetHash2: bigint;
    pubkeyHash: bigint;
    receiverAddressHashHead: bigint;
  };
  proof: {
    pi_a: Buffer;
    pi_b: Buffer;
    pi_c: Buffer;
  };
}

let openContract: OpenedContract<PushEscrow | PushEscrowV3 | PushNftEscrow | PushEscrowJwt> | undefined;

export async function cashCheck<T extends ContractVersion>(
  contractAddress: string,
  contractVersions: T,
  checkId: number,
  checkData: StandardCashCheckData | JwtCashCheckData,
): Promise<void> {
  const receiverAddress = Address.parse(checkData.receiverAddress);

  ensureOpenContract(contractAddress, contractVersions);

  if (contractVersions.isJwt) {
    const openContractTyped = openContract as OpenedContract<PushEscrowJwt>;
    const checkDataTyped = checkData as JwtCashCheckData;

    await openContractTyped.sendCashCheck({
      checkId,
      receiverAddress,
      pubkeyIndex: checkDataTyped.pubkeyIndex,
      publicSignals: checkDataTyped.publicSignals,
      proof: checkDataTyped.proof,
    });
  } else {
    const openContractTyped = openContract as OpenedContract<PushEscrow | PushEscrowV3 | PushNftEscrow>;
    const dataTyped = checkData as StandardCashCheckData;

    await openContractTyped.sendCashCheck({
      checkId,
      authDate: dataTyped.authDate,
      chatInstance: dataTyped.chatInstance,
      username: dataTyped.username,
      receiverAddress,
      signature: Buffer.from(dataTyped.signature, 'base64'),
    });
  }
}

export async function fetchPubkeyIndicesByHashes(check: ApiJwtCheck) {
  ensureOpenContract(check.contractAddress, { isJwt: true });

  const { dict } = await (openContract as OpenedContract<PushEscrowJwt>).getPubkeys();

  return mapValues(
    swapKeysAndValues(
      mapValues(dict, (p) => p.hash),
    ),
    Number,
  );
}

export function fetchCheckInfo(check: ApiJwtCheck) {
  ensureOpenContract(check.contractAddress, { isJwt: true });

  return (openContract as OpenedContract<PushEscrowJwt>).getCheckInfo(check.id);
}

export async function collectAvailablePubkeyIndices(check: ApiJwtCheck) {
  ensureOpenContract(check.contractAddress, { isJwt: true });

  const [
    wellKnownPubkeyHashes,
    contractPubkeyIndicesByHashes,
  ] = await Promise.all([
    collectWellKnownPubkeyHashes(),
    fetchPubkeyIndicesByHashes(check),
  ]);

  const missingHashes = wellKnownPubkeyHashes.filter((hash) => !contractPubkeyIndicesByHashes[hash]);
  if (missingHashes.length) {
    // Unlikely event, wait for 30 seconds and try again
    // eslint-disable-next-line no-console
    console.warn(`The contract is missing some pubkeys: ${missingHashes.join(', ')}. Retrying...`);

    await pause(1000 * 30);

    return collectAvailablePubkeyIndices(check);
  }

  const filteredIndicesByHashes = pickTruthy(contractPubkeyIndicesByHashes, wellKnownPubkeyHashes);

  return Object.values(filteredIndicesByHashes).map(Number);
}

export async function findCheckPubkeyIndex(
  contractPubkeyIndicesByHashes: Record<string, number>,
  checkInfo: CheckInfo,
  jwk: JwkRs256,
) {
  const { calcPubkeyPoseidonHash } = await import('../util/jwt/poseidon');
  const jwkPubkeyHash = String(calcPubkeyPoseidonHash(bufferFromBase64Url(jwk.n)));
  const globalIndex = contractPubkeyIndicesByHashes[jwkPubkeyHash];

  return checkInfo.pubkeyIndices.indexOf(globalIndex);
}

function ensureOpenContract(
  contractAddress: string,
  contractVersions: ContractVersion,
) {
  const addressObj = Address.parse(contractAddress);

  if (openContract?.address.equals(addressObj)) return;

  let contractClass: typeof PushEscrowV3 | typeof PushNftEscrow | typeof PushEscrowJwt | typeof PushEscrow;

  if (contractVersions.isV3) {
    contractClass = PushEscrowV3;
  } else if (contractVersions.isNft) {
    contractClass = PushNftEscrow;
  } else if (contractVersions.isJwt) {
    contractClass = PushEscrowJwt;
  } else {
    contractClass = PushEscrow;
  }

  openContract = getTonClient(NETWORK).open(new contractClass(addressObj));
}

function swapKeysAndValues(obj: Record<string, any>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(obj).map(([key, value]) => [value, key]),
  );
}
