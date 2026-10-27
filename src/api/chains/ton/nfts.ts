import type { Cell } from '@ton/core';
import { Address, Builder } from '@ton/core';

import type {
  ApiCheckTransactionDraftResult,
  ApiNetwork,
  ApiNft,
  ApiNftSuperCollection,
  ApiNftTransfer,
  ApiNftUpdate,
  ApiSubmitNftTransferResult,
} from '../../types';
import { ApiCommonError, ApiTransactionDraftError } from '../../types';

import {
  BURN_ADDRESS,
  NFT_BATCH_SIZE,
  NOTCOIN_EXCHANGERS,
  NOTCOIN_FORWARD_TON_AMOUNT,
  NOTCOIN_VOUCHERS_ADDRESS,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../config';
import { parseAccountId } from '../../../util/account';
import { getChainConfig } from '../../../util/chain';
import { explainApiTransferFee } from '../../../util/fee/transferFee';
import { compact, split } from '../../../util/iteratees';
import { logDebug, logDebugError } from '../../../util/logs';
import { getNativeToken } from '../../../util/tokens';
import { getMaxMessagesInTransaction } from '../../../util/ton/transfer';
import { generateQueryId } from './util';
import { getSigner } from './util/signer';
import { commentToBytes, packBytesAsSnakeCell, storeInlineOrRefCell, toBase64Address } from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { fetchAllPaginated, streamPaginated } from '../../common/pagination';
import { parseToncenterNft } from './toncenter/actions';
import { fetchNftItems, fetchNftTransfers, parseNftItem, parseNftItems } from './toncenter/nfts';
import {
  NFT_PAYLOAD_SAFE_MARGIN,
  NFT_TRANSFER_AMOUNT,
  NFT_TRANSFER_FORWARD_AMOUNT,
  NFT_TRANSFER_REAL_AMOUNT,
  NftOpCode,
} from './constants';
import {
  checkMultiTransactionDraft, checkToAddress, resolveTransactionError, submitMultiTransferWithMfa,
} from './transfer';
import { isActiveNonWalletContract } from './wallet';

const NFT_TRANSFER_BATCH_SIZE = 100;

export async function getAccountNfts(accountId: string, options?: {
  collectionAddress?: string;
  offset?: number;
  limit?: number;
}): Promise<ApiNft[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  // The super collection is an abstraction of ours, so it has no address the indexer would accept
  if (options?.collectionAddress === TELEGRAM_GIFTS_SUPER_COLLECTION) return [];

  if (options?.offset !== undefined || options?.limit !== undefined) {
    const response = await fetchNftItems(network, { ownerAddress: address, ...options });
    return compact(parseNftItems(network, response, nftSuperCollectionsByCollectionAddress));
  }

  const { nftBatchLimit, nftBatchPauseMs } = getChainConfig('ton');
  const nfts = await fetchAllPaginated({
    batchLimit: nftBatchLimit!,
    pauseMs: nftBatchPauseMs!,
    fetchBatch: (cursor) => fetchNftItems(network, {
      ownerAddress: address,
      collectionAddress: options?.collectionAddress,
      offset: cursor * nftBatchLimit!,
      limit: nftBatchLimit!,
    }).then((response) => parseNftItems(network, response, nftSuperCollectionsByCollectionAddress)),
  });

  return compact(nfts);
}

export async function streamAllAccountNfts(accountId: string, options: {
  signal?: AbortSignal;
  onBatch: (nfts: ApiNft[]) => void;
}): Promise<void> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const { nftBatchLimit, nftBatchPauseMs } = getChainConfig('ton');
  await streamPaginated({
    signal: options.signal,
    batchLimit: nftBatchLimit!,
    pauseMs: nftBatchPauseMs!,
    fetchBatch: (cursor) => fetchNftItems(network, {
      ownerAddress: address,
      offset: cursor * nftBatchLimit!,
      limit: nftBatchLimit!,
    }).then((response) => parseNftItems(network, response, nftSuperCollectionsByCollectionAddress)),
    onBatch: (batch) => options.onBatch(compact(batch)),
  });
}

export async function checkNftOwnership(accountId: string, nftAddress: string) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  return Boolean(await fetchOwnedNft(network, address, nftAddress, nftSuperCollectionsByCollectionAddress));
}

