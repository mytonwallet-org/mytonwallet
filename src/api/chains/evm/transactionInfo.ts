import type { ApiActivity, ApiFetchTransactionByIdOptions, EVMChain } from '../../types';

import { logDebugError } from '../../../util/logs';
import { collectTokensFromTransactions, fetchEvmTx, transformEvmTxToUnified } from './activities';

export async function fetchTransactionById(
  chain: EVMChain,
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in options;

  try {
    if (!isTxId) {
      return [];
    }
    const tx = await fetchEvmTx(chain, network, options.txId);

    if (!tx) {
      return [];
    }

    const address = walletAddress || tx.attributes.sent_from;

    await collectTokensFromTransactions(network, chain, address, [tx]);

    return [transformEvmTxToUnified(chain, tx, address)];
  } catch (err) {
    logDebugError('fetchTransactionById', 'solana', err);
    return [];
  }
}
