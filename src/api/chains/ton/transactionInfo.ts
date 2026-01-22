import type { ApiActivity, ApiFetchTransactionByIdOptions, ApiSwapActivity } from '../../types';

import { omit } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { parseActionsToActivities } from './toncenter/actions';
import { fetchTraceByIdOrHash, fetchTraceByTxHash } from './toncenter/traces';
import { fillActivityDetails } from './activities';
import { parseTrace } from './traces';

/**
 * Fetches transaction/trace info by hash or trace ID for deeplink viewing.
 * Returns all activities from a transaction, regardless of which wallet initiated it.
 * `walletAddress` is only used for determining the isIncoming perspective.
 * For TON, `txId` can be either a trace_id or msg_hash.
 */
export async function fetchTransactionById(
  { network, walletAddress, ...options }: ApiFetchTransactionByIdOptions,
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in options;

  try {
    const { trace, addressBook, metadata } = isTxId
      ? await fetchTraceByIdOrHash({ network, txId: options.txId })
      : await fetchTraceByTxHash({ network, txHash: options.txHash });

    if (!trace || !trace.actions?.length) {
      return [];
    }

    const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

    const activities = parseActionsToActivities(trace.actions, {
      network,
      walletAddress,
      addressBook,
      metadata,
      nftSuperCollectionsByCollectionAddress,
    });

    /*
      Populate fee details for activities that require them.
      We need to parse the trace using the activity's initiator address, not the viewer's wallet,
      because `parseTrace` filters actions by the wallet address - therefore, actions with other initiators will be missing.
      Also, we omit the `ourFee` field to avoid duplication (`ourFee` will be presented as its own activity).
    */
    return activities.map((activity) => {
      if (!activity.shouldLoadDetails) {
        return activity;
      }

      let initiatorAddress = activity.fromAddress;
      if (initiatorAddress.startsWith('0:')) {
        const userFriendly = addressBook[initiatorAddress]?.user_friendly;
        if (userFriendly) {
          initiatorAddress = userFriendly;
        }
      }

      const parsedTrace = parseTrace({
        network,
        walletAddress: initiatorAddress,
        actions: trace.actions,
        traceDetail: trace.trace,
        addressBook,
        metadata,
        transactions: trace.transactions,
        nftSuperCollectionsByCollectionAddress,
      });

      const filledActivity = fillActivityDetails(activity, parsedTrace);

      return omit(filledActivity as ApiSwapActivity, ['ourFee']);
    });
  } catch (err) {
    logDebugError('fetchTransactionById', 'ton', err);
    return [];
  }
}
