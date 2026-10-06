import type { ApiChain, ApiNetwork, EVMChain } from '../../types';

export type EvmCaipChainEntry = { chain: ApiChain; network: ApiNetwork };
export type EvmCaipChainIds = Record<string, EvmCaipChainEntry>;

/** CAIP-2 EVM chain ids (eip155:…). */
export const EVM_CHAIN_IDS: EvmCaipChainIds = {
  'eip155:1': { chain: 'ethereum', network: 'mainnet' },
  'eip155:5': { chain: 'ethereum', network: 'testnet' },
  'eip155:8453': { chain: 'base', network: 'mainnet' },
  'eip155:84532': { chain: 'base', network: 'testnet' },
  'eip155:137': { chain: 'polygon', network: 'mainnet' },
  'eip155:80002': { chain: 'polygon', network: 'testnet' },
  'eip155:42161': { chain: 'arbitrum', network: 'mainnet' },
  'eip155:421614': { chain: 'arbitrum', network: 'testnet' },
  'eip155:10': { chain: 'optimism', network: 'mainnet' },
  'eip155:11155420': { chain: 'optimism', network: 'testnet' },
  'eip155:56': { chain: 'bnb', network: 'mainnet' },
  'eip155:97': { chain: 'bnb', network: 'testnet' },
  'eip155:43114': { chain: 'avalanche', network: 'mainnet' },
  'eip155:43113': { chain: 'avalanche', network: 'testnet' },
  'eip155:143': { chain: 'monad', network: 'mainnet' },
  'eip155:10143': { chain: 'monad', network: 'testnet' },
  'eip155:999': { chain: 'hyperliquid', network: 'mainnet' },
  'eip155:998': { chain: 'hyperliquid', network: 'testnet' },
  'eip155:4663': { chain: 'robinhood', network: 'mainnet' },
  'eip155:46630': { chain: 'robinhood', network: 'testnet' },
  'eip155:5042': { chain: 'arc', network: 'mainnet' },
  'eip155:5042002': { chain: 'arc', network: 'testnet' },
};

export const EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN = Object.entries(EVM_CHAIN_IDS)
  .reduce<Partial<Record<ApiNetwork, Partial<Record<EVMChain, number>>>>>((acc, [caip, { chain, network }]) => {
    acc[network] ??= {};
    acc[network][chain as EVMChain] = Number(caip.slice('eip155:'.length));
    return acc;
  }, {});

export function getEvmChainId(network: ApiNetwork, chain: EVMChain): number | undefined {
  return EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN[network]?.[chain];
}

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
  '0xa46cc63eBF4Bd77888AA327837d20b23A63a56B5': 'Simple7702 (Candide)',
  '0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00': 'Uniswap',
  '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b': 'Metamask',
  '0x69007702764179f14F51cdce752f4f775d74E139': 'My Wallet (Alchemy v1)',
  '0x77021100bD87b7008E5E1989d0eB38555d0d0000': 'My Wallet (Alchemy v1.1)',
  '0x5A7FC11397E9a8AD41BF10bf13F22B0a63f96f6d': 'Ambire',
  '0xD2e28229F6f2c235e57De2EbC727025A1D0530FB': 'Trust Wallet',
  '0x4Cd241E8d1510e30b2076397afc7508Ae59C66c9': 'Eth Foundation',
};

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

/** Uniswap Permit2 — same address on all supported EVM chains. */
export const UNISWAP_PERMIT2_ADDRESS = '0x000000000022D473030F116dDEE9F6B43aC78BA3';

/**
 * Low 20 bytes of `sha3_256("mytonwallet fee-check address")`. Must hold nothing: OpenZeppelin ERC20s revert on the
 * zero address, and a funded recipient under-reports the gas of a transfer to a fresh CEX deposit address.
 */
export const EVM_FEE_CHECK_ADDRESS = '0x93fa28647b06ab40554d6905e4e9d8e8bb24380c';
