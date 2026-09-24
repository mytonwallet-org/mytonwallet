import type { ApiNetwork, ApiNft, ApiNftSuperCollection } from '../../../types';
import type { MetadataMap, NftItemsResponse, NftItemState, NftTransfersResponse } from './types';

import { toBase64Address, toRawAddress } from '../util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../../common/addresses';
import { parseToncenterNft } from './actions';
import { callToncenterV3 } from './other';

export function fetchNftItems(network: ApiNetwork, options: {
  addresses?: string[];
  ownerAddress?: string;
  collectionAddress?: string;
  limit?: number;
  offset?: number;
}) {
  const { addresses, ownerAddress, collectionAddress, limit, offset } = options;

  return callToncenterV3<NftItemsResponse>(network, '/nft/items', {
    address: addresses?.map(toRawAddress),
    owner_address: ownerAddress && toRawAddress(ownerAddress),
    collection_address: collectionAddress && toRawAddress(collectionAddress),
    limit,
    offset,
    // Defaults to `false`, which would drop the NFTs held by a sale contract from the account list
    include_on_sale: true,
  });
}

export function fetchNftTransfers(network: ApiNetwork, options: {
  ownerAddress: string;
  /** Unix seconds */
  startUtime?: number;
  direction?: 'in' | 'out';
  limit?: number;
  offset?: number;
}) {
  const { ownerAddress, startUtime, direction, limit, offset } = options;

  return callToncenterV3<NftTransfersResponse>(network, '/nft/transfers', {
    owner_address: toRawAddress(ownerAddress),
    start_utime: startUtime,
    direction,
    limit,
    offset,
    sort: 'desc',
  });
}

export async function fetchNftByAddress(network: ApiNetwork, nftAddress: string): Promise<ApiNft | undefined> {
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
  const { nft_items: items, metadata } = await fetchNftItems(network, { addresses: [nftAddress] });

  return items[0] && parseNftItem(network, items[0], metadata, nftSuperCollectionsByCollectionAddress);
}

/**
 * Keeps the entry count of `nft_items`, putting `undefined` where an NFT could not be parsed. Paginated
 * callers compare the batch length against the page limit to detect the last page, so dropping entries
 * here would end the pagination early.
 */
export function parseNftItems(
  network: ApiNetwork,
  response: NftItemsResponse,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
): (ApiNft | undefined)[] {
  return response.nft_items.map((item) => parseNftItem(
    network,
    item,
    response.metadata,
    nftSuperCollectionsByCollectionAddress,
  ));
}

export function parseNftItem(
  network: ApiNetwork,
  item: NftItemState,
  metadata: MetadataMap,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
): ApiNft | undefined {
  const rawOwnerAddress = item.real_owner ?? item.owner_address;
  const { nft } = parseToncenterNft(
    network,
    metadata,
    item.address,
    nftSuperCollectionsByCollectionAddress,
    {
      rawCollectionAddress: item.collection_address ?? undefined,
      index: item.index,
      // `real_owner` sees through a sale contract, so it is the owner the user thinks of
      ownerAddress: rawOwnerAddress ? toBase64Address(rawOwnerAddress, false, network) : undefined,
      isOnSale: item.on_sale,
      isMetadataOptional: true,
    },
  );

  return nft;
}
