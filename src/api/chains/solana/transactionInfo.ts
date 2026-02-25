import type { ApiActivity, ApiFetchTransactionByIdOptions } from '../../types';

import { logDebugError } from '../../../util/logs';
import {
  collectNftsFromTransactions,
  collectTokensFromTransactions,
  parseSolTx,
  transformSolanaTxToUnified,
} from './activities';

export async function fetchTransactionById(
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in options;

  try {
    if (!isTxId) {
      return [];
    }
    const parsed = await parseSolTx(network, options.txId);

    if (!parsed) {
      return [];
    }

    const address = walletAddress || parsed.feePayer;

    const [, nfts] = await Promise.all([
      collectTokensFromTransactions(network, address, [parsed]),
      collectNftsFromTransactions(network, address, [parsed]),
    ]);

    return [transformSolanaTxToUnified(address, parsed, nfts)];
  } catch (err) {
    logDebugError('fetchTransactionById', 'solana', err);
    return [];
  }
}
