import { Address, beginCell, Cell } from '@ton/core';
import type { SignDataPayload, SignDataPayloadCell } from '@tonconnect/protocol';
import nacl from 'tweetnacl';

import type { TonConnectProof } from './types';

import { crc32 } from '../../../../util/crcHash';
import { encodeDomain } from '../../../chains/ton/util/dns';
import { sha256 } from '../../../common/utils';

export async function signTonProofWithPrivateKey(
  walletAddress: string | Address,
  privateKey: Uint8Array,
  proof: TonConnectProof,
): Promise<Uint8Array> {
  const { timestamp, domain, payload } = proof;
  const address = walletAddress instanceof Address ? walletAddress : Address.parse(walletAddress);

  const messageBuffer = Buffer.concat([
    Buffer.from('ton-proof-item-v2/'),
    makeAddressBuffer(address),
    makeBytesWithLengthBuffer(Buffer.from(domain), false),
    makeTimestampBuffer(timestamp, false),
    Buffer.from(payload),
  ]);

  const bufferToSign = Buffer.concat([
    Buffer.from([0xff, 0xff]),
    Buffer.from('ton-connect'),
    Buffer.from(await sha256(messageBuffer)),
  ]);

  return nacl.sign.detached(
    new Uint8Array(await sha256(bufferToSign)),
    privateKey,
  );
}

/**
 * See https://docs.tonconsole.com/academy/sign-data#how-the-signature-is-built for more details
 */
export async function signDataWithPrivateKey(
  walletAddress: string | Address,
  timestamp: number, // Unix seconds, should be the current time
  domain: string,
  payload: SignDataPayload,
  privateKey: Uint8Array,
): Promise<Uint8Array> {
  const address = walletAddress instanceof Address ? walletAddress : Address.parse(walletAddress);

  const hash = await (payload.type === 'cell'
    ? createCellDataHash(address, timestamp, domain, payload)
    : createTextDataHash(address, timestamp, domain, payload));

  return nacl.sign.detached(hash, privateKey);
}

// https://docs.tonconsole.com/academy/sign-data#for-cell
function createCellDataHash(
  walletAddress: Address,
  timestamp: number,
  domain: string,
  payload: SignDataPayloadCell,
) {
  const message = beginCell()
    .storeUint(0x75569022, 32)
    .storeUint(crc32(payload.schema), 32)
    .storeUint(timestamp, 64)
    .storeAddress(walletAddress)
    .storeStringRefTail(encodeDomain(domain))
    .storeRef(Cell.fromBase64(payload.cell))
    .endCell();

  const hashBuffer = message.hash();
  return new Uint8Array(hashBuffer.buffer, hashBuffer.byteOffset, hashBuffer.byteLength);
}

// https://docs.tonconsole.com/academy/sign-data#for-text-and-binary
async function createTextDataHash(
  walletAddress: Address,
  timestamp: number,
  domain: string,
  payload: Exclude<SignDataPayload, SignDataPayloadCell>,
) {
  const message = Buffer.concat([
    Buffer.from([0xff, 0xff]),
    Buffer.from('ton-connect/sign-data/'),
    makeAddressBuffer(walletAddress),
    makeBytesWithLengthBuffer(Buffer.from(domain), true),
    makeTimestampBuffer(timestamp, true),
    Buffer.from(payload.type === 'text' ? 'txt' : 'bin'),
    makeBytesWithLengthBuffer(
      payload.type === 'text'
        ? Buffer.from(payload.text, 'utf8')
        : Buffer.from(payload.bytes, 'base64'),
      true,
    ),
  ]);

  return new Uint8Array(await sha256(message));
}

function makeAddressBuffer(address: Address) {
  const workChainLength = 4;
  const addressBuffer = Buffer.allocUnsafe(workChainLength + address.hash.length);
  addressBuffer.writeInt32BE(address.workChain);
  address.hash.copy(addressBuffer, workChainLength);
  return addressBuffer;
}

function makeBytesWithLengthBuffer(bytes: Buffer, isBigEndian: boolean) {
  const lengthLength = 4;
  const buffer = Buffer.allocUnsafe(lengthLength + bytes.length);
  if (isBigEndian) {
    buffer.writeInt32BE(bytes.length);
  } else {
    buffer.writeInt32LE(bytes.length);
  }
  bytes.copy(buffer, lengthLength);
  return buffer;
}

function makeTimestampBuffer(unixSeconds: number, isBigEndian: boolean) {
  const timestampBuffer = Buffer.allocUnsafe(8);
  const timestamp = BigInt(unixSeconds);
  if (isBigEndian) {
    timestampBuffer.writeBigInt64BE(timestamp);
  } else {
    timestampBuffer.writeBigInt64LE(timestamp);
  }
  return timestampBuffer;
}
