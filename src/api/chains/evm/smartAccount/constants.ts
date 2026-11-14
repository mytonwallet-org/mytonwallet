import type { ApiNetwork, EVMChain } from '../../../types';

import {
  EVM_MAINNET_RPC_URL,
  EVM_TESTNET_RPC_URL,
} from '../../../../config';
import { EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN } from '../constants';

export const EVM_CHAIN_IDS = EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN;

/** Alchemy SemiModularAccount7702 delegate addresses accepted by wallet_prepareCalls. */
export const ALCHEMY_7702_DELEGATEE_ADDRESSES = new Set([
  '0x69007702764179f14f51cdce752f4f775d74e139',
  '0x77021100bd87b7008e5e1989d0eb38555d0d0000',
]);

/** ModularAccountV2 v1.1.0, the delegate `prepareAlchemyCalls` requests. */
export const ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS = '0x77021100bd87b7008e5e1989d0eb38555d0d0000';

export const ENTRY_POINT_V07_ADDRESS = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';

/** Pimlico SingletonPaymaster v0.7. The same CREATE2 address on every chain. */
export const PIMLICO_SINGLETON_PAYMASTER_ADDRESS = '0x777777777777AeC03fd955926DbF81597e66834C';

/** ModularAccountV2 global owner validation entity id (nonce prefix `0x01 << 64`). */
export const MODULAR_ACCOUNT_GLOBAL_OWNER_NONCE_KEY = 1n;

/** ERC-20 tokens that can pay Pimlico gas on each chain */
export const PIMLICO_GAS_TOKEN_BY_NETWORK_AND_CHAIN: Partial<
  Record<ApiNetwork, Partial<Record<EVMChain, readonly string[]>>>
> = {
  mainnet: {
    ethereum: [
      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
      '0xdAC17F958D2ee523a2206206994597C13D831ec7', // USDT
    ],
    base: [
      '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // USDC
      '0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2', // Bridged USDT
    ],
    bnb: [
      '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d', // USDC
      '0x55d398326f99059fF775485246999027B3197955', // USDT
    ],
    arbitrum: [
      '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', // USDC
      '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9', // USDT0
    ],
    // Pimlico lists neither USDC nor USDT on these chains.
    hyperliquid: [],
    robinhood: [],
    arc: [],
    optimism: [
      '0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85', // USDC
      '0x94b008aA00579c1307B0EF2c499aD98a8ce58e58', // Bridged USDT
    ],
  },
};

export function getPimlicoGasTokenAddresses(network: ApiNetwork, chain: EVMChain): readonly string[] {
  return PIMLICO_GAS_TOKEN_BY_NETWORK_AND_CHAIN[network]?.[chain] ?? [];
}

export function isPimlicoGasToken(network: ApiNetwork, chain: EVMChain, tokenAddress: string) {
  const needle = tokenAddress.toLowerCase();

  return getPimlicoGasTokenAddresses(network, chain).some((address) => address.toLowerCase() === needle);
}

export function getEvmChainId(network: ApiNetwork, chain: EVMChain): bigint | undefined {
  const chainId = EVM_CHAIN_IDS[network]?.[chain];

  return chainId ? BigInt(chainId) : undefined;
}

export function getAlchemyWalletApiUrl(network: ApiNetwork) {
  const url = network === 'mainnet' ? EVM_MAINNET_RPC_URL : EVM_TESTNET_RPC_URL;
  return `${url}/v2`;
}
