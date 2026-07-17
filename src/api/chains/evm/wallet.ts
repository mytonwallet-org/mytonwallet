import { Contract, isError } from 'ethers';

import type { ApiAddressInfo, ApiBalanceBySlug, ApiNetwork, ApiTokenWithMaybePrice, EVMChain } from '../../types';
import type {
  AlchemyGetAssetTransfersResponse,
  AlchemyGetTokenAssetResponse,
  ZerionPosition,
  ZerionPositionsResponse,
} from './types';
import { ApiCommonError } from '../../types';

import { getChainConfig, getChainsByStandard } from '../../../util/chain';
import { fetchJson, isNegativeCacheableStatus } from '../../../util/fetch';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import withCacheAsync from '../../../util/withCacheAsync';
import { getEvmProvider } from './util/client';
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

export async function fetchAssetsByAddresses(network: ApiNetwork, chain: EVMChain, addresses: string[]) {
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
      payload,
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

export async function fetchCrosschainAccountAssets(
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
) {
  const assets = await fetchAccountAssets('ethereum', network, address, sendUpdateTokens, true);

  return assets;
}

// When several accounts share the same EVM address, their independent poll timers can fire
// identical positions requests at once. This map coalesces concurrent identical fetches into a
// single in-flight request; entries are deleted as soon as the request settles, so positions stay
// uncached across poll cycles.
//
// The resolved `ApiBalanceBySlug` is the SAME object instance returned to every coalesced caller,
// so it MUST be treated as read-only. A caller that needs to mutate the result must copy it first,
// otherwise it would corrupt a sibling account that coalesced onto the same fetch.
const inFlightPositions = new Map<string, Promise<ApiBalanceBySlug>>();

export function fetchAccountAssets(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  isCrossChain?: boolean,
): Promise<ApiBalanceBySlug> {
  // The address is lowercased so the same wallet passed in different casing (EIP-55 checksummed vs
  // lowercase) still coalesces onto one request. The `isCrossChain` component is required so a
  // cross-chain ethereum fetch does not collide with a single-chain ethereum fetch for the same address.
  const key = `${network}:${chain}:${address.toLowerCase()}:${isCrossChain ? 1 : 0}`;

  const existing = inFlightPositions.get(key);
  if (existing) {
    return existing;
  }

  const promise = fetchAccountAssetsUncoalesced(chain, network, address, sendUpdateTokens, isCrossChain)
    .finally(() => {
      inFlightPositions.delete(key);
    });

  inFlightPositions.set(key, promise);

  return promise;
}

async function fetchAccountAssetsUncoalesced(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
  isCrossChain?: boolean,
): Promise<ApiBalanceBySlug> {
  const isUntrackableGuarded = getIsNegVerdictCacheEnabled();
  if (isUntrackableGuarded && untrackableRegistry.has(network, address)) {
    // Same address Zerion already rejected (e.g. on the transactions endpoint); skip the
    // round-trip and return converged-empty positions so the balance poller stops probing it.
    return buildEmptyEvmBalances(chain, isCrossChain);
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
  try {
    response = await fetchJson<ZerionPositionsResponse>(
      `${getEvmApiUrl(network)}/v1/wallets/${address}/positions/`,
      params,
    );
  } catch (err) {
    if (isUntrackableGuarded && err instanceof ApiServerError && isNegativeCacheableStatus(err.statusCode)) {
      untrackableRegistry.mark(network, address);
      logDebugError('fetchAccountAssets: wallet is untrackable on Zerion', { address, chain, status: err.statusCode });
      return buildEmptyEvmBalances(chain, isCrossChain);
    }

    throw err;
  }

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

  return slugPairs;
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

export const getIsWalletActive = withCacheAsync(
  async (network: ApiNetwork, chain: EVMChain, address: string) => {
    const balance = await getWalletBalance(chain, network, address);

    if (balance > 0n) {
      return true;
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

    return !!response.result.transfers.length;
  },
);
