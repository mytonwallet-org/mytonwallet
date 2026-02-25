import { TronWeb } from 'tronweb';

import type { ApiActivity, ApiFetchActivitySliceOptions, ApiNetwork, ApiTransactionActivity } from '../../types';
import { TronContractMethodSignature } from './types';

import { TRX } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { mergeSortedActivities, sortActivities } from '../../../util/activities/order';
import { fetchJson } from '../../../util/fetch';
import isEmptyObject from '../../../util/isEmptyObject';
import { buildCollectionByKey } from '../../../util/iteratees';
import { getTokenSlugs } from './util/tokens';
import { fetchStoredWallet } from '../../common/accounts';
import { updateActivityMetadata } from '../../common/helpers';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';
import { SEC } from '../../constants';
import { NETWORK_CONFIG } from './constants';

export async function fetchActivitySlice({
  accountId,
  tokenSlug,
  toTimestamp,
  fromTimestamp,
  limit,
}: ApiFetchActivitySliceOptions): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'tron');

  if (tokenSlug) {
    return getTokenActivitySlice(
      network,
      address,
      tokenSlug,
      toTimestamp,
      fromTimestamp,
      limit,
    );
  } else {
    return getAllActivitySlice(
      network,
      address,
      toTimestamp,
      fromTimestamp,
      limit,
    );
  }
}

export async function getTokenActivitySlice(
  network: ApiNetwork,
  address: string,
  slug: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  let activities: ApiActivity[];

  if (slug === TRX.slug) {
    const rawTransactions = await getTrxTransactions(network, address, {
      min_timestamp: fromTimestamp ? fromTimestamp + SEC : undefined,
      max_timestamp: toTimestamp ? toTimestamp - SEC : undefined,
      limit,
      search_internal: false, // The parsing is not supported and not needed currently
    });
    activities = rawTransactions
      .map((rawTx) => parseRawTrxTransaction(address, rawTx))
      .filter((activity) => !activity.shouldHide);
  } else {
    const { tokenAddress } = getTokenBySlug(slug) || {};
    const rawTransactions = await getTrc20Transactions(network, address, {
      contract_address: tokenAddress,
      min_timestamp: fromTimestamp ? fromTimestamp + SEC : undefined,
      max_timestamp: toTimestamp ? toTimestamp - SEC : undefined,
      limit,
    });
    activities = rawTransactions.map((rawTx) => parseRawTrc20Transaction(address, rawTx));
  }

  // Even though the activities returned by the Tron API are sorted by timestamp, our sorting may differ.
  // It's important to enforce our sorting, because otherwise `mergeSortedActivities` may leave duplicates.
  return sortActivities(activities);
}

async function getAllActivitySlice(
  network: ApiNetwork,
  address: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  const tokenSlugs = getTokenSlugs(network);
  const txsBySlug: Record<string, ApiActivity[]> = {};

  await Promise.all(tokenSlugs.map(async (slug) => {
    const txs = await getTokenActivitySlice(
      network, address, slug, toTimestamp, fromTimestamp, limit,
    );

    if (txs.length) {
      txsBySlug[slug] = txs;
    }
  }));

  if (isEmptyObject(txsBySlug)) {
    return [];
  }

  // TODO Нужно, чтобы чанки всегда именли "все транзакции", так как это всё работает только при корректной работе лимита.
  // А только потом должна быть очистка от ненужных транзакций.
  const mainChunk = Object.values(txsBySlug).reduce((prevChunk, chunk) => {
    if (prevChunk.length > chunk.length) return prevChunk;
    if (prevChunk.length < chunk.length) return chunk;
    if (prevChunk[prevChunk.length - 1].timestamp < chunk[chunk.length - 1].timestamp) return chunk;
    return prevChunk;
  }, [] as ApiTransactionActivity[]);

  const oldestTimestamp = mainChunk[mainChunk.length - 1].timestamp;

  return mergeActivities(txsBySlug)
    .filter(({ timestamp }) => timestamp >= oldestTimestamp);
}

