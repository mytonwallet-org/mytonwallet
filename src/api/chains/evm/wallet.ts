import { Contract, isError } from 'ethers';

import type { ApiAddressInfo, ApiNetwork, ApiTokenWithMaybePrice, EVMChain } from '../../types';
import type { AlchemyGetTokenAssetResponse, ZerionPosition, ZerionPositionsResponse } from './types';
import { ApiCommonError } from '../../types';

import { getChainConfig } from '../../../util/chain';
import { fetchJson } from '../../../util/fetch';
import withCacheAsync from '../../../util/withCacheAsync';
import { getEvmProvider } from './util/client';
import { getZerionFungibleImplementation, isZerionNativeFungible } from './util/tokens';
import { getKnownAddressInfo } from '../../common/addresses';
import { buildTokenSlug, updateTokens } from '../../common/tokens';
import { isValidAddress } from './address';
import { EVM_RPC_URLS, getEvmApiUrl, getZerionChainByApiChain } from './constants';

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

export async function fetchAccountAssets(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
) {
  const zerionChain = getZerionChainByApiChain(chain);
  const params = {
    'filter[positions]': 'only_simple',
    currency: 'usd',
    'filter[chain_ids]': zerionChain,
  };

  const response = await fetchJson<ZerionPositionsResponse>(
    `${getEvmApiUrl(network)}/v1/wallets/${address}/positions/`,
    params,
  );

  const tokenEntities: ApiTokenWithMaybePrice[] = [];
  const slugPairs: Record<string, bigint> = {};

  response.data
    .filter((e) =>
      e.attributes.fungible_info.name
      && e.attributes.fungible_info.symbol
      && !isNativeZerionAsset(chain, zerionChain, e),
    )
    .forEach((e) => {
      const assetImplementation = getZerionFungibleImplementation(e.attributes.fungible_info, zerionChain);

      if (!assetImplementation?.address) {
        return;
      }

      const slug = buildTokenSlug(chain, assetImplementation.address);

      slugPairs[slug] = BigInt(e.attributes.quantity.int ?? 0);

      tokenEntities.push({
        priceUsd: e.attributes.price ?? 0,
        percentChange24h: undefined,
        name: e.attributes.fungible_info.name,
        symbol: e.attributes.fungible_info.symbol,
        slug,
        decimals: assetImplementation.decimals,
        chain,
        image: e.attributes.fungible_info.icon?.url,
        tokenAddress: assetImplementation.address,
      });
    });

  const nativeAsset = response.data.find((e) =>
    isNativeZerionAsset(chain, zerionChain, e),
  );

  if (nativeAsset) {
    slugPairs[getChainConfig(chain).nativeToken.slug] = BigInt(nativeAsset.attributes.quantity.int ?? 0);
  }

  tokenEntities.push({
    priceUsd: nativeAsset?.attributes.price ?? 0,
    percentChange24h: undefined,
    ...getChainConfig(chain).nativeToken,
  });

  await updateTokens(tokenEntities, sendUpdateTokens, [], true);

  return slugPairs;
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

    return balance > 0n;

    // TODO: use backend-based activity checking instead of balance checking
    // const txs = await fetchEvmTxs({
    //   chain,
    //   network,
    //   address,
    //   limit: 1,
    // });

    // return !!txs.length;
  },
);
