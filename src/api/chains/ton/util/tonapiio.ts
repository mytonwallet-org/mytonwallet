import { Api, HttpClient } from 'tonapi-sdk-js';

import type { ApiNetwork } from '../../../types';

import { fetchWithRetry } from '../../../../util/fetch';
import withCache from '../../../../util/withCache';
import { getEnvironment } from '../../../environment';
import { NETWORK_CONFIG } from '../constants';

const MAX_LIMIT = 500;
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

export async function fetchJettonBalances(network: ApiNetwork, account: string) {
  return (await getApi(network).accounts.getAccountJettonsBalances(account, {
    supported_extensions: ['custom_payload'],
  })).balances;
}

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

  return (await getApi(network).accounts.getAccountNftItems(
    address,
    {
      offset: offset ?? 0,
      limit: limit ?? MAX_LIMIT,
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
