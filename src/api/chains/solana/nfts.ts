import type { Base58EncodedBytes } from '@solana/kit';

import type {
  ApiCheckTransactionDraftResult,
  ApiNetwork,
  ApiNft,
  ApiNftMetadata,
  ApiSubmitNftTransferResult,
} from '../../types';
import type {
  SolanaAssetProofRaw,
  SolanaSPLToken,
  SolanaSPLTokenByAddressRaw,
  SolanaSPLTokensByAddressRaw,
} from './types';

import { parseAccountId } from '../../../util/account';
import { getChainConfig } from '../../../util/chain';
import { fetchJson, fixIpfsUrl } from '../../../util/fetch';
import { compact, omitUndefined } from '../../../util/iteratees';
import { getSolanaClient } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { checkHasScamLink } from '../../common/addresses';
import { fetchAllPaginated, streamPaginated } from '../../common/pagination';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { NETWORK_CONFIG } from './constants';
import { buildTransaction, estimateTransactionFee, sendSignedTransaction } from './transfer';

export async function getAccountNfts(accountId: string, options?: {
  collectionAddress?: string;
  offset?: number;
  limit?: number;
}): Promise<ApiNft[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');

  if (options?.offset !== undefined || options?.limit !== undefined) {
    const rawNfts = await fetchAccountNfts(network, address, options);
    return parseNfts(rawNfts);
  }

  const { nftBatchLimit, nftBatchPauseMs } = getChainConfig('solana');
  const rawNfts = await fetchAllPaginated({
    batchLimit: nftBatchLimit!,
    pauseMs: nftBatchPauseMs!,
    fetchBatch: (cursor) => fetchAccountNfts(network, address, {
      collectionAddress: options?.collectionAddress,
      page: cursor + 1,
      limit: nftBatchLimit!,
    }),
  });

  return parseNfts(rawNfts);
}

export async function streamAllAccountNfts(accountId: string, options: {
  signal?: AbortSignal;
  onBatch: (nfts: ApiNft[]) => void;
}): Promise<void> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');

  const { nftBatchLimit, nftBatchPauseMs } = getChainConfig('solana');
  await streamPaginated({
    signal: options.signal,
    batchLimit: nftBatchLimit!,
    pauseMs: nftBatchPauseMs!,
    fetchBatch: (cursor) => fetchAccountNfts(network, address, {
      page: cursor + 1,
      limit: nftBatchLimit!,
    }),
    onBatch: (batch) => options.onBatch(parseNfts(batch)),
  });
}

export async function fetchAccountNfts(network: ApiNetwork, address: string, options?: {
  collectionAddress?: string;
  offset?: number;
  limit?: number;
  page?: number;
}) {
  const { collectionAddress, page = 1, limit = getChainConfig('solana').nftBatchLimit! } = options ?? {};

  const params = collectionAddress
    ? {
      ownerAddress: address,
      grouping: ['collection', collectionAddress],
      tokenType: 'nonFungible',
      burnt: false,
      page,
      limit,
      options: {
        showUnverifiedCollections: true,
        showCollectionMetadata: true,
        showInscription: false,
      },
    }
    : {
      ownerAddress: address,
      page,
      limit,
      options: {
        showUnverifiedCollections: true,
        showCollectionMetadata: true,
        showInscription: false,
      },
    };

  const request = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: collectionAddress ? 'searchAssets' : 'getAssetsByOwner',
      params,
    }),
  };

  const res = await fetchJson<SolanaSPLTokensByAddressRaw>(NETWORK_CONFIG[network].rpcUrl, undefined, request);

  return res.result.items;
}

export async function fetchNftByAddress(network: ApiNetwork, address: string) {
  const request = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'getAsset',
      params: {
        id: address,
        options: {
          showUnverifiedCollections: true,
          showCollectionMetadata: true,
          showFungible: false,
          showInscription: false,
        },
      },
    }),
  };

  const res = await fetchJson<SolanaSPLTokenByAddressRaw>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    request,
  );

  return parseHeliusNft(res.result);
}

export async function fetchNftsByAddresses(network: ApiNetwork, addresses: string[]) {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'getAssetBatch',
      params: {
        ids: addresses,
        options: {
          showUnverifiedCollections: true,
          showCollectionMetadata: true,
          showInscription: false,
          showFungible: true,
        },
      },
    }),
  };

  const { result: assets } = await fetchJson<{ result: SolanaSPLToken[] }>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    options,
  );

  return assets.map((e) => parseHeliusNft(e));
}