export async function getNftUpdates(accountId: string, fromSec: number) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const { nft_transfers: transfers, metadata } = await fetchNftTransfers(network, {
    ownerAddress: address,
    startUtime: fromSec,
    limit: NFT_TRANSFER_BATCH_SIZE,
  });

  // The response is sorted from the newest to the oldest
  fromSec = transfers[0]?.transaction_now ?? fromSec;
  const updates: ApiNftUpdate[] = [];

  for (const transfer of transfers.slice().reverse()) {
    const nftAddress = toBase64Address(transfer.nft_address, true, network);
    const newOwnerAddress = toBase64Address(transfer.new_owner, false, network);

    if (Address.parse(newOwnerAddress).equals(Address.parse(address))) {
      const { nft } = parseToncenterNft(
        network,
        metadata,
        transfer.nft_address,
        nftSuperCollectionsByCollectionAddress,
        {
          rawCollectionAddress: transfer.nft_collection ?? undefined,
          // `/nft/transfers` reports no ownership, but the check above has just confirmed that this
          // transfer handed the NFT to our wallet
          ownerAddress: address,
        },
      );

      if (nft) {
        updates.push({ type: 'nftReceived', accountId, nftAddress, nft });
      }
    } else if (await isActiveNonWalletContract(network, newOwnerAddress)) {
      // A finished sale never hits this branch: its transfer goes from the sale contract to the
      // buyer, so the `owner_address` filter does not return it for the seller at all. The seller's
      // gallery catches up on the next full reload instead.
      //
      // `startUtime` is inclusive, so every round returns the newest transfer again, and the listing keeps
      // coming after the NFT has been sold. That is why the NFT is taken from its current state, and only
      // while our wallet still owns it.
      const nft = await fetchOwnedNft(network, address, nftAddress, nftSuperCollectionsByCollectionAddress);

      updates.push({ type: 'nftPutUpForSale', accountId, nftAddress, nft });
    } else {
      updates.push({
        type: 'nftSent',
        accountId,
        chain: 'ton',
        nftAddress,
        newOwnerAddress,
      });
    }
  }

  return [fromSec, updates] as [number, ApiNftUpdate[]];
}

/** Returns the current state of the NFT if `ownerAddress` owns it, directly or through a sale contract */
async function fetchOwnedNft(
  network: ApiNetwork,
  ownerAddress: string,
  nftAddress: string,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
) {
  const response = await fetchNftItems(network, { addresses: [nftAddress] });
  const item = response.nft_items[0];
  const nft = item && parseNftItem(network, item, response.metadata, nftSuperCollectionsByCollectionAddress);

  return nft?.ownerAddress === ownerAddress ? nft : undefined;
}

export async function checkNftTransferDraft(options: {
  accountId: string;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
  isNftBurn?: boolean;
}): Promise<ApiCheckTransactionDraftResult> {
  const { accountId, nfts, comment, isNftBurn } = options;
  let { toAddress } = options;

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const { address: fromAddress } = account.byChain.ton;

  const isNotcoinVouchers = nfts.some((n) => n.collectionAddress === NOTCOIN_VOUCHERS_ADDRESS);

  toAddress = isNftBurn
    ? isNotcoinVouchers
      ? NOTCOIN_EXCHANGERS[0]
      : BURN_ADDRESS
    : toAddress;

  const result: ApiCheckTransactionDraftResult = await checkToAddress(network, toAddress);
  if ('error' in result) {
    return result;
  }

  toAddress = result.resolvedAddress!;

  logDebug('checkNftTransferDraft', 'Checking NFT transfer draft', {
    accountId,
    fromAddress,
    toAddress,
    nftsCount: nfts.length,
    hasComment: Boolean(comment),
    isNftBurn: Boolean(isNftBurn),
  });

  if (account.byChain.ton.mfa && nfts.length > NFT_BATCH_SIZE) {
    return {
      ...result,
      error: ApiTransactionDraftError.MfaNftBatchLimit,
    };
  }

  if (!nfts.length) {
    return { ...result, error: ApiCommonError.Unexpected };
  }

  let networkFee = 0n;
  let previousCost = 0n;
  for (const batch of split(nfts, getMaxMessagesInTransaction(account))) {
    const messages = batch.map(
      (nft) => buildNftTransferMessage(nft, fromAddress, toAddress, comment, account.type === 'ledger'),
    );
    const checkResult = await checkMultiTransactionDraft(accountId, messages, undefined, undefined, previousCost);

    if ('error' in checkResult) {
      result.error = checkResult.error;
      if (checkResult.error !== ApiTransactionDraftError.InsufficientBalance) return result;
    }
    if (!checkResult.emulation) return result;
    networkFee += checkResult.emulation.networkFee;
    previousCost += BigInt(batch.length) * NFT_TRANSFER_AMOUNT + checkResult.emulation.networkFee;
  }

  result.explainedFee = explainApiTransferFee({
    fee: networkFee + BigInt(nfts.length) * NFT_TRANSFER_AMOUNT,
    realFee: networkFee + BigInt(nfts.length) * NFT_TRANSFER_REAL_AMOUNT,
    tokenSlug: getNativeToken('ton').slug,
  });

  return result;
}

