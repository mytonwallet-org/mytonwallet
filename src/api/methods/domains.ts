import type { ApiNft } from '../types';

import { TONCOIN } from '../../config';
import { buildCollectionByKey, extractKey } from '../../util/iteratees';
import * as ton from '../chains/ton';
import { fetchStoredWallet } from '../common/accounts';
import { createLocalTransactions } from './transfer';

export function checkDnsRenewalDraft(accountId: string, nfts: ApiNft[]) {
  const nftAddresses = extractKey(nfts, 'address');
  return ton.checkDnsRenewalDraft(accountId, nftAddresses);
}

export async function submitDnsRenewal(accountId: string, password: string | undefined, nfts: ApiNft[], realFee = 0n) {
  const { address: fromAddress } = await fetchStoredWallet(accountId, 'ton');

  const nftByAddress = buildCollectionByKey(nfts, 'address');
  const results: ({ activityIds: string[] } | { error: string })[] = [];

  for await (const { addresses, result } of ton.submitDnsRenewal(accountId, password, Object.keys(nftByAddress))) {
    if ('error' in result) {
      results.push(result);
      continue;
    }

    const localActivities = createLocalTransactions(accountId, 'ton', addresses.map((address) => {
      const nft = nftByAddress[address];
      return {
        id: result.msgHashNormalized,
        amount: 0n,
        fromAddress,
        toAddress: nft.address,
        fee: realFee / BigInt(nfts.length),
        normalizedAddress: nft.address,
        slug: TONCOIN.slug,
        externalMsgHashNorm: result.msgHashNormalized,
        nft,
        type: 'dnsRenew',
      };
    }));

    results.push({
      activityIds: extractKey(localActivities, 'id'),
    });
  }

  return results;
}

export function checkDnsChangeWalletDraft(accountId: string, nft: ApiNft, address: string) {
  return ton.checkDnsChangeWalletDraft(accountId, nft.address, address);
}

export async function submitDnsChangeWallet(
  accountId: string,
  password: string | undefined,
  nft: ApiNft,
  address: string,
  realFee = 0n,
) {
  const { address: walletAddress } = await fetchStoredWallet(accountId, 'ton');
  const result = await ton.submitDnsChangeWallet(accountId, password, nft.address, address);

  if ('error' in result) {
    return result;
  }

  const [activity] = createLocalTransactions(accountId, 'ton', [{
    id: result.msgHashNormalized,
    amount: 0n,
    fromAddress: walletAddress,
    toAddress: nft.address,
    fee: realFee,
    normalizedAddress: nft.address,
    slug: TONCOIN.slug,
    externalMsgHashNorm: result.msgHashNormalized,
    nft,
    type: 'dnsChangeAddress',
  }]);

  return { activityId: activity.id };
}
