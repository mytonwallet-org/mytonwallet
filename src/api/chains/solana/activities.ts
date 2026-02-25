import type {
  ApiActivity,
  ApiFetchActivitySliceOptions,
  ApiNetwork,
  ApiNft,
} from '../../types';
import type { SolanaParsedTransaction } from './types';

import { SOLANA } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { mergeSortedActivities, sortActivities } from '../../../util/activities/order';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { fetchJson } from '../../../util/fetch';
import isEmptyObject from '../../../util/isEmptyObject';
import { updateTokensMetadataByAddress } from './util/metadata';
import { parseTxComment } from './util/programParsers';
import { fetchStoredWallet } from '../../common/accounts';
import { updateActivityMetadata } from '../../common/helpers';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';
import { SEC } from '../../constants';
import { NETWORK_CONFIG, WSOL_MINT } from './constants';
import { fetchNftsByAddresses } from './nfts';

export async function fetchActivitySlice({
  accountId,
  tokenSlug,
  toTimestamp,
  fromTimestamp,
  limit,
}: ApiFetchActivitySliceOptions): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');

  if (tokenSlug) {
    return getTokenActivitySlice(network, address, tokenSlug, toTimestamp, fromTimestamp, limit);
  } else {
    return getAllActivitySlice(network, address, toTimestamp, fromTimestamp, limit);
  }
}

export async function getTokenActivitySlice(
  network: ApiNetwork,
  address: string,
  slug?: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  let activities: ApiActivity[] = [];

  let rawTransactions: SolanaParsedTransaction[] = [];

  const options = {
    min_timestamp: fromTimestamp ? fromTimestamp + SEC : undefined,
    max_timestamp: toTimestamp ? toTimestamp - SEC : undefined,
    limit,
    search_internal: false,
  };

  if (!slug) {
    rawTransactions = await fetchSolTxs(network, address, true, options);
  }

  if (slug === SOLANA.slug) {
    rawTransactions = await fetchSolTxs(network, address, false, options);
  }

  if (slug && slug !== SOLANA.slug) {
    const token = getTokenBySlug(slug);

    if (token?.tokenWalletAddress && token.tokenAddress) {
      rawTransactions = await fetchSolTxs(network, token.tokenWalletAddress, false, options);
    }
  }

  const [, nfts] = await Promise.all([
    collectTokensFromTransactions(network, address, rawTransactions),
    collectNftsFromTransactions(network, address, rawTransactions),
  ]);

  activities = rawTransactions
    .map((e) => transformSolanaTxToUnified(address, e, nfts))
    .filter(Boolean);

  return sortActivities(activities);
}

async function getAllActivitySlice(
  network: ApiNetwork,
  address: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
) {
  const txsBySlug: Record<string, ApiActivity[]> = {};

  const txs = await getTokenActivitySlice(network, address, undefined, toTimestamp, fromTimestamp, limit);
  for (const tx of txs) {
    if (tx.kind === 'transaction') {
      txsBySlug[tx.slug] = [...(txsBySlug[tx.slug] || []), tx];
    } else {
      txsBySlug[tx.from] = [...(txsBySlug[tx.from] || []), tx];
      txsBySlug[tx.to] = [...(txsBySlug[tx.to] || []), tx];
    }
  }

  if (isEmptyObject(txsBySlug)) {
    return [];
  }

  return mergeSortedActivities(...Object.values(txsBySlug));
}

