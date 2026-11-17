import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsHistoryState } from '../../../global/types';

import {
  isPerpsHistoryStale, selectCurrentAccountPerps, selectPerpsMarketAssetsByName,
} from '../../../global/selectors';
import { buildPerpsActivityItems } from '../helpers/perpsActivity';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsStaleness from '../hooks/usePerpsStaleness';

import ActivityList from './ActivityList';

interface StateProps {
  history?: PerpsHistoryState;
  assetsByName?: Record<string, ApiPerpsMarketAsset>;
}

/** The trades of the account on the Futures screen */
function AccountActivity({ history, assetsByName }: StateProps) {
  const { loadPerpsHistory } = getActions();
  const lang = useLang();

  // A refresh replaces `history` once to mark the loading and once with the result, while `fills` changes only with it
  const fills = history?.fills;
  const items = useMemo(() => fills && buildPerpsActivityItems(fills, assetsByName), [assetsByName, fills]);
  const isStale = usePerpsStaleness(isPerpsHistoryStale(history), Boolean(history?.fills.length));

  const handleLoadMore = useLastCallback(() => {
    loadPerpsHistory({ isNextPage: true });
  });

  const handleRetry = useLastCallback(() => {
    loadPerpsHistory();
  });

  if (!history || !items) return undefined;

  return (
    <ActivityList
      title={lang('Activity')}
      items={items}
      nextCursor={history.nextCursor}
      isStale={isStale}
      assetsByName={assetsByName}
      onRetry={history.hasError ? handleRetry : undefined}
      onLoadMore={handleLoadMore}
    />
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    history: selectCurrentAccountPerps(global)?.history,
    assetsByName: selectPerpsMarketAssetsByName(global),
  };
})(AccountActivity));
