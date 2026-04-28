import { getAddress } from 'ethers';

import type { ApiActivity, ApiFetchActivitySliceOptions, ApiNetwork, EVMChain } from '../../types';
import type { ZerionNftTransfer, ZerionTokenTransfer, ZerionTransaction, ZerionTransactionsResponse } from './types';

import { parseAccountId } from '../../../util/account';
import { getChainConfig, getIsSupportedChain } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { fetchJson } from '../../../util/fetch';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { getEvmProvider } from './util/client';
import { updateTokensMetadataByAddress } from './util/metadata';
import { getZerionFungibleImplementation, getZerionFungibleTokenSlug } from './util/tokens';
import { fetchStoredWallet } from '../../common/accounts';
import { updateActivityMetadata } from '../../common/helpers';
import { getTokenBySlug } from '../../common/tokens';
import { SEC } from '../../constants';
import { getApiChainByZerionChain, getEvmApiUrl, getZerionChainByApiChain } from './constants';

export async function fetchActivitySlice(
  chain: EVMChain,
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

  const { activities } = await getTokenActivitySlice(
    chain,
    network,
    address,
    tokenSlug,
    toTimestamp,
    fromTimestamp,
    limit,
  );

  return activities;
}

export async function getTokenActivitySlice(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  slug?: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
  isCrossChain?: boolean,
): Promise<{ activities: ApiActivity[]; hasMore: boolean }> {
  const checksumAddress = getAddress(address);

  const txs = await fetchEvmTxs({
    chain,
    network,
    address: checksumAddress,
    slug,
    toTimestamp,
    fromTimestamp,
    limit,
    isCrossChain,
  });

  // hasMore is computed from the raw API response length, not the post-transform `activities`.
  // `transformEvmTxToUnified` returns undefined for unsupported tx shapes, and `compact` drops
  // those - so a length check on the returned activities would underreport remaining pages.
  const hasMore = limit !== undefined && txs.length >= limit;

  if (isCrossChain) {
    await collectCrossChainTokensFromTransactions(network, address, txs);

    const activities = compact(txs.map((tx) => {
      const txChain = getZerionTransactionChain(tx);

      return txChain ? transformEvmTxToUnified(txChain, tx, address) : undefined;
    }));

    return { activities, hasMore };
  }

  await collectTokensFromTransactions(network, chain, address, txs);

  const activities = compact(txs.map((tx) => transformEvmTxToUnified(chain, tx, address)));

  return { activities, hasMore };
}

export async function fetchEvmTxs(options: {
  chain: EVMChain;
  network: ApiNetwork;
  address: string;
  slug?: string;
  toTimestamp?: number;
  fromTimestamp?: number;
  limit?: number;
  isCrossChain?: boolean;
  hash?: string;
}) {
  const { chain, network, address, slug, toTimestamp, fromTimestamp, limit, isCrossChain, hash } = options;

  const tokenAddress = slug
    ? (slug === getChainConfig(chain).nativeToken.slug || slug === 'eth')
      ? undefined
      : getTokenBySlug(slug)?.tokenAddress
    : undefined;
  const zerionChain = getZerionChainByApiChain(chain);

  const params = {
    'filter[min_mined_at]': fromTimestamp ? fromTimestamp + SEC : undefined,
    'filter[max_mined_at]': toTimestamp ? toTimestamp - SEC : undefined,
    'page[size]': limit,
    'filter[chain_ids]': isCrossChain ? undefined : zerionChain,
    'filter[fungible_implementations]': tokenAddress ? `${zerionChain}:${tokenAddress.toLowerCase()}` : undefined,
    'filter[search_query]': hash,
  };

  const data = await fetchJson<ZerionTransactionsResponse>(
    `${getEvmApiUrl(network)}/v1/wallets/${address}/transactions/`,
    params,
  );

  return data.data;
}

export async function parseEvmTx(
  chain: EVMChain,
  network: ApiNetwork,
  hash: string,
): Promise<ZerionTransaction | undefined> {
  // We nned to get unparsed tx from node first
  const transfer = await getEvmProvider(network, chain).getTransaction(hash);

  if (!transfer) {
    return undefined;
  }

  // Then get it parsed by participant address & hash from Zerion
  const tx = await fetchEvmTxs({ chain, network, hash, address: transfer.from });

  if (!tx.length) {
    return undefined;
  }

  return tx[0];
}

export async function collectTokensFromTransactions(
  network: ApiNetwork,
  chain: EVMChain,
  address: string,
  rawTxs: ZerionTransaction[],
) {
  const addresses = new Set<string>();
  const zerionChain = getZerionChainByApiChain(chain);

  for (const tx of rawTxs) {
    if (tx.attributes.transfers.length) {
      for (const transfer of tx.attributes.transfers) {
        if ('fungible_info' in transfer && !tx.attributes.flags.is_trash) {
          const implementation = getZerionFungibleImplementation(transfer.fungible_info, zerionChain);

          if (implementation?.address) {
            addresses.add(implementation.address);
          }
        }
      }
    }
  }

  await updateTokensMetadataByAddress(network, chain, [...addresses]);
}

async function collectCrossChainTokensFromTransactions(
  network: ApiNetwork,
  address: string,
  rawTxs: ZerionTransaction[],
) {
  const txsByChain = new Map<EVMChain, ZerionTransaction[]>();

  for (const tx of rawTxs) {
    const chain = getZerionTransactionChain(tx);

    if (!chain) {
      continue;
    }

    const chainTxs = txsByChain.get(chain) ?? [];
    chainTxs.push(tx);
    txsByChain.set(chain, chainTxs);
  }

  await Promise.all(
    [...txsByChain.entries()].map(([chain, txs]) => collectTokensFromTransactions(network, chain, address, txs)),
  );
}