async function fetchSolTxs(
  network: ApiNetwork,
  address: string,
  withTokens?: boolean,
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
) {
  const params = {
    'sort-order': queryParams.order_by === 'block_timestamp,asc'
      ? 'asc'
      : queryParams.order_by === 'block_timestamp,desc'
        ? 'desc'
        : undefined,
    limit: queryParams.limit,
    commitment: 'confirmed',
    'token-accounts': withTokens ? 'balanceChanged' : undefined,
    'gte-time': queryParams.min_timestamp ? queryParams.min_timestamp / 1000 : undefined,
    'lte-time': queryParams.max_timestamp ? queryParams.max_timestamp / 1000 : undefined,
  };

  // Use non-standard Helius API to retrieve parsed txs by 1 call and with timestamp filtering
  const response = await fetchJson<SolanaParsedTransaction[]>(
    NETWORK_CONFIG[network].getApiUrl(`/v0/addresses/${address}/transactions`),
    params,
  );

  return response;
}

export async function parseSolTx(
  network: ApiNetwork,
  signature: string,
): Promise<SolanaParsedTransaction | undefined> {
  const url = NETWORK_CONFIG[network].getApiUrl('/v0/transactions');

  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      transactions: [signature],
    }),
  };

  const response = await fetchJson<SolanaParsedTransaction[]>(url, undefined, options);

  return response[0];
}

export async function collectTokensFromTransactions(
  network: ApiNetwork,
  address: string,
  rawTxs: SolanaParsedTransaction[],
) {
  const addresses = new Set<string>();
  for (const tx of rawTxs) {
    if (tx.tokenTransfers && tx.tokenTransfers.length) {
      for (const transfer of tx.tokenTransfers) {
        if ([transfer.fromUserAccount, transfer.toUserAccount].includes(address)) {
          addresses.add(transfer.mint);
        }
      }
    }
  }
  await updateTokensMetadataByAddress(network, [...addresses]);
}

export async function collectNftsFromTransactions(
  network: ApiNetwork,
  address: string,
  rawTxs: SolanaParsedTransaction[],
) {
  const addresses = new Set<string>();

  for (const tx of rawTxs) {
    if (tx.events.compressed) {
      for (const event of tx.events.compressed) {
        if ([event.oldLeafOwner, event.newLeafOwner].includes(address)) {
          addresses.add(event.assetId);
        }
      }
    }
    if (tx.events.nft?.nfts.length) {
      for (const nft of tx.events.nft.nfts) {
        addresses.add(nft.mint);
      }
    }
    if (tx.tokenTransfers.length) {
      for (const transfer of tx.tokenTransfers) {
        if (transfer.tokenStandard !== 'Fungible'
          && [transfer.fromUserAccount, transfer.toUserAccount].includes(address)
        ) {
          addresses.add(transfer.mint);
        }
      }
    }
  }
  if (addresses.size) {
    const nfts = await fetchNftsByAddresses(network, [...addresses]);
    return nfts;
  }
  return [];
}

function transformParsedSwap(
  address: string,
  tx: SolanaParsedTransaction,
  comment: string | undefined,
) {
  const { tokenInputs, nativeInput, tokenOutputs, nativeOutput } = tx.events.swap!;

  const fromAsset = tokenInputs.length
    ? {
      asset: buildTokenSlug('solana', tokenInputs[0].mint),
      amount: toDecimal(
        BigInt(tokenInputs[0].rawTokenAmount.tokenAmount),
        tokenInputs[0].rawTokenAmount.decimals,
      ),
    }
    : {
      asset: SOLANA.slug,
      amount: toDecimal(BigInt(nativeInput?.amount || 0), SOLANA.decimals),
    };

  const toAsset = tokenOutputs.length
    ? {
      asset: buildTokenSlug('solana', tokenOutputs[0].mint),
      amount: toDecimal(
        BigInt(tokenOutputs[0].rawTokenAmount.tokenAmount),
        tokenOutputs[0].rawTokenAmount.decimals,
      ),
    }
    : {
      asset: SOLANA.slug,
      amount: toDecimal(BigInt(nativeOutput?.amount || 0), SOLANA.decimals),
    };

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'swap',
    comment,
    fromAddress: address,
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    from: fromAsset.asset,
    fromAmount: fromAsset.amount,
    to: toAsset.asset,
    toAmount: toAsset.amount,
    networkFee: toDecimal(BigInt(tx.fee), SOLANA.decimals),
    swapFee: '0',
    status: 'completed',
    hashes: [],
    externalMsgHashNorm: tx.signature,
  });
}

