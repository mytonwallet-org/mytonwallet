import type { ApiActivity, ApiFetchTransactionByIdOptions, UTXOChain } from '../../types';
import type { UtxoTransaction } from './types';

import { fetchJson } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { parseUtxoTransaction } from './activities';
import { UTXO_RPC_URLS } from './constants';

export async function fetchTransactionById(
  chain: UTXOChain,
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const txId = 'txId' in options ? options.txId : options.txHash;

  try {
    const endpoint = UTXO_RPC_URLS[network](chain);
    const tx = await fetchJson<UtxoTransaction>(`${endpoint}/api/v2/tx/${txId}`);

    if (!walletAddress) {
      const firstAddress = tx.vin[0]?.addresses?.[0] ?? tx.vout[0]?.addresses?.[0];
      if (!firstAddress) {
        return [];
      }
      walletAddress = firstAddress;
    }

    return [parseUtxoTransaction(chain, network, walletAddress, tx)];
  } catch (err) {
    logDebugError('fetchTransactionById', chain, err);

    return [];
  }
}
