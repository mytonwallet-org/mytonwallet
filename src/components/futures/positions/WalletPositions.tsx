import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../api/types';

import {
  selectCurrentAccountId,
  selectCurrentAccountPerps,
  selectCurrentAccountState,
  selectIsPerpsWalletBlockVisible,
  selectPerpsMarketAssetsById,
} from '../../../global/selectors';
import { POSITIONS_PREVIEW_LIMIT, POSITIONS_SECTION_ID } from '../helpers/buildPerpsSections';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useCataloguePositions from '../hooks/useCataloguePositions';
import usePerpsSnapshotPolling from '../hooks/usePerpsSnapshotPolling';

import PositionList from './PositionList';

import futuresStyles from '../Futures.module.scss';
import styles from './WalletPositions.module.scss';

interface StateProps {
  accountId?: string;
  isVisible: boolean;
  positions?: ApiPerpsAccountPosition[];
  assetsById?: Record<string, ApiPerpsMarketAsset>;
  isSnapshotLoadFailed?: true;
}

function WalletPositions({
  accountId, isVisible, positions, assetsById, isSnapshotLoadFailed,
}: StateProps) {
  const { openFuturesSection } = getActions();

  const lang = useLang();
  const positionsCount = useCataloguePositions(positions, assetsById)?.length;

  // A failed load keeps polling, so a position opened on another device still shows up
  usePerpsSnapshotPolling(isVisible, !positionsCount && !isSnapshotLoadFailed, accountId);

  const handleShowAllClick = useLastCallback(() => {
    openFuturesSection({ sectionId: POSITIONS_SECTION_ID });
  });

  // The block shows only with positions, as on iOS, so the Wallet does not jump when the first snapshot arrives empty
  if (!isVisible || !positionsCount) return undefined;

  return (
    <section className={styles.root}>
      <h2 className={styles.caption}>{lang('Open Positions')}</h2>
      <div className={futuresStyles.card}>
        <PositionList
          limit={POSITIONS_PREVIEW_LIMIT}
          showAllIconClassName="icon-show-all-positions"
          onShowAllClick={handleShowAllClick}
        />
      </div>
    </section>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountPerps = selectCurrentAccountPerps(global);

  return {
    accountId: selectCurrentAccountId(global),
    // In portrait a token opened from the wallet covers it
    isVisible: selectIsPerpsWalletBlockVisible(global) && !selectCurrentAccountState(global)?.currentTokenSlug,
    positions: accountPerps?.snapshot?.positions,
    assetsById: selectPerpsMarketAssetsById(global),
    isSnapshotLoadFailed: accountPerps?.isSnapshotLoadFailed,
  };
})(WalletPositions));
