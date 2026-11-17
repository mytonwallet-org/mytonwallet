import type { ApiPerpsMarketAsset, ApiPerpsMarketSnapshot } from '../../src/api/types';

export function buildPerpsMarketFixture(assets: ApiPerpsMarketAsset[] = []): ApiPerpsMarketSnapshot {
  return {
    assets,
    marketSections: [],
    limits: { minOpenDepositUsdc: '0', minIncreaseDepositUsdc: '0', minPositionMarginUsdc: '0' },
    assetsFetchedAt: 1,
  };
}
