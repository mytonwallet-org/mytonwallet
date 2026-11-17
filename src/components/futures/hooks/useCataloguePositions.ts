import { useMemo } from '../../../lib/teact/teact';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../api/types';

/**
 * The positions that the position lists show. A market the loaded catalogue does not have cannot be opened, so its
 * position is left out, as on iOS. Until the catalogue loads, every position stays.
 *
 * The blocks around the lists count the same positions, so a block never shows up empty.
 */
export default function useCataloguePositions(
  positions?: ApiPerpsAccountPosition[],
  assetsById?: Record<string, ApiPerpsMarketAsset>,
) {
  return useMemo(
    () => (assetsById ? positions?.filter(({ assetId }) => assetsById[assetId]) : positions),
    [assetsById, positions],
  );
}
