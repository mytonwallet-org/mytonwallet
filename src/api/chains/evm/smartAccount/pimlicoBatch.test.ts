import { getBytes, hexlify, verifyMessage, Wallet } from 'ethers';

import { PIMLICO_SINGLETON_PAYMASTER_ADDRESS } from './constants';
import {
  decodeModularAccountNonceValidation,
  isPimlicoUserOperationBound,
  packModularAccountV2UserOpSignature,
  signPimlicoUserOperation,
} from './pimlicoBatch';
import {
  encodeModularAccountCallData,
  hashUserOperationV07,
  type UserOperationV07Data,
} from './userOperation';

const CHAIN_ID = 8453n; // base
/** Base paymaster debit tolerance: 0.1 USDC (6 decimals). */
const BASE_DEBIT_TOLERANCE = 100_000n;

const BASE_USER_OPERATION: UserOperationV07Data = {
  sender: '0xFad818EBe50790749d530E9743045a5740796100',
  nonce: '0x10000000000000000',
  callData: '0x34fcd5be'
    + '0000000000000000000000000000000000000000000000000000000000000020'
    + '0000000000000000000000000000000000000000000000000000000000000002'
    + '0000000000000000000000000000000000000000000000000000000000000040'
    + '00000000000000000000000000000000000000000000000000000000000000c0'
    + '000000000000000000000000000000000000000000000000000000000000dead'
    + '0000000000000000000000000000000000000000000000000000000000000000'
    + '0000000000000000000000000000000000000000000000000000000000000060'
    + '0000000000000000000000000000000000000000000000000000000000000000'
    + '000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913'
    + '0000000000000000000000000000000000000000000000000000000000000000'
    + '0000000000000000000000000000000000000000000000000000000000000060'
    + '0000000000000000000000000000000000000000000000000000000000000044'
    + '095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b4'
    + '3ac78ba300000000000000000000000000000000000000000000000000000000'
    + '0000000100000000000000000000000000000000000000000000000000000000',
  callGasLimit: '0xbea9',
  verificationGasLimit: '0x15495',
  preVerificationGas: '0x11b4c',
  maxFeePerGas: '0xa52d28',
  maxPriorityFeePerGas: '0x16e360',
};

const BASE_USER_OPERATION_HASH = '0x343819eece56691f2745c1062f4cf19638b9c0dcc4f1463fc1fc357fe21d7c48';

describe('pimlicoBatch helpers', () => {
  it('keeps the Base user operation hash unchanged without a paymaster', () => {
    expect(hashUserOperationV07(BASE_USER_OPERATION, CHAIN_ID)).toBe(BASE_USER_OPERATION_HASH);
  });

  it('changes the user operation hash when a paymaster is attached', () => {
    const withoutPaymaster = hashUserOperationV07(BASE_USER_OPERATION, CHAIN_ID);
    const withPaymaster = hashUserOperationV07({
      ...BASE_USER_OPERATION,
      paymaster: '0x777777777777AeC03fd955926DbF81597e66834C',
      paymasterVerificationGasLimit: '0x1',
      paymasterPostOpGasLimit: '0x2',
      paymasterData: '0x1234',
    }, CHAIN_ID);

    expect(withPaymaster).not.toBe(withoutPaymaster);
  });

  it('signs the paymaster-aware digest with the owner key', async () => {
    const wallet = Wallet.createRandom();
    const userOperation: UserOperationV07Data = {
      ...BASE_USER_OPERATION,
      sender: wallet.address,
      callData: encodeModularAccountCallData([
        { to: '0x000000000000000000000000000000000000dEaD', value: 0n, data: '0x' },
      ]),
      paymaster: '0x777777777777AeC03fd955926DbF81597e66834C',
      paymasterVerificationGasLimit: '0x1',
      paymasterPostOpGasLimit: '0x2',
      paymasterData: '0x1234',
    };

    const digest = hashUserOperationV07(userOperation, CHAIN_ID);
    const ownerSignature = await wallet.signMessage(getBytes(digest));
    const signature = await signPimlicoUserOperation(userOperation, wallet.privateKey, CHAIN_ID);
    const validation = decodeModularAccountNonceValidation(userOperation.nonce);

    expect(validation).toEqual({ entityId: 0, isGlobal: true, hasDeferredAction: false });
    expect(signature).toBe(packModularAccountV2UserOpSignature(ownerSignature));
    expect(signature.startsWith('0xff00')).toBe(true);
    expect(verifyMessage(getBytes(digest), `0x${signature.slice(6)}`)).toBe(wallet.address);
  });
});

const GAS_TOKEN = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831';
const OTHER_TOKEN = '0x000000000000000000000000000000000000dEaD';
const SENDER = '0xFad818EBe50790749d530E9743045a5740796100';
const CALLS = [{ to: OTHER_TOKEN, value: 0n, data: '0x' as const }];