async function getTrxTransactions(
  network: ApiNetwork,
  address: string,
  queryParams: {
    only_confirmed?: boolean;
    only_unconfirmed?: boolean;
    only_to?: boolean;
    only_from?: boolean;
    limit?: number;
    fingerprint?: string;
    order_by?: 'block_timestamp,asc' | 'block_timestamp,desc';
    min_timestamp?: number;
    max_timestamp?: number;
    search_internal?: boolean;
  } = {},
): Promise<any[]> {
  const baseUrl = NETWORK_CONFIG[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions`);

  const result = await fetchJson(url.toString(), queryParams);

  return result.data;
}

function isTokenTransferTransaction(rawTx: any): boolean {
  const rawData = rawTx.raw_data;
  if (!rawData?.contract?.[0]) return false;

  const contract = rawData.contract[0];
  if (contract.type !== 'TriggerSmartContract') return false;

  const data = contract.parameter?.value?.data;
  if (!data) return false;

  return data.startsWith(TronContractMethodSignature.Transfer)
    || data.startsWith(TronContractMethodSignature.TransferFrom);
}

export function parseRawTrxTransaction(address: string, rawTx: any): ApiTransactionActivity {
  const {
    raw_data: rawData,
    txID: txId,
    block_timestamp: timestamp,
  } = rawTx;

  const parameters = rawData.contract[0].parameter.value;
  const amount = BigInt(parameters.amount ?? 0);
  const fromAddress = TronWeb.address.fromHex(parameters.owner_address);
  const toAddress = TronWeb.address.fromHex(
    parameters.to_address || parameters.receiver_address || parameters.contract_address,
  );

  const slug = TRX.slug;
  const isIncoming = toAddress === address;
  const normalizedAddress = isIncoming ? fromAddress : toAddress;
  const fee = BigInt(rawTx.ret?.[0].fee ?? 0);
  const type = rawData.contract[0].type === 'TriggerSmartContract' ? 'callContract' : undefined;
  const shouldHide = rawData.contract[0].type === 'TransferAssetContract' || isTokenTransferTransaction(rawTx);

  return updateActivityMetadata({
    id: txId,
    kind: 'transaction',
    timestamp,
    fromAddress,
    toAddress,
    amount: isIncoming ? amount : -amount,
    slug,
    isIncoming,
    normalizedAddress,
    fee,
    type,
    shouldHide,
    status: 'completed',
  });
}

export async function getTrc20Transactions(
  network: ApiNetwork,
  address: string,
  queryParams: {
    only_confirmed?: boolean;
    only_unconfirmed?: boolean;
    limit?: number;
    fingerprint?: string;
    order_by?: 'block_timestamp,asc' | 'block_timestamp,desc';
    min_timestamp?: number;
    max_timestamp?: number;
    contract_address?: string;
    only_to?: boolean;
    only_from?: boolean;
  } = {},
): Promise<any[]> {
  const baseUrl = NETWORK_CONFIG[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions/trc20`);

  const result = await fetchJson(url.toString(), queryParams);

  return result.data;
}

export function parseRawTrc20Transaction(address: string, rawTx: any): ApiTransactionActivity {
  const {
    transaction_id: txId,
    block_timestamp: timestamp,
    from: fromAddress,
    to: toAddress,
    value,
    token_info: tokenInfo,
  } = rawTx;

  const amount = BigInt(value);
  const slug = buildTokenSlug(TRX.chain, tokenInfo.address);
  const isIncoming = toAddress === address;
  const normalizedAddress = isIncoming ? fromAddress : toAddress;
  const fee = 0n;

  return updateActivityMetadata({
    id: txId,
    kind: 'transaction',
    timestamp,
    fromAddress,
    toAddress,
    amount: isIncoming ? amount : -amount,
    slug,
    isIncoming,
    normalizedAddress,
    fee,
    status: 'completed',
  });
}

export function mergeActivities(txsBySlug: Record<string, ApiActivity[]>): ApiActivity[] {
  const seenTxIds = new Set<string>();
  const isSeenTxId = (id: string) => {
    if (seenTxIds.has(id)) return true;
    seenTxIds.add(id);
    return false;
  };

  const {
    [TRX.slug]: trxTxs = [],
    ...tokenTxs
  } = txsBySlug;

  const trxTxById = buildCollectionByKey(trxTxs, 'id');

  return mergeSortedActivities(
    ...Object.values(tokenTxs).map((tokenTxList) =>
      tokenTxList
        // Different tokens have the same transaction id if they share the same backend swap.
        // The duplicates need to removed.
        .filter((tokenTx) => !isSeenTxId(tokenTx.id))
        .map((tokenTx) => {
          const trxTx = trxTxById[tokenTx.id];
          if (tokenTx.kind === 'transaction' && trxTx?.kind === 'transaction') {
            tokenTx.fee = trxTx.fee;
          }
          return tokenTx;
        }),
    ),
    // Because of `isSeenTxId`, it's necessary to filter the TRX transactions after the token transactions
    trxTxs.filter(
      (trxTx) => !isSeenTxId(trxTx.id) && !trxTx.shouldHide && (trxTx.kind !== 'transaction' || trxTx.toAddress),
    ),
  );
}

export function fetchActivityDetails() {
  return undefined;
}
