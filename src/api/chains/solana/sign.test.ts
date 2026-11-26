import type { Address, Blockhash, Instruction } from '@solana/kit';
import {
  AccountRole,
  appendTransactionMessageInstructions,
  compileTransaction,
  compressTransactionMessageUsingAddressLookupTables,
  createTransactionMessage,
  getAddressDecoder,
  getAddressEncoder,
  getBase58Decoder,
  getBase58Encoder,
  pipe,
  setTransactionMessageFeePayer,
  setTransactionMessageLifetimeUsingBlockhash,
  TRANSACTION_SIZE_LIMIT,
} from '@solana/kit';
import nacl from 'tweetnacl';

import { ApiCommonError } from '../../types';

import { getTransferSolInstructionDataEncoder } from '../../../lib/solana-program/system';
import { fetchPrivateKeyString } from './auth';
import { SOLANA_PROGRAM_IDS } from './constants';
import solanaSdk from './index';
import { signPayload } from './sign';
import { getSignDataRefusal } from './signData';

jest.mock('./auth', () => ({
  ...jest.requireActual('./auth'),
  fetchPrivateKeyString: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const PRIVATE_KEY = '07'.repeat(32);
const KEY_PAIR = nacl.sign.keyPair.fromSeed(new Uint8Array(32).fill(7));
const USER = getAddressDecoder().decode(KEY_PAIR.publicKey);
const ATTACKER = makeAddress(2);
const LOOKUP_TABLE = makeAddress(3);
const V1_VERSION_MARKER = 0x81;
const UNKNOWN_VERSION_MARKER = 0x82;
const SIGNATURE_SIZE = 64;
const MAX_LEGACY_MESSAGE_SIZE = TRANSACTION_SIZE_LIMIT - 1 - SIGNATURE_SIZE;
const MAX_V1_MESSAGE_SIZE = 4096 - SIGNATURE_SIZE;
const BASE_INSTRUCTION_DATA_SIZE = 1000;
const V1_HEADER = [1, 0, 1];
const V1_CONFIG_MASK = [0, 0, 0, 0];
const V1_LIFETIME_TOKEN = new Uint8Array(32).fill(4);
const OFFCHAIN_TEXT = new TextEncoder().encode('Sign in to example.com to confirm that you own this wallet');
const LIFETIME = { blockhash: makeAddress(4) as string as Blockhash, lastValidBlockHeight: 1n };
const DRAIN: Instruction = {
  programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
  accounts: [
    { address: USER, role: AccountRole.WRITABLE_SIGNER },
    { address: ATTACKER, role: AccountRole.WRITABLE },
  ],
  data: getTransferSolInstructionDataEncoder().encode({ amount: 1_000_000_000n }),
};

function makeAddress(seed: number) {
  return getAddressDecoder().decode(new Uint8Array(32).fill(seed));
}

function buildLegacyMessage() {
  return pipe(
    createTransactionMessage({ version: 'legacy' }),
    (tx) => setTransactionMessageFeePayer(USER, tx),
    (tx) => setTransactionMessageLifetimeUsingBlockhash(LIFETIME, tx),
    (tx) => appendTransactionMessageInstructions([DRAIN], tx),
  );
}

function buildV0Message() {
  return pipe(
    createTransactionMessage({ version: 0 }),
    (tx) => setTransactionMessageFeePayer(USER, tx),
    (tx) => setTransactionMessageLifetimeUsingBlockhash(LIFETIME, tx),
    (tx) => appendTransactionMessageInstructions([DRAIN], tx),
  );
}

const V0_MESSAGE_BYTES = compileTransaction(buildV0Message()).messageBytes;

function buildLegacyMessageBytes(dataSize: number) {
  return new Uint8Array(compileTransaction(pipe(
    buildLegacyMessage(),
    (tx) => appendTransactionMessageInstructions([{ ...DRAIN, data: new Uint8Array(dataSize) }], tx),
  )).messageBytes);
}

function buildLegacyMessageBytesOfSize(size: number) {
  const baseSize = buildLegacyMessageBytes(BASE_INSTRUCTION_DATA_SIZE).length;

  return buildLegacyMessageBytes(BASE_INSTRUCTION_DATA_SIZE + size - baseSize);
}

function buildV1MessageBytes(dataSize: number) {
  const accounts = [USER, ATTACKER, DRAIN.programAddress].map((address) => getAddressEncoder().encode(address));
  const instructionHeader = [accounts.length - 1, 2, dataSize % 256, Math.floor(dataSize / 256)];
  const instructionPayload = [0, 1, ...new Uint8Array(dataSize)];

  return Uint8Array.of(
    V1_VERSION_MARKER, ...V1_HEADER, ...V1_CONFIG_MASK, ...V1_LIFETIME_TOKEN, 1, accounts.length,
    ...accounts.flatMap((account) => [...account]), ...instructionHeader, ...instructionPayload,
  );
}

function buildV1MessageBytesOfSize(size: number) {
  return buildV1MessageBytes(size - buildV1MessageBytes(0).length);
}

function signAsMessage(bytes: Uint8Array) {
  return signPayload(ACCOUNT_ID, { type: 'binary', bytes: getBase58Decoder().decode(bytes) }, 'token');
}

function expectSignatureOver(result: Awaited<ReturnType<typeof signPayload>>, bytes: Uint8Array) {
  if (!('result' in result)) throw new Error(`Expected a signature, got ${result.error}`);

  const signature = new Uint8Array(getBase58Encoder().encode(result.result));
  expect(nacl.sign.detached.verify(bytes, signature, KEY_PAIR.publicKey)).toBe(true);
}

beforeEach(() => {
  jest.mocked(fetchPrivateKeyString).mockResolvedValue(PRIVATE_KEY);
});

describe('signPayload', () => {
  it.each([
    ['a legacy transaction', () => compileTransaction(buildLegacyMessage())],
    ['a v0 transaction', () => compileTransaction(buildV0Message())],
    ['a legacy transaction without instructions', () => compileTransaction(pipe(
      createTransactionMessage({ version: 'legacy' }),
      (tx) => setTransactionMessageFeePayer(USER, tx),
      (tx) => setTransactionMessageLifetimeUsingBlockhash(LIFETIME, tx),
    ))],
    ['a v0 transaction without instructions', () => compileTransaction(pipe(
      createTransactionMessage({ version: 0 }),
      (tx) => setTransactionMessageFeePayer(USER, tx),
      (tx) => setTransactionMessageLifetimeUsingBlockhash(LIFETIME, tx),
    ))],
    ['a v0 transaction with an address lookup table', () => compileTransaction(
      compressTransactionMessageUsingAddressLookupTables(buildV0Message(), { [LOOKUP_TABLE]: [ATTACKER] }),
    )],
    ['a v1 transaction', () => ({ messageBytes: buildV1MessageBytes(DRAIN.data!.length) })],
    ['a v1 transaction with one account and no instructions', () => ({
      messageBytes: Uint8Array.of(
        V1_VERSION_MARKER, 1, 0, 0, 0, 0, 0, 0, ...new Uint8Array(32).fill(4), 0, 1, ...KEY_PAIR.publicKey,
      ),
    })],
    ['the largest legacy transaction', () => ({
      messageBytes: buildLegacyMessageBytesOfSize(MAX_LEGACY_MESSAGE_SIZE),
    })],
    ['the largest v1 transaction', () => ({ messageBytes: buildV1MessageBytesOfSize(MAX_V1_MESSAGE_SIZE) })],
  ])('refuses to sign the message bytes of %s as a message', async (_, build) => {
    const result = await signAsMessage(new Uint8Array(build().messageBytes));

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
  });

  it.each([
    ['a sign-in text', 'example.com wants you to sign in with your Solana account:\n'
    + `${USER}\n\nURI: https://example.com\nVersion: 1\nChain ID: mainnet\nNonce: 8f2c1a9b`],
    ['a short text', 'Sign in'],
    ['a text outside ASCII', 'Войти в example.com 🔑, подтвердите вход подписью этого сообщения'],
    ['a text of several kilobytes', 'By signing you accept the terms of service.\n'.repeat(200)],
    ['a text as long as the account list its first characters describe', 'example.com wants you to sign in'.padEnd(
      4 + 32 * 'm'.charCodeAt(0) + 32,
      '.',
    )],
  ])('signs %s', async (_, text) => {
    const bytes = new TextEncoder().encode(text);

    expectSignatureOver(await signAsMessage(bytes), bytes);
  });

  it.each([
    ['109 bytes', Uint8Array.of(
      0xa1, 0x69, ...new TextEncoder().encode('challenge'), 0x58, 0x60, ...new Uint8Array(96).fill(9),
    )],
    ['65 bytes', new Uint8Array(65).fill(UNKNOWN_VERSION_MARKER)],
  ])('refuses a binary payload of %s that starts with the marker of a version yet to exist', async (_, bytes) => {
    expect(await signAsMessage(bytes)).toEqual({ error: ApiCommonError.Unexpected });
  });

  it('signs an off-chain message envelope', async () => {
    const bytes = new Uint8Array([
      0xff, ...new TextEncoder().encode('solana offchain'), 0, 0, OFFCHAIN_TEXT.length, 0, ...OFFCHAIN_TEXT,
    ]);

    expectSignatureOver(await signAsMessage(bytes), bytes);
  });

  it.each([
    ['32 bytes starting with the v0 marker', new Uint8Array(32).fill(0x80)],
    ['32 bytes starting with the v1 marker', new Uint8Array(32).fill(V1_VERSION_MARKER)],
    ['64 bytes starting with the v1 marker', new Uint8Array(64).fill(V1_VERSION_MARKER)],
    ['64 bytes starting with the marker of a version yet to exist', new Uint8Array(64).fill(UNKNOWN_VERSION_MARKER)],
    ['bytes starting with the v1 marker and shorter than a v1 transaction message', Uint8Array.of(
      V1_VERSION_MARKER, 0x58, 0x40, ...new Uint8Array(70).fill(9),
    )],
    ['a header without signers', Uint8Array.of(0, 0, 0, 0, ...new Uint8Array(32).fill(9), 0)],
    ['a header with a signer and no accounts', Uint8Array.of(1, 0, 0, 0, ...new Uint8Array(32).fill(9), 0)],
    ['a signer, a key and a hash with no instruction count', Uint8Array.of(1, 0, 0, 1, ...new Uint8Array(64).fill(9))],
    ['a signer, a key and a hash ending in zero with no instruction count', Uint8Array.of(
      1, 0, 0, 1, ...new Uint8Array(63).fill(9), 0,
    )],
    ['a v0 message with an instruction count and no lookup table count', Uint8Array.of(
      0x80, 1, 0, 0, 1, ...new Uint8Array(64).fill(9), 0,
    )],
    ['an account count spelled in two bytes and no instruction count', Uint8Array.of(
      1, 0, 0, 0x81, 0, ...new Uint8Array(64).fill(9),
    )],
    ['a legacy transaction message too large for a transaction', buildLegacyMessageBytesOfSize(
      MAX_LEGACY_MESSAGE_SIZE + 1,
    )],
    ['a v1 transaction message too large for a transaction', buildV1MessageBytesOfSize(MAX_V1_MESSAGE_SIZE + 1)],
    ['more signatures than a transaction can carry', Uint8Array.of(
      70, 0, 0, 70, ...new Uint8Array(70 * 32).fill(9), ...new Uint8Array(32).fill(9), 1, 0, 0, 0,
    )],
    ['a header with more signers than accounts', Uint8Array.of(2, 1, 0, 1, ...new Uint8Array(64).fill(9), 0)],
    ['a header with a read-only fee payer', Uint8Array.of(1, 1, 0, 1, ...new Uint8Array(64).fill(9), 0)],
    ['a header with more read-only accounts than accounts', Uint8Array.of(
      1, 0, 1, 1, ...new Uint8Array(64).fill(9), 0,
    )],
    ['a transaction message followed by another byte', Uint8Array.of(...V0_MESSAGE_BYTES, 0)],
    ['a v0 transaction message cut before its lookup tables', new Uint8Array(compileTransaction(pipe(
      buildV0Message(),
      (tx) => appendTransactionMessageInstructions([{ ...DRAIN, data: Uint8Array.of(1) }], tx),
    )).messageBytes.slice(0, -1))],
  ])('signs a binary payload of %s', async (_, bytes) => {
    expectSignatureOver(await signAsMessage(bytes), bytes);
  });
});

describe('getSignDataRefusal', () => {
  it('is offered to the dApp protocol adapters', () => {
    expect(solanaSdk.dapp?.getSignDataRefusal).toBe(getSignDataRefusal);
  });

  it('does not decode a payload longer than any transaction', () => {
    const startedAt = performance.now();

    expect(getSignDataRefusal({ type: 'binary', bytes: '2'.repeat(100_000) })).toBeUndefined();
    expect(performance.now() - startedAt).toBeLessThan(1000);
  });

  it('accepts a payload that is not base58', () => {
    expect(getSignDataRefusal({ type: 'binary', bytes: 'example.com wants you to sign in: 0OIl' })).toBeUndefined();
  });
});