export async function submitNftTransfers(options: {
  accountId: string;
  enclaveToken: string | undefined;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
  isNftBurn?: boolean;
}): Promise<ApiSubmitNftTransferResult> {
  const {
    accountId, enclaveToken, nfts, comment, isNftBurn,
  } = options;

  let { toAddress } = options;

  const isNotcoinVouchers = nfts.some((n) => n.collectionAddress === NOTCOIN_VOUCHERS_ADDRESS);

  toAddress = isNftBurn
    ? isNotcoinVouchers
      ? NOTCOIN_EXCHANGERS[0]
      : BURN_ADDRESS
    : toAddress;

  const account = await fetchStoredChainAccount(accountId, 'ton');
  const { address: fromAddress } = account.byChain.ton;

  logDebug('submitNftTransfers', 'Submitting NFT transfers', {
    accountId,
    fromAddress,
    toAddress,
    nftsCount: nfts.length,
    hasComment: Boolean(comment),
    hasStoredMfa: Boolean(account.byChain.ton.mfa),
    mfaAddress: account.byChain.ton.mfa?.address,
  });

  if (account.byChain.ton.mfa && nfts.length > NFT_BATCH_SIZE) {
    return { error: ApiTransactionDraftError.MfaNftBatchLimit };
  }

  if (!nfts.length) {
    return { error: ApiCommonError.Unexpected };
  }

  const messageBatches = split(nfts.map(
    (nft) => buildNftTransferMessage(nft, fromAddress, toAddress, comment, account.type === 'ledger'),
  ), getMaxMessagesInTransaction(account));

  // One signer keeps the whole operation within one Enclave authorization usage
  const signer = getSigner(accountId, account, enclaveToken);
  const transfers: ApiNftTransfer[] = [];
  let previousSeqno: number | undefined;

  for (const messages of messageBatches) {
    const sentTx = await submitMultiTransferWithMfa({
      accountId, signer, messages, previousSeqno,
    }).catch((err) => {
      logDebugError('submitNftTransfers', err);
      return { error: resolveTransactionError(err) };
    });

    if ('error' in sentTx) {
      logDebugError('submitNftTransfers', sentTx);
      return { error: sentTx.error, transfers };
    }

    if ('mfaRequest' in sentTx) {
      return transfers.length
        ? { error: ApiCommonError.Unexpected, transfers }
        : { mfaRequest: sentTx.mfaRequest };
    }

    previousSeqno = sentTx.seqno;
    transfers.push(...sentTx.messages.map((message) => ({
      toAddress: message.toAddress,
      msgHashNormalized: sentTx.msgHashNormalized,
    })));
  }

  return { transfers };
}

function buildNftTransferMessage(
  nft: ApiNft,
  fromAddress: string,
  toAddress: string,
  comment?: string,
  isLedger?: boolean,
) {
  const isNotcoinBurn = nft.collectionAddress === NOTCOIN_VOUCHERS_ADDRESS
    && (toAddress === BURN_ADDRESS || NOTCOIN_EXCHANGERS.includes(toAddress as any));
  const payload = isNotcoinBurn
    ? buildNotcoinVoucherExchange(fromAddress, nft.address, nft.index, isLedger)
    : buildNftTransferPayload({ fromAddress, toAddress, payload: comment, isLedger });

  return {
    payload,
    amount: NFT_TRANSFER_AMOUNT,
    toAddress: nft.address,
  };
}

function buildNotcoinVoucherExchange(
  fromAddress: string,
  nftAddress: string,
  nftIndex: number,
  isLedger?: boolean,
) {
  const first4Bits = Address.parse(nftAddress).hash.readUint8() >> 4;
  const toAddress = NOTCOIN_EXCHANGERS[first4Bits];

  const payload = new Builder()
    .storeUint(0x5fec6642, 32)
    .storeUint(nftIndex, 64)
    .endCell();

  return buildNftTransferPayload({
    fromAddress,
    toAddress,
    payload,
    forwardAmount: NOTCOIN_FORWARD_TON_AMOUNT,
    isLedger,
  });
}

interface NftTransferPayloadParams {
  fromAddress: string;
  toAddress: string;
  payload?: string | Cell;
  /**
   * `payload` can be stored either at a tail of the root cell (i.e. inline) or as its ref.
   * This option forbids the inline variant. This requires more gas but safer.
   */
  noInlinePayload?: boolean;
  forwardAmount?: bigint;
  /** todo: Remove when the Ledger TON App is fixed */
  isLedger?: boolean;
}

export function buildNftTransferPayload({
  fromAddress,
  toAddress,
  payload,
  forwardAmount = NFT_TRANSFER_FORWARD_AMOUNT,
  isLedger,
  noInlinePayload,
}: NftTransferPayloadParams) {
  // In ledger-app-ton v2.7.0 a queryId not equal to 0 is handled incorrectly.
  const queryId = isLedger ? 0n : generateQueryId();

  // Schema definition: https://github.com/ton-blockchain/TEPs/blob/0d7989fba6f2d9cb08811bf47263a9b314dc5296/text/0062-nft-standard.md#1-transfer
  let builder = new Builder()
    .storeUint(NftOpCode.TransferOwnership, 32)
    .storeUint(queryId, 64)
    .storeAddress(Address.parse(toAddress))
    .storeAddress(Address.parse(fromAddress))
    .storeBit(false) // null custom_payload
    .storeCoins(forwardAmount);

  let forwardPayload: Cell | undefined;

  if (payload) {
    if (typeof payload === 'string') {
      forwardPayload = packBytesAsSnakeCell(commentToBytes(payload));
    } else {
      forwardPayload = payload;
    }
  }

  builder = storeInlineOrRefCell(builder, forwardPayload, NFT_PAYLOAD_SAFE_MARGIN, noInlinePayload);

  return builder.endCell();
}