function parseHeliusNft(rawNft: SolanaSPLToken): ApiNft {
  const collection = rawNft.grouping.find((e) => e.group_key === 'collection');
  const { name: collectionName } = collection?.collection_metadata || {};

  let nftInterface: ApiNft['interface'] = 'default';

  if (rawNft.compression.compressed) {
    nftInterface = 'compressed';
  }
  if (rawNft.interface === 'MplCoreAsset') {
    nftInterface = 'mplCore';
  }

  const { owner, delegated } = rawNft.ownership;
  const { files, metadata: { name, description, attributes } } = rawNft.content;

  const imageUrl = fixIpfsUrl(files?.[0]?.uri || files?.[0]?.cdn_uri || '');

  let hasScamLink = false;

  if (!collection?.group_value) {
    for (const text of [name, description].filter(Boolean)) {
      if (checkHasScamLink(text)) {
        hasScamLink = true;
      }
    }
  }

  const isScam = hasScamLink || description === 'SCAM';

  const metadata: ApiNftMetadata = {
    attributes,
  };

  const compression = rawNft.compression.compressed ? {
    tree: rawNft.compression.tree,
    dataHash: rawNft.compression.data_hash,
    creatorHash: rawNft.compression.creator_hash,
    leafId: rawNft.compression.leaf_id,
  } : undefined;

  return omitUndefined<ApiNft>({
    chain: 'solana',
    interface: nftInterface,
    index: 1,
    name,
    ownerAddress: owner,
    address: rawNft.id,
    image: imageUrl,
    thumbnail: imageUrl,
    isOnSale: delegated,
    isHidden: isScam,
    isScam,
    description,
    ...(collection && {
      collectionAddress: collection.group_value,
      collectionName,
    }),
    metadata,
    compression,
  });
}

function parseNfts(rawNfts: SolanaSPLToken[]) {
  return compact(rawNfts.filter((e) => !e.burnt).map((rawNft) => parseHeliusNft(rawNft)));
}

export async function getAssetProof(network: ApiNetwork, nftAddress: string) {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'getAssetProof',
      params: {
        id: nftAddress,
      },
    }),
  };
  const response = await fetchJson<SolanaAssetProofRaw>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    options,
  );

  return response.result;
}

export async function checkNftTransferDraft(options: {
  accountId: string;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
  isNftBurn?: boolean;
}): Promise<ApiCheckTransactionDraftResult> {
  const { accountId, nfts, comment, isNftBurn } = options;
  const { toAddress } = options;

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredChainAccount(accountId, 'solana');
  const { address: fromAddress } = account.byChain.solana;

  const client = getSolanaClient(network);

  const tx = await buildTransaction(client, network, {
    type: 'simulation',
    amount: 0n,
    nfts,
    source: fromAddress,
    destination: toAddress,
    payload: comment ? { type: 'comment', text: comment } : undefined,
    isNftBurn,
  });

  const fee = await estimateTransactionFee(client, { network, serializedB64Transaction: tx });

  return {
    fee,
    resolvedAddress: toAddress,
  };
}

export async function submitNftTransfers(options: {
  accountId: string;
  password: string | undefined;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
  isNftBurn?: boolean;
}): Promise<ApiSubmitNftTransferResult> {
  const {
    accountId, password = '', nfts, toAddress, comment, isNftBurn,
  } = options;

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredChainAccount(accountId, 'solana');

  if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
  if (account.type === 'view') throw new Error('Not supported by View accounts');

  const privateKey = (await fetchPrivateKeyString(accountId, password, account))!;
  const signer = getSignerFromPrivateKey(network, privateKey);

  const client = getSolanaClient(network);

  const tx = await buildTransaction(client, network, {
    type: 'real',
    amount: 0n,
    nfts,
    signer,
    destination: toAddress,
    payload: comment ? { type: 'comment', text: comment } : undefined,
    isNftBurn,
  });

  const result = await sendSignedTransaction(tx as Base58EncodedBytes, network);

  return {
    msgHashNormalized: result,
    transfers: nfts.map(() => ({ toAddress })),
  };
}

export async function checkNftOwnership(accountId: string, nftAddress: string) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');
  const nft = await fetchNftByAddress(network, nftAddress);

  return address === nft.ownerAddress;
}
