import { useEffect } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiPriceHistoryPeriod } from '../../api/types';

import { SECOND } from '../../util/dateFormat';
import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../util/priceHistory';

import useInterval from '../../hooks/useInterval';
import useLastCallback from '../../hooks/useLastCallback';

const CHART_REFRESH_INTERVAL = 15 * SECOND;
const DETAIL_RETRY_INTERVAL = 5 * SECOND;

/**
 * Loads `POST /perps/asset` and `POST /perps/asset/chart` for the open perp, and keeps the chart
 * current while that page stays open. The catalogue itself comes from the cached `GET /perps/assets`.
 */
export default function usePerpsAssetPage({
  assetId,
  period = DEFAULT_PRICE_HISTORY_PERIOD,
  isActive,
  hasDetailError,
}: {
  assetId?: string;
  period?: ApiPriceHistoryPeriod;
  isActive?: boolean;
  hasDetailError?: boolean;
}) {
  const { loadPerpsAsset, loadPerpsAssetChart } = getActions();

  const refreshDetail = useLastCallback(() => {
    if (assetId) loadPerpsAsset({ assetId });
  });

  const refreshChart = useLastCallback(() => {
    if (assetId) loadPerpsAssetChart({ assetId, period });
  });

  useEffect(() => {
    if (!isActive || !assetId) return;

    refreshDetail();
  }, [isActive, assetId, refreshDetail]);

  useEffect(() => {
    if (!isActive || !assetId) return;

    refreshChart();
  }, [isActive, assetId, period, refreshChart]);

  useInterval(refreshChart, isActive && assetId ? CHART_REFRESH_INTERVAL : undefined, true);
  useInterval(
    refreshDetail,
    isActive && assetId && hasDetailError ? DETAIL_RETRY_INTERVAL : undefined,
    true,
  );
}
