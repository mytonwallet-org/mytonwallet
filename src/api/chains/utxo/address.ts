import { Address } from '@scure/btc-signer';

import type { ApiNetwork, UTXOChain } from '../../types';

import {
  bitcoinCashAddressToLegacy,
  bitcoinCashAddressToPayload,
  decodeBitcoinCashLegacyAddress,
  parseBitcoinCashAddress,
} from './cashaddr';
import { getUtxoSignerNetwork } from './network';

function parseBitcoinCashLegacyAddress(network: ApiNetwork, address: string) {
  decodeBitcoinCashLegacyAddress(network, address);

  return address;
}

/** Bitcoin Cash addresses reach the UI as a cashaddr payload, without the `bitcoincash:`/`bchtest:` scheme. */
export function normalizeAddress(chain: UTXOChain, address: string, network?: ApiNetwork) {
  if (chain !== 'bitcoincash') {
    return address;
  }

  try {
    return bitcoinCashAddressToPayload(network ?? 'mainnet', address);
  } catch {
    return address;
  }
}

export function isValidAddress(chain: UTXOChain, network: ApiNetwork, address: string): boolean {
  if (chain === 'bitcoincash') {
    try {
      parseBitcoinCashAddress(network, address);
      return true;
    } catch {
      try {
        parseBitcoinCashLegacyAddress(network, address);
        return true;
      } catch {
        return false;
      }
    }
  }

  try {
    Address(getUtxoSignerNetwork(chain, network)).decode(address);
    return true;
  } catch {
    return false;
  }
}

/** @scure/btc-signer accepts legacy base58 addresses only. */
export function toUtxoSignerAddress(chain: UTXOChain, network: ApiNetwork, address: string) {
  if (chain !== 'bitcoincash') {
    return address;
  }

  try {
    return bitcoinCashAddressToLegacy(network, address);
  } catch {
    return parseBitcoinCashLegacyAddress(network, address);
  }
}

/** Some indexers expect legacy base58 for BCH lookups. */
export function toUtxoApiAddress(chain: UTXOChain, network: ApiNetwork, address: string) {
  return toUtxoSignerAddress(chain, network, address);
}

export function isSameUtxoAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  left: string,
  right: string,
) {
  try {
    return toUtxoApiAddress(chain, network, left) === toUtxoApiAddress(chain, network, right);
  } catch {
    return false;
  }
}
