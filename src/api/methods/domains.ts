import type { ApiChain, ApiNft } from '../types';

import { buildCollectionByKey, extractKey } from '../../util/iteratees';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import { doesAccountHaveChain, fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import { requireMfaMethods } from './optional';
import { createLocalTransactions } from './transfer';

async function getDnsChain(accountId: string): Promise<ApiChain> {
  const account = await fetchStoredAccount(accountId);
  const chain = (Object.keys(chains) as ApiChain[]).find(
    (item) => chains[item].dns && doesAccountHaveChain(account, item),
  );
  if (!chain) {
    throw new Error('DNS is not supported for this account');
  }
  return chain;
}

export async function checkDnsRenewalDraft(accountId: string, nfts: ApiNft[]) {
  const chain = await getDnsChain(accountId);
  const nftAddresses = extractKey(nfts, 'address');
  return chains[chain].dns!.checkDnsRenewalDraft(accountId, nftAddresses);
}

export async function submitDnsRenewal(
  accountId: string, enclaveToken: string | undefined, nfts: ApiNft[], realFee = 0n,
) {
  const chain = await getDnsChain(accountId);
  const { address: fromAddress } = await fetchStoredWallet(accountId, chain);
  const nativeSlug = getNativeToken(chain).slug;

  const nftByAddress = buildCollectionByKey(nfts, 'address');
  const results: (
    { activityIds: string[] }
    | { mfaRequestHash: string }
    | { error: string }
  )[] = [];

  for await (const { addresses, result } of chains[chain].dns!.submitDnsRenewal(
    accountId, enclaveToken, Object.keys(nftByAddress),
  )) {
    if ('error' in result) {
      results.push(result);
      continue;
    }

    if ('mfaRequest' in result) {
      return [await requireMfaMethods().publishSignedMfaRequest(accountId, chain, result.mfaRequest)];
    }

    const localActivities = createLocalTransactions(accountId, chain, addresses.map((address) => {
      const nft = nftByAddress[address];
      return {
        id: result.msgHashNormalized,
        amount: 0n,
        fromAddress,
        toAddress: nft.address,
        fee: realFee / BigInt(nfts.length),
        normalizedAddress: nft.address,
        slug: nativeSlug,
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

// Without `address`, the domain is unlinked: its wallet record is deleted
export async function checkDnsChangeWalletDraft(accountId: string, nft: ApiNft, address?: string) {
  const chain = await getDnsChain(accountId);
  return chains[chain].dns!.checkDnsChangeWalletDraft(accountId, nft.address, address);
}

// Without `address`, the domain is unlinked: its wallet record is deleted
export async function submitDnsChangeWallet(
  accountId: string,
  enclaveToken: string | undefined,
  nft: ApiNft,
  address?: string,
  realFee = 0n,
) {
  const chain = await getDnsChain(accountId);
  const { address: walletAddress } = await fetchStoredWallet(accountId, chain);
  const result = await chains[chain].dns!.submitDnsChangeWallet(accountId, enclaveToken, nft.address, address);

  if ('error' in result) {
    return result;
  }

  if ('mfaRequest' in result) {
    return requireMfaMethods().publishSignedMfaRequest(accountId, chain, result.mfaRequest);
  }

  const [activity] = createLocalTransactions(accountId, chain, [{
    id: result.msgHashNormalized,
    amount: 0n,
    fromAddress: walletAddress,
    toAddress: nft.address,
    fee: realFee,
    normalizedAddress: nft.address,
    slug: getNativeToken(chain).slug,
    externalMsgHashNorm: result.msgHashNormalized,
    nft,
    type: address ? 'dnsChangeAddress' : 'dnsDelete',
  }]);

  return { activityId: activity.id };
}
