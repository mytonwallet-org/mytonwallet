import {
  AbiCoder,
  concat,
  Interface,
  keccak256,
  toBeHex,
} from 'ethers';

import type { EvmMetaTransaction } from './types';

import { ENTRY_POINT_V07_ADDRESS } from './constants';

export type UserOperationV07Data = Record<string, string | undefined>;

const abiCoder = AbiCoder.defaultAbiCoder();
const EMPTY_BYTES_HASH = keccak256('0x');

const modularAccountInterface = new Interface([
  'function execute(address target, uint256 value, bytes data)',
  'function executeBatch((address target, uint256 value, bytes data)[] calls)',
]);

function toUint128(value: string | undefined) {
  return toBeHex(BigInt(value || 0), 16);
}

/** The hash EntryPoint v0.7 `getUserOpHash` returns for this user operation, which has no factory and no paymaster. */
export function hashUserOperationV07(userOperation: UserOperationV07Data, chainId: bigint): string {
  const packed = abiCoder.encode(
    ['address', 'uint256', 'bytes32', 'bytes32', 'bytes32', 'uint256', 'bytes32', 'bytes32'],
    [
      userOperation.sender,
      BigInt(userOperation.nonce || 0),
      EMPTY_BYTES_HASH,
      keccak256(userOperation.callData || '0x'),
      concat([toUint128(userOperation.verificationGasLimit), toUint128(userOperation.callGasLimit)]),
      BigInt(userOperation.preVerificationGas || 0),
      concat([toUint128(userOperation.maxPriorityFeePerGas), toUint128(userOperation.maxFeePerGas)]),
      EMPTY_BYTES_HASH,
    ],
  );

  return keccak256(abiCoder.encode(
    ['bytes32', 'address', 'uint256'],
    [keccak256(packed), ENTRY_POINT_V07_ADDRESS, chainId],
  ));
}

/** Whether `callData` is the ModularAccountV2 `execute` or `executeBatch` encoding of exactly these calls. */
export function isModularAccountCallData(callData: string, calls: EvmMetaTransaction[]) {
  const encodings = [modularAccountInterface.encodeFunctionData('executeBatch', [
    calls.map(({ to, value, data }) => [to, value ?? 0n, data || '0x']),
  ])];

  if (calls.length === 1) {
    const [{ to, value, data }] = calls;
    encodings.push(modularAccountInterface.encodeFunctionData('execute', [to, value ?? 0n, data || '0x']));
  }

  return encodings.includes(callData.toLowerCase());
}
