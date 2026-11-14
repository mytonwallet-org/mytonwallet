import {
  concat,
  getBytes,
  hexlify,
  Interface,
  Wallet,
} from 'ethers';

import type { EVMChain } from '../../../types';
import type { EvmMetaTransaction } from './types';

import { logDebugError } from '../../../../util/logs';
import { normalizeAddress } from '../address';
import { EVM_CHAIN_IDS } from '../constants';
import { MODULAR_ACCOUNT_GLOBAL_OWNER_NONCE_KEY, PIMLICO_SINGLETON_PAYMASTER_ADDRESS } from './constants';
import {
  hashUserOperationV07,
  isModularAccountCallData,
  type UserOperationV07Data,
} from './userOperation';

type PimlicoGaslessEstimateBinding = {
  userOperation: UserOperationV07Data;
  chainId: string;
  gasTokenAddress: string;
  paymaster: string;
};

/** MAv2 `SparseCalldataSegmentLib.RESERVED_VALIDATION_DATA_INDEX`. */
const MODULAR_ACCOUNT_USER_OP_VALIDATION_SEGMENT_INDEX = 0xff;

/** Max uint256, the approval the diesel backend writes for the paymaster when allowance is missing. */
const ERC20_UNLIMITED_ALLOWANCE = (1n << 256n) - 1n;

/** SingletonPaymasterV7 ERC-20 mode. The low bit of the mode byte is `allowAllBundlers`. */
const PIMLICO_ERC20_PAYMASTER_MODE = 1;

/** `_parseErc20Config` fixed prefix: flags through treasury, before the optional fields and signature. */
const ERC20_PAYMASTER_CONFIG_LENGTH = 117;

const ERC20_PAYMASTER_CONSTANT_FEE_FLAG = 0x01;
const ERC20_PAYMASTER_RECIPIENT_FLAG = 0x02;
const ERC20_PAYMASTER_PRE_FUND_FLAG = 0x04;

const PAYMASTER_ADDRESS_BYTES = 20;
const PAYMASTER_TIMESTAMP_BYTES = 6;
const PAYMASTER_UINT128_BYTES = 16;
const PAYMASTER_UINT256_BYTES = 32;
const NATIVE_WEI_SCALE = 10n ** 18n;

const PAYMASTER_DEBIT_TOLERANCE_BY_CHAIN: Partial<Record<EVMChain, bigint>> = {
  ethereum: 800_000n, // 0.8
  base: 100_000n, // 0.1
  bnb: 5n * 10n ** 17n, // 0.5
  arbitrum: 100_000n, // 0.1
  optimism: 100_000n, // 0.1
};

function getPaymasterDebitTolerance(chainId: bigint) {
  const chain = EVM_CHAIN_IDS[`eip155:${chainId}`]?.chain as EVMChain | undefined;

  return chain ? PAYMASTER_DEBIT_TOLERANCE_BY_CHAIN[chain] : undefined;
}

const PAYMASTER_DATA_TOKEN_OFFSET = 1 + 1 + PAYMASTER_TIMESTAMP_BYTES + PAYMASTER_TIMESTAMP_BYTES;
const PAYMASTER_DATA_POST_OP_GAS_OFFSET = PAYMASTER_DATA_TOKEN_OFFSET + PAYMASTER_ADDRESS_BYTES;
const PAYMASTER_DATA_EXCHANGE_RATE_OFFSET = PAYMASTER_DATA_POST_OP_GAS_OFFSET + PAYMASTER_UINT128_BYTES;
const PAYMASTER_DATA_OPTIONALS_OFFSET = 1 + ERC20_PAYMASTER_CONFIG_LENGTH;

const erc20ApproveInterface = new Interface([
  'function approve(address spender, uint256 amount) returns (bool)',
]);

function createWallet(privateKey: string) {
  return new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);
}

/** ModularAccountV2 picks the validation from bits 64-103 of the nonce; 1 is the account's own key, global. */
function getValidationLocator(nonce: string) {
  return (BigInt(nonce) >> 64n) & 0xFFFFFFFFFFn;
}

function encodeUnlimitedPaymasterApproval(
  gasTokenAddress: string,
  paymasterAddress: string,
): EvmMetaTransaction {
  return {
    to: gasTokenAddress,
    value: 0n,
    data: erc20ApproveInterface.encodeFunctionData('approve', [
      paymasterAddress,
      ERC20_UNLIMITED_ALLOWANCE,
    ]),
  };
}

