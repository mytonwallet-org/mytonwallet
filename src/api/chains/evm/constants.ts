import type { ApiNetwork, EVMChain } from '../../types';

import { EVM_MAINNET_RPC_URL, EVM_TESTNET_RPC_URL } from '../../../config';

/** Safety multiplier applied to the estimated gas fee when sending the max native balance */
export const EVM_MAX_TRANSFER_FEE_MULTIPLIER = 1.5;

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

export const EVM_MAX_NUMBER = 2n ** 256n - 1n;

export const EVM_RPC_URLS: Record<ApiNetwork, (chain: EVMChain) => string> = {
  mainnet: (chain: EVMChain) => `${EVM_MAINNET_RPC_URL}/${chain}`,
  testnet: (chain: EVMChain) => `${EVM_TESTNET_RPC_URL}/${chain}`,
};

export const getEvmApiUrl = (network: ApiNetwork) => {
  return network === 'mainnet' ? EVM_MAINNET_RPC_URL : EVM_TESTNET_RPC_URL;
};

export const EVM_DALEGATOR_ADDRESSES: Record<string, string> = {
  '0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00': 'Uniswap',
  '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b': 'Metamask',
  '0x69007702764179f14F51cdce752f4f775d74E139': 'Alchemy',
  '0x5A7FC11397E9a8AD41BF10bf13F22B0a63f96f6d': 'Ambire',
  '0xD2e28229F6f2c235e57De2EbC727025A1D0530FB': 'Trust Wallet',
  '0x4Cd241E8d1510e30b2076397afc7508Ae59C66c9': 'Eth Foundation',
};

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
