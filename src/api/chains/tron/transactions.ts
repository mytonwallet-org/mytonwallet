import { TronWeb } from 'tronweb';

import type { ApiActivity, ApiNetwork, ApiTransactionActivity } from '../../types';

import { TRX } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { mergeSortedActivities } from '../../../util/activities/order';
import { getChainConfig } from '../../../util/chain';
import { fetchJson } from '../../../util/fetch';
import { buildCollectionByKey } from '../../../util/iteratees';
import { getTokenSlugs } from './util/tokens';
import { fetchStoredTronWallet } from '../../common/accounts';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';

export async function getTokenTransactionSlice(
  accountId: string,
  slug: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredTronWallet(accountId);

  if (slug === TRX.slug) {
    const rawTransactions = await getTrxTransactions(network, address, {
      min_timestamp: fromTimestamp ? fromTimestamp + 1000 : undefined,
      max_timestamp: toTimestamp ? toTimestamp - 1000 : undefined,
      limit,
      search_internal: false, // The parsing is not supported and not needed currently
    });
    return rawTransactions.map((rawTx) => parseRawTrxTransaction(address, rawTx)).filter(Boolean);
  } else {
    const { tokenAddress } = getTokenBySlug(slug);
    const rawTransactions = await getTrc20Transactions(network, address, {
      contract_address: tokenAddress,
      min_timestamp: fromTimestamp ? fromTimestamp + 1000 : undefined,
      max_timestamp: toTimestamp ? toTimestamp - 1000 : undefined,
      limit,
    });
    return rawTransactions.map((rawTx) => parseRawTrc20Transaction(address, rawTx));
  }
}

export async function getAllTransactionSlice(accountId: string, toTimestamp: number | undefined, limit: number) {
  const { network } = parseAccountId(accountId);
  const tokenSlugs = getTokenSlugs(network);

  const chunks = (await Promise.all([
    getTokenTransactionSlice(accountId, TRX.slug, toTimestamp, undefined, limit),
    ...tokenSlugs.map((slug) => getTokenTransactionSlice(
      accountId, slug, toTimestamp, undefined, limit,
    )),
  ])).filter((chunk) => chunk.length);

  if (!chunks.length) {
    return [];
  }

  // TODO Нужно, чтобы чанки всегда именли "все транзакции", так как это всё работает только при корректной работе лимита.
  // А только потом должна быть очистка от ненужных транзакций.
  const mainChunk = chunks.reduce((prevChunk, chunk) => {
    if (prevChunk.length > chunk.length) return prevChunk;
    if (prevChunk.length < chunk.length) return chunk;
    if (prevChunk[prevChunk.length - 1].timestamp < chunk[chunk.length - 1].timestamp) return chunk;
    return prevChunk;
  }, [] as ApiTransactionActivity[]);

  const fromTimestamp = mainChunk[mainChunk.length - 1].timestamp;

  const [trxChunk, ...tokenChunks] = chunks;

  return mergeActivities(trxChunk, ...tokenChunks)
    .filter(({ timestamp }) => timestamp >= fromTimestamp);
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
  const baseUrl = getChainConfig('tron')[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions`);

  const result = await fetchJson(url.toString(), queryParams);

  return result.data;
}

function parseRawTrxTransaction(address: string, rawTx: any): ApiTransactionActivity | undefined {
  const {
    raw_data: rawData,
    txID: txId,
    energy_fee: energyFee,
    net_fee: netFee,
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
  const fee = BigInt(energyFee + netFee);
  const type = rawData.contract[0].type === 'TriggerSmartContract' ? 'callContract' : undefined;
  const shouldHide = rawData.contract[0].type === 'TransferAssetContract';

  return {
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
  };
}

async function getTrc20Transactions(
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
  const baseUrl = getChainConfig('tron')[network].apiUrl;
  const url = new URL(`${baseUrl}/v1/accounts/${address}/transactions/trc20`);

  const result = await fetchJson(url.toString(), queryParams);

  return result.data;
}

function parseRawTrc20Transaction(address: string, rawTx: any): ApiTransactionActivity {
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

  return {
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
  };
}

export function mergeActivities(trxTxs: ApiActivity[], ...tokenTxs: ApiActivity[][]): ApiActivity[] {
  const seenTxIds = new Set<string>();
  const isSeenTxId = (id: string) => {
    if (seenTxIds.has(id)) return true;
    seenTxIds.add(id);
    return false;
  };

  const trxTxById = buildCollectionByKey(trxTxs, 'id');
  let result: ApiActivity[] = [];

  for (const tokenTxList of tokenTxs) {
    result = mergeSortedActivities(
      result,
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
    );
  }

  return mergeSortedActivities(
    result,
    trxTxs.filter((trxTx) => !isSeenTxId(trxTx.id) && (trxTx.kind !== 'transaction' || trxTx.toAddress)),
  );
}