/** Exact requested calls, or the same list with the diesel unlimited paymaster approval prepended. */
function isBoundPimlicoCallData(
  callData: string,
  calls: EvmMetaTransaction[],
  gasTokenAddress: string,
  paymaster: string,
) {
  if (isModularAccountCallData(callData, calls)) {
    return true;
  }

  return isModularAccountCallData(callData, [
    encodeUnlimitedPaymasterApproval(gasTokenAddress, paymaster),
    ...calls,
  ]);
}

/** Matches Modular Account `ValidationLocatorLib.packNonce` / `packSignature` flags. */
export function decodeModularAccountNonceValidation(nonce: string): {
  entityId: number;
  isGlobal: boolean;
  hasDeferredAction: boolean;
} {
  const packed = BigInt(nonce) >> 64n;

  return {
    entityId: Number(packed >> 8n),
    isGlobal: (packed & 1n) !== 0n,
    hasDeferredAction: (packed & 2n) !== 0n,
  };
}

/** Matches Alchemy aa-sdk `packUOSignature`: reserved validation segment + owner ECDSA. */
export function packModularAccountV2UserOpSignature(validationSignature: string): string {
  return concat([
    Uint8Array.of(MODULAR_ACCOUNT_USER_OP_VALIDATION_SEGMENT_INDEX, 0),
    getBytes(validationSignature),
  ]);
}

/** What the unsigned gasless user operation must execute; every digest the key signs is bound to it. */
export type PimlicoUserOperationBinding = {
  chainId: bigint;
  sender: string;
  calls: EvmMetaTransaction[];
  gasTokenAddress: string;
  /** Quoted token debit. It must not exceed the chain's paymaster debit tolerance, and neither may the paymaster debit. */
  maxTokenCost: bigint;
};

type PimlicoErc20PaymasterConfig = {
  postOpGas: bigint;
  exchangeRate: bigint;
  preFundInToken: bigint;
  constantFee: bigint;
};

/**
 * Whether a `/diesel/evm/estimate` user operation executes the calls the wallet sent
 * and pays gas with the quoted token on this chain.
 */
export function isPimlicoUserOperationBound(
  estimate: PimlicoGaslessEstimateBinding,
  binding: PimlicoUserOperationBinding,
) {
  try {
    const { userOperation, paymaster } = estimate;

    if (BigInt(estimate.chainId) !== binding.chainId) {
      throw new Error('Pimlico estimate targets another chain');
    }

    if (normalizeAddress(estimate.gasTokenAddress) !== normalizeAddress(binding.gasTokenAddress)) {
      throw new Error('Pimlico estimate names another gas token');
    }

    if (normalizeAddress(userOperation.sender) !== normalizeAddress(binding.sender)) {
      throw new Error('Pimlico user operation has another sender');
    }

    if (userOperation.factory || userOperation.factoryData) {
      throw new Error('Pimlico user operation carries an init call');
    }

    if (!isSingletonPaymaster(paymaster) || !isSingletonPaymaster(userOperation.paymaster)) {
      throw new Error('Pimlico user operation names a paymaster other than the singleton');
    }

    if (!isBoundPimlicoCallData(
      userOperation.callData,
      binding.calls,
      binding.gasTokenAddress,
      paymaster,
    )) {
      throw new Error('Pimlico user operation calls differ from the requested calls');
    }

    if (getValidationLocator(userOperation.nonce) !== MODULAR_ACCOUNT_GLOBAL_OWNER_NONCE_KEY) {
      throw new Error('Pimlico user operation selects another validation');
    }

    const debit = getPimlicoPaymasterDebit(userOperation, binding.gasTokenAddress);
    const debitTolerance = getPaymasterDebitTolerance(binding.chainId);

    if (
      debitTolerance === undefined
      || debit > binding.maxTokenCost
      || binding.maxTokenCost > debitTolerance
      || debit > debitTolerance
    ) {
      throw new Error(
        `Paymaster debit exceeds the chain tolerance: ${debitTolerance} > ${binding.maxTokenCost}(${debit})`,
      );
    }

    return true;
  } catch (err) {
    logDebugError('isPimlicoUserOperationBound', err);
    return false;
  }
}

function isSingletonPaymaster(address: string | undefined) {
  return address !== undefined
    && normalizeAddress(address) === normalizeAddress(PIMLICO_SINGLETON_PAYMASTER_ADDRESS);
}

function readPaymasterUint(bytes: Uint8Array, offset: number, length: number) {
  if (offset + length > bytes.length) {
    throw new Error('Pimlico paymasterData is not an ERC-20 sponsorship');
  }

  let value = 0n;

  for (let index = offset; index < offset + length; index++) {
    value = (value << 8n) | BigInt(bytes[index]);
  }

  return value;
}