function writeUint(bytes: Uint8Array, offset: number, length: number, value: bigint) {
  for (let index = length - 1; index >= 0; index--) {
    bytes[offset + index] = Number(value & 0xffn);
    value >>= 8n;
  }
}

function encodeErc20PaymasterData({
  token = GAS_TOKEN,
  exchangeRate = 10n ** 18n,
  postOpGas = 0n,
  constantFee = 0n,
  preFund = 0n,
  mode = 1,
  allowAllBundlers = false,
}: {
  token?: string;
  exchangeRate?: bigint;
  postOpGas?: bigint;
  constantFee?: bigint;
  preFund?: bigint;
  mode?: number;
  allowAllBundlers?: boolean;
} = {}) {
  const flags = (constantFee > 0n ? 0x01 : 0) | (preFund > 0n ? 0x04 : 0);
  const optionalLength = (preFund > 0n ? 16 : 0) + (constantFee > 0n ? 16 : 0);
  const bytes = new Uint8Array(118 + optionalLength + 65);

  bytes[0] = (mode << 1) | (allowAllBundlers ? 1 : 0);
  bytes[1] = flags;
  bytes.set(getBytes(token), 14);
  writeUint(bytes, 34, 16, postOpGas);
  writeUint(bytes, 50, 32, exchangeRate);

  let offset = 118;

  if (preFund > 0n) {
    writeUint(bytes, offset, 16, preFund);
    offset += 16;
  }

  if (constantFee > 0n) {
    writeUint(bytes, offset, 16, constantFee);
  }

  return hexlify(bytes);
}

function bindEstimate(paymasterData: string, maxTokenCost: bigint) {
  return isPimlicoUserOperationBound({
    chainId: CHAIN_ID.toString(),
    gasTokenAddress: GAS_TOKEN,
    paymaster: PIMLICO_SINGLETON_PAYMASTER_ADDRESS,
    userOperation: {
      sender: SENDER,
      nonce: '0x10000000000000000',
      callData: encodeModularAccountCallData(CALLS),
      callGasLimit: '0x1',
      verificationGasLimit: '0x1',
      preVerificationGas: '0x1',
      maxFeePerGas: '0x1',
      maxPriorityFeePerGas: '0x1',
      paymaster: PIMLICO_SINGLETON_PAYMASTER_ADDRESS,
      paymasterVerificationGasLimit: '0x1',
      paymasterPostOpGasLimit: '0x1',
      paymasterData,
    },
  }, {
    chainId: CHAIN_ID,
    sender: SENDER,
    calls: CALLS,
    gasTokenAddress: GAS_TOKEN,
    maxTokenCost,
  });
}

describe('isPimlicoUserOperationBound', () => {
  it('accepts an ERC-20 sponsorship when both the debit and the quote stay within the Base debit tolerance', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ allowAllBundlers: true }), BASE_DEBIT_TOLERANCE)).toBe(true);
  });

  it('rejects a quote above the Base debit tolerance even when the paymaster debit is smaller', () => {
    expect(bindEstimate(encodeErc20PaymasterData(), BASE_DEBIT_TOLERANCE + 1n)).toBe(false);
  });

  it('rejects a sponsorship that charges another token', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ token: OTHER_TOKEN }), 5n)).toBe(false);
  });

  it('rejects a sponsorship whose exchange rate costs more than the Base debit tolerance', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ exchangeRate: 100_002n * 10n ** 18n }), 5n)).toBe(false);
  });

  it('rejects a constant fee above the Base debit tolerance', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ constantFee: BASE_DEBIT_TOLERANCE + 1n }), 5n)).toBe(false);
  });

  it('rejects a pre-fund above the Base debit tolerance', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ preFund: BASE_DEBIT_TOLERANCE + 6n }), 5n)).toBe(false);
  });

  it('rejects verifying mode and a paymaster other than the singleton', () => {
    expect(bindEstimate(encodeErc20PaymasterData({ mode: 0 }), 5n)).toBe(false);

    expect(isPimlicoUserOperationBound({
      chainId: CHAIN_ID.toString(),
      gasTokenAddress: GAS_TOKEN,
      paymaster: OTHER_TOKEN,
      userOperation: {
        sender: SENDER,
        nonce: '0x10000000000000000',
        callData: encodeModularAccountCallData(CALLS),
        callGasLimit: '0x1',
        verificationGasLimit: '0x1',
        preVerificationGas: '0x1',
        maxFeePerGas: '0x1',
        maxPriorityFeePerGas: '0x1',
        paymaster: OTHER_TOKEN,
        paymasterData: encodeErc20PaymasterData(),
      },
    }, {
      chainId: CHAIN_ID,
      sender: SENDER,
      calls: CALLS,
      gasTokenAddress: GAS_TOKEN,
      maxTokenCost: 5n,
    })).toBe(false);
  });
});
