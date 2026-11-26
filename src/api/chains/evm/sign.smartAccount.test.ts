import { getIcapAddress, hexlify, toUtf8Bytes, verifyMessage, verifyTypedData, Wallet } from 'ethers';

import type { UnifiedSignDataPayload } from '../../dappProtocols';
import { ApiCommonError } from '../../types';

import { signPimlicoUserOperation } from './smartAccount/pimlicoBatch';
import {
  encodeModularAccountCallData,
  hashUserOperationV07,
  type UserOperationV07Data,
} from './smartAccount/userOperation';
import { fetchPrivateKeyString } from './auth';
import { signPayload } from './sign';

jest.mock('./auth', () => ({
  fetchPrivateKeyString: jest.fn(),
  getSignerFromPrivateKey: jest.fn((_network: string, privateKey: string) => {
    const { Wallet: EthersWallet } = jest.requireActual('ethers');

    return new EthersWallet(privateKey);
  }),
}));

const ACCOUNT_ID = '0-mainnet';
const CHAIN_ID = 8453n; // base
const PRIVATE_KEY = `0x${'01'.repeat(32)}`;
const OWNER_ADDRESS = new Wallet(PRIVATE_KEY).address;
const ATTACKER_ADDRESS = '0x000000000000000000000000000000000000dEaD';

/** An operation the account never asked for: the dApp picks the calls and an unused parallel nonce key. */
const FOREIGN_USER_OPERATION: UserOperationV07Data = {
  sender: OWNER_ADDRESS,
  nonce: `0x${((0xabcdefn << 104n) | (1n << 64n)).toString(16)}`,
  callData: encodeModularAccountCallData([{ to: ATTACKER_ADDRESS, value: 10n ** 18n, data: '0x' }]),
  callGasLimit: '0xbea9',
  verificationGasLimit: '0x15495',
  preVerificationGas: '0x11b4c',
  maxFeePerGas: '0xa52d28',
  maxPriorityFeePerGas: '0x16e360',
};

const USER_OPERATION_HASH = hashUserOperationV07(FOREIGN_USER_OPERATION, CHAIN_ID);

function binary(bytes: string): UnifiedSignDataPayload {
  return { type: 'binary', bytes } as UnifiedSignDataPayload;
}

function typedData(
  verifyingContract: string,
  primaryType: string,
  fields: Array<{ name: string; type: string }>,
  message: Record<string, unknown>,
): UnifiedSignDataPayload {
  return {
    type: 'eip712',
    domain: { chainId: Number(CHAIN_ID), verifyingContract },
    types: { [primaryType]: fields },
    primaryType,
    message,
  } as UnifiedSignDataPayload;
}

beforeEach(() => {
  jest.mocked(fetchPrivateKeyString).mockResolvedValue(PRIVATE_KEY);
});

