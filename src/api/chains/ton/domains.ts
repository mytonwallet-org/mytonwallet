import type { ApiDomainData, ApiNetwork, ApiNft } from '../../types';
import type { TonTransferParams } from './types';

import { parseAccountId } from '../../../util/account';
import { HOUR, MINUTE, YEAR } from '../../../util/dateFormat';
import { split } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { createTaskQueue } from '../../../util/schedulers';
import { getMaxMessagesInTransaction } from '../../../util/ton/transfer';
import { parseTonapiioNft } from './util/metadata';
import { getSigner } from './util/signer';
import { getDnsItemDomain, toBase64Address } from './util/tonCore';
import { DnsItem } from './contracts/DnsItem';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { resolveAddressByDomain } from './address';
import { TON_GAS } from './constants';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from './transfer';

const LINKED_ADDRESS_VERIFICATION_CONCURRENCY = 3;
// The backend's linked address is the change trigger; the TTL bounds how long stale backend data can hide a chain change
const LINKED_ADDRESS_VERIFIED_TTL = HOUR;
const LINKED_ADDRESS_UNVERIFIED_TTL = MINUTE;
const linkedAddressVerificationQueue = createTaskQueue(LINKED_ADDRESS_VERIFICATION_CONCURRENCY);
const dnsItemDomainCache = new Map<string, Promise<string | undefined>>();
const linkedAddressVerificationCache = new Map<string, {
  linkedAddress: string;
  verifiedLinkedAddress: string | undefined;
  checkedAt: number;
}>();

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

export async function* submitDnsRenewal(
  accountId: string, enclaveToken: string | undefined, nftAddresses: string[],
) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const maxMessages = getMaxMessagesInTransaction(account);
  const nftBatches = split(nftAddresses, maxMessages);
  if (!nftBatches.length) return;

  // All the batches share one signer: the renewal is one operation and holds one Enclave session
  // usage, so a signer per batch would run the session dry after the first one.
  const signer = getSigner(accountId, account, enclaveToken);

  for (const nftBatch of nftBatches) {
    const messages: TonTransferParams[] = nftBatch.map(makeRenewMessage);

    yield {
      addresses: nftBatch,
      result: await submitMultiTransferWithMfa({ accountId, signer, messages }),
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

export async function submitDnsChangeWallet(
  accountId: string,
  enclaveToken: string | undefined,
  nftAddress: string,
  address: string,
) {
  const account = await fetchStoredChainAccount(accountId, 'ton');

  return submitMultiTransferWithMfa({
    accountId,
    signer: getSigner(accountId, account, enclaveToken),
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

  await Promise.all(Object.keys(data).map(async (nftAddress) => {
    const { lastFillUpTime, linkedAddress, nft: rawNft } = data[nftAddress];
    expirationByAddress[nftAddress] = new Date(lastFillUpTime).getTime() + YEAR;
    if (linkedAddress) {
      const verifiedLinkedAddress = await verifyTonDnsLinkedAddress(network, nftAddress, linkedAddress);

      if (verifiedLinkedAddress) {
        linkedAddressByAddress[nftAddress] = verifiedLinkedAddress;
      }
    }
    const nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);
    if (nft) {
      nfts[nftAddress] = nft;
    }
  }));

  return {
    expirationByAddress,
    linkedAddressByAddress,
    nfts,
  };
}

async function verifyTonDnsLinkedAddress(network: ApiNetwork, nftAddress: string, linkedAddress: string) {
  try {
    const normalizedLinkedAddress = toBase64Address(linkedAddress, true, network);
    const cacheKey = `${network}:${nftAddress}`;
    const cached = linkedAddressVerificationCache.get(cacheKey);
    const ttl = cached?.verifiedLinkedAddress ? LINKED_ADDRESS_VERIFIED_TTL : LINKED_ADDRESS_UNVERIFIED_TTL;

    if (cached?.linkedAddress === normalizedLinkedAddress && Date.now() - cached.checkedAt < ttl) {
      return cached.verifiedLinkedAddress;
    }

    const verifiedLinkedAddress = await linkedAddressVerificationQueue.run(async () => {
      const domain = await getCachedDnsItemDomain(network, nftAddress);
      if (!domain) {
        return undefined;
      }

      const resolvedLinkedAddress = await resolveAddressByDomain(network, domain);

      if (!resolvedLinkedAddress) {
        return undefined;
      }

      const normalizedResolvedLinkedAddress = toBase64Address(resolvedLinkedAddress, true, network);

      if (normalizedLinkedAddress !== normalizedResolvedLinkedAddress) {
        logDebugError('verifyTonDnsLinkedAddress:mismatch', {
          nftAddress,
          linkedAddress,
          resolvedLinkedAddress,
        });
        return undefined;
      }

      return normalizedResolvedLinkedAddress;
    });

    linkedAddressVerificationCache.set(cacheKey, {
      linkedAddress: normalizedLinkedAddress,
      verifiedLinkedAddress,
      checkedAt: Date.now(),
    });

    return verifiedLinkedAddress;
  } catch (err) {
    logDebugError('verifyTonDnsLinkedAddress', { nftAddress }, err);
    return undefined;
  }
}

function getCachedDnsItemDomain(network: ApiNetwork, nftAddress: string) {
  const cacheKey = `${network}:${nftAddress}`;
  let domainPromise = dnsItemDomainCache.get(cacheKey);
  if (!domainPromise) {
    domainPromise = getDnsItemDomain(network, nftAddress).catch((err: unknown) => {
      dnsItemDomainCache.delete(cacheKey);
      throw err;
    });
    dnsItemDomainCache.set(cacheKey, domainPromise);
  }

  return domainPromise;
}
