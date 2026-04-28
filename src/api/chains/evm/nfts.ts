import type {
  ApiCheckTransactionDraftResult,
  ApiNetwork,
  ApiNft,
  ApiNftMetadata,
  ApiSubmitNftTransferResult,
  EVMChain,
} from '../../types';
import type { AlchemyNftsForOwnerResponse, AlchemyOwnedNft } from './types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { getChainConfig } from '../../../util/chain';
import { explainApiTransferFee } from '../../../util/fee/transferFee';
import { fetchJson } from '../../../util/fetch';
import { compact, omitUndefined } from '../../../util/iteratees';
import { logDebug, logDebugError } from '../../../util/logs';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { checkHasScamLink } from '../../common/addresses';
import { handleServerError } from '../../errors';
import { isValidAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { EVM_RPC_URLS } from './constants';
import { buildTransaction, estimateEvmFee } from './transfer';
import { getIsWalletActive, getWalletBalance } from './wallet';

type AlchemyNftMetadataResponse = Omit<AlchemyOwnedNft, 'balance'>;

const EVM_NFT_PAGE_SIZE = 100;

export async function getAccountNfts(
  chain: EVMChain,
  accountId: string,
  options?: {
    collectionAddress?: string;
    offset?: number;
    limit?: number;
  },
): Promise<ApiNft[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, chain);

  if (options?.offset !== undefined || options?.limit !== undefined) {
    const result = await fetchNftsPage(chain, network, address, {
      contractAddresses: options?.collectionAddress ? [options.collectionAddress] : undefined,
      pageSize: options?.limit,
    });
    return parseNfts(result.ownedNfts, chain, address);
  }

  return fetchAllNfts(chain, network, address, options?.collectionAddress);
}

export async function streamAllAccountNfts(
  chain: EVMChain,
  accountId: string,
  options: {
    signal?: AbortSignal;
    onBatch: (nfts: ApiNft[]) => void;
    ignorePreCheck?: boolean;
    onPreCheckResult?: (isActive: boolean) => void;
  },
): Promise<void> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, chain);

  if (!options.ignorePreCheck) {
    const isActive = await getIsWalletActive(network, chain, address);

    options.onPreCheckResult?.(isActive);

    if (!isActive) {
      logDebug('streamAllAccountNfts EVM: wallet is inactive, skip polling', chain, address);
      return;
    }
  }

  let pageKey: string | undefined;
  do {
    if (options.signal?.aborted) break;

    const result = await fetchNftsPage(chain, network, address, { pageKey });

    if (options.signal?.aborted) break;

    const nfts = parseNfts(result.ownedNfts, chain, address);

    if (nfts.length) {
      options.onBatch(nfts);
    }

    pageKey = result.pageKey ?? undefined;
  } while (pageKey);
}

export async function fetchNftByAddress(
  chain: EVMChain,
  network: ApiNetwork,
  contractAddress: string,
  tokenId: string,
  ownerAddress: string,
): Promise<ApiNft> {
  const nftApiUrl = `${EVM_RPC_URLS[network](chain)}/nft/v3/getNFTMetadata`;

  const raw = await fetchJson<AlchemyNftMetadataResponse>(nftApiUrl, {
    contractAddress,
    tokenId,
  });

  return parseAlchemyNft({ ...raw, balance: '0' }, chain, ownerAddress);
}

async function fetchAllNfts(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  collectionAddress?: string,
): Promise<ApiNft[]> {
  const all: ApiNft[] = [];
  let pageKey: string | undefined;

  do {
    const result = await fetchNftsPage(chain, network, address, {
      contractAddresses: collectionAddress ? [collectionAddress] : undefined,
      pageKey,
    });

    all.push(...parseNfts(result.ownedNfts, chain, address));
    pageKey = result.pageKey ?? undefined;
  } while (pageKey);

  return all;
}

async function fetchNftsPage(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  options?: {
    contractAddresses?: string[];
    pageSize?: number;
    pageKey?: string;
  },
): Promise<AlchemyNftsForOwnerResponse> {
  const params: Record<string, string | number | boolean | string[] | undefined> = {
    owner: address,
    withMetadata: true,
    pageSize: options?.pageSize ?? EVM_NFT_PAGE_SIZE,
  };

  if (options?.contractAddresses?.length) {
    params['contractAddresses[]'] = options.contractAddresses;
  }

  if (options?.pageKey) {
    params.pageKey = options.pageKey;
  }

  const nftApiUrl = `${EVM_RPC_URLS[network](chain)}/nft/v3/getNFTsForOwner`;

  return fetchJson<AlchemyNftsForOwnerResponse>(nftApiUrl, params);
}

