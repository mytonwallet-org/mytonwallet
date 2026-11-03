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
 * Universal Router 2.0, 2.1.1 and 2.1.2 per chain, lowercased. The lists differ because one address can hold another
 * contract elsewhere: the Base 2.1.2 router address is a MaxBalanceDripCheck on Ethereum.
 */
export const UNISWAP_UNIVERSAL_ROUTER_ADDRESSES: Partial<Record<EVMChain, string[]>> = {
  ethereum: [
    '0x66a9893cc07d91d95644aedd05d03f95e1dba8af', '0x4c82d1fbfe28c977cbb58d8c7ff8fcf9f70a2cca',
    '0x23617e59a5925b2a4bf75d73ff6711cd0b29de85',
  ],
  base: [
    '0x6ff5693b99212da76ad316178a184ab56d299b43', '0xfdf682f51fe81aa4898f0ae2163d8a55c127fbc7',
    '0xd6145b2d3f379919e8cdeda7b97e37c4b2ca9c40',
  ],
  bnb: [
    '0x1906c1d672b88cd1b9ac7593301ca990f94eae07', '0x8b844f885672f333bc0042cb669255f93a4c1e6b',
    '0xdc264714f68d84cf29bc605589405e78bdbe7c9f',
  ],
  polygon: [
    '0x1095692a6237d83c6a72f3f5efedb9a670c49223', '0x8b844f885672f333bc0042cb669255f93a4c1e6b',
    '0xdc264714f68d84cf29bc605589405e78bdbe7c9f',
  ],
  arbitrum: [
    '0xa51afafe0263b40edaef0df8781ea9aa03e381a3', '0x8b844f885672f333bc0042cb669255f93a4c1e6b',
    '0x2d01411773c8c24805306e89a41f7855c3c4fe65',
  ],
  optimism: [
    '0x851116d9223fabed8e56c0e6b8ad0c31d98b3507', '0x8b844f885672f333bc0042cb669255f93a4c1e6b',
    '0xc09255d86db563cbc11c2fcf4a0c512e160111b4',
  ],
  avalanche: [
    '0x94b75331ae8d42c1b61065089b7d48fe14aa73b7', '0x8b844f885672f333bc0042cb669255f93a4c1e6b',
    '0x661e93cca42afacb172121ef892830ca3b70f08d',
  ],
  monad: [
    '0x0d97dc33264bfc1c226207428a79b26757fb9dc3', '0xfdf682f51fe81aa4898f0ae2163d8a55c127fbc7',
    '0xa6ce4f10d83dbddac17e68e1837ca9ce6a1b596e',
  ],
  robinhood: [
    '0x8876789976decbfcbbbe364623c63652db8c0904', '0x204faca1764b154221e35c0d20abb3c525710498',
  ],
  arc: [
    '0x4fca4a51ab4f23a7447b3284fbd7d73289a89fb1', '0x8702463e73f74d0b6765abceb314ef07acb92650',
  ],
};

const LIFI_SHARED_CONTRACTS = {
  permit2Proxy: '0x89c6340B1a1f4b25D36cd8B063D49045caF3f818',
  diamond: '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE',
};

/**
 * LI.FI Permit2Proxy, the only spender a LI.FI Permit2 transfer is signed for, and the Diamond it forwards to,
 * the only target of a LI.FI transaction. Each Diamond is the one its proxy's `LIFI_DIAMOND()` returns.
 */
export const LIFI_CONTRACTS: Partial<Record<EVMChain, { permit2Proxy: string; diamond: string }>> = {
  ethereum: LIFI_SHARED_CONTRACTS,
  base: LIFI_SHARED_CONTRACTS,
  bnb: LIFI_SHARED_CONTRACTS,
  polygon: LIFI_SHARED_CONTRACTS,
  arbitrum: LIFI_SHARED_CONTRACTS,
  optimism: LIFI_SHARED_CONTRACTS,
  avalanche: LIFI_SHARED_CONTRACTS,
  monad: {
    permit2Proxy: '0x3c6B2E0b7421254846C53c118e24c65d59eAe75e',
    diamond: '0x026F252016A7C47CDEf1F05a3Fc9E20C92a49C37',
  },
  hyperliquid: {
    permit2Proxy: '0x3e851976DCA1bc02A2F35Ce926dCAFD1dEB3359b',
    diamond: '0x0a0758d937d1059c356D4714e57F5df0239bce1A',
  },
};

/**
 * Low 20 bytes of `sha3_256("mytonwallet fee-check address")`. Must hold nothing: OpenZeppelin ERC20s revert on the
 * zero address, and a funded recipient under-reports the gas of a transfer to a fresh CEX deposit address.
 */
export const EVM_FEE_CHECK_ADDRESS = '0x93fa28647b06ab40554d6905e4e9d8e8bb24380c';
