import type { ApiPriceHistoryPeriod } from '../../api/types';
import type { GlobalState } from '../types';

export function selectPerpsListedAsset(global: GlobalState, assetId: string) {
  return global.perpsAssets?.byId[assetId];
}

export function selectPerpsAssetDetail(
  global: GlobalState,
  accountId: string | undefined,
  assetId: string | undefined,
) {
  if (!accountId || !assetId) return undefined;

  return global.byAccountId[accountId]?.perpsAssetDetailById?.[assetId];
}

export function selectPerpsAssetChart(
  global: GlobalState,
  assetId: string | undefined,
  period: ApiPriceHistoryPeriod,
) {
  if (!assetId) return undefined;

  return global.perpsAssetChart?.byAssetId[assetId]?.[period];
}