function transformParsedCNFTOperation(
  address: string,
  tx: SolanaParsedTransaction,
  nfts: ApiNft[],
  comment: string | undefined,
) {
  const { newLeafOwner, oldLeafOwner, assetId } = tx.events.compressed![0];

  const nft: ApiNft | undefined = nfts.find((e) => e.address === assetId);

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'transaction',
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    comment,
    // These fields are nullish in case of NFT burn
    fromAddress: oldLeafOwner || '',
    toAddress: newLeafOwner || '',
    amount: 0n,
    slug: SOLANA.slug,
    isIncoming: newLeafOwner === address,
    normalizedAddress: address,
    fee: BigInt(tx.fee),
    nft,
    type: tx.type === 'COMPRESSED_NFT_BURN' ? 'burn' : undefined,
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.signature,
  });
}

function transformUnparsedSwap(
  address: string,
  tx: SolanaParsedTransaction,
  comment: string | undefined,
) {
  const resultAssets = new Map<string, number>();

  tx.tokenTransfers
    .filter((e) => e.toUserAccount === address)
    .forEach((e) => {
      e.mint = e.mint === WSOL_MINT ? SOLANA.slug : buildTokenSlug('solana', e.mint);
      if (!resultAssets.has(e.mint)) {
        resultAssets.set(e.mint, 0);
      }
      const current = resultAssets.get(e.mint)!;
      resultAssets.set(e.mint, current + e.tokenAmount);
    });

  tx.tokenTransfers
    .filter((e) => e.fromUserAccount === address)
    .forEach((e) => {
      e.mint = e.mint === WSOL_MINT ? SOLANA.slug : buildTokenSlug('solana', e.mint);
      if (!resultAssets.has(e.mint)) {
        resultAssets.set(e.mint, 0);
      }
      const current = resultAssets.get(e.mint)!;
      resultAssets.set(e.mint, current - e.tokenAmount);
    });

  const sent = [...resultAssets].find((e) => e[1] < 0)!;
  const received = [...resultAssets].find((e) => e[1] > 0)!;

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'swap',
    comment,
    fromAddress: address,
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    from: sent[0],
    fromAmount: String(sent[1]),
    to: received[0],
    toAmount: String(received[1]),
    networkFee: toDecimal(BigInt(tx.fee), SOLANA.decimals),
    swapFee: '0',
    status: 'completed',
    hashes: [],
    externalMsgHashNorm: tx.signature,
  });
}

function transformSimpleTransfer(
  address: string,
  tx: SolanaParsedTransaction,
  comment: string | undefined,
) {
  const inTransfer = tx.nativeTransfers.find((e) => e.toUserAccount === address);
  const outTransfer = tx.nativeTransfers.find((e) => e.fromUserAccount === address);

  const fromAddress = inTransfer ? inTransfer.fromUserAccount : outTransfer!.fromUserAccount;
  const toAddress = inTransfer ? inTransfer.toUserAccount : outTransfer!.toUserAccount;

  const isIncoming = toAddress === address;
  const amount = BigInt(inTransfer?.amount || outTransfer?.amount || 0);

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'transaction',
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    comment,
    fromAddress,
    toAddress,
    amount: isIncoming ? amount : -amount,
    slug: SOLANA.slug,
    isIncoming,
    normalizedAddress: address,
    fee: BigInt(tx.fee),
    nft: undefined,
    type: undefined,
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.signature,
  });
}

