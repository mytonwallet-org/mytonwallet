import type { ApiDomainData, ApiNft } from '../../types';
import type { TonTransferParams } from './types';

import { parseAccountId } from '../../../util/account';
import { YEAR } from '../../../util/dateFormat';
import { split } from '../../../util/iteratees';
import { getMaxMessagesInTransaction } from '../../../util/ton/transfer';
import { parseTonapiioNft } from './util/metadata';
import { DnsItem } from './contracts/DnsItem';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { TON_GAS } from './constants';
import { checkMultiTransactionDraft, submitMultiTransfer } from './transfer';

export async function checkDnsRenewalDraft(accountId: string, nftAddresses: string[]) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const maxMessages = getMaxMessagesInTransaction(account);
  const transactionCount = Math.ceil(nftAddresses.length / maxMessages);

  const messages = nftAddresses
    .slice(0, maxMessages)
    .map(makeRenewMessage);

  const result = await checkMultiTransactionDraft(accountId, messages);

  if ('error' in result) {
    return result;
  }

  const totalAmount = TON_GAS.changeDns * BigInt(nftAddresses.length);
  const realFee = totalAmount + result.emulation.networkFee * BigInt(transactionCount); // Not very correct, but ≥ the actual fee

  return { realFee };
}

export async function* submitDnsRenewal(accountId: string, password: string | undefined, nftAddresses: string[]) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const maxMessages = getMaxMessagesInTransaction(account);
  const nftBatches = split(nftAddresses, maxMessages);

  for (const nftBatch of nftBatches) {
    const messages: TonTransferParams[] = nftBatch.map(makeRenewMessage);

    yield {
      addresses: nftBatch,
      result: await submitMultiTransfer({ accountId, password, messages }),
    };
  }
}

export async function checkDnsChangeWalletDraft(accountId: string, nftAddress: string, address: string) {
  const result = await checkMultiTransactionDraft(accountId, [makeChangeMessage(nftAddress, address)]);

  if ('error' in result) {
    return result;
  }

  return { realFee: result.emulation.networkFee + TON_GAS.changeDns };
}

export function submitDnsChangeWallet(
  accountId: string,
  password: string | undefined,
  nftAddress: string,
  address: string,
) {
  return submitMultiTransfer({
    accountId,
    password,
    messages: [makeChangeMessage(nftAddress, address)],
  });
}

function makeRenewMessage(nftAddress: string) {
  return {
    toAddress: nftAddress,
    payload: DnsItem.buildFillUpMessage(),
    amount: TON_GAS.changeDns,
  };
}

function makeChangeMessage(nftAddress: string, linkedAddress: string) {
  return {
    toAddress: nftAddress,
    payload: DnsItem.buildChangeDnsWalletMessage(linkedAddress),
    amount: TON_GAS.changeDns,
  };
}

export async function fetchDomains(accountId: string) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const data = await callBackendGet<Record<string, ApiDomainData>>('/dns/getDomains', { address });
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const expirationByAddress: Record<string, number> = {};
  const linkedAddressByAddress: Record<string, string> = {};
  const nfts: Record<string, ApiNft> = {};

  Object.keys(data).forEach((nftAddress) => {
    const { lastFillUpTime, linkedAddress, nft: rawNft } = data[nftAddress];
    expirationByAddress[nftAddress] = new Date(lastFillUpTime).getTime() + YEAR;
    if (linkedAddress) {
      linkedAddressByAddress[nftAddress] = linkedAddress;
    }
    const nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);
    if (nft) {
      nfts[nftAddress] = nft;
    }
  });

  return {
    expirationByAddress,
    linkedAddressByAddress,
    nfts,
  };
}
