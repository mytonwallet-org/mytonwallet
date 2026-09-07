import { TronWeb } from 'tronweb';

import type { ApiActivity, ApiFetchActivitySliceOptions, ApiNetwork, ApiTransactionActivity } from '../../types';
import type { TronTrc20Transaction } from './types';
import { TronContractMethodSignature } from './types';

import { TRX } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { mergeSortedActivities, sortActivities } from '../../../util/activities/order';
import { fetchJson } from '../../../util/fetch';
import isEmptyObject from '../../../util/isEmptyObject';
import { buildCollectionByKey, compact } from '../../../util/iteratees';
import { getTokenSlugs } from './util/tokens';
import { fetchStoredWallet } from '../../common/accounts';
import { updateActivityMetadata } from '../../common/helpers';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';
import { SEC } from '../../constants';
import { NETWORK_CONFIG } from './constants';

const MAX_UINT256 = 2n ** 256n - 1n;

export async function fetchActivitySlice({
  accountId,
  tokenSlug,
  toTimestamp,
  fromTimestamp,
  limit,
  signal,
}: ApiFetchActivitySliceOptions): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'tron');

  if (tokenSlug) {
    const { activities } = await getTokenActivitySlice(
      network,
      address,
      tokenSlug,
      toTimestamp,
      fromTimestamp,
      limit,
      signal,
    );
    return activities;
  } else {
    return getAllActivitySlice(
      network,
      address,
      toTimestamp,
      fromTimestamp,
      limit,
      signal,
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
  signal?: AbortSignal,
): Promise<{ activities: ApiActivity[]; hasMore: boolean }> {
  let activities: ApiActivity[];
  let rawCount: number;

  if (slug === TRX.slug) {
    const rawTransactions = await getTrxTransactions(network, address, {
      min_timestamp: fromTimestamp ? fromTimestamp + SEC : undefined,
      max_timestamp: toTimestamp ? toTimestamp - SEC : undefined,
      limit,
      search_internal: false, // The parsing is not supported and not needed currently
    }, signal);
    rawCount = rawTransactions.length;
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
    }, signal);
    rawCount = rawTransactions.length;
    activities = parseRawTrc20Transactions(address, rawTransactions);
  }

  // `hasMore` is derived from the raw API response length before activity filtering, so cursor-style pagination keeps
  // advancing through pages containing only hidden or unsupported records.
  const hasMore = limit !== undefined && rawCount >= limit;

  // Even though the activities returned by the Tron API are sorted by timestamp, our sorting may differ.
  // It's important to enforce our sorting, because otherwise `mergeSortedActivities` may leave duplicates.
  return { activities: sortActivities(activities), hasMore };
}

async function getAllActivitySlice(
  network: ApiNetwork,
  address: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
  signal?: AbortSignal,
) {
  const tokenSlugs = getTokenSlugs(network);
  const txsBySlug: Record<string, ApiActivity[]> = {};

  await Promise.all(tokenSlugs.map(async (slug) => {
    const { activities: txs } = await getTokenActivitySlice(
      network, address, slug, toTimestamp, fromTimestamp, limit, signal,
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
  signal?: AbortSignal,
): Promise<any[]> {
  const baseUrl = NETWORK_CONFIG[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions`);

  const result = await fetchJson(url.toString(), queryParams, { signal });

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
  signal?: AbortSignal,
): Promise<TronTrc20Transaction[]> {
  const baseUrl = NETWORK_CONFIG[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions/trc20`);

  const result = await fetchJson(url.toString(), queryParams, { signal });

  return result.data;
}

export function parseRawTrc20Transactions(
  address: string,
  rawTransactions: readonly TronTrc20Transaction[],
): ApiTransactionActivity[] {
  const activities = compact(rawTransactions.map((rawTx) => parseRawTrc20Transaction(address, rawTx)));
  return selectPrimaryTrc20Activities(activities);
}

export function parseRawTrc20Transaction(
  address: string,
  rawTx: TronTrc20Transaction,
): ApiTransactionActivity | undefined {
  if (rawTx.type !== 'Transfer' && rawTx.type !== 'Approval') return undefined;

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
  const isApproval = rawTx.type === 'Approval';
  const normalizedAddress = isIncoming ? fromAddress : toAddress;
  const fee = 0n;

  return updateActivityMetadata({
    id: txId,
    kind: 'transaction',
    timestamp,
    fromAddress,
    toAddress,
    amount: isApproval || isIncoming ? amount : -amount,
    slug,
    isIncoming,
    normalizedAddress,
    fee,
    type: isApproval ? 'approval' : undefined,
    isApprovalUnlimited: isApproval ? amount === MAX_UINT256 : undefined,
    status: 'completed',
  });
}

function selectPrimaryTrc20Activities<T extends ApiActivity>(activities: readonly T[]): T[] {
  const activitiesById = new Map<string, T>();

  activities.forEach((activity) => {
    const current = activitiesById.get(activity.id);
    // A balance-changing event represents the primary activity when the same transaction also updates an allowance
    if (!current || (isApprovalActivity(current) && !isApprovalActivity(activity))) {
      activitiesById.set(activity.id, activity);
    }
  });

  return Array.from(activitiesById.values());
}

function isApprovalActivity(activity: ApiActivity) {
  return activity.kind === 'transaction' && activity.type === 'approval';
}

export function mergeActivities(txsBySlug: Record<string, ApiActivity[]>): ApiActivity[] {
  const {
    [TRX.slug]: trxTxs = [],
    ...tokenTxs
  } = txsBySlug;

  const trxTxById = buildCollectionByKey(trxTxs, 'id');
  const primaryTokenTxs = sortActivities(selectPrimaryTrc20Activities(Object.values(tokenTxs).flat()))
    .map((tokenTx) => {
      const trxTx = trxTxById[tokenTx.id];
      if (tokenTx.kind === 'transaction' && trxTx?.kind === 'transaction') {
        tokenTx.fee = trxTx.fee;
      }
      return tokenTx;
    });
  const tokenTxIds = new Set(primaryTokenTxs.map(({ id }) => id));

  return mergeSortedActivities(
    primaryTokenTxs,
    trxTxs.filter(
      (trxTx) => !tokenTxIds.has(trxTx.id)
        && !trxTx.shouldHide
        && (trxTx.kind !== 'transaction' || trxTx.toAddress),
    ),
  );
}

export function fetchActivityDetails() {
  return undefined;
}
