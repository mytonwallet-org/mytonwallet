import type { ApiPerpsGetAssetsResult, ApiPerpsListedAsset, ApiPerpsOperation } from '../../api/types';
import type {
  GlobalState, PerpsAssetDetailState, PerpsBalanceDepositProgress, PriceHistoryPeriods,
} from '../types';

import { areDeepEqual } from '../../util/areDeepEqual';
import { selectAccountState } from '../selectors/accounts';
import { updateAccountState } from './misc';

export function updatePerpsAssets(
  global: GlobalState,
  assets: ApiPerpsGetAssetsResult,
  langCode: string | undefined,
  fetchedAt: number,
): GlobalState {
  const perpsAssets = {
    ...assets,
    byId: indexPerpsAssets(assets),
    langCode,
    fetchedAt,
  };

  if (areDeepEqual(global.perpsAssets, perpsAssets)) return global;

  return { ...global, perpsAssets };
}

export function updatePerpsAssetDetail(
  global: GlobalState,
  accountId: string,
  assetId: string,
  partial: PerpsAssetDetailState,
): GlobalState {
  const current = selectAccountState(global, accountId)?.perpsAssetDetailById;

  return updateAccountState(global, accountId, {
    perpsAssetDetailById: {
      ...current,
      [assetId]: {
        ...current?.[assetId],
        ...partial,
      },
    },
  });
}

export function updatePerpsAssetChart(
  global: GlobalState,
  assetId: string,
  partial: PriceHistoryPeriods,
): GlobalState {
  const byAssetId = global.perpsAssetChart?.byAssetId ?? {};

  return {
    ...global,
    perpsAssetChart: {
      byAssetId: {
        ...byAssetId,
        [assetId]: {
          ...byAssetId[assetId],
          ...partial,
        },
      },
    },
  };
}

function indexPerpsAssets(assets: ApiPerpsGetAssetsResult): Record<string, ApiPerpsListedAsset> {
  const byId: Record<string, ApiPerpsListedAsset> = {};

  for (const listed of Object.values(assets.assetsByChain)) {
    for (const asset of listed ?? []) {
      byId[asset.id] = asset;
    }
  }

  for (const section of assets.sections ?? []) {
    for (const asset of section.assets) {
      byId[asset.id] = asset;
    }
  }

  return byId;
}

export function updatePerpsBalanceDeposit(
  global: GlobalState,
  accountId: string,
  progress: PerpsBalanceDepositProgress,
): GlobalState {
  if (!global.accounts?.byId[accountId]) return global;
  return updateAccountState(global, accountId, { perpsBalanceDeposit: progress });
}

export function updatePerpsOperation(global: GlobalState, operation: ApiPerpsOperation): GlobalState {
  const { accountId } = operation;
  if (!global.accounts?.byId[accountId]) return global;

  const operations = {
    ...global.byAccountId[accountId]?.perpsOperations,
    [operation.id]: operation,
  };
  const resolved = Object.values(operations)
    .filter((value) => value.state === 'completed' || value.state === 'failed' || value.acknowledgedAt !== undefined)
    .sort((a, b) => b.createdAt - a.createdAt);
  for (const value of resolved.slice(20)) delete operations[value.id];

  return updateAccountState(global, accountId, { perpsOperations: operations });
}
