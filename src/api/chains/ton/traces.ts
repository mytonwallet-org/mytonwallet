import type { ApiNetwork, ApiNftSuperCollection } from '../../types';
import type { AddressBook, AnyAction, MetadataMap, TraceDetail, Transaction } from './toncenter/types';
import type { ApiTransactionExtended, ParsedAction, ParsedTrace, TraceOutput } from './types';

import { TONCOIN } from '../../../config';
import { bigintAbs } from '../../../util/bigint';
import { groupBy, intersection } from '../../../util/iteratees';
import { parseBidaskPayload } from './util/metadata';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { fetchTrace } from './toncenter/traces';
import { BidaskOpCode } from './constants';
import { parseActions, parseRawTransactions } from './toncenter';

/**
 * Returns `undefined` when there is no trace for the given hash. It may be unavailable YET, for example if the trace is
 * requested immediately after receiving an action from the socket.
 */
export async function fetchAndParseTrace(
  network: ApiNetwork,
  walletAddress: string,
  msgHashNormalized: string,
  isActionPending?: boolean,
): Promise<ParsedTrace | undefined> {
  const { trace, addressBook, metadata } = await fetchTrace({ network, msgHashNormalized, isActionPending });
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  return trace && parseTrace({
    network,
    walletAddress,
    actions: trace.actions,
    traceDetail: trace.trace,
    addressBook,
    metadata,
    transactions: trace.transactions,
    nftSuperCollectionsByCollectionAddress,
  });
}

export function parseTrace(options: {
  network: ApiNetwork;
  walletAddress: string;
  actions: AnyAction[];
  traceDetail: TraceDetail;
  addressBook: AddressBook;
  metadata: MetadataMap;
  transactions: Record<string, Transaction>;
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>;
}): ParsedTrace {
  const {
    network,
    walletAddress,
    actions,
    traceDetail,
    addressBook,
    metadata,
    transactions: rawTransactionMap,
    nftSuperCollectionsByCollectionAddress,
  } = options;

  let traceOutputs: TraceOutput[];

  const parsedActions = parseActions(actions, {
    network,
    walletAddress,
    addressBook,
    metadata,
    nftSuperCollectionsByCollectionAddress,
  });

  if (isFailedTransactionTrace(traceDetail)) {
    traceOutputs = buildFailedOutputs(traceDetail, rawTransactionMap, parsedActions, walletAddress);
  } else {
    const transactions = parseRawTransactions(network, Object.values(rawTransactionMap), addressBook);
    const transactionByHash = groupBy(transactions, 'hash');

    traceOutputs = splitTraceToOutputs(walletAddress, traceDetail, transactionByHash);

    fixLiquidityActions(parsedActions, traceOutputs);

    for (const traceOutput of traceOutputs) {
      fillTraceOutput(parsedActions, traceOutput, transactionByHash, walletAddress, addressBook);
    }
  }

  return {
    actions,
    traceDetail,
    addressBook,
    traceOutputs,
    totalSent: traceOutputs.reduce((total, { sent }) => total + sent, 0n),
    totalReceived: traceOutputs.reduce((total, { received }) => total + received, 0n),
    totalNetworkFee: traceOutputs.reduce((total, { networkFee }) => total + networkFee, 0n),
  };
}

function fixLiquidityActions(parsedActions: ParsedAction[], traceOutputs: TraceOutput[]) {
  for (const index of Object.keys(parsedActions)) {
    const parsedAction = parsedActions[Number(index)];
    if (parsedAction?.action.type === 'dex_deposit_liquidity' && parsedAction.activities.length > 1) {
      const actionHashes = new Set(parsedAction.action.transactions);
      const mainActivity = parsedAction.activities[0];
      parsedAction.action.transactions = Array.from(intersection(actionHashes, new Set(traceOutputs[0].hashes),
      ));
      const additionalActivity = parsedAction.activities.pop();

      if (!additionalActivity) {
        continue;
      }

      const isMainTonTransaction = mainActivity.kind === 'transaction' && mainActivity.slug === TONCOIN.slug;
      const isAdditionalTonTransaction = additionalActivity.kind === 'transaction'
        && additionalActivity.slug === TONCOIN.slug;

      parsedAction.toncoinChange = isMainTonTransaction
        ? (mainActivity.kind === 'transaction' ? mainActivity.amount : 0n)
        : 0n;

      parsedActions.splice(Number(index), 0, {
        ...parsedAction,
        action: {
          ...parsedAction.action,
          transactions: Array.from(intersection(
            actionHashes,
            new Set(traceOutputs[1].hashes),
          )),
        },
        activities: [additionalActivity],
        toncoinChange: isAdditionalTonTransaction
          ? additionalActivity.amount
          : 0n,
      });
    }
  }
}

function isFailedTransactionTrace(traceDetails: TraceDetail) {
  return traceDetails.children.length === 0;
}

