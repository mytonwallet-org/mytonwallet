import type { ApiNetwork } from '../../../types';

import { buildTokenSlug, getTokenBySlug, updateTokens } from '../../../common/tokens';
import { fetchAssetsByAddresses } from '../wallet';

export async function updateTokensMetadataByAddress(network: ApiNetwork, addresses: string[]) {
  const slugs = addresses.map((e) => ({ address: e, slug: buildTokenSlug('solana', e) }));

  const uncachedTokenAddresses: string[] = [];
  for (const asset of slugs) {
    const metadata = getTokenBySlug(asset.slug);
    if (!metadata) {
      uncachedTokenAddresses.push(asset.address);
    }
  }

  if (uncachedTokenAddresses.length) {
    const fetched = await fetchAssetsByAddresses(network, uncachedTokenAddresses);
    await updateTokens(fetched);
  }
}
