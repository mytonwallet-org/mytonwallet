import type { ApiNft } from '../../api/types';

export function buildTelegramGiftCatalog(nfts: readonly ApiNft[], visibleAddresses?: ReadonlySet<string>) {
  const seen = new Set<string>();
  const collections = new Map<string, { address: string; name?: string; count: number; hiddenCount: number }>();
  let hiddenCount = 0;

  for (const nft of nfts) {
    // Classification comes from the wallet's super-collection registry, never the display name.
    if (nft.chain !== 'ton' || !nft.isTelegramGift || !nft.collectionAddress || seen.has(nft.address)) continue;
    seen.add(nft.address);
    const isVisible = !visibleAddresses || visibleAddresses.has(nft.address);
    const name = isVisible ? nft.collectionName?.trim() || undefined : undefined;
    if (!isVisible) hiddenCount += 1;
    const existing = collections.get(nft.collectionAddress);
    if (existing) {
      existing.count += 1;
      if (!isVisible) existing.hiddenCount += 1;
      // Use a stable visible label even if pages arrive in a different order.
      if (name && (!existing.name || name < existing.name)) existing.name = name;
    } else {
      collections.set(nft.collectionAddress, {
        address: nft.collectionAddress,
        name,
        count: 1,
        hiddenCount: isVisible ? 0 : 1,
      });
    }
  }

  return {
    count: seen.size,
    hiddenCount,
    collections: [...collections.values()].sort((a, b) => (
      b.count - a.count
      || (a.name || '').localeCompare(b.name || '')
      || a.address.localeCompare(b.address)
    )),
  };
}
