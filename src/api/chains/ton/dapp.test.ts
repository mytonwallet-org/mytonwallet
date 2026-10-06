import { Address } from '@ton/core';
import nacl from 'tweetnacl';

import type { ApiAccountWithChain } from '../../types';

import { base64ToBytes, bytesToHex, sha256 } from '../../common/utils';
import { signConnectionProof } from './dapp';

const mockFetchStoredChainAccount = jest.fn();
const mockFetchPrivateKey = jest.fn();

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: (...args: unknown[]) => mockFetchStoredChainAccount(...args),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('./auth', () => ({
  fetchPrivateKey: (...args: unknown[]) => mockFetchPrivateKey(...args),
}));

const ADDRESS = 'UQCyqTmXJpshFu1GW1tyTX6paa3c-37OG9s3uv8ZzX_9GDfx';
const ANCHOR_KEY_PAIR = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(1)));
const SIGNING_KEY_PAIR = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(2)));
const PROOF = {
  timestamp: 1703731900,
  domain: 'example.com',
  payload: 'rotated Telegram Wallet proof',
};

function makeAddressBuffer(address: Address) {
  const workChainLength = 4;
  const addressBuffer = Buffer.allocUnsafe(workChainLength + address.hash.length);
  addressBuffer.writeInt32BE(address.workChain);
  address.hash.copy(addressBuffer, workChainLength);
  return addressBuffer;
}

function makeBytesWithLengthBuffer(bytes: Buffer) {
  const lengthLength = 4;
  const buffer = Buffer.allocUnsafe(lengthLength + bytes.length);
  buffer.writeInt32LE(bytes.length);
  bytes.copy(buffer, lengthLength);
  return buffer;
}

function makeTimestampBuffer(unixSeconds: number) {
  const timestampBuffer = Buffer.allocUnsafe(8);
  timestampBuffer.writeBigInt64LE(BigInt(unixSeconds));
  return timestampBuffer;
}

async function makeTonProofHash() {
  const messageBuffer = Buffer.concat([
    Buffer.from('ton-proof-item-v2/'),
    makeAddressBuffer(Address.parse(ADDRESS)),
    makeBytesWithLengthBuffer(Buffer.from(PROOF.domain)),
    makeTimestampBuffer(PROOF.timestamp),
    Buffer.from(PROOF.payload),
  ]);

  const bufferToSign = Buffer.concat([
    Buffer.from([0xff, 0xff]),
    Buffer.from('ton-connect'),
    Buffer.from(await sha256(messageBuffer)),
  ]);

  return new Uint8Array(await sha256(bufferToSign));
}

describe('signConnectionProof', () => {
  const account = {
    type: 'bip39',
    byChain: {
      ton: {
        address: ADDRESS,
        publicKey: bytesToHex(ANCHOR_KEY_PAIR.publicKey),
        version: 'telegram',
        index: 0,
      },
    },
  } satisfies ApiAccountWithChain<'ton'>;

  beforeEach(() => {
    jest.clearAllMocks();
    mockFetchStoredChainAccount.mockResolvedValue(account);
    mockFetchPrivateKey.mockResolvedValue(SIGNING_KEY_PAIR.secretKey);
  });

  it('returns the signing public key for a rotated Telegram Wallet proof', async () => {
    const result = await signConnectionProof('0-mainnet', PROOF, 'enclave-token');

    expect(result).toEqual(expect.objectContaining({
      publicKey: bytesToHex(SIGNING_KEY_PAIR.publicKey),
      signature: expect.any(String),
    }));
    if ('error' in result) return;

    const proofHash = await makeTonProofHash();
    const signature = base64ToBytes(result.signature);
    expect(nacl.sign.detached.verify(proofHash, signature, SIGNING_KEY_PAIR.publicKey)).toBe(true);
    expect(nacl.sign.detached.verify(proofHash, signature, ANCHOR_KEY_PAIR.publicKey)).toBe(false);
  });
});
