import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { ApiActivity, ApiFetchTransactionByIdOptions, ApiNetwork, ApiSwapActivity } from '../../types';
import type { AddressBook, Trace } from './toncenter/types';

import { omit } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { toBase64Address } from './util/tonCore';
import { OpCode as MfaOpCode } from './contracts/MfaExtension';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { parseActionsToActivities } from './toncenter/actions';
import { fetchTraceByIdOrHash, fetchTraceByTxHash } from './toncenter/traces';
import { fillActivityDetails } from './activities';
import { parseTrace } from './traces';

/**
 * Fetches transaction/trace info by hash or trace ID for deeplink viewing.
 * `walletAddress` is the wallet the caller views the transaction from: `isIncoming` is relative to it, and all
 * activities of the trace are returned. The caller passes an empty `walletAddress` when it does not know whose
 * transaction it is (a shared link). Then the wallet that signed the transaction takes this role, and only its
 * activities are returned, the same ones its history shows.
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
    const signerAddress = walletAddress || getSignerAddress(trace, addressBook, network);

    const activities = parseActionsToActivities(trace.actions, {
      network,
      walletAddress: signerAddress,
      addressBook,
      metadata,
      nftSuperCollectionsByCollectionAddress,
    }).filter((activity) => (
      walletAddress || activity.kind !== 'transaction' || activity.isIncoming || activity.fromAddress === signerAddress
    ));

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

      try {
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
      } catch (err) {
        logDebugError('fetchTransactionById.fillActivityDetails', activity.id, err);

        return activity;
      }
    });
  } catch (err) {
    logDebugError('fetchTransactionById', 'ton', err);
    return [];
  }
}

/**
 * The account that received the external message signed the transaction, unless the message came through the MFA
 * extension or a gasless relayer: then the wallet is the one they make act.
 */
function getSignerAddress(trace: Trace, addressBook: AddressBook, network: ApiNetwork) {
  const rootTransaction = trace.transactions[trace.trace.tx_hash];
  if (!rootTransaction) return '';

  const { account, in_msg: inMessage, out_msgs: outMessages } = rootTransaction;
  const isMfaExtensionMessage = (Number(inMessage.opcode) as MfaOpCode) === MfaOpCode.SEND_ACTIONS;
  const walletOpCode = isMfaExtensionMessage
    ? WalletContractV5R1.OpCodes.auth_extension
    : WalletContractV5R1.OpCodes.auth_signed_internal;
  const walletMessage = outMessages.find(({ opcode }) => Number(opcode) === walletOpCode);
  const rawAddress = walletMessage?.destination ?? account;

  return addressBook[rawAddress]?.user_friendly ?? toBase64Address(rawAddress, false, network);
}
