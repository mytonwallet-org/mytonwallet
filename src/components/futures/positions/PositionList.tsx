import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../api/types';

import { selectCurrentAccountPerps, selectPerpsMarketAssetsById } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useCataloguePositions from '../hooks/useCataloguePositions';

import ShowAllButton from '../../common/ShowAllButton';
import Spinner from '../../ui/Spinner';
import LoadError from '../LoadError';
import PositionRow from './PositionRow';

import styles from './PositionList.module.scss';

interface OwnProps {
  limit?: number;
  showAllIconClassName?: string;
  onShowAllClick?: NoneToVoidFunction;
}

interface StateProps {
  positions?: ApiPerpsAccountPosition[];
  isLoadFailed?: boolean;
  assetsById?: Record<string, ApiPerpsMarketAsset>;
  isSensitiveDataHidden?: true;
}

function PositionList({
  limit,
  showAllIconClassName = 'icon-show-all',
  positions,
  isLoadFailed,
  assetsById,
  isSensitiveDataHidden,
  onShowAllClick,
}: OwnProps & StateProps) {
  const { openFuturesPosition, openFutures, loadPerpsSnapshot } = getActions();

  const lang = useLang();
  const shownPositions = useCataloguePositions(positions, assetsById);

  // The Wallet screen also lists positions. `openFutures` keeps the position screen, which a tap on the tab would reset.
  const handlePositionClick = useLastCallback((assetId: string) => {
    openFuturesPosition({ assetId });
    openFutures(undefined, { forceOnHeavyAnimation: true });
  });

  if (!shownPositions) {
    return isLoadFailed
      ? <LoadError className="content-centered" onRetry={loadPerpsSnapshot} />
      : <div className={buildClassName(styles.status, 'content-centered')}><Spinner /></div>;
  }

  // The full list shows an empty-state message, while a preview renders nothing and its block hides
  if (!shownPositions.length) {
    return limit === undefined ? <p className={styles.status}>{lang('$perps_no_positions')}</p> : undefined;
  }

  return (
    <>
      <div className={styles.rows}>
        {shownPositions.slice(0, limit).map((position) => (
          <PositionRow
            key={position.id}
            position={position}
            asset={assetsById?.[position.assetId]}
            isSensitiveDataHidden={isSensitiveDataHidden}
            onClick={handlePositionClick}
          />
        ))}
      </div>
      {onShowAllClick && limit !== undefined && shownPositions.length > limit && (
        <ShowAllButton
          icon={showAllIconClassName}
          label={lang('Show All Positions')}
          amount={shownPositions.length}
          onClick={onShowAllClick}
        />
      )}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountPerps = selectCurrentAccountPerps(global);

  return {
    positions: accountPerps?.snapshot?.positions,
    isLoadFailed: accountPerps?.isSnapshotLoadFailed,
    assetsById: selectPerpsMarketAssetsById(global),
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(PositionList));
