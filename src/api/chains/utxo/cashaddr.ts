import { Address, NETWORK, TEST_NETWORK } from '@scure/btc-signer';

import type { ApiNetwork } from '../../types';

type CashAddrType = 'p2pkh' | 'p2sh';

const CASHADDR_TYPE_P2PKH = 0;
const CASHADDR_TYPE_P2SH = 1;
const HASH_BYTES_BY_SIZE_BITS = [20, 24, 28, 32, 40, 48, 56, 64];

const CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const CHARSET_INVERSE_INDEX: Record<string, number> = Object.fromEntries(
  CHARSET.split('').map((char, index) => [char, index]),
);
const GENERATOR = [0x98f2bc8e61n, 0x79b76d99e2n, 0xf33e5fb3c4n, 0xae2eabe2a8n, 0x1e4f43e470n];

function convertBits(data: Uint8Array, fromBits: number, toBits: number, pad = true) {
  const length = pad
    ? Math.ceil(data.length * fromBits / toBits)
    : Math.floor(data.length * fromBits / toBits);
  const mask = (1 << toBits) - 1;
  const result = new Uint8Array(length);
  let index = 0;
  let accumulator = 0;
  let bits = 0;

  for (const value of data) {
    accumulator = (accumulator << fromBits) | value;
    bits += fromBits;

    while (bits >= toBits) {
      bits -= toBits;
      result[index] = (accumulator >> bits) & mask;
      index += 1;
    }
  }

  if (pad && bits > 0) {
    result[index] = (accumulator << (toBits - bits)) & mask;
  }

  return result;
}

function prefixToUint5Array(prefix: string) {
  const result = new Uint8Array(prefix.length + 1);

  for (let i = 0; i < prefix.length; i++) {
    result[i] = prefix.charCodeAt(i) & 31;
  }

  return result;
}

function concat(a: Uint8Array, b: Uint8Array) {
  const result = new Uint8Array(a.length + b.length);
  result.set(a);
  result.set(b, a.length);

  return result;
}

function polymod(data: Uint8Array) {
  let checksum = 1n;

  for (const value of data) {
    const topBits = checksum >> 35n;
    checksum = ((checksum & 0x07ffffffffn) << 5n) ^ BigInt(value);

    for (let j = 0; j < GENERATOR.length; j++) {
      if ((topBits >> BigInt(j)) & 1n) {
        checksum ^= GENERATOR[j];
      }
    }
  }

  return checksum ^ 1n;
}

function checksumToUint5Array(checksum: bigint) {
  const result = new Uint8Array(8);

  for (let i = 0; i < 8; i++) {
    result[7 - i] = Number(checksum & 0x1fn);
    checksum >>= 5n;
  }

  return result;
}

function decodeBase32(string: string) {
  const data = new Uint8Array(string.length);

  for (let i = 0; i < string.length; i++) {
    const value = CHARSET_INVERSE_INDEX[string[i]];
    if (value === undefined) {
      throw new Error(`Invalid cashaddr character: ${string[i]}`);
    }
    data[i] = value;
  }

  return data;
}

function getCashAddrType(version: number): CashAddrType {
  if (version & 0x80) {
    throw new Error('Invalid cashaddr version');
  }

  const typeBits = (version >> 3) & 0xf;
  if (typeBits === CASHADDR_TYPE_P2PKH) {
    return 'p2pkh';
  }
  if (typeBits === CASHADDR_TYPE_P2SH) {
    return 'p2sh';
  }

  throw new Error(`Unsupported cashaddr type: ${typeBits}`);
}

function getVersionByte(type: CashAddrType, hash: Uint8Array) {
  const typeBits = type === 'p2pkh' ? CASHADDR_TYPE_P2PKH << 3 : CASHADDR_TYPE_P2SH << 3;

  switch (hash.length * 8) {
    case 160:
      return typeBits;
    case 192:
      return typeBits + 1;
    case 224:
      return typeBits + 2;
    case 256:
      return typeBits + 3;
    default:
      throw new Error(`Unsupported cashaddr hash size: ${hash.length}`);
  }
}

function isValidChecksum(prefix: string, payload: Uint8Array) {
  const checksumData = concat(prefixToUint5Array(prefix), payload);

  return polymod(checksumData) === 0n;
}