function transformTokenTransfer(
  address: string,
  tx: SolanaParsedTransaction,
  comment: string | undefined,
) {
  const inTransfer = tx.tokenTransfers.find((e) => e.toUserAccount === address);
  const outTransfer = tx.tokenTransfers.find((e) => e.fromUserAccount === address);

  const fromAddress = inTransfer ? inTransfer.fromUserAccount : outTransfer!.fromUserAccount;
  const toAddress = inTransfer ? inTransfer.toUserAccount : outTransfer!.toUserAccount;

  const asset = getTokenBySlug(buildTokenSlug('solana', inTransfer?.mint || outTransfer?.mint || '')) || SOLANA;

  const isIncoming = toAddress === address;
  const amount = fromDecimal(inTransfer?.tokenAmount || outTransfer?.tokenAmount || 0, asset.decimals);

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'transaction',
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    comment,
    fromAddress,
    toAddress,
    amount: isIncoming ? amount : -amount,
    slug: asset.slug,
    isIncoming,
    normalizedAddress: address,
    fee: BigInt(tx.fee),
    nft: undefined,
    type: undefined,
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.signature,
  });
}

function transformUnparsedNFTTransfer(
  address: string,
  tx: SolanaParsedTransaction,
  nfts: ApiNft[],
  comment: string | undefined,
) {
  const inTransfer = tx.tokenTransfers.find((e) => e.toUserAccount === address);
  const outTransfer = tx.tokenTransfers.find((e) => e.fromUserAccount === address);

  const fromAddress = inTransfer ? inTransfer.fromUserAccount : outTransfer!.fromUserAccount;
  const toAddress = inTransfer ? inTransfer.toUserAccount : outTransfer!.toUserAccount;

  const nft: ApiNft | undefined = nfts.find((e) => e.address === (inTransfer?.mint || outTransfer?.mint || ''));

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'transaction',
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    comment,
    fromAddress,
    toAddress,
    amount: 0n,
    slug: SOLANA.slug,
    isIncoming: toAddress === address,
    normalizedAddress: address,
    fee: BigInt(tx.fee),
    nft,
    type: undefined,
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.signature,
  });
}

export function transformSolanaTxToUnified(
  address: string,
  tx: SolanaParsedTransaction,
  nfts: ApiNft[],
): ApiActivity {
  const comment = parseTxComment(tx);

  if (tx.events.swap) {
    try {
      return transformParsedSwap(address, tx, comment);
    } catch (error) {
      // Fallback
    }
  }

  if (tx.events.compressed) {
    try {
      return transformParsedCNFTOperation(address, tx, nfts, comment);
    } catch (error) {
      // Fallback
    }
  }

  if (['UNKNOWN', 'SWAP'].includes(tx.type) && tx.tokenTransfers.length) {
    try {
      return transformUnparsedSwap(address, tx, comment);
    } catch (error) {
      // Fallback
    }
  }

  if (tx.type === 'TRANSFER') {
    if (tx.nativeTransfers.length && !tx.tokenTransfers.length) {
      try {
        return transformSimpleTransfer(address, tx, comment);
      } catch (error) {
        // Fallback
      }
    }

    if (tx.tokenTransfers.length) {
      try {
        return transformTokenTransfer(address, tx, comment);
      } catch (error) {
        // Fallback
      }
    }

    if (tx.tokenTransfers.length && tx.tokenTransfers.find((e) => e.tokenStandard !== 'Fungible')) {
      try {
        return transformUnparsedNFTTransfer(address, tx, nfts, comment);
      } catch (error) {
        // Fallback
      }
    }
  }

  const fromAddress = tx.feePayer;

  return updateActivityMetadata({
    id: tx.signature,
    kind: 'transaction',
    timestamp: Number(tx.timestamp ?? 0) * 1000,
    comment,
    fromAddress,
    toAddress: fromAddress !== address ? address : tx.instructions.at(-1)!.programId,
    amount: 0n,
    slug: SOLANA.slug,
    isIncoming: fromAddress !== address,
    normalizedAddress: address,
    fee: BigInt(tx.fee),
    type: 'callContract',
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.signature,
  });
}

export function fetchActivityDetails() {
  return undefined;
}
