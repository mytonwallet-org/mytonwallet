import type { ApiNetwork, ApiTransaction } from '../../../types';
import type { ApiTransactionExtended } from '../types';
import type { AddressBook, Transaction, TransactionMessage } from './types';

import { TONCOIN } from '../../../../config';
import { toSeconds } from '../../../../util/datetime';
import { omitUndefined } from '../../../../util/iteratees';
import { toBase64Address } from '../util/tonCore';
import { callToncenterV3 } from './other';

export async function fetchTransactions(options: {
  network: ApiNetwork;
  address: string | string[];
  limit: number;
  fromTimestamp?: number;
  toTimestamp?: number;
  shouldIncludeFrom?: boolean;
  shouldIncludeTo?: boolean;
}): Promise<ApiTransaction[]> {
  const {
    network,
    address,
    limit,
    toTimestamp,
    fromTimestamp,
    shouldIncludeFrom,
    shouldIncludeTo,
  } = options;

  const data: {
    transactions: Transaction[];
    address_book: AddressBook;
  } = await callToncenterV3(network, '/transactions', {
    account: address,
    limit,
    start_utime: fromTimestamp && toSeconds(fromTimestamp) + (!shouldIncludeFrom ? 1 : 0),
    end_utime: toTimestamp && toSeconds(toTimestamp) - (!shouldIncludeTo ? 1 : 0),
    sort: 'desc',
  });

  const {
    transactions: rawTransactions,
    address_book: addressBook,
  } = data;

  if (!rawTransactions.length) {
    return [];
  }

  return parseRawTransactions(network, rawTransactions, addressBook)
    .flat()
    .map(({ body, ...tx }) => tx);
}

export function parseRawTransactions(network: ApiNetwork, rawTxs: Transaction[], addressBook: AddressBook) {
  return rawTxs.map((rawTx) => parseRawTransaction(network, rawTx, addressBook)).flat();
}

export function parseRawTransaction(
  network: ApiNetwork,
  rawTx: Transaction,
  addressBook: AddressBook,
): ApiTransactionExtended[] {
  const {
    now,
    hash,
    total_fees: totalFees,
    description: {
      compute_ph: {
        exit_code: exitCode,
      },
    },
  } = rawTx;

  const timestamp = now * 1000;
  const isIncoming = !!rawTx.in_msg.source && !rawTx.out_msgs.length;
  const inMsgHashNorm = rawTx.in_msg.hash_norm ?? rawTx.in_msg.hash;
  const msgs: TransactionMessage[] = isIncoming ? [rawTx.in_msg] : rawTx.out_msgs;

  if (!msgs.length) return [];

  const oneMsgFee = BigInt(totalFees) / BigInt(msgs.length);

  const transactions: ApiTransactionExtended[] = [];

  msgs.forEach((msg, i) => {
    const {
      source,
      destination,
      value,
      fwd_fee: fwdFee,
      opcode,
      hash: msgHash,
      bounced,
    } = msg;

    if (!destination) {
      // This is log
      return;
    }

    const fromAddress = addressBook[source!].user_friendly;
    const toAddress = addressBook[destination].user_friendly;
    const normalizedAddress = toBase64Address(isIncoming ? source! : destination, true, network);
    const fee = oneMsgFee + BigInt(fwdFee ?? 0);
    const body = getRawBody(msg);

    const tx: ApiTransactionExtended = omitUndefined({
      timestamp,
      isIncoming,
      fromAddress,
      toAddress,
      amount: isIncoming ? BigInt(value!) : -BigInt(value!),
      slug: TONCOIN.slug,
      fee,
      externalMsgHashNorm: isIncoming ? undefined : inMsgHashNorm,
      normalizedAddress,
      shouldHide: exitCode ? true : undefined,
      hash,
      opCode: Number(opcode) || undefined,
      msgHash,
      type: bounced ? 'bounced' : undefined,
      status: 'completed',
      body,
    });

    transactions.push(tx);
  });

  return transactions;
}

function getRawBody(msg: any): string | undefined {
  return msg.message_content?.body || undefined;
}

export async function fetchLatestTxLt(network: ApiNetwork, address: string): Promise<number | undefined> {
  const { transactions }: { transactions: any[] } = await callToncenterV3(network, '/transactions', {
    account: address,
    limit: 1,
    sort: 'desc',
  });

  if (!transactions.length) {
    return undefined;
  }

  return Number(transactions[0].lt);
}
