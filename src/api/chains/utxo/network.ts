import { NETWORK, TEST_NETWORK } from '@scure/btc-signer';

import type { ApiNetwork, UTXOChain } from '../../types';

export type UtxoSignerNetwork = {
  bech32: string;
  pubKeyHash: number;
  scriptHash: number;
  wif: number;
};

const LTC_MAINNET: UtxoSignerNetwork = {
  bech32: 'ltc',
  pubKeyHash: 0x30,
  scriptHash: 0x32,
  wif: 0xb0,
};

const LTC_TESTNET: UtxoSignerNetwork = {
  bech32: 'tltc',
  pubKeyHash: 0x6f,
  scriptHash: 0x3a,
  wif: 0xef,
};

const DOGE_MAINNET: UtxoSignerNetwork = {
  bech32: 'doge',
  pubKeyHash: 0x1e,
  scriptHash: 0x16,
  wif: 0x9e,
};

const DOGE_TESTNET: UtxoSignerNetwork = {
  bech32: 'tdge',
  pubKeyHash: 0x71,
  scriptHash: 0xc4,
  wif: 0xf1,
};

const UTXO_SIGNER_NETWORKS: Record<UTXOChain, Record<ApiNetwork, UtxoSignerNetwork>> = {
  bitcoin: {
    mainnet: NETWORK,
    testnet: TEST_NETWORK,
  },
  litecoin: {
    mainnet: LTC_MAINNET,
    testnet: LTC_TESTNET,
  },
  bitcoincash: {
    mainnet: NETWORK,
    testnet: TEST_NETWORK,
  },
  dogecoin: {
    mainnet: DOGE_MAINNET,
    testnet: DOGE_TESTNET,
  },
};

export function getUtxoSignerNetwork(chain: UTXOChain, network: ApiNetwork): UtxoSignerNetwork {
  return UTXO_SIGNER_NETWORKS[chain][network];
}

export function getUtxoCashAddrPrefix(network: ApiNetwork): string {
  return network === 'mainnet' ? 'bitcoincash' : 'bchtest';
}
