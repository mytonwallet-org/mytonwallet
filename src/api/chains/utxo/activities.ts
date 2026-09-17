import type {
  ApiActivity,
  ApiFetchActivitySliceOptions,
  ApiNetwork,
  ApiTransactionActivity,
  UTXOChain,
} from '../../types';
import type { UtxoAddressInfo, UtxoTransaction } from './types';

import { parseAccountId } from '../../../util/account';
import { getIsActivityPending } from '../../../util/activities';
import { sortActivities } from '../../../util/activities/order';
import { fetchJson } from '../../../util/fetch';
import { getNativeToken } from '../../../util/tokens';
import { fetchStoredWallet } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { SEC } from '../../constants';
import { isSameUtxoAddress, normalizeAddress, toUtxoApiAddress } from './address';
import { UTXO_REST_ACTIVITY_MAX_CONFIRMATIONS_FALLBACK, UTXO_RPC_URLS } from './constants';

const INDEXER_PAGE_SIZE = 100;
const MAX_COLLECTED_PAGES = 20;

export async function fetchActivitySlice(
  chain: UTXOChain,
  {
    accountId,
    tokenSlug,
    toTimestamp,
    fromTimestamp,
    limit,
  }: ApiFetchActivitySliceOptions,
): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, chain);
  const nativeTokenSlug = getNativeToken(chain).slug;

  if (tokenSlug && tokenSlug !== nativeTokenSlug) {
    return [];
  }

  const { activities } = await getTokenActivitySlice(
    chain,
    network,
    address,
    toTimestamp,
    fromTimestamp,
    limit,
  );

  return activities;
}

export async function getTokenActivitySlice(
  chain: UTXOChain,
  network: ApiNetwork,
  address: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
): Promise<{ activities: ApiActivity[]; hasMore: boolean }> {
  const pageSize = limit ?? INDEXER_PAGE_SIZE;
  const collected: ApiActivity[] = [];
  let page = 1;
  let totalPages = 1;
  let reachedOlderThanFrom = false;
  let collectedPages = 0;

  while (collected.length < pageSize && page <= totalPages) {
    const { transactions, page: currentPage, totalPages: reportedPages } = await fetchAddressTransactions(
      chain,
      network,
      address,
      { page, pageSize: INDEXER_PAGE_SIZE },
    );

    totalPages = reportedPages;
    page = currentPage + 1;

    const pageActivities = sortActivities(
      transactions
        .map((tx) => parseUtxoTransaction(chain, network, address, tx))
        .filter((activity) => !activity.shouldHide),
    );
    const oldestOnPage = pageActivities[pageActivities.length - 1];
    const isPageEntirelyNewer = toTimestamp !== undefined
      && oldestOnPage !== undefined
      && oldestOnPage.timestamp >= toTimestamp;

    for (const activity of pageActivities) {
      // Pending transactions must be restored even when their mempool timestamp predates the confirmed cursor.
      if (fromTimestamp !== undefined && activity.timestamp <= fromTimestamp && !getIsActivityPending(activity)) {
        reachedOlderThanFrom = true;
        continue;
      }

      if (toTimestamp !== undefined && activity.timestamp >= toTimestamp) {
        continue;
      }

      collected.push(activity);
    }

    if (reachedOlderThanFrom) {
      break;
    }

    if (!transactions.length) {
      break;
    }

    // Pages that are still newer than the pagination cursor are skipped, not counted.
    if (!isPageEntirelyNewer) {
      collectedPages += 1;
      if (collectedPages >= MAX_COLLECTED_PAGES) {
        break;
      }
    }
  }

  const activities = sortActivities(collected).slice(0, pageSize);
  const hasMore = collected.length > pageSize
    || (activities.length === pageSize && page <= totalPages && !reachedOlderThanFrom);

  return { activities, hasMore };
}

async function fetchAddressTransactions(
  chain: UTXOChain,
  network: ApiNetwork,
  address: string,
  options: {
    page: number;
    pageSize: number;
  },
) {
  const endpoint = UTXO_RPC_URLS[network](chain);
  const apiAddress = toUtxoApiAddress(chain, network, address);
  const response = await fetchJson<UtxoAddressInfo>(`${endpoint}/api/v2/address/${apiAddress}`, {
    page: options.page,
    pageSize: options.pageSize,
    details: 'txs',
  });

  const transactions = response.transactions ?? await Promise.all(
    (response.txids ?? []).map(async (txId) => (
      fetchJson<UtxoTransaction>(`${UTXO_RPC_URLS[network](chain)}/api/v2/tx/${txId}`)
    )),
  );

  return {
    transactions,
    page: response.page ?? options.page,
    totalPages: response.totalPages ?? 1,
  };
}