function getZerionTransactionChain(tx: ZerionTransaction) {
  const chain = getApiChainByZerionChain(tx.relationships.chain.data.id);

  if (!getIsSupportedChain(chain) || getChainConfig(chain).chainStandard !== 'ethereum') {
    logDebugError('getZerionTransactionChain', 'Unsupported chain', { chain });

    return undefined;
  }

  return chain;
}

export async function fetchCrossChainActivitySlice(options: {
  accountId: string;
  tokenSlug?: string;
  toTimestamp?: number;
  fromTimestamp?: number;
  limit?: number;
}): Promise<ApiActivity[]> {
  const { accountId, tokenSlug, toTimestamp, fromTimestamp, limit } = options;

  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ethereum');

  const { activities } = await getTokenActivitySlice(
    'ethereum', network, address, tokenSlug, toTimestamp, fromTimestamp, limit, true,
  );

  return activities;
}

function transformUnknownTx(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: tx.attributes.sent_from,
    toAddress: tx.attributes.sent_to,
    amount: 0n,
    slug: getChainConfig(chain).nativeToken.slug,
    isIncoming: tx.attributes.sent_from !== address,
    normalizedAddress: address,
    fee: BigInt(tx.attributes.fee.quantity.int),
    type: 'callContract',
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.attributes.hash,
  });
}

function transformEvmSwap(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  const nativeToken = getChainConfig(chain).nativeToken;
  const zerionChain = getZerionChainByApiChain(chain);

  const inAsset = tx.attributes.transfers.find((e) =>
    e.direction === 'in'
    && 'fungible_info' in e
    && getAddress(e.recipient) === address,
  ) as ZerionTokenTransfer
  || undefined;

  const outAsset = tx.attributes.transfers.find((e) =>
    e.direction === 'out'
    && 'fungible_info' in e
    && getAddress(e.sender) === address,
  ) as ZerionTokenTransfer
  || undefined;

  if (!inAsset || !outAsset) {
    return transformUnknownTx(chain, tx, address);
  }

  const inTokenSlug = getZerionFungibleTokenSlug(chain, zerionChain, inAsset.fungible_info);
  const outTokenSlug = getZerionFungibleTokenSlug(chain, zerionChain, outAsset.fungible_info);

  const inToken = inTokenSlug === nativeToken.slug
    ? nativeToken
    : inTokenSlug ? getTokenBySlug(inTokenSlug) : undefined;

  const outToken = outTokenSlug === nativeToken.slug
    ? nativeToken
    : outTokenSlug ? getTokenBySlug(outTokenSlug) : undefined;

  if (!inToken || !outToken) {
    return transformUnknownTx(chain, tx, address);
  }

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'swap',
    comment: undefined,
    fromAddress: address,
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    from: outToken.slug,
    fromAmount: toDecimal(BigInt(outAsset.quantity.int || 0), outToken.decimals),
    to: inToken.slug,
    toAmount: toDecimal(BigInt(inAsset.quantity.int || 0), inToken.decimals),
    networkFee: tx.attributes.fee.quantity.int,
    swapFee: '0',
    status: 'completed',
    hashes: [],
    externalMsgHashNorm: tx.attributes.hash,
  });
}

function transformEvmTransfer(
  chain: EVMChain,
  tx: ZerionTransaction,
  transfer: ZerionTokenTransfer,
  address: string,
): ApiActivity {
  if (tx.attributes.flags.is_trash) {
    return transformUnknownTx(chain, tx, address);
  }

  const slug = getZerionFungibleTokenSlug(chain, getZerionChainByApiChain(chain), transfer.fungible_info);
  if (!slug) {
    return transformUnknownTx(chain, tx, address);
  }

  const isIncoming = transfer.direction === 'in';

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: transfer.sender.toLowerCase(),
    toAddress: transfer.recipient.toLowerCase(),
    amount: isIncoming ? BigInt(transfer.quantity.int) : -BigInt(transfer.quantity.int),
    slug,
    isIncoming,
    normalizedAddress: address.toLowerCase(),
    fee: BigInt(tx.attributes.fee.quantity.int),
    status: 'completed',
  });
}

function transformEvmNftTransfer(
  chain: EVMChain,
  transfer: ZerionNftTransfer,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: transfer.sender.toLowerCase(),
    toAddress: transfer.recipient.toLowerCase(),
    amount: 0n,
    slug: getChainConfig(chain).nativeToken.slug,
    isIncoming: transfer.direction === 'in',
    normalizedAddress: address.toLowerCase(),
    fee: BigInt(tx.attributes.fee.quantity.int),
    status: 'completed',
    nft: {
      chain,
      index: 0,
      address: transfer.nft_info.contract_address,
      image: transfer.nft_info.content?.preview?.url || '',
      thumbnail: transfer.nft_info.content?.preview?.url || '',
      name: transfer.nft_info.name,
      description: '',
      isOnSale: false,
      metadata: {
        attributes: [],
      },
      interface: 'default',
    },
  });
}

export function transformEvmTxToUnified(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  address = getAddress(address);

  if (tx.attributes.transfers.length > 1) {
    try {
      return transformEvmSwap(chain, tx, address);
    } catch (error) {
      // Fallback
    }
  }

  const transfer = tx.attributes.transfers.find((e) =>
    e.direction === 'in'
      ? getAddress(e.recipient) === address
      : getAddress(e.sender) === address,
  );

  if (!transfer) {
    return transformUnknownTx(chain, tx, address);
  }

  const isNftTransfer = 'nft_info' in transfer;

  if (isNftTransfer) {
    return transformEvmNftTransfer(chain, transfer, tx, address);
  }

  return transformEvmTransfer(chain, tx, transfer, address);
}

export function fetchActivityDetails() {
  return undefined;
}