describe('signPayload against user operation authorization', () => {
  it('never returns the signature that authorizes a user operation of the account', async () => {
    const authorization = await signPimlicoUserOperation(FOREIGN_USER_OPERATION, PRIVATE_KEY, CHAIN_ID);
    const ownerSignature = `0x${authorization.slice('0xff00'.length)}`;

    const result = await signPayload('base', ACCOUNT_ID, binary(USER_OPERATION_HASH), 'token');

    expect('result' in result ? result.result : undefined).not.toBe(ownerSignature);
  });

  it.each([
    ['a user operation hash', USER_OPERATION_HASH],
    ['32 bytes of upper-case hex', `0x${'AB'.repeat(32)}`],
    ['32 ASCII characters passed as text', 'k'.repeat(32)],
    ['16 two-byte characters passed as text', 'я'.repeat(16)],
    ['31 hex digits and one other letter passed as text', `${'a'.repeat(31)}g`],
  ])('refuses %s', async (_title, bytes) => {
    const result = await signPayload('base', ACCOUNT_ID, binary(bytes), 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
  });

  it.each([
    ['a text message', 'Sign in to example.org'],
    ['a hex-encoded text message', hexlify(toUtf8Bytes('Sign in to example.org'))],
    ['31 bytes', `0x${'ab'.repeat(31)}`],
    ['33 bytes', `0x${'ab'.repeat(33)}`],
    ['32 characters that take 64 bytes', 'я'.repeat(32)],
    ['an empty message', '0x'],
    ['32 hex digits passed as text', '0123456789abcdefABCDEF0123456789'],
    ['32 hex digits passed as hex-encoded text', hexlify(toUtf8Bytes('0123456789abcdefABCDEF0123456789'))],
  ])('signs %s', async (_title, bytes) => {
    const result = await signPayload('base', ACCOUNT_ID, binary(bytes), 'token');

    const message = bytes.startsWith('0x') ? Uint8Array.from(Buffer.from(bytes.slice(2), 'hex')) : bytes;
    expect(verifyMessage(message, (result as { result: string }).result)).toBe(OWNER_ADDRESS);
  });
});

describe('signPayload against typed data of the account itself', () => {
  const REPLAY_SAFE_HASH = [{ name: 'hash', type: 'bytes32' }];
  const DEFERRED_ACTION = [
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint48' },
    { name: 'call', type: 'bytes' },
  ];

  // Swapping the case of one letter leaves the same address with a wrong checksum
  const WRONG_CHECKSUM_ADDRESS = OWNER_ADDRESS.replace(
    /[a-f]/i,
    (letter) => (letter === letter.toLowerCase() ? letter.toUpperCase() : letter.toLowerCase()),
  );

  it('uses a wrong checksum that differs from the checksum spelling', () => {
    expect(WRONG_CHECKSUM_ADDRESS).not.toBe(OWNER_ADDRESS);
    expect(WRONG_CHECKSUM_ADDRESS.toLowerCase()).toBe(OWNER_ADDRESS.toLowerCase());
  });

  it('refuses a deferred action', async () => {
    const payload = typedData(OWNER_ADDRESS, 'DeferredAction', DEFERRED_ACTION, { nonce: 1, deadline: 0, call: '0x' });

    expect(await signPayload('base', ACCOUNT_ID, payload, 'token')).toEqual({ error: ApiCommonError.Unexpected });
  });

  it.each([
    ['its checksum spelling', OWNER_ADDRESS],
    ['lower case', OWNER_ADDRESS.toLowerCase()],
    ['a wrong checksum', WRONG_CHECKSUM_ADDRESS],
    ['no 0x prefix', OWNER_ADDRESS.slice(2)],
    ['the ICAP spelling', getIcapAddress(OWNER_ADDRESS)],
  ])('refuses an ERC-1271 wrapper whose verifying contract is the own address in %s', async (_title, address) => {
    const payload = typedData(address, 'ReplaySafeHash', REPLAY_SAFE_HASH, { hash: USER_OPERATION_HASH });

    expect(await signPayload('base', ACCOUNT_ID, payload, 'token')).toEqual({ error: ApiCommonError.Unexpected });
  });

  it('refuses a verifying contract given by name', async () => {
    const payload = typedData('wallet.eth', 'ReplaySafeHash', REPLAY_SAFE_HASH, { hash: USER_OPERATION_HASH });

    expect(await signPayload('base', ACCOUNT_ID, payload, 'token')).toEqual({ error: ApiCommonError.Unexpected });
  });

  it.each([
    ['the own address', `{ "chainId": 8453, "__proto__": { "verifyingContract": "${OWNER_ADDRESS}" } }`],
    ['another chain', `{ "verifyingContract": "${ATTACKER_ADDRESS}", "__proto__": { "chainId": 1 } }`],
  ])('refuses a domain that hides %s in a `__proto__` key', async (_title, domain) => {
    const payload = typedData(ATTACKER_ADDRESS, 'ReplaySafeHash', REPLAY_SAFE_HASH, { hash: USER_OPERATION_HASH });
    (payload as { domain: unknown }).domain = JSON.parse(domain);

    expect(await signPayload('base', ACCOUNT_ID, payload, 'token')).toEqual({ error: ApiCommonError.Unexpected });
  });

  it('signs the same structure for another verifying contract', async () => {
    const message = { hash: USER_OPERATION_HASH };
    const result = await signPayload(
      'base', ACCOUNT_ID, typedData(ATTACKER_ADDRESS, 'ReplaySafeHash', REPLAY_SAFE_HASH, message), 'token',
    );

    const recovered = verifyTypedData(
      { chainId: CHAIN_ID, verifyingContract: ATTACKER_ADDRESS },
      { ReplaySafeHash: REPLAY_SAFE_HASH },
      message,
      (result as { result: string }).result,
    );
    expect(recovered).toBe(OWNER_ADDRESS);
  });
});
