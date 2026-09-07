import { Contract, isError } from 'ethers';

import type { QueryParams } from '../../../util/fetch';
import type {
  ApiAddressInfo, ApiBalanceBySlug, ApiNetwork, ApiTokenWithMaybePrice, EVMChain, StampedBalances,
} from '../../types';
import type {
  AlchemyGetAssetTransfersResponse,
  AlchemyGetTokenAssetResponse,
  ZerionPosition,
  ZerionPositionsResponse,
} from './types';
import { ApiCommonError } from '../../types';

import { throwIfAborted } from '../../../util/abortSignal';
import { getChainConfig, getChainsByStandard } from '../../../util/chain';
import { buildRequestUrl, fetchJson, fetchWithRetry, isNegativeCacheableStatus } from '../../../util/fetch';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import withCacheAsync from '../../../util/withCacheAsync';
import { getEvmProvider } from './util/client';
import { inactiveWallets } from './util/inactiveWallets';
import { getZerionFungibleImplementation, isZerionNativeFungible } from './util/tokens';
import { untrackableRegistry } from './util/untrackable';
import { getKnownAddressInfo } from '../../common/addresses';
import { getIsNegVerdictCacheEnabled } from '../../common/cache';
import { buildTokenSlug, updateTokens } from '../../common/tokens';
import { ApiServerError } from '../../errors';
import { isValidAddress } from './address';
import { EVM_RPC_URLS, getApiChainByZerionChain, getEvmApiUrl, getZerionChainByApiChain } from './constants';

export async function getWalletBalance(chain: EVMChain, network: ApiNetwork, address: string) {
  return getEvmProvider(network, chain).getBalance(address);
}

export async function getWalletTransactionCount(chain: EVMChain, network: ApiNetwork, address: string) {
  return getEvmProvider(network, chain).getTransactionCount(address);
}

export async function fetchAssetsByAddresses(
  network: ApiNetwork,
  chain: EVMChain,
  addresses: string[],
  signal?: AbortSignal,
) {
  const assets = await Promise.all(addresses.map(async (e) => {
    const payload = {
      method: 'POST',
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'alchemy_getTokenMetadata',
        params: [
          e,
        ],
      }),
      headers: {
        'Content-Type': 'application/json',
      },
    };

    const response = await fetchJson<AlchemyGetTokenAssetResponse>(
      `${EVM_RPC_URLS[network](chain)}/v2`,
      undefined,
      { ...payload, ...(signal && { signal }) },
    );

    return {
      address: e,
      ...response.result,
    };
  }));

  const tokenEntities: ApiTokenWithMaybePrice[] = [];

  assets
    .filter((e) => e?.name)
    .forEach((e) => {
      const slug = buildTokenSlug(chain, e.address);

      tokenEntities.push({
        priceUsd: undefined,
        percentChange24h: undefined,
        name: e.name,
        symbol: e.symbol,
        slug,
        decimals: e.decimals,
        chain,
        image: e.logo,
        tokenAddress: e.address,
      });
    });

  return tokenEntities;
}

export function fetchCrosschainAccountAssets(
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  options?: { signal?: AbortSignal },
) {
  return fetchAccountAssets('ethereum', network, address, sendUpdateTokens, {
    isCrossChain: true,
    ...(options?.signal && { signal: options.signal }),
  });
}

/** The chain registry consumes balances alone: nothing there merges sources, so no stamp is needed. */
export async function fetchAccountBalances(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  options: { isCrossChain?: boolean; signal?: AbortSignal } = {},
) {
  return (await fetchAccountAssets(chain, network, address, sendUpdateTokens, options)).balances;
}

export async function fetchCrosschainAccountBalances(
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  options?: { signal?: AbortSignal },
) {
  return (await fetchCrosschainAccountAssets(network, address, sendUpdateTokens, options)).balances;
}

/** How far ahead of this device's clock a corrected observation instant may sit and still be trusted. */
const MAX_SNAPSHOT_CLOCK_SKEW = 5 * 60 * 1000; // 5 min

