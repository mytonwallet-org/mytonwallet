import type { ApiNft, OnApiUpdate } from '../types';

import { TONCOIN } from '../../config';
import { bigintDivideToNumber } from '../../util/bigint';
import { extractKey } from '../../util/iteratees';
import * as ton from '../chains/ton';
import { fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import { createLocalTransactions } from './transfer';

let onUpdate: OnApiUpdate;

export function initNfts(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function fetchNftsFromCollection(accountId: string, collectionAddress: string) {
  const account = await fetchStoredAccount(accountId);
  if (!account.byChain.ton) return;

  const nfts = await ton.getAccountNfts(accountId, { collectionAddress });

  onUpdate({ type: 'updateNfts', accountId, nfts, shouldAppend: true });
}

export function checkNftTransferDraft(options: {
  accountId: string;
  nfts: ApiNft[];
  toAddress: string;
  comment?: string;
}) {
  return ton.checkNftTransferDraft(options);
}

export async function submitNftTransfers(
  accountId: string,
  password: string | undefined,
  nfts: ApiNft[],
  toAddress: string,
  comment?: string,
  totalRealFee = 0n,
): Promise<{ activityIds: string[] } | { error: string }> {
  const { address: fromAddress } = await fetchStoredWallet(accountId, 'ton');

  const result = await ton.submitNftTransfers({
    accountId, password, nfts, toAddress, comment,
  });

  if ('error' in result) {
    return result;
  }

  const realFeePerNft = bigintDivideToNumber(totalRealFee, Object.keys(result.messages).length);

  const localActivities = createLocalTransactions(accountId, 'ton', result.messages.map((message, index) => ({
    id: result.msgHashNormalized,
    amount: 0n, // Regular NFT transfers should have no amount in the activity list
    fromAddress,
    toAddress,
    comment,
    fee: realFeePerNft,
    normalizedAddress: message.toAddress,
    slug: TONCOIN.slug,
    externalMsgHashNorm: result.msgHashNormalized,
    nft: nfts?.[index],
  })));

  return {
    activityIds: extractKey(localActivities, 'id'),
  };
}

export async function checkNftOwnership(accountId: string, nftAddress: string) {
  const account = await fetchStoredAccount(accountId);
  return account.byChain.ton && ton.checkNftOwnership(accountId, nftAddress);
}
