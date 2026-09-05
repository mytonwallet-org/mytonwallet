import type { ApiChain } from './misc';

export type ApiMarketSectionLayout = 'largeHorizontal' | 'grid' | 'rows';

export type ApiMarketAsset = {
  newBackendId: string;
  name: string;
  symbol: string;
  /** Any chain the backend knows, including ones this app cannot open; narrowed by `fetchMarketAssets` */
  chain: string;
  image: string;
  tokenAddress?: string;
  label?: string;
  price: number;
  percentChange24h: number;
  sparkline?: number[];
  tintColor?: string;
};

export type ApiMarketSection = {
  id: string;
  title: string;
  layout: ApiMarketSectionLayout;
  limit?: number;
  hasMore: boolean;
  assets: ApiMarketAsset[];
};

export type ApiMarketAssetsResponse = {
  sections: ApiMarketSection[];
};

export type ApiMarketAssetWithSlug = Omit<ApiMarketAsset, 'chain'> & {
  chain: ApiChain;
  slug: string;
};

export type ApiMarketSectionWithSlug = Omit<ApiMarketSection, 'assets'> & {
  assets: ApiMarketAssetWithSlug[];
};

export type ApiMarketAssetsResponseWithSlug = {
  sections: ApiMarketSectionWithSlug[];
};
