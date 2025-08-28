import type { NftItem } from 'tonapi-sdk-js';
import type { Cell } from '@ton/core';
import { Address, Builder } from '@ton/core';

import type { ApiNft, ApiNftUpdate } from '../../types';
import type { ApiCheckTransactionDraftResult } from './types';

import {
  BURN_ADDRESS,
  NFT_BATCH_SIZE,
  NOTCOIN_EXCHANGERS,
  NOTCOIN_FORWARD_TON_AMOUNT,
  NOTCOIN_VOUCHERS_ADDRESS,
} from '../../../config';
import { parseAccountId } from '../../../util/account';
import { bigintMultiplyToNumber } from '../../../util/bigint';
import { compact } from '../../../util/iteratees';
import { generateQueryId } from './util';
import { parseTonapiioNft } from './util/metadata';
import {
  fetchAccountEvents, fetchAccountNfts, fetchNftByAddress, fetchNftItems,
} from './util/tonapiio';
import { commentToBytes, packBytesAsSnake, toBase64Address } from './util/tonCore';
import { fetchStoredTonAccount, fetchStoredTonWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import {
  NFT_PAYLOAD_SAFE_MARGIN,
  NFT_TRANSFER_AMOUNT,
  NFT_TRANSFER_FORWARD_AMOUNT,
  NFT_TRANSFER_REAL_AMOUNT,
  NftOpCode,
} from './constants';
import { checkMultiTransactionDraft, checkToAddress, submitMultiTransfer } from './transfer';
import { isActiveSmartContract } from './wallet';

export async function getAccountNfts(accountId: string, options?: {
  collectionAddress?: string;
  offset?: number;
  limit?: number;
}): Promise<ApiNft[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredTonWallet(accountId);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const rawNfts = await fetchAccountNfts(network, address, options);
  return compact(rawNfts.map((rawNft) => parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress)));
}

export async function checkNftOwnership(accountId: string, nftAddress: string) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredTonWallet(accountId);
  const rawNft = await fetchNftByAddress(network, nftAddress);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);

  return address === nft?.ownerAddress;
}

export async function getNftUpdates(accountId: string, fromSec: number) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredTonWallet(accountId);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const events = await fetchAccountEvents(network, address, fromSec);
  fromSec = events[0]?.timestamp ?? fromSec;
  events.reverse();
  const updates: ApiNftUpdate[] = [];

  for (const event of events) {
    for (const action of event.actions) {
      let to: string;
      let nftAddress: string;
      let rawNft: NftItem | undefined;
      const isPurchase = !!action.NftPurchase;

      if (action.NftItemTransfer) {
        const { sender, recipient, nft: rawNftAddress } = action.NftItemTransfer;
        if (!sender || !recipient) continue;
        to = recipient.address;
        nftAddress = toBase64Address(rawNftAddress, true, network);
      } else if (action.NftPurchase) {
        const { buyer } = action.NftPurchase;
        to = buyer.address;
        rawNft = action.NftPurchase.nft;
        if (!rawNft) {
          continue;
        }
        nftAddress = toBase64Address(rawNft.address, true, network);
      } else {
        continue;
      }

      if (Address.parse(to).equals(Address.parse(address))) {
        if (!rawNft) {
          [rawNft] = await fetchNftItems(network, [nftAddress]);
        }

        if (rawNft) {
          const nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);

          if (nft) {
            updates.push({
              type: 'nftReceived',
              accountId,
              nftAddress,
              nft,
            });
          }
        }
      } else if (!isPurchase && await isActiveSmartContract(network, to)) {
        updates.push({
          type: 'nftPutUpForSale',
          accountId,
          nftAddress,
        });
      } else {
        updates.push({
          type: 'nftSent',
          accountId,
          nftAddress,
          newOwnerAddress: to,
        });
      }
    }
  }

  return [fromSec, updates] as [number, ApiNftUpdate[]];
}

export async function checkNftTransferDraft(options: {
  accountId: string;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
}): Promise<ApiCheckTransactionDraftResult> {
  const { accountId, nfts, comment } = options;
  let { toAddress } = options;

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredTonAccount(accountId);
  const { address: fromAddress } = account.ton;

  const result: ApiCheckTransactionDraftResult = await checkToAddress(network, toAddress);
  if ('error' in result) {
    return result;
  }

  toAddress = result.resolvedAddress!;

  const messages = nfts
    .slice(0, account.type === 'ledger' ? 1 : NFT_BATCH_SIZE) // We only need to check the first batch of a multi-transaction
    .map((nft) => buildNftTransferMessage(nft, fromAddress, toAddress, comment));

  const checkResult = await checkMultiTransactionDraft(accountId, messages);

  if (checkResult.emulation) {
    // todo: Use `received` from the emulation to calculate the real fee. Check what happens when the receiver is the same wallet.
    const batchFee = checkResult.emulation.networkFee;
    result.fee = calculateNftTransferFee(nfts.length, messages.length, batchFee, NFT_TRANSFER_AMOUNT);
    result.realFee = calculateNftTransferFee(nfts.length, messages.length, batchFee, NFT_TRANSFER_REAL_AMOUNT);
  }

  if ('error' in checkResult) {
    result.error = checkResult.error;
  }

  return result;
}

