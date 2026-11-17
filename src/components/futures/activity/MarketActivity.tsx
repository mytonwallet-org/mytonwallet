import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsMarketDetailState } from '../../../global/types';

import {
  isPerpsHistoryStale,
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsPosition,
  selectPerpsMarketAsset,
} from '../../../global/selectors';
import { buildPositionActivityItems } from '../helpers/perpsActivity';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsPolling, { PERPS_REFRESH_INTERVAL } from '../hooks/usePerpsPolling';
import usePerpsStaleness from '../hooks/usePerpsStaleness';

import ActivityList from './ActivityList';

interface OwnProps {
  assetId: string;
  isActive?: boolean;
}

interface StateProps {
  detail?: PerpsMarketDetailState;
  asset?: ApiPerpsMarketAsset;
  position?: ApiPerpsAccountPosition;
}

/**
 * The trades of the market since the current position opened, or its recent trades without a position or when the
 * opening time is unknown
 */
function MarketActivity({
  assetId, isActive, detail, asset, position,
}: OwnProps & StateProps) {
  const { loadPerpsMarketDetail } = getActions();
  const lang = useLang();

  const refresh = useLastCallback(() => {
    loadPerpsMarketDetail({ assetId });
  });

  // A trade made from this screen, or on another device, reaches the list with the next refresh
  usePerpsPolling(refresh, isActive, PERPS_REFRESH_INTERVAL, [assetId]);

  const history = detail?.history;
  const fills = history?.fills;
  const { items, isSinceOpening } = useMemo(
    () => buildPositionActivityItems(fills ?? [], position),
    [fills, position],
  );
  const isStale = usePerpsStaleness(isPerpsHistoryStale(history), Boolean(history?.fills.length));

  const handleLoadMore = useLastCallback(() => {
    loadPerpsMarketDetail({ assetId, isNextPage: true });
  });

  return (
    <ActivityList
      title={lang(isSinceOpening ? 'Activity' : 'Recent Market Activity')}
      items={items}
      nextCursor={history?.nextCursor}
      isStale={isStale}
      asset={asset}
      onRetry={detail?.hasError ? refresh : undefined}
      onLoadMore={handleLoadMore}
    />
  );
}

export default memo(withGlobal<OwnProps>((global, { assetId }): StateProps => {
  return {
    detail: selectCurrentAccountPerps(global)?.marketDetailById?.[assetId],
    asset: selectPerpsMarketAsset(global, assetId),
    position: selectCurrentAccountPerpsPosition(global, assetId),
  };
})(MarketActivity));
