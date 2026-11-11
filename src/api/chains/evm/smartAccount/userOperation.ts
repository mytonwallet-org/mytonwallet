import {
  AbiCoder,
  concat,
  getAddress,
  Interface,
  keccak256,
  toBeHex,
} from 'ethers';

import type { EvmMetaTransaction } from './types';

import { ENTRY_POINT_V07_ADDRESS } from './constants';

export type UserOperationV07Data = {
  sender: string;
  nonce: string;
  callData: string;
  callGasLimit: string;
  verificationGasLimit: string;
  preVerificationGas: string;
  maxFeePerGas: string;
  maxPriorityFeePerGas: string;
  factory?: string;
  factoryData?: string;
  paymaster?: string;
  paymasterVerificationGasLimit?: string;
  paymasterPostOpGasLimit?: string;
  paymasterData?: string;
};

const abiCoder = AbiCoder.defaultAbiCoder();
const EMPTY_BYTES_HASH = keccak256('0x');

const modularAccountInterface = new Interface([
  'function execute(address target, uint256 value, bytes data)',
  'function executeBatch((address target, uint256 value, bytes data)[] calls)',
]);

function toUint128(value: string | undefined) {
  return toBeHex(BigInt(value || 0), 16);
}

export function encodeModularAccountCallData(calls: EvmMetaTransaction[]): string {
  if (calls.length === 1) {
    const [{ to, value, data }] = calls;

    return modularAccountInterface.encodeFunctionData('execute', [to, value ?? 0n, data || '0x']);
  }

  return modularAccountInterface.encodeFunctionData('executeBatch', [
    calls.map(({ to, value, data }) => [to, value ?? 0n, data || '0x']),
  ]);
}

function encodePaymasterAndData(userOperation: UserOperationV07Data): string {
  if (!userOperation.paymaster) {
    return '0x';
  }

  return concat([
    getAddress(userOperation.paymaster),
    toUint128(userOperation.paymasterVerificationGasLimit),
    toUint128(userOperation.paymasterPostOpGasLimit),
    userOperation.paymasterData || '0x',
  ]);
}

function hashPaymasterAndData(userOperation: UserOperationV07Data): string {
  const encoded = encodePaymasterAndData(userOperation);

  if (encoded === '0x') {
    return EMPTY_BYTES_HASH;
  }

  return keccak256(encoded);
}

/** EntryPoint v0.7 `getUserOpHash` for an unsigned user operation (no factory; paymaster optional). */
export function hashUserOperationV07(userOperation: UserOperationV07Data, chainId: bigint): string {
  const packed = abiCoder.encode(
    ['address', 'uint256', 'bytes32', 'bytes32', 'bytes32', 'uint256', 'bytes32', 'bytes32'],
    [
      userOperation.sender,
      BigInt(userOperation.nonce),
      EMPTY_BYTES_HASH,
      keccak256(userOperation.callData),
      concat([toUint128(userOperation.verificationGasLimit), toUint128(userOperation.callGasLimit)]),
      BigInt(userOperation.preVerificationGas),
      concat([toUint128(userOperation.maxPriorityFeePerGas), toUint128(userOperation.maxFeePerGas)]),
      hashPaymasterAndData(userOperation),
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
