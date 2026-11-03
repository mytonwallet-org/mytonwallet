import type { StateInit } from '@ton/core';
import { Address, beginCell, BitString, Cell, storeStateInit } from '@ton/core';

import type { ApiParsedStateInit } from '../../../types';
import type { ContractName } from '../types';

import { ContractType } from '../constants';
import { findKnownContract } from './knownContracts';
import { parseStateInitCell } from './tonCore';

const HASH_BITS = 256;
// `max_acc_fixed_prefix_length` of ConfigParam 43
const MAX_FIXED_PREFIX_LENGTH = 8;
// Registry keys that differ from the names the wallets are known by
const WALLET_NAMES: Partial<Record<ContractName, string>> = {
  simpleR1: 'v1R1',
  simpleR2: 'v1R2',
  simpleR3: 'v1R3',
  telegram: 'Telegram',
  highloadV2: 'Highload v2',
  multisig: 'Multisig',
  multisigV2: 'Multisig',
  multisigNew: 'Multisig',
  vesting: 'Vesting',
};

/** Describes a StateInit attached to a message, in the form the message is signed with */
export function parseStateInit(stateInitBase64: string, toAddress: string): ApiParsedStateInit | undefined {
  let stateInit: StateInit;
  let recipient: Address;

  try {
    stateInit = parseStateInitCell(Cell.fromBase64(stateInitBase64))!;
    recipient = Address.parse(toAddress);
  } catch {
    return undefined;
  }

  const contract = stateInit.code ? findKnownContract(stateInit.code.hash().toString('hex')) : undefined;

  return {
    ...(contract?.type === ContractType.Wallet && { walletName: WALLET_NAMES[contract.name] ?? contract.name }),
    isDeployable: isDeployableAt(stateInit, recipient),
  };
}

// Repeats the checks the network makes before deploying a StateInit from a message to an empty account
function isDeployableAt(stateInit: StateInit, address: Address) {
  const prefixBits = stateInit.splitDepth ?? 0;
  if (prefixBits > MAX_FIXED_PREFIX_LENGTH || stateInit.libraries) {
    return false;
  }

  const hash = beginCell().store(storeStateInit(stateInit)).endCell().hash();
  // The network does not compare the first `splitDepth` bits: they place the contract in a chosen shard
  const suffix = (bytes: Buffer) => new BitString(bytes, 0, HASH_BITS).substring(prefixBits, HASH_BITS - prefixBits);

  return suffix(hash).equals(suffix(address.hash));
}
