import { Api, HttpClient } from 'tonapi-sdk-js';

import type { ApiNetwork } from '../../../types';

import { getChainConfig } from '../../../../util/chain';
import { fetchWithRetry } from '../../../../util/fetch';
import withCache from '../../../../util/withCache';
import { getEnvironment } from '../../../environment';
import { NETWORK_CONFIG } from '../constants';

const EVENTS_LIMIT = 100;

const getApi = withCache((network: ApiNetwork) => {
  const headers = {
    ...getEnvironment().apiHeaders,
    'Content-Type': 'application/json',
  };

  return new Api(new HttpClient({
    baseUrl: NETWORK_CONFIG[network].tonApiIoUrl,
    baseApiParams: { headers },
    customFetch: fetchWithRetry as typeof fetch,
  }));
});

export async function fetchNftItems(network: ApiNetwork, addresses: string[]) {
  return (await getApi(network).nft.getNftItemsByAddresses({
    account_ids: addresses,
  })).nft_items;
}

export async function fetchAccountNfts(network: ApiNetwork, address: string, options?: {
  collectionAddress?: string;
  offset?: number;
  limit?: number;
}) {
  const { collectionAddress, offset, limit } = options ?? {};
  const defaultLimit = getChainConfig('ton').nftBatchLimit!;

  return (await getApi(network).accounts.getAccountNftItems(
    address,
    {
      offset: offset ?? 0,
      limit: limit ?? defaultLimit,
      indirect_ownership: true,
      collection: collectionAddress,
    },
  )).nft_items;
}

export function fetchNftByAddress(network: ApiNetwork, nftAddress: string) {
  return getApi(network).nft.getNftItemByAddress(nftAddress);
}

export async function fetchAccountEvents(network: ApiNetwork, address: string, fromSec: number, limit?: number) {
  return (await getApi(network).accounts.getAccountEvents(address, {
    limit: limit ?? EVENTS_LIMIT,
    start_date: fromSec,
  })).events;
}