// When several accounts share the same EVM address, their independent poll timers can fire
// identical positions requests at once. This map coalesces concurrent identical fetches into a
// single in-flight request; entries are deleted as soon as the request settles, so positions stay
// uncached across poll cycles.
//
// The resolved snapshot is the SAME object instance returned to every coalesced caller,
// so it MUST be treated as read-only. A caller that needs to mutate the result must copy it first,
// otherwise it would corrupt a sibling account that coalesced onto the same fetch.
const inFlightPositions = new Map<string, Promise<StampedBalances>>();

export function fetchAccountAssets(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  options: { isCrossChain?: boolean; signal?: AbortSignal } = {},
): Promise<StampedBalances> {
  const { isCrossChain = false, signal } = options;
  if (signal) {
    return fetchAccountAssetsUncoalesced(chain, network, address, sendUpdateTokens, options);
  }

  // The address is lowercased so the same wallet passed in different casing (EIP-55 checksummed vs
  // lowercase) still coalesces onto one request. The `isCrossChain` component is required so a
  // cross-chain ethereum fetch does not collide with a single-chain ethereum fetch for the same address.
  const key = `${network}:${chain}:${address.toLowerCase()}:${isCrossChain ? 1 : 0}`;

  const existing = inFlightPositions.get(key);
  if (existing) {
    return existing;
  }

  const promise = fetchAccountAssetsUncoalesced(chain, network, address, sendUpdateTokens, options)
    .finally(() => {
      inFlightPositions.delete(key);
    });

  inFlightPositions.set(key, promise);

  return promise;
}

/**
 * Fetches a positions page and reads the gateway's observation instant off it. That instant, not
 * the moment the response arrived, says how fresh the payload is: a page served from the gateway
 * cache can reach us after a socket delta that is genuinely newer. An older gateway sends no such
 * header, and the caller then falls back to arrival ordering.
 */
async function fetchPositionsPage(url: string, params: QueryParams, signal?: AbortSignal) {
  const response = await fetchWithRetry(buildRequestUrl(url, params), signal ? { signal } : undefined);

  return {
    data: (await response.json()) as ZerionPositionsResponse,
    snapshotAt: readSnapshotAt(response),
  };
}

/**
 * Reads the observation instant and states it on this device's clock. The gateway stamps the
 * instant by its own clock while socket deltas are stamped by ours, so a device whose clock is
 * off would rank every snapshot wrong in one direction or the other. The response's own Date is
 * the same event seen by the gateway clock, so the gap between it and arrival is the offset
 * between the two, and adding it puts both stamps on one clock. Without a readable Date there is
 * nothing to correct by, and an instant that still sits further ahead than MAX_SNAPSHOT_CLOCK_SKEW
 * is reported as none at all: it would outrank every delta for as long as the account lives, and
 * arrival ordering, which is what the app did before any of this, is the safer answer.
 */
function readSnapshotAt(response: Response) {
  const raw = response.headers.get('X-Snapshot-At');
  if (!raw) return undefined;

  const snapshotAt = Number(raw);
  if (!Number.isFinite(snapshotAt) || snapshotAt <= 0) return undefined;

  const now = Date.now();
  const responseAt = Date.parse(response.headers.get('Date') ?? '');
  const observedAt = Number.isFinite(responseAt) ? snapshotAt + (now - responseAt) : snapshotAt;

  return observedAt <= now + MAX_SNAPSHOT_CLOCK_SKEW ? observedAt : undefined;
}