export function decodeCashAddress(address: string) {
  const [prefix, encoded] = address.toLowerCase().split(':');
  if (!prefix || !encoded) {
    throw new Error(`Invalid cashaddr: ${address}`);
  }

  const payload = decodeBase32(encoded);
  if (!isValidChecksum(prefix, payload)) {
    throw new Error(`Invalid cashaddr checksum: ${address}`);
  }

  const payloadData = convertBits(payload.subarray(0, -8), 5, 8, false);
  if (payloadData.length < 2) {
    throw new Error(`Invalid cashaddr: ${address}`);
  }

  const version = payloadData[0];
  const hash = payloadData.subarray(1);
  const type = getCashAddrType(version);
  const expectedHashLength = HASH_BYTES_BY_SIZE_BITS[version & 7];

  if (hash.length !== expectedHashLength) {
    throw new Error(`Invalid cashaddr hash size: ${address}`);
  }

  return { prefix, hash, type };
}

export function encodeCashAddress(
  prefix: string,
  type: CashAddrType,
  hash: Uint8Array,
): string {
  const prefixData = prefixToUint5Array(prefix);
  const payloadData = convertBits(new Uint8Array([getVersionByte(type, hash), ...hash]), 8, 5);
  const checksumData = concat(concat(prefixData, payloadData), new Uint8Array(8));
  const payload = concat(payloadData, checksumToUint5Array(polymod(checksumData)));

  return `${prefix}:${Array.from(payload, (value) => CHARSET[value]).join('')}`;
}

export function encodeCashAddressPayload(
  prefix: string,
  type: CashAddrType,
  hash: Uint8Array,
): string {
  return encodeCashAddress(prefix, type, hash).split(':')[1];
}

export function getCashAddrPrefix(network: ApiNetwork) {
  return network === 'mainnet' ? 'bitcoincash' : 'bchtest';
}

export function parseBitcoinCashAddress(network: ApiNetwork, address: string) {
  const trimmed = address.trim();
  const lower = trimmed.toLowerCase();
  const expectedPrefix = getCashAddrPrefix(network);

  if (lower.includes(':')) {
    const decoded = decodeCashAddress(lower);

    if (decoded.prefix !== expectedPrefix) {
      throw new Error(`Invalid cashaddr network: ${address}`);
    }

    return decoded;
  }

  if (isCashAddrPayload(trimmed)) {
    return decodeCashAddress(`${expectedPrefix}:${lower}`);
  }

  throw new Error(`Invalid cashaddr: ${address}`);
}

export function decodeBitcoinCashLegacyAddress(network: ApiNetwork, address: string) {
  const decoded = Address(network === 'mainnet' ? NETWORK : TEST_NETWORK).decode(address);

  if (decoded.type !== 'pkh' && decoded.type !== 'sh') {
    throw new Error('Bitcoin Cash does not support this address type');
  }

  return {
    hash: decoded.hash,
    type: (decoded.type === 'sh' ? 'p2sh' : 'p2pkh') as CashAddrType,
  };
}

/** The canonical Bitcoin Cash form: a cashaddr payload without the URI scheme. Accepts cashaddr and legacy base58. */
export function bitcoinCashAddressToPayload(network: ApiNetwork, address: string) {
  let parsed;

  try {
    parsed = parseBitcoinCashAddress(network, address);
  } catch {
    parsed = decodeBitcoinCashLegacyAddress(network, address);
  }

  return encodeCashAddressPayload(getCashAddrPrefix(network), parsed.type, parsed.hash);
}

export function bitcoinCashAddressToLegacy(network: ApiNetwork, address: string) {
  const { hash, type } = parseBitcoinCashAddress(network, address);
  const signerNetwork = network === 'mainnet' ? NETWORK : TEST_NETWORK;

  return Address(signerNetwork).encode({
    type: type === 'p2sh' ? 'sh' : 'pkh',
    hash,
  });
}

export function cashAddrPayloadToLegacy(network: ApiNetwork, payload: string) {
  return bitcoinCashAddressToLegacy(network, payload);
}

export function isCashAddrPayload(address: string) {
  return /^[qp][a-z0-9]{41}$/i.test(address);
}