/** SingletonPaymasterV7 ERC-20 `paymasterData`: mode byte, then the config `_parseErc20Config` reads. */
function parsePimlicoErc20PaymasterData(
  paymasterData: string,
  gasTokenAddress: string,
): PimlicoErc20PaymasterConfig {
  const bytes = getBytes(paymasterData);

  if (bytes.length < PAYMASTER_DATA_OPTIONALS_OFFSET + 64 || (bytes[0] >> 1) !== PIMLICO_ERC20_PAYMASTER_MODE) {
    throw new Error('Pimlico paymasterData is not an ERC-20 sponsorship');
  }

  const token = hexlify(bytes.subarray(
    PAYMASTER_DATA_TOKEN_OFFSET,
    PAYMASTER_DATA_TOKEN_OFFSET + PAYMASTER_ADDRESS_BYTES,
  ));

  if (normalizeAddress(token) !== normalizeAddress(gasTokenAddress)) {
    throw new Error('Pimlico paymasterData charges a token other than the gas token');
  }

  const flags = bytes[1];
  let offset = PAYMASTER_DATA_OPTIONALS_OFFSET;
  const preFundInToken = (flags & ERC20_PAYMASTER_PRE_FUND_FLAG) === 0
    ? 0n
    : readPaymasterUint(bytes, offset, PAYMASTER_UINT128_BYTES);

  if ((flags & ERC20_PAYMASTER_PRE_FUND_FLAG) !== 0) {
    offset += PAYMASTER_UINT128_BYTES;
  }

  const constantFee = (flags & ERC20_PAYMASTER_CONSTANT_FEE_FLAG) === 0
    ? 0n
    : readPaymasterUint(bytes, offset, PAYMASTER_UINT128_BYTES);

  if ((flags & ERC20_PAYMASTER_CONSTANT_FEE_FLAG) !== 0) {
    offset += PAYMASTER_UINT128_BYTES;
  }

  if ((flags & ERC20_PAYMASTER_RECIPIENT_FLAG) !== 0) {
    offset += PAYMASTER_ADDRESS_BYTES;
  }

  const signatureLength = bytes.length - offset;

  if (signatureLength !== 64 && signatureLength !== 65) {
    throw new Error('Pimlico paymasterData is not an ERC-20 sponsorship');
  }

  return {
    postOpGas: readPaymasterUint(bytes, PAYMASTER_DATA_POST_OP_GAS_OFFSET, PAYMASTER_UINT128_BYTES),
    exchangeRate: readPaymasterUint(bytes, PAYMASTER_DATA_EXCHANGE_RATE_OFFSET, PAYMASTER_UINT256_BYTES),
    preFundInToken,
    constantFee,
  };
}

/**
 * `postOp` debits `(gas + postOpGas) * gasPrice * exchangeRate / 1e18 + constantFee`.
 * `preFundInToken` is taken during validation and netted in `postOp`, so the larger of the two is the debit.
 */
function getPimlicoPaymasterDebit(userOperation: UserOperationV07Data, gasTokenAddress: string) {
  if (!userOperation.paymasterData) {
    throw new Error('Pimlico paymasterData is not an ERC-20 sponsorship');
  }

  const config = parsePimlicoErc20PaymasterData(userOperation.paymasterData, gasTokenAddress);

  if (config.exchangeRate === 0n) {
    throw new Error('Pimlico paymasterData is not an ERC-20 sponsorship');
  }

  const gasUnits = BigInt(userOperation.callGasLimit)
    + BigInt(userOperation.verificationGasLimit)
    + BigInt(userOperation.preVerificationGas)
    + BigInt(userOperation.paymasterVerificationGasLimit || 0)
    + BigInt(userOperation.paymasterPostOpGasLimit || 0)
    + config.postOpGas;
  const tokenCost = (gasUnits * BigInt(userOperation.maxFeePerGas) * config.exchangeRate) / NATIVE_WEI_SCALE
    + config.constantFee;

  return tokenCost > config.preFundInToken ? tokenCost : config.preFundInToken;
}

export async function signPimlicoUserOperation(
  userOperation: UserOperationV07Data,
  privateKey: string,
  chainId: bigint,
): Promise<string> {
  const wallet = createWallet(privateKey);
  const digest = hashUserOperationV07(userOperation, chainId);
  const ownerSignature = await wallet.signMessage(getBytes(digest));

  return packModularAccountV2UserOpSignature(ownerSignature);
}
