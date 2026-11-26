import type { Transaction } from 'ethers';

import type { ApiNetwork, EVMChain } from '../../types';

import { getEvmChainId } from './constants';

/** A transaction without a chain id does not match: its signature is valid on every chain */
export function isTransactionOnChain(tx: Transaction, network: ApiNetwork, chain: EVMChain): boolean {
  const expectedChainId = getEvmChainId(network, chain);

  return expectedChainId !== undefined && tx.chainId === BigInt(expectedChainId);
}
