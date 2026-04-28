import type { ApiNetwork, EVMChain } from '../../types';

import { EVM_MAINNET_RPC_URL, EVM_TESTNET_RPC_URL } from '../../../config';

export const EVM_DEFAULT_DERIVATION_PATH = `m/44'/60'/0'/0/0`;

export const EVM_DERIVATION_PATHS = {
  default: `m/44'/60'/0'/0/{index}`,
  legacy: `m/44'/60'/0'/{index}`,
  alt: `m/44'/60'/0'`,
} as const;

export function getApiChainByZerionChain(chain: string): EVMChain {
  switch (chain) {
    case 'binance-smart-chain':
      return 'bnb';
    case 'hyperevm':
      return 'hyperliquid';
    default:
      return chain as EVMChain;
  }
}

export function getZerionChainByApiChain(chain: EVMChain): string {
  switch (chain) {
    case 'bnb':
      return 'binance-smart-chain';
    case 'hyperliquid':
      return 'hyperevm';
    default:
      return chain;
  }
}

export const EVM_RPC_URLS: Record<ApiNetwork, (chain: EVMChain) => string> = {
  mainnet: (chain: EVMChain) => `${EVM_MAINNET_RPC_URL}/${chain}`,
  testnet: (chain: EVMChain) => `${EVM_TESTNET_RPC_URL}/${chain}`,
};

export const getEvmApiUrl = (network: ApiNetwork) => {
  return network === 'mainnet' ? EVM_MAINNET_RPC_URL : EVM_TESTNET_RPC_URL;
};
