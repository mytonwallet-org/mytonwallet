import { createSolanaRpc } from '@solana/kit';

import type { ApiNetwork } from '../../../types';

import withCache from '../../../../util/withCache';
import { NETWORK_CONFIG } from '../constants';

export const getSolanaClient = withCache((network: ApiNetwork) => {
  return createSolanaRpc(NETWORK_CONFIG[network].rpcUrl);
});

export type SolanaClient = ReturnType<typeof getSolanaClient>;
