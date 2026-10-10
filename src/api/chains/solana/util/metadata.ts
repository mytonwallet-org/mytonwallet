import type { ApiNetwork } from '../../../types';

import { buildTokenSlug, getTokenBySlug, updateTokens, waitForTokenSlugResolver } from '../../../common/tokens';
import { fetchAssetsByAddresses } from '../wallet';

export async function updateTokensMetadataByAddress(network: ApiNetwork, addresses: string[], signal?: AbortSignal) {
  const slugs = addresses.map((e) => ({ address: e, slug: buildTokenSlug('solana', e) }));

  const uncachedTokenAddresses: string[] = [];
  for (const asset of slugs) {
    const metadata = getTokenBySlug(asset.slug);
    if (!metadata) {
      uncachedTokenAddresses.push(asset.address);
    }
  }

  if (uncachedTokenAddresses.length) {
    const fetched = await fetchAssetsByAddresses(network, uncachedTokenAddresses, signal);
    // The tokens fetched together may share a backend slug, so their slugs are assigned together, right before the
    // cache gets them
    const resolveTokenSlugs = await waitForTokenSlugResolver(signal);
    const fetchedSlugs = resolveTokenSlugs(fetched.map((token) => ({ chain: 'solana', address: token.tokenAddress! })));
    await updateTokens(fetched.map((token, i) => ({ ...token, slug: fetchedSlugs[i] })));
  }
}