export async function submitNftTransfers(options: {
  accountId: string;
  password: string | undefined;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
}) {
  const {
    accountId, password, nfts, toAddress, comment,
  } = options;
  const { address: fromAddress } = await fetchStoredTonWallet(accountId);
  const messages = nfts.map((nft) => buildNftTransferMessage(nft, fromAddress, toAddress, comment));
  return submitMultiTransfer({ accountId, password, messages });
}

function buildNftTransferMessage(nft: ApiNft, fromAddress: string, toAddress: string, comment?: string) {
  const isNotcoinBurn = nft.collectionAddress === NOTCOIN_VOUCHERS_ADDRESS
    && (toAddress === BURN_ADDRESS || NOTCOIN_EXCHANGERS.includes(toAddress as any));
  const payload = isNotcoinBurn
    ? buildNotcoinVoucherExchange(fromAddress, nft.address, nft.index)
    : buildNftTransferPayload(fromAddress, toAddress, comment);

  return {
    payload,
    amount: NFT_TRANSFER_AMOUNT,
    toAddress: nft.address,
  };
}

function buildNotcoinVoucherExchange(fromAddress: string, nftAddress: string, nftIndex: number) {
  const first4Bits = Address.parse(nftAddress).hash.readUint8() >> 4;
  const toAddress = NOTCOIN_EXCHANGERS[first4Bits];

  const payload = new Builder()
    .storeUint(0x5fec6642, 32)
    .storeUint(nftIndex, 64)
    .endCell();

  return buildNftTransferPayload(fromAddress, toAddress, payload, NOTCOIN_FORWARD_TON_AMOUNT);
}

export function buildNftTransferPayload(
  fromAddress: string,
  toAddress: string,
  payload?: string | Cell,
  forwardAmount = NFT_TRANSFER_FORWARD_AMOUNT,
) {
  let builder = new Builder()
    .storeUint(NftOpCode.TransferOwnership, 32)
    .storeUint(generateQueryId(), 64)
    .storeAddress(Address.parse(toAddress))
    .storeAddress(Address.parse(fromAddress))
    .storeBit(false) // null custom_payload
    .storeCoins(forwardAmount);

  let forwardPayload: Cell | Uint8Array | undefined;

  if (payload) {
    if (typeof payload === 'string') {
      const bytes = commentToBytes(payload);
      const freeBytes = Math.floor((builder.availableBits - NFT_PAYLOAD_SAFE_MARGIN) / 8);
      forwardPayload = packBytesAsSnake(bytes, freeBytes);
    } else {
      forwardPayload = payload;
    }
  }

  if (forwardPayload instanceof Uint8Array) {
    builder.storeBit(0);
    builder = builder.storeBuffer(Buffer.from(forwardPayload));
  } else {
    builder = builder.storeMaybeRef(forwardPayload);
  }

  return builder.endCell();
}

export function calculateNftTransferFee(
  totalNftCount: number,
  // How many NFTs were added to the multi-transaction before estimating it
  estimatedBatchSize: number,
  // The blockchain fee of the estimated multi-transaction
  estimatedBatchBlockchainFee: bigint,
  // How much TON is attached to each NFT during the transfer
  amountPerNft: bigint,
) {
  const fullBatchCount = Math.floor(totalNftCount / estimatedBatchSize);
  let remainingBatchSize = totalNftCount % estimatedBatchSize;

  // The blockchain fee for the first NFT in a batch is almost twice higher than the fee for the other NFTs. Therefore,
  // simply using the average NFT fee to calculate the last incomplete batch fee gives an insufficient number. To fix
  // that, we increase the last batch size.
  //
  // A real life example:
  // 1 NFT  in the batch: 0.002939195 TON
  // 2 NFTs in the batch: 0.004470516 TON
  // 3 NFTs in the batch: 0.006001837 TON
  // 4 NFTs in the batch: 0.007533158 TON
  if (remainingBatchSize > 0 && remainingBatchSize < estimatedBatchSize) {
    remainingBatchSize += 1;
  }

  const totalBlockchainFee = bigintMultiplyToNumber(
    estimatedBatchBlockchainFee,
    (fullBatchCount * estimatedBatchSize + remainingBatchSize) / estimatedBatchSize,
  );
  return totalBlockchainFee + BigInt(totalNftCount) * amountPerNft;
}
