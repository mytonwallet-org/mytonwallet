import { Address } from '@ton/core';

import type { Storage } from '../../storages/types';
import type { ApiDomainData, ApiNetwork, ApiNft } from '../../types';
import type { TonTransferParams } from './types';

import { parseAccountId } from '../../../util/account';
import { DAY, HOUR, MINUTE, YEAR } from '../../../util/dateFormat';
import { getDnsDomainZone } from '../../../util/dns';
import { split } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { createTaskQueue } from '../../../util/schedulers';
import { getMaxMessagesInTransaction } from '../../../util/ton/transfer';
import { dnsResolve } from './util/dns';
import { parseTonapiioNft } from './util/metadata';
import { getSigner } from './util/signer';
import { getDnsItemDomain, getTonClient, toBase64Address } from './util/tonCore';
import { DnsItem } from './contracts/DnsItem';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { getCurrentStorage } from '../../storages';
import { DnsCategory, TON_GAS } from './constants';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from './transfer';

const LINKED_ADDRESS_VERIFICATION_CONCURRENCY = 3;
// The backend's linked address is the change trigger; the TTL bounds how long stale backend data can hide a chain change
const LINKED_ADDRESS_VERIFIED_TTL = HOUR;
const LINKED_ADDRESS_UNVERIFIED_TTL = MINUTE;
const DNS_CACHE_RETENTION = 30 * DAY;
const linkedAddressVerificationQueue = createTaskQueue(LINKED_ADDRESS_VERIFICATION_CONCURRENCY);

type StoredDnsEntry = {
  lastSeenAt: number;
  domain?: { name: string; resolverAddress: string };
  verification?: {
    linkedAddress: string;
    verifiedLinkedAddress?: string;
    checkedAt: number;
  };
  // The backend reports a wallet record change only after a delay. Until it does, a change submitted from this app is
  // checked on chain on every poll, so the cached verification of the previous record cannot hide it. The change is
  // stored with the entry, so the check survives a restart of the app or the SDK worker.
  submittedChange?: {
    // A normalized address, or `undefined` when the change deletes the record
    linkedAddress?: string;
    submittedAt: number;
  };
};

type DnsCache = {
  entries: Record<string, StoredDnsEntry>;
  domainNames: Map<string, Promise<string | undefined>>;
  loaded?: Promise<void>;
  generation: number;
  canPersist: boolean;
  queue: ReturnType<typeof createTaskQueue>;
};

const dnsCaches = new WeakMap<Storage, DnsCache>();

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

export async function checkDnsChangeWalletDraft(accountId: string, nftAddress: string, address?: string) {
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
  address?: string,
) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const result = await submitMultiTransferWithMfa({
    accountId,
    signer: getSigner(accountId, account, enclaveToken),
    messages: [makeChangeMessage(nftAddress, address)],
  });

  if (!('error' in result)) {
    await rememberSubmittedChange(accountId, nftAddress, address);
  }

  return result;
}

function makeRenewMessage(nftAddress: string) {
  return {
    toAddress: nftAddress,
    payload: DnsItem.buildFillUpMessage(),
    amount: TON_GAS.changeDns,
  };
}

function makeChangeMessage(nftAddress: string, linkedAddress?: string) {
  return {
    toAddress: nftAddress,
    // Native bridges pass `null` for a deletion. An empty string must fail in `Address.parse` instead of deleting
    // the record.
    payload: typeof linkedAddress === 'string'
      ? DnsItem.buildChangeDnsWalletMessage(linkedAddress)
      : DnsItem.buildDeleteDnsRecordMessage(undefined, DnsCategory.Wallet),
    amount: TON_GAS.changeDns,
  };
}

async function rememberSubmittedChange(accountId: string, nftAddress: string, linkedAddress?: string) {
  const storage = getCurrentStorage();
  const cache = getDnsCache(storage);
  const generation = cache.generation;
  const { network } = parseAccountId(accountId);

  await loadDnsCache(storage, cache, generation);
  if (cache.generation !== generation) return;

  const cacheKey = `${network}:${nftAddress}`;
  const now = Date.now();
  cache.entries[cacheKey] ??= { lastSeenAt: now };
  cache.entries[cacheKey].submittedChange = {
    linkedAddress: linkedAddress ? toBase64Address(linkedAddress, true, network) : undefined,
    submittedAt: now,
  };

  await persistDnsCache(storage, cache, generation);
}

