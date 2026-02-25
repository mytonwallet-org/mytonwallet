import type { ApiChain } from '../types';
import type { ChainSdk } from '../types/chains';

import solana from './solana';
import ton from './ton';
import tron from './tron';

/**
 * This dictionary contains only universal chain methods, i.e. the methods having the same interface in all the chains.
 *
 * If you need chain-specific methods, import them directly from the corresponding chain module. This is deprecated —
 * all chain methods should be universal. If a chain doesn't support some functionality yet, the corresponding methods
 * should simply throw an error.
 */
export const chains: { [K in ApiChain]: ChainSdk<K> } = {
  ton,
  tron,
  solana,
};

export default chains;
