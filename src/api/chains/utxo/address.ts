import { Address } from '@scure/btc-signer';

import type { ApiNetwork, UTXOChain } from '../../types';

import {
  bitcoinCashAddressToLegacy,
  bitcoinCashAddressToPayload,
  decodeBitcoinCashLegacyAddress,
  parseBitcoinCashAddress,
} from './cashaddr';
import { getUtxoSignerNetwork } from './network';
import {
  isZcashTransparentAddress,
  toBridgeP2pkhAddress,
} from './zcashTransparentAddress';

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
  if (chain === 'zcash') {
    return isZcashTransparentAddress(network, address);
  }

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
  if (chain === 'zcash') {
    return toBridgeP2pkhAddress(network, address);
  }

  if (chain !== 'bitcoincash') {
    return address;
  }

  try {
    return bitcoinCashAddressToLegacy(network, address);
  } catch {
    return parseBitcoinCashLegacyAddress(network, address);
  }
}

/** Blockbook / REST indexers: BCH expects legacy base58; Zcash expects native t-addresses. */
export function toUtxoApiAddress(chain: UTXOChain, network: ApiNetwork, address: string) {
  if (chain === 'zcash') {
    return address;
  }

  return toUtxoSignerAddress(chain, network, address);
}

export function isSameUtxoAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  left: string,
  right: string,
) {
  try {
    const normalizedLeft = toUtxoApiAddress(chain, network, left);
    const normalizedRight = toUtxoApiAddress(chain, network, right);

    return normalizedLeft === normalizedRight;
  } catch {
    return false;
  }
}