async function fetchAccountAssetsUncoalesced(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  options: { isCrossChain?: boolean; signal?: AbortSignal },
): Promise<StampedBalances> {
  const { isCrossChain = false, signal } = options;
  const isUntrackableGuarded = !signal && getIsNegVerdictCacheEnabled();
  if (isUntrackableGuarded && untrackableRegistry.has(network, address)) {
    // Same address Zerion already rejected (e.g. on the transactions endpoint); skip the
    // round-trip and return converged-empty positions so the balance poller stops probing it.
    return { balances: buildEmptyEvmBalances(chain, isCrossChain) };
  }

  const zerionChain = getZerionChainByApiChain(chain);

  const params = {
    'filter[positions]': 'only_simple',
    'filter[trash]': 'no_filter',
    currency: 'usd',
    'filter[chain_ids]': isCrossChain
      ? getChainsByStandard(chain).map((c) => getZerionChainByApiChain(c as EVMChain)).join(',')
      : zerionChain,
  };

  let response: ZerionPositionsResponse;
  let asOf: number | undefined;
  try {
    const { data, snapshotAt } = await fetchPositionsPage(
      `${getEvmApiUrl(network)}/v1/wallets/${address}/positions/`,
      params,
      signal,
    );
    response = data;
    asOf = snapshotAt;
  } catch (err) {
    throwIfAborted(signal);
    if (isUntrackableGuarded && err instanceof ApiServerError && isNegativeCacheableStatus(err.statusCode)) {
      untrackableRegistry.mark(network, address);
      logDebugError('fetchAccountAssets: wallet is untrackable on Zerion', { address, chain, status: err.statusCode });
      return { balances: buildEmptyEvmBalances(chain, isCrossChain) };
    }

    throw err;
  }
  throwIfAborted(signal);

  const tokenEntities: ApiTokenWithMaybePrice[] = [];
  const slugPairs: Record<string, bigint> = {};

  response.data
    .filter((e) =>
      e.attributes.fungible_info.name
      && e.attributes.fungible_info.symbol
      && !isNativeZerionAsset(
        getApiChainByZerionChain(e.relationships.chain.data.id),
        e.relationships.chain.data.id,
        e),
    )
    .forEach((e) => {
      const assetChain = getApiChainByZerionChain(e.relationships.chain.data.id);

      const assetImplementation = getZerionFungibleImplementation(
        e.attributes.fungible_info,
        e.relationships.chain.data.id,
      );

      if (!assetImplementation?.address) {
        return;
      }

      const slug = buildTokenSlug(assetChain, assetImplementation.address);

      slugPairs[slug] = BigInt(e.attributes.quantity.int ?? 0);

      tokenEntities.push({
        priceUsd: typeof e.attributes.price === 'number' ? e.attributes.price : undefined,
        percentChange24h: undefined,
        name: e.attributes.fungible_info.name,
        symbol: e.attributes.fungible_info.symbol,
        slug,
        decimals: assetImplementation.decimals,
        chain: assetChain,
        image: e.attributes.fungible_info.icon?.url,
        tokenAddress: assetImplementation.address,
      });
    });

  const chainsForNative = (isCrossChain ? getChainsByStandard(chain) : [chain]) as EVMChain[];

  for (const balanceChain of chainsForNative) {
    const { nativeToken: nativeTokenMetadata } = getChainConfig(balanceChain);

    const zerionBalanceChain = getZerionChainByApiChain(balanceChain);

    const nativeAsset = response.data.find((e) =>
      isNativeZerionAsset(balanceChain, zerionBalanceChain, e),
    );

    const nativeSlug = getChainConfig(balanceChain).nativeToken.slug;

    slugPairs[nativeSlug] = BigInt(nativeAsset?.attributes.quantity.int ?? 0);

    tokenEntities.push({
      priceUsd: typeof nativeAsset?.attributes.price === 'number'
        ? nativeAsset.attributes.price
        : undefined,
      percentChange24h: undefined,
      ...nativeTokenMetadata,
    });
  }

  await updateTokens(tokenEntities, sendUpdateTokens, [], true);

  return { balances: slugPairs, asOf };
}

// An untrackable address genuinely has no positions; return the same converged-empty shape a
// normal empty wallet produces (native slug present at 0) so the balance poller emits a zero
// update instead of leaving the previous balances stale (an empty {} yields no update at all).
function buildEmptyEvmBalances(chain: EVMChain, isCrossChain?: boolean): ApiBalanceBySlug {
  const chainsForNative = (isCrossChain ? getChainsByStandard(chain) : [chain]) as EVMChain[];
  const balances: ApiBalanceBySlug = {};
  for (const balanceChain of chainsForNative) {
    balances[getChainConfig(balanceChain).nativeToken.slug] = 0n;
  }
  return balances;
}

