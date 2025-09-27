import type { OpenedContract } from '@ton/core';
import { Address } from '@ton/core';

import { NETWORK } from '../config';
import { getTonClient } from '../../api/chains/ton/util/tonCore';

import { PushEscrow } from '../../api/chains/ton/contracts/PushEscrow';
import { PushEscrow as PushEscrowV3 } from '../../api/chains/ton/contracts/PushEscrowV3';
import { PushNftEscrow } from '../../api/chains/ton/contracts/PushNftEscrow';

interface ContractVersion {
  isV1: boolean;
  isV3: boolean;
  isV2: boolean;
  isNft: boolean;
}

export interface CheckData {
  authDate: string;
  chatInstance?: string;
  username?: string;
  receiverAddress: string;
  signature: string;
}

const HEAD_BYTES = 72 / 8;

let openedContract: OpenedContract<PushEscrow | PushEscrowV3 | PushNftEscrow> | undefined;

export function calcAddressHead(address: string) {
  const head = Address.parse(address).hash.subarray(0, HEAD_BYTES);

  // base64url
  return head
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export async function calcAddressSha256HeadBase64(checkId: number, address: string) {
  const checkIdBuffer = Buffer.from(checkId.toString(16).padStart(8, '0'), 'hex');
  const addressBuffer = Address.parse(address).hash;
  const combined = Buffer.concat([checkIdBuffer, addressBuffer]);
  const hash256 = Buffer.from(await window.crypto.subtle.digest('SHA-256', combined));
  const head = hash256.subarray(0, HEAD_BYTES);

  // base64url
  return head
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export function calcAddressHashBase64(address: string) {
  return Address.parse(address).hash.toString('base64');
}

export async function cashCheck(contractAddress: string,
  contractVersions: ContractVersion,
  checkId: number,
  checkData: CheckData,
) {
  const { authDate, chatInstance, username, receiverAddress, signature } = checkData;

  await getOpenedContract(contractAddress, contractVersions).sendCashCheck({
    checkId,
    authDate,
    chatInstance,
    username,
    receiverAddress: Address.parse(receiverAddress),
    signature: Buffer.from(signature, 'base64'),
  });
}

function getOpenedContract(contractAddress: string, contractVersions: ContractVersion) {
  const addressObj = Address.parse(contractAddress);

  if (!openedContract?.address.equals(addressObj)) {
    const contractClass = contractVersions.isV3
      ? PushEscrowV3
      : contractVersions.isNft
        ? PushNftEscrow
        : PushEscrow;
    openedContract = getTonClient(NETWORK).open(new contractClass(addressObj));
  }

  return openedContract;
}
