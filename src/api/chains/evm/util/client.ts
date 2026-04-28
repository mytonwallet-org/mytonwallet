import { JsonRpcProvider } from 'ethers';

import type { EVMChain } from '../../../types';
import type { ApiNetwork } from '../../../types';

import withCache from '../../../../util/withCache';
import { EVM_RPC_URLS } from '../constants';

export const getEvmProvider = withCache((network: ApiNetwork, chain: EVMChain) => {
  return new JsonRpcProvider(`${EVM_RPC_URLS[network](chain)}/v2`);
});

export type EvmProvider = JsonRpcProvider;
