import type { ApiPerpsGetAssetsResult, ApiPerpsMarketAsset, ApiPerpsMarketSection } from '../types';

/** Resolve section membership through the trading catalogue; section metadata never replaces wire fields. */
export function buildPerpsMarketCatalogue(response: ApiPerpsGetAssetsResult): {
  assets: ApiPerpsMarketAsset[];
  sections: ApiPerpsMarketSection[];
} {
  const byId = new Map<string, ApiPerpsMarketAsset>(
    (response.assetsByChain.hyperliquid ?? []).map((asset) => [asset.id, { ...asset }]),
  );
  const sectionIDs = new Set<string>();
  const sections = response.sections.flatMap((section) => {
    if (sectionIDs.has(section.id) || !['largeHorizontal', 'grid', 'rows'].includes(section.layout)) return [];
    sectionIDs.add(section.id);
    const assetIDs = new Set<string>();
    const assets = section.assets.flatMap((entry) => {
      const asset = byId.get(entry.id);
      if (!asset || asset.isDelisted || assetIDs.has(asset.id)) return [];
      assetIDs.add(asset.id);
      asset.displayName = entry.displayName ?? asset.displayName;
      asset.description = entry.description ?? asset.description;
      asset.label = entry.label ?? asset.label;
      asset.keywords = entry.keywords ?? asset.keywords;
      asset.sparkline = entry.sparkline ?? asset.sparkline;
      asset.tintColor = entry.tintColor ?? asset.tintColor;
      return [asset];
    });
    return assets.length ? [{ ...section, assets }] : [];
  });
  return { assets: [...byId.values()], sections };
}
