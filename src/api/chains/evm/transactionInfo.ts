import type { ApiActivity, ApiFetchTransactionByIdOptions, EVMChain } from '../../types';

import { logDebugError } from '../../../util/logs';
import { collectTokensFromTransactions, parseEvmTx, transformEvmTxToUnified } from './activities';

export async function fetchTransactionById(
  chain: EVMChain,
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in options;

  try {
    if (!isTxId) {
      return [];
    }
    const parsed = await parseEvmTx(chain, network, options.txId);

    if (!parsed) {
      return [];
    }

    const address = walletAddress || parsed.attributes.sent_from;

    await collectTokensFromTransactions(network, chain, address, [parsed]);

    return [transformEvmTxToUnified(chain, parsed, address)];
  } catch (err) {
    logDebugError('fetchTransactionById', 'solana', err);
    return [];
  }
}
