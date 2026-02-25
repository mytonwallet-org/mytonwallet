import type { Address } from '@solana/kit';

import type { ApiAddressInfo, ApiNetwork, ApiTokenWithMaybePrice } from '../../types';
import type { SolanaSPLToken, SolanaSPLTokensByAddressRaw } from './types';
import { ApiCommonError } from '../../types';

import { SOLANA } from '../../../config';
import { fetchJson } from '../../../util/fetch';
import { getSolanaClient } from './util/client';
import { getKnownAddressInfo } from '../../common/addresses';
import { buildTokenSlug, updateTokens } from '../../common/tokens';
import { isValidAddress } from './address';
import { NETWORK_CONFIG, SOLANA_PROGRAM_IDS } from './constants';

export async function getWalletBalance(network: ApiNetwork, address: string) {
  const client = getSolanaClient(network);

  const { value } = await client.getBalance(address as Address).send();

  return BigInt(value);
}

export async function fetchAccountAssets(
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
) {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'searchAssets',
      params: {
        ownerAddress: address,
        tokenType: 'fungible',
        page: 1,
        options: {
          showUnverifiedCollections: false,
          showCollectionMetadata: false,
          showGrandTotal: false,
          showNativeBalance: true,
          showInscription: false,
          showZeroBalance: true,
        },
      },
    }),
  };
  const tokenEntities: ApiTokenWithMaybePrice[] = [];
  const slugPairs: Record<string, bigint> = {};

  const response = await fetchJson<SolanaSPLTokensByAddressRaw>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    options,
  );

  response.result.items
    .filter((e) => e.content.metadata.symbol && e.content.metadata.name)
    .forEach((e) => {
      const slug = buildTokenSlug('solana', e.id);

      slugPairs[slug] = BigInt(e.token_info.balance ?? 0);

      tokenEntities.push({
        priceUsd: e.token_info.price_info?.price_per_token,
        percentChange24h: undefined,
        type: e.token_info.token_program === SOLANA_PROGRAM_IDS.token[1] ? 'token_2022' : 'legacy_token',
        name: e.content.metadata.name,
        symbol: e.content.metadata.symbol,
        slug,
        decimals: e.token_info.decimals,
        chain: 'solana',
        image: e.content.files?.[0]?.uri || e.content.files?.[0]?.cdn_uri || e.content?.links?.image,
        tokenAddress: e.id,
        tokenWalletAddress: e.token_info.associated_token_address,
      });
    });

  slugPairs[SOLANA.slug] = BigInt(response.result.nativeBalance?.lamports ?? 0);

  tokenEntities.push({
    priceUsd: response.result?.nativeBalance?.price_per_sol,
    percentChange24h: undefined,
    ...SOLANA,
  });

  await updateTokens(tokenEntities, sendUpdateTokens, [], true);

  return slugPairs;
}

export async function fetchAssetsByAddresses(
  network: ApiNetwork,
  addreses: string[],
): Promise<ApiTokenWithMaybePrice[]> {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'getAssetBatch',
      params: {
        ids: addreses,
        options: {
          showUnverifiedCollections: true,
          showCollectionMetadata: true,
          showInscription: false,
          showFungible: true,
        },
      },
    }),
  };
  const tokenEntities: ApiTokenWithMaybePrice[] = [];

  const { result: assets } = await fetchJson<{ result: SolanaSPLToken[] }>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    options,
  );

  assets
    .filter((e) => e.content.metadata.symbol && e.content.metadata.name)
    .forEach((e) => {
      const slug = buildTokenSlug('solana', e.id);

      tokenEntities.push({
        priceUsd: e.token_info.price_info?.price_per_token,
        type: e.token_info.token_program === SOLANA_PROGRAM_IDS.token[1] ? 'token_2022' : 'legacy_token',
        percentChange24h: undefined,
        name: e.content.metadata.name,
        symbol: e.content.metadata.symbol,
        slug,
        decimals: e.token_info.decimals,
        chain: 'solana',
        image: e.content.files?.[0]?.uri || e.content.files?.[0]?.cdn_uri,
        tokenAddress: e.id,
      });
    });

  return tokenEntities;
}

export function getAddressInfo(
  network: ApiNetwork,
  addressOrDomain: string,
): ApiAddressInfo | { error: ApiCommonError } {
  if (!isValidAddress(addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    resolvedAddress: addressOrDomain,
    addressName: getKnownAddressInfo(addressOrDomain)?.name,
  };
}
