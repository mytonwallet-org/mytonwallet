import { sha256 } from '@noble/hashes/sha256';
import { createBase58check } from '@scure/base';
import { NETWORK, TEST_NETWORK } from '@scure/btc-signer';

import type { ApiNetwork } from '../../types';

const base58check = createBase58check(sha256);

const ZCASH_P2PKH_PREFIX: Record<ApiNetwork, readonly [number, number]> = {
  mainnet: [0x1c, 0xb8],
  testnet: [0x1d, 0x25],
};

const ZCASH_P2SH_PREFIX: Record<ApiNetwork, readonly [number, number]> = {
  mainnet: [0x1c, 0xbd],
  testnet: [0x1c, 0xba],
};

function readPrefix(data: Uint8Array, network: ApiNetwork): 'p2pkh' | 'p2sh' | undefined {
  const p2pkh = ZCASH_P2PKH_PREFIX[network];
  const p2sh = ZCASH_P2SH_PREFIX[network];

  if (data.length === 22 && data[0] === p2pkh[0] && data[1] === p2pkh[1]) {
    return 'p2pkh';
  }

  if (data.length === 22 && data[0] === p2sh[0] && data[1] === p2sh[1]) {
    return 'p2sh';
  }

  return undefined;
}

export function encodeZcashTransparentAddress(
  network: ApiNetwork,
  type: 'p2pkh' | 'p2sh',
  hash: Uint8Array,
): string {
  const prefix = type === 'p2pkh' ? ZCASH_P2PKH_PREFIX[network] : ZCASH_P2SH_PREFIX[network];
  const payload = new Uint8Array(2 + hash.length);
  payload[0] = prefix[0];
  payload[1] = prefix[1];
  payload.set(hash, 2);

  return base58check.encode(payload);
}

export function decodeZcashTransparentAddress(network: ApiNetwork, address: string) {
  const data = base58check.decode(address);
  const type = readPrefix(data, network);

  if (!type) {
    throw new Error('Invalid Zcash transparent address prefix');
  }

  return {
    type,
    hash: data.slice(2),
  };
}

export function isZcashTransparentAddress(network: ApiNetwork, address: string): boolean {
  try {
    decodeZcashTransparentAddress(network, address);
    return true;
  } catch {
    return false;
  }
}

function encodeBitcoinBase58Address(
  network: ApiNetwork,
  type: 'p2pkh' | 'p2sh',
  hash: Uint8Array,
): string {
  const bridgeNetwork = network === 'mainnet' ? NETWORK : TEST_NETWORK;
  const version = type === 'p2pkh' ? bridgeNetwork.pubKeyHash : bridgeNetwork.scriptHash;
  const payload = new Uint8Array(1 + hash.length);
  payload[0] = version;
  payload.set(hash, 1);

  return base58check.encode(payload);
}

/**
 * Bitcoin base58 address with the same pubkey/script hash as a Zcash t-address.
 * Used only by @scure/btc-signer UTXO selection (it decodes addresses, not t1/t3).
 */
export function toBridgeP2pkhAddress(network: ApiNetwork, zcashAddress: string): string {
  const { type, hash } = decodeZcashTransparentAddress(network, zcashAddress);

  return encodeBitcoinBase58Address(network, type, hash);
}

export function p2pkhHashFromScript(script: Uint8Array): Uint8Array {
  if (script.length !== 25 || script[0] !== 0x76 || script[1] !== 0xa9 || script[2] !== 0x14) {
    throw new Error('Unexpected P2PKH script');
  }

  return script.slice(3, 23);
}