function isNativeZerionAsset(chain: EVMChain, zerionChain: string, position: ZerionPosition) {
  return position.relationships.chain.data.id === zerionChain
    && isZerionNativeFungible(
      chain,
      zerionChain,
      position.attributes.fungible_info,
      position.relationships.fungible.data.id,
    );
}

export async function getErc20Balance(
  network: ApiNetwork,
  chain: EVMChain,
  ownerAddress: string,
  tokenAddress: string,
) {
  try {
    const contract = new Contract(
      tokenAddress,
      ['function balanceOf(address owner) view returns (uint256)'],
      getEvmProvider(network, chain),
    );

    const balance = await contract.balanceOf(ownerAddress);

    return BigInt(balance.toString());
  } catch (err) {
    if (isError(err, 'BAD_DATA') || isError(err, 'CALL_EXCEPTION')) {
      return 0n;
    }

    throw err;
  }
}

export function getWalletLastTransaction(_network: ApiNetwork, _address: string) {
  return Promise.resolve(undefined);
}

export const getAddressInfo = (
  chain: EVMChain,
  network: ApiNetwork,
  addressOrDomain: string,
): ApiAddressInfo | { error: ApiCommonError } => {
  if (!isValidAddress(addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    resolvedAddress: addressOrDomain,
    addressName: getKnownAddressInfo(addressOrDomain)?.name,
  };
};

// The two verdicts are remembered in different places because they expire differently.
// "Active" is monotonic - an address that has held a balance or received a transfer can never
// stop having done so - so `withCacheAsync`, which keeps only truthy results, holds it for the
// whole process. "Inactive" is revocable by the next block, so it lives in `inactiveWallets`
// under a TTL.
//
// The balance read runs before that TTL is consulted. It is a single cheap RPC, and letting it
// answer first means an address that receives native funds is recognised on the next check
// rather than whenever the TTL happens to lapse - which matters because `BalanceStream` runs
// this precheck once per stream and holds the answer for the stream's lifetime. The registry
// then covers only the transfer probe, the expensive half, for an address whose balance is
// still zero.
export const getIsWalletActive = withCacheAsync(
  async (network: ApiNetwork, chain: EVMChain, address: string) => {
    const [balance, transactionCount] = await Promise.all([
      getWalletBalance(chain, network, address),
      getWalletTransactionCount(chain, network, address),
    ]);

    // An EOA's native balance only ever decreases through a transaction it signed itself, so a
    // zero balance beside a zero nonce proves nothing native ever arrived. That closes the case a
    // balance read alone misses - an address that received funds and spent them all reads as empty
    // yet carries a non-zero nonce - which matters because the inbound-transfer probe below cannot
    // see it either: `internal` is not among the categories asked for outside Ethereum. A contract
    // address reports a nonce of at least 1 under EIP-161 and so errs towards active, the safe
    // direction. The nonce also arrives before the probe, so an address it settles never pays for
    // one.
    if (balance > 0n || transactionCount > 0) {
      inactiveWallets.forget(network, chain, address);
      return true;
    }

    if (inactiveWallets.has(network, chain, address)) {
      return false;
    }

    const payload = {
      method: 'POST',
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'alchemy_getAssetTransfers',
        params: [
          {
            toAddress: address,
            excludeZeroValue: false,
            withMetadata: false,
            category: compact([
              'erc721',
              'erc1155',
              'external',
              chain === 'ethereum' ? 'internal' : undefined,
              'erc20',
              'specialnft',
            ]),
            maxCount: '0x1',
          },
        ],
      }),
      headers: {
        'Content-Type': 'application/json',
      },
    };

    const response = await fetchJson<AlchemyGetAssetTransfersResponse>(
      `${EVM_RPC_URLS[network](chain)}/v2`,
      undefined,
      payload,
    );

    const isActive = !!response.result.transfers.length;

    if (isActive) {
      inactiveWallets.forget(network, chain, address);
    } else {
      inactiveWallets.mark(network, chain, address);
    }

    return isActive;
  },
);
