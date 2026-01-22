import { TronWeb } from 'tronweb';

import type { ApiActivity, ApiFetchTransactionByIdOptions } from '../../types';

import { SECOND } from '../../../util/dateFormat';
import isEmptyObject from '../../../util/isEmptyObject';
import { logDebugError } from '../../../util/logs';
import { getTronClient } from './util/tronweb';
import { getTrc20Transactions, parseRawTrc20Transaction, parseRawTrxTransaction } from './activities';

/**
 * Fetches transaction/trace info by hash or trace ID for deeplink viewing.
 * Returns all activities from a transaction, regardless of which wallet initiated it.
 * `walletAddress` is only used for determining the isIncoming perspective.
 * For TRON, `txId` is a transaction hash.
 */
export async function fetchTransactionById(
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in options;
  const txId = isTxId ? options.txId : options.txHash;

  try {
    const tronWeb = getTronClient(network);

    const [txResult, txInfoResult] = await Promise.all([
      tronWeb.trx.getTransaction(txId),
      tronWeb.trx.getTransactionInfo(txId),
    ]);

    if (!txResult || !txResult.raw_data || !txInfoResult || isEmptyObject(txInfoResult)) {
      return [];
    }

    if (!walletAddress) {
      const ownerAddressHex = txResult.raw_data.contract[0].parameter.value.owner_address;
      walletAddress = TronWeb.address.fromHex(ownerAddressHex);
    }

    const timestamp = txInfoResult.blockTimeStamp;

    const fee = BigInt(txInfoResult.fee);

    const trc20Transactions = await getTrc20Transactions(network, walletAddress, {
      min_timestamp: timestamp - SECOND,
      max_timestamp: timestamp + SECOND,
    });

    const matchingTrc20Tx = trc20Transactions.find((tx) => tx.transaction_id === txId);

    if (matchingTrc20Tx) {
      const activity = parseRawTrc20Transaction(walletAddress, matchingTrc20Tx);
      if (activity.kind === 'transaction') {
        activity.fee = fee;
      }
      return [activity];
    }

    const combinedTx = {
      ...txResult,
      txID: txResult.txID,
      raw_data: txResult.raw_data,
      energy_fee: txInfoResult.receipt?.energy_fee ?? 0,
      net_fee: txInfoResult.receipt?.net_fee ?? 0,
      block_timestamp: timestamp,
    };

    const activity = parseRawTrxTransaction(walletAddress, combinedTx);
    return [activity];
  } catch (err) {
    logDebugError('fetchTransactionById', 'tron', err);
    return [];
  }
}