function parseAlchemyNft(rawNft: AlchemyOwnedNft, chain: EVMChain, ownerAddress: string): ApiNft {
  const { contract, tokenId, name, description, image, raw } = rawNft;

  const imageUrl = image.cachedUrl || image.originalUrl || '';
  const thumbnailUrl = image.thumbnailUrl || imageUrl;

  let isScam = false;
  for (const text of [name, description].filter(Boolean)) {
    if (checkHasScamLink(text)) {
      isScam = true;
      break;
    }
  }

  const metadata: ApiNftMetadata = {
    attributes: raw?.metadata?.attributes,
  };

  return omitUndefined<ApiNft>({
    chain,
    interface: contract.tokenType,
    index: 1,
    name,
    ownerAddress,
    address: `${contract.address}/${tokenId}`,
    image: imageUrl,
    thumbnail: thumbnailUrl,
    isOnSale: false,
    isHidden: isScam,
    isScam,
    description,
    collectionAddress: contract.address,
    collectionName: contract.name,
    metadata,
  });
}

function parseNfts(rawNfts: AlchemyOwnedNft[], chain: EVMChain, ownerAddress: string): ApiNft[] {
  return compact(rawNfts.map((nft) => parseAlchemyNft(nft, chain, ownerAddress)));
}

export async function checkNftTransferDraft(
  chain: EVMChain,
  options: {
    accountId: string;
    nfts: ApiNft[];
    toAddress: string;
    comment?: string;
    isNftBurn?: boolean;
  },
): Promise<ApiCheckTransactionDraftResult> {
  const { accountId, nfts, toAddress } = options;
  const { network } = parseAccountId(accountId);

  const result: ApiCheckTransactionDraftResult = {};

  if (nfts.length > 1) {
    logDebugError(`evm:${chain}:checkNftTransferDraft: multiple NFTs are not supported`, nfts);

    return { error: ApiCommonError.Unexpected };
  }

  try {
    if (!isValidAddress(toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    const nft = nfts[0];

    result.resolvedAddress = toAddress;

    const { address: fromAddress } = await fetchStoredWallet(accountId, chain);
    const provider = getEvmProvider(network, chain);

    const transaction = buildTransaction({ from: fromAddress, to: toAddress, amount: 0n, nft });

    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, fromAddress),
      estimateEvmFee(provider, transaction),
    ]);

    const nativeTokenSlug = getChainConfig(chain).nativeToken.slug;

    result.explainedFee = explainApiTransferFee({
      fee,
      realFee: fee,
      tokenSlug: nativeTokenSlug,
    });

    if (nativeBalance < fee) {
      result.error = ApiTransactionDraftError.InsufficientBalance;
    }

    return result;
  } catch (err) {
    logDebugError(`evm:${chain}:checkNftTransferDraft`, err);

    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

export async function submitNftTransfers(
  chain: EVMChain,
  options: {
    accountId: string;
    password: string | undefined;
    nfts: ApiNft[];
    toAddress: string;
    comment?: string;
    isNftBurn?: boolean;
  },
): Promise<ApiSubmitNftTransferResult> {
  const { accountId, password = '', nfts, toAddress } = options;
  const { network } = parseAccountId(accountId);

  if (nfts.length > 1) {
    logDebugError(`evm:${chain}:submitNftTransfers: multiple NFTs are not supported`, nfts);

    return { error: ApiCommonError.Unexpected };
  }

  try {
    const nft = nfts[0];

    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address: fromAddress } = account.byChain[chain];
    const provider = getEvmProvider(network, chain);

    const privateKey = await fetchPrivateKeyString(chain, accountId, password, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);

    const transaction = buildTransaction({ from: fromAddress, to: toAddress, amount: 0n, nft });
    const response = await signer.sendTransaction(transaction);

    return {
      msgHashNormalized: response.hash,
      transfers: [{ toAddress }],
    };
  } catch (err) {
    logDebugError(`evm:${chain}:submitNftTransfers`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function checkNftOwnership(chain: EVMChain, accountId: string, nftAddress: string) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, chain);

  const [contractAddress, tokenId] = nftAddress.split('/');

  if (!contractAddress || !tokenId) {
    throw new Error(`checkNftOwnership:${chain}: invalid NFT address ${nftAddress}`);
  }

  const nft = await fetchNftByAddress(chain, network, contractAddress, tokenId, address);

  return address === nft.ownerAddress;
}
