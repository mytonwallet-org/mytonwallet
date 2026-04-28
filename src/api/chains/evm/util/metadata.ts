import type { ApiNetwork, EVMChain } from '../../../types';

import { buildTokenSlug, getTokenBySlug, updateTokens } from '../../../common/tokens';
import { fetchAssetsByAddresses } from '../wallet';

export async function updateTokensMetadataByAddress(network: ApiNetwork, chain: EVMChain, addresses: string[]) {
  const slugs = addresses.map((e) => ({ address: e, slug: buildTokenSlug(chain, e) }));

  const uncachedTokenAddresses: string[] = [];
  for (const asset of slugs) {
    const metadata = getTokenBySlug(asset.slug);

    if (!metadata) {
      uncachedTokenAddresses.push(asset.address);
    }
  }

  if (uncachedTokenAddresses.length) {
    const fetched = await fetchAssetsByAddresses(network, chain, uncachedTokenAddresses);
    await updateTokens(fetched);
  }
}
