import { JsonRpcProvider, Network } from 'ethers';

import type { EVMChain } from '../../../types';
import type { ApiNetwork } from '../../../types';
import { EVM_CHAIN_IDS } from '../../../dappProtocols/adapters/walletConnect/types';

import withCache from '../../../../util/withCache';
import { EVM_RPC_URLS } from '../constants';

/**
 * Chain id per (chain, network), derived from the CAIP-2 map the dapp protocols already keep so the two can never
 * disagree. Feeding it to the provider as a static network is what stops ethers from asking the node who it is.
 */
const CHAIN_IDS_BY_NETWORK_AND_CHAIN = Object.entries(EVM_CHAIN_IDS)
  .reduce<Partial<Record<ApiNetwork, Partial<Record<EVMChain, number>>>>>((acc, [caip, { chain, network }]) => {
    acc[network] ??= {};
    acc[network][chain as EVMChain] = Number(caip.slice('eip155:'.length));
    return acc;
  }, {});

/**
 * The chain id is pinned so ethers never resolves it over the wire. Left to discover the network itself, its
 * bootstrap retries `eth_chainId` once a second with no backoff while the upstream is failing, and nine cached
 * providers then hold a standing ~9 rps against an evmapi that is already in trouble.
 */
export const getEvmProvider = withCache((network: ApiNetwork, chain: EVMChain) => {
  const chainId = CHAIN_IDS_BY_NETWORK_AND_CHAIN[network]?.[chain];

  return new JsonRpcProvider(
    `${EVM_RPC_URLS[network](chain)}/v2`,
    // A chain missing from the map is resolved over the network instead: that costs a round-trip, whereas throwing
    // on an absent constant would cost the whole import.
    chainId === undefined ? undefined : Network.from(chainId),
    chainId === undefined ? undefined : { staticNetwork: true },
  );
});

export type EvmProvider = JsonRpcProvider;