export async function fetchDomains(accountId: string) {
  const storage = getCurrentStorage();
  const cache = getDnsCache(storage);
  const generation = cache.generation;
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');
  const data = await callBackendGet<Record<string, ApiDomainData>>('/dns/getDomains', { address });
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
  const linkedAddressByAddress = await verifyTonDnsLinkedAddresses(network, data, storage, cache, generation);

  const expirationByAddress: Record<string, number> = {};
  const nfts: Record<string, ApiNft> = {};

  Object.keys(data).forEach((nftAddress) => {
    const { lastFillUpTime, nft: rawNft } = data[nftAddress];
    expirationByAddress[nftAddress] = new Date(lastFillUpTime).getTime() + YEAR;
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

export async function clearDnsCache() {
  const storage = getCurrentStorage();
  const cache = getDnsCache(storage);
  cache.generation++;
  cache.entries = {};
  cache.domainNames = new Map();
  cache.loaded = Promise.resolve();
  await cache.queue.run(() => storage.removeItem('tonDnsCache'));
}

function getDnsCache(storage: Storage) {
  let cache = dnsCaches.get(storage);
  if (!cache) {
    cache = { entries: {}, domainNames: new Map(), generation: 0, canPersist: true, queue: createTaskQueue() };
    dnsCaches.set(storage, cache);
  }
  return cache;
}

async function verifyTonDnsLinkedAddresses(
  network: ApiNetwork, data: Record<string, ApiDomainData>, storage: Storage, cache: DnsCache, generation: number,
) {
  return loadDnsCache(storage, cache, generation).then(async () => {
    const currentCache = { ...cache };
    if (currentCache.generation !== generation) {
      currentCache.entries = {};
      currentCache.domainNames = new Map();
    }

    const now = Date.now();
    const cacheKeyByAddress = new Map<string, string>();
    for (const nftAddress of Object.keys(data)) {
      const cacheKey = `${network}:${nftAddress}`;
      cacheKeyByAddress.set(nftAddress, cacheKey);
      currentCache.entries[cacheKey] ??= { lastSeenAt: now };
      currentCache.entries[cacheKey].lastSeenAt = now;
    }
    for (const [cacheKey, entry] of Object.entries(currentCache.entries)) {
      if (now - entry.lastSeenAt > DNS_CACHE_RETENTION) {
        delete currentCache.entries[cacheKey];
        currentCache.domainNames.delete(cacheKey);
      }
    }

    const linkedAddressByAddress: Record<string, string> = {};
    await Promise.all(Object.entries(data).map(async ([nftAddress, { linkedAddress }]) => {
      const verifiedLinkedAddress = await getVerifiedLinkedAddress(
        network, nftAddress, currentCache, cacheKeyByAddress.get(nftAddress)!, now, linkedAddress,
      );
      if (verifiedLinkedAddress) {
        linkedAddressByAddress[nftAddress] = verifiedLinkedAddress;
      }
    }));

    await persistDnsCache(storage, cache, generation);

    return linkedAddressByAddress;
  });
}

function loadDnsCache(storage: Storage, cache: DnsCache, generation: number) {
  cache.loaded ??= (async () => {
    try {
      const entries = await storage.getItem('tonDnsCache') as DnsCache['entries'] | undefined;
      if (cache.generation === generation) cache.entries = entries ?? {};
    } catch (err) {
      logDebugError('tonDnsCache:read', err);
      if (cache.generation === generation) cache.canPersist = false;
    }
  })();

  return cache.loaded;
}

function persistDnsCache(storage: Storage, cache: DnsCache, generation: number) {
  return cache.queue.run(async () => {
    if (cache.generation !== generation || !cache.canPersist) return;
    try {
      await storage.setItem('tonDnsCache', cache.entries);
    } catch (err) {
      logDebugError('tonDnsCache:write', err);
    }
  });
}

// While a change submitted from this app is pending, the backend still reports the previous wallet. The submitted
// wallet shows up as soon as the chain has it. Until then, the previous wallet stays while the chain still has it.
async function getVerifiedLinkedAddress(
  network: ApiNetwork,
  nftAddress: string,
  cache: DnsCache,
  cacheKey: string,
  now: number,
  backendLinkedAddress?: string,
) {
  const submittedChange = getPendingSubmittedChange(cache.entries[cacheKey], network, now, backendLinkedAddress);

  if (submittedChange?.linkedAddress) {
    const submittedLinkedAddress = await verifyTonDnsLinkedAddress(
      network, nftAddress, submittedChange.linkedAddress, cache, cacheKey, true,
    );
    if (submittedLinkedAddress) return submittedLinkedAddress;
  }

  if (!backendLinkedAddress) return undefined;

  return verifyTonDnsLinkedAddress(
    network, nftAddress, backendLinkedAddress, cache, cacheKey, Boolean(submittedChange),
  );
}

// A change is dropped once the backend reports it or `LINKED_ADDRESS_VERIFIED_TTL` passes. By then, the cached
// verification of the previous record has expired too.
function getPendingSubmittedChange(
  entry: StoredDnsEntry, network: ApiNetwork, now: number, backendLinkedAddress?: string,
) {
  const change = entry.submittedChange;
  if (!change) return undefined;

  const isExpired = change.submittedAt > now || now - change.submittedAt >= LINKED_ADDRESS_VERIFIED_TTL;
  if (isExpired || normalizeBackendLinkedAddress(network, backendLinkedAddress) === change.linkedAddress) {
    delete entry.submittedChange;
    return undefined;
  }

  return change;
}

function normalizeBackendLinkedAddress(network: ApiNetwork, linkedAddress?: string) {
  if (!linkedAddress) return undefined;

  try {
    return toBase64Address(linkedAddress, true, network);
  } catch {
    return undefined;
  }
}

async function verifyTonDnsLinkedAddress(
  network: ApiNetwork,
  nftAddress: string,
  linkedAddress: string,
  cache: DnsCache,
  cacheKey: string,
  shouldSkipCache?: boolean,
) {
  try {
    const normalizedLinkedAddress = toBase64Address(linkedAddress, true, network);
    const entry = cache.entries[cacheKey];
    const cached = entry.verification;
    const ttl = cached?.verifiedLinkedAddress ? LINKED_ADDRESS_VERIFIED_TTL : LINKED_ADDRESS_UNVERIFIED_TTL;
    const now = Date.now();

    if (
      !shouldSkipCache
      && cached?.linkedAddress === normalizedLinkedAddress && cached.checkedAt <= now && now - cached.checkedAt < ttl
    ) {
      return cached.verifiedLinkedAddress;
    }

    const verifiedLinkedAddress = await linkedAddressVerificationQueue.run(async () => {
      const name = entry.domain?.name ?? await getCachedDnsItemDomain(network, nftAddress, cache, cacheKey);
      let domain = entry.domain;
      try {
        if (!domain) {
          const zoneMatch = name && getDnsDomainZone(name);
          if (!zoneMatch) return undefined;

          const resolver = await dnsResolve(
            getTonClient(network), zoneMatch.zone.resolver, zoneMatch.base, DnsCategory.DnsNextResolver, true,
          );
          if (!(resolver instanceof Address)) return undefined;

          const resolverAddress = toBase64Address(resolver, true, network);
          if (resolverAddress !== toBase64Address(nftAddress, true, network)) {
            logDebugError('verifyTonDnsLinkedAddress:resolverMismatch', { nftAddress, domain: name, resolverAddress });
            return undefined;
          }
          domain = { name, resolverAddress };
        }

        const resolvedLinkedAddress = await dnsResolve(
          getTonClient(network), domain.resolverAddress, '.', DnsCategory.Wallet, true,
        );
        // Only a completed on-chain lookup admits immutable data to persistent storage
        entry.domain = domain;

        if (!(resolvedLinkedAddress instanceof Address)) {
          return undefined;
        }

        const normalizedResolvedLinkedAddress = toBase64Address(resolvedLinkedAddress, true, network);

        if (normalizedLinkedAddress !== normalizedResolvedLinkedAddress) {
          logDebugError('verifyTonDnsLinkedAddress:mismatch', {
            nftAddress,
            linkedAddress,
            resolvedLinkedAddress: toBase64Address(resolvedLinkedAddress, undefined, network),
          });
          return undefined;
        }

        return normalizedResolvedLinkedAddress;
      } catch (err) {
        if (err instanceof Error && err.message.includes('exit_code')) return undefined;
        throw err;
      }
    });

    entry.verification = {
      linkedAddress: normalizedLinkedAddress,
      verifiedLinkedAddress,
      checkedAt: Date.now(),
    };

    return verifiedLinkedAddress;
  } catch (err) {
    logDebugError('verifyTonDnsLinkedAddress', { nftAddress }, err);
    return undefined;
  }
}

function getCachedDnsItemDomain(network: ApiNetwork, nftAddress: string, cache: DnsCache, cacheKey: string) {
  let domainPromise = cache.domainNames.get(cacheKey);
  if (!domainPromise) {
    domainPromise = getDnsItemDomain(network, nftAddress).catch((err: unknown) => {
      cache.domainNames.delete(cacheKey);
      throw err;
    });
    cache.domainNames.set(cacheKey, domainPromise);
  }

  return domainPromise;
}
