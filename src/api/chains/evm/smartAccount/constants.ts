import type { ApiNetwork, EVMChain } from '../../../types';

import { EVM_MAINNET_RPC_URL, EVM_TESTNET_RPC_URL } from '../../../../config';
import { EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN } from '../constants';

export const EVM_CHAIN_IDS = EVM_CHAIN_IDS_BY_NETWORK_AND_CHAIN;

/** Alchemy SemiModularAccount7702 delegate addresses accepted by wallet_prepareCalls. */
export const ALCHEMY_7702_DELEGATEE_ADDRESSES = new Set([
  '0x69007702764179f14f51cdce752f4f775d74e139',
  '0x77021100bd87b7008e5e1989d0eb38555d0d0000',
]);

export function getEvmChainId(network: ApiNetwork, chain: EVMChain): bigint | undefined {
  const chainId = EVM_CHAIN_IDS[network]?.[chain];

  return chainId ? BigInt(chainId) : undefined;
}

export function getAlchemyWalletApiUrl(network: ApiNetwork) {
  const url = network === 'mainnet' ? EVM_MAINNET_RPC_URL : EVM_TESTNET_RPC_URL;
  return `${url}/v2`;
}
