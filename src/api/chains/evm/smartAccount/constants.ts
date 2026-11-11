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

/** ERC-20 token used to pay Pimlico gas on each chain (must be supported by Pimlico on that chain). */
export const PIMLICO_GAS_TOKEN_BY_NETWORK_AND_CHAIN: Partial<
  Record<ApiNetwork, Partial<Record<EVMChain, string>>>
> = {
  mainnet: {
    arbitrum: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
  },
};

export function getPimlicoGasTokenAddress(network: ApiNetwork, chain: EVMChain): string | undefined {
  return PIMLICO_GAS_TOKEN_BY_NETWORK_AND_CHAIN[network]?.[chain];
}

export function getEvmChainId(network: ApiNetwork, chain: EVMChain): bigint | undefined {
  const chainId = EVM_CHAIN_IDS[network]?.[chain];

  return chainId ? BigInt(chainId) : undefined;
}

export function getAlchemyWalletApiUrl(network: ApiNetwork) {
  const url = network === 'mainnet' ? EVM_MAINNET_RPC_URL : EVM_TESTNET_RPC_URL;
  return `${url}/v2`;
}