function splitTraceToOutputs(
  walletAddress: string,
  traceDetail: TraceDetail,
  transactionsByHash: Record<string, ApiTransactionExtended[]>,
): TraceOutput[] {
  const traceOutputs: TraceOutput[] = [];
  let isWalletTransactionFound = false;

  function processTrace(_traceDetail: TraceDetail, _index?: number) {
    const hash = _traceDetail.tx_hash;
    const txs = transactionsByHash[hash] || [];

    if (!isWalletTransactionFound) {
      isWalletTransactionFound = txs.some(({
        fromAddress,
        isIncoming,
      }) => {
        return fromAddress === walletAddress && !isIncoming;
      });

      // In gasless operations, we need to skip transactions before our wallet
      if (!isWalletTransactionFound) {
        _traceDetail.children.forEach(processTrace);
        return;
      }
    }

    for (const [i, tx] of txs.entries()) {
      const { fromAddress, toAddress, amount, isIncoming, fee, msgHash } = tx;

      const index = _index ?? i;

      if (!(index in traceOutputs)) {
        // First transaction from wallet includes all sub-transactions, and its hash is not unique
        traceOutputs.push({
          hashes: new Set(),
          sent: 0n,
          received: 0n,
          networkFee: 0n,
          isSuccess: true,
          realFee: 0n,
          excess: 0n,
          walletActions: [],
        });
      } else {
        traceOutputs[index].hashes.add(hash);
      }

      if (fromAddress === walletAddress && !isIncoming) {
        traceOutputs[index].sent += bigintAbs(amount);
        traceOutputs[index].networkFee = fee;
      } else if (toAddress === walletAddress && isIncoming) {
        traceOutputs[index].received += bigintAbs(amount);
      }

      const child = _traceDetail.children.find(({ in_msg_hash }) => in_msg_hash === msgHash);
      if (child) {
        processTrace(child, index);
      }
    }
  }

  processTrace(traceDetail);

  return traceOutputs;
}

function fillTraceOutput(
  parsedActions: ParsedAction[],
  traceOutput: TraceOutput,
  txsByHash: Record<string, ApiTransactionExtended[]>,
  walletAddress: string,
  addressBook: AddressBook,
) {
  const walletActions: ParsedAction[] = parsedActions.filter(({ action, activities }) => {
    const hasCommonTransactions = !!intersection(new Set(action.transactions), traceOutput.hashes).size;
    const isWalletAction = activities.some((activity) => {
      if (activity.kind === 'transaction') {
        return activity.fromAddress === walletAddress || activity.toAddress === walletAddress;
      } else if (activity.kind === 'swap') {
        return addressBook[activity.fromAddress]?.user_friendly === walletAddress;
      } else {
        throw new Error(`Unknown activity kind: ${JSON.stringify(activity)}`);
      }
    });

    return hasCommonTransactions && isWalletAction;
  });

  const isLiquidityAction = walletActions.some(({ action }) => (
    action.type === 'dex_deposit_liquidity' || action.type === 'dex_withdraw_liquidity'
  ));

  if (!traceOutput.received && !isLiquidityAction) {
    traceOutput.walletActions = walletActions;
    traceOutput.realFee = traceOutput.networkFee;
    traceOutput.excess = 0n;
    return;
  }

  const toncoinChangeIn = walletActions.reduce((result, { toncoinChange }) => {
    if (toncoinChange !== undefined && toncoinChange > 0) result += toncoinChange;
    return result;
  }, 0n);

  const toncoinChangeOut = walletActions.reduce((result, { toncoinChange }) => {
    if (toncoinChange !== undefined && toncoinChange < 0) result += toncoinChange;
    return result;
  }, 0n);

  const transactions = Object.values(txsByHash).flat();
  const toncoinChangeFromTransactions = findToncoinChangeInTransactions(walletAddress, transactions);
  const toncoinChange = toncoinChangeFromTransactions + toncoinChangeIn + toncoinChangeOut;

  traceOutput.realFee = traceOutput.sent - traceOutput.received + toncoinChange + traceOutput.networkFee;
  traceOutput.excess = traceOutput.received - toncoinChangeIn;
  traceOutput.walletActions = walletActions;
}

export function findToncoinChangeInTransactions(
  walletAddress: string,
  transactions: ApiTransactionExtended[],
): bigint {
  for (const transaction of transactions) {
    if (!transaction.body) {
      continue;
    }

    let amount = 0n;

    switch (transaction.opCode) {
      case BidaskOpCode.Swap:
      case BidaskOpCode.NativeTransferNotification:
        amount = parseBidaskPayload(transaction.body).amount;
        break;
      default:
        continue;
    }

    if (amount === 0n) {
      continue;
    }

    const isToncoinIn = transaction.slug === TONCOIN.slug
      && transaction.toAddress === walletAddress
      && transaction.isIncoming;
    const isToncoinOut = transaction.slug === TONCOIN.slug
      && transaction.fromAddress === walletAddress
      && !transaction.isIncoming;

    if (isToncoinIn) {
      return amount;
    } else if (isToncoinOut) {
      return -amount;
    }
  }

  return 0n;
}

function buildFailedOutputs(
  traceDetails: TraceDetail,
  rawTransactions: Record<string, Transaction>,
  parsedActions: ParsedAction[],
  walletAddress: string,
): TraceOutput[] {
  const txHash = traceDetails.tx_hash;
  const rawTx = rawTransactions[txHash];
  const traceOutputs: TraceOutput[] = [];

  for (const parsedAction of parsedActions) {
    for (const activity of parsedAction.activities) {
      if (activity.kind === 'transaction' && activity.fromAddress === walletAddress) {
        traceOutputs.push({
          hashes: new Set(),
          sent: 0n,
          received: 0n,
          networkFee: 0n,
          isSuccess: false,
          realFee: 0n,
          excess: 0n,
          walletActions: [parsedAction],
        });
      }
    }
  }

  for (const traceOutput of traceOutputs) {
    const networkFee = BigInt(rawTx.total_fees) / BigInt(traceOutputs.length);
    traceOutput.networkFee = networkFee;
    traceOutput.realFee = networkFee;
  }

  return traceOutputs;
}