export function parseUtxoTransaction(
  chain: UTXOChain,
  network: ApiNetwork,
  walletAddress: string,
  tx: UtxoTransaction,
): ApiTransactionActivity {
  const timestamp = (tx.blockTime ?? 0) * SEC;
  const fee = BigInt(tx.fees ?? '0');
  const isIncoming = getIsIncoming(chain, network, walletAddress, tx);
  const transferAmount = getTransferAmount(chain, network, walletAddress, tx, isIncoming);
  const counterparty = normalizeAddress(
    chain,
    getCounterpartyAddress(chain, network, walletAddress, tx, isIncoming),
    network,
  );
  const activityAddress = normalizeAddress(chain, walletAddress, network);
  const confirmations = tx.confirmations ?? 0;
  const status = getUtxoActivityStatus(confirmations);

  return {
    kind: 'transaction',
    id: tx.txid,
    timestamp,
    amount: isIncoming ? transferAmount : -transferAmount,
    fee,
    slug: getNativeToken(chain).slug,
    fromAddress: isIncoming ? counterparty : activityAddress,
    toAddress: isIncoming ? activityAddress : counterparty,
    isIncoming,
    normalizedAddress: activityAddress,
    status,
    confirmations,
    maxConfirmations: UTXO_REST_ACTIVITY_MAX_CONFIRMATIONS_FALLBACK,
    metadata: getKnownAddressInfo(counterparty),
    shouldHide: transferAmount === 0n && !isIncoming,
  };
}

export function getUtxoActivityStatus(confirmations: number): ApiTransactionActivity['status'] {
  return confirmations >= UTXO_REST_ACTIVITY_MAX_CONFIRMATIONS_FALLBACK ? 'completed' : 'pending';
}

function hasWalletAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  walletAddress: string,
  addresses?: string[],
) {
  return Boolean(addresses?.some((address) => isSameUtxoAddress(chain, network, walletAddress, address)));
}

function getIsIncoming(
  chain: UTXOChain,
  network: ApiNetwork,
  walletAddress: string,
  tx: UtxoTransaction,
) {
  const received = tx.vout
    .filter((output) => hasWalletAddress(chain, network, walletAddress, output.addresses))
    .reduce((sum, output) => sum + BigInt(output.value), 0n);

  const sent = tx.vin
    .filter((input) => hasWalletAddress(chain, network, walletAddress, input.addresses))
    .reduce((sum, input) => sum + BigInt(input.value ?? '0'), 0n);

  return received > sent;
}

function getTransferAmount(
  chain: UTXOChain,
  network: ApiNetwork,
  walletAddress: string,
  tx: UtxoTransaction,
  isIncoming: boolean,
) {
  if (isIncoming) {
    return tx.vout
      .filter((output) => hasWalletAddress(chain, network, walletAddress, output.addresses))
      .reduce((sum, output) => sum + BigInt(output.value), 0n);
  }

  const change = tx.vout
    .filter((output) => hasWalletAddress(chain, network, walletAddress, output.addresses))
    .reduce((sum, output) => sum + BigInt(output.value), 0n);

  const externalOut = tx.vout
    .filter((output) => !hasWalletAddress(chain, network, walletAddress, output.addresses))
    .reduce((sum, output) => sum + BigInt(output.value), 0n);

  if (externalOut > 0n) {
    return externalOut;
  }

  // Blockbook `value` is the sum of all outputs; subtract change to get the sent amount.
  if (tx.value) {
    const totalOut = BigInt(tx.value);
    if (totalOut > change) {
      return totalOut - change;
    }
  }

  const fee = BigInt(tx.fees ?? '0');
  const sent = tx.vin
    .filter((input) => hasWalletAddress(chain, network, walletAddress, input.addresses))
    .reduce((sum, input) => sum + BigInt(input.value ?? '0'), 0n);

  if (sent > change + fee) {
    return sent - change - fee;
  }

  if (tx.valueIn) {
    const valueIn = BigInt(tx.valueIn);
    if (valueIn > change + fee) {
      return valueIn - change - fee;
    }
  }

  return 0n;
}

function getCounterpartyAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  walletAddress: string,
  tx: UtxoTransaction,
  isIncoming: boolean,
) {
  if (isIncoming) {
    const sender = tx.vin.find((input) => input.addresses?.length)?.addresses?.[0];
    return sender ?? walletAddress;
  }

  const recipient = tx.vout.find(
    (output) => !hasWalletAddress(chain, network, walletAddress, output.addresses),
  )?.addresses?.[0];
  return recipient ?? walletAddress;
}

export async function fetchActivityDetails(
  chain: UTXOChain,
  accountId: string,
  activity: ApiActivity,
): Promise<ApiActivity | undefined> {
  const nativeTokenSlug = getNativeToken(chain).slug;

  if (activity.kind !== 'transaction' || activity.slug !== nativeTokenSlug) {
    return undefined;
  }

  const { network } = parseAccountId(accountId);
  const txId = activity.id;

  const endpoint = UTXO_RPC_URLS[network](chain);
  const tx = await fetchJson<UtxoTransaction>(`${endpoint}/api/v2/tx/${txId}`);

  const { address } = await fetchStoredWallet(accountId, chain);
  const parsed = parseUtxoTransaction(chain, network, address, tx);

  if (parsed.fee === activity.fee && parsed.status === activity.status) {
    return undefined;
  }

  return {
    ...activity,
    fee: parsed.fee,
    status: parsed.status,
    timestamp: parsed.timestamp || activity.timestamp,
  };
}

export async function getAllActivitySlice(
  chain: UTXOChain,
  network: ApiNetwork,
  address: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  return getTokenActivitySlice(chain, network, address, toTimestamp, fromTimestamp, limit);
}
