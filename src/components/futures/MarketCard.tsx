import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsMarketAsset } from '../../api/types';

import {
  getIsPerpsWalletSwitchReason,
  isPerpsTradeDisabledBy,
  selectIsCurrentAccountViewMode,
  selectIsPerpsMarketStale,
  selectPerpsAssetDescription,
  selectPerpsMarketAsset,
  selectPerpsTradeBlockReason,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { buildPerpsToken } from './helpers/buildPerpsSections';
import { getPerpsAssetName, getPerpsErrorText } from './helpers/formatPerps';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePerpsStaleness from './hooks/usePerpsStaleness';

import TradeNotice from '../swap/TradeNotice';
import ActionTile from './ActionTile';
import MarketActivity from './activity/MarketActivity';
import Chart from './Chart';
import Info from './Info';
import Screen from './Screen';

import styles from './Futures.module.scss';

interface OwnProps {
  assetId: string;
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  asset?: ApiPerpsMarketAsset;
  description?: string;
  tradeBlockReason?: string;
  isViewMode: boolean;
  isMarketStale: boolean;
}

function MarketCard({
  assetId, isActive, asset, description, tradeBlockReason, isViewMode, isMarketStale, onBackClick,
}: OwnProps & StateProps) {
  const { startPerpsTrade } = getActions();
  const lang = useLang();

  // A market that leaves the catalogue keeps its card until the user goes back
  const renderedAsset = useCurrentOrPrev(asset, true);
  const token = useMemo(() => renderedAsset && buildPerpsToken(renderedAsset), [renderedAsset]);
  const isTradingDisabled = !asset || isPerpsTradeDisabledBy(tradeBlockReason);
  const isWalletSwitchRequired = getIsPerpsWalletSwitchReason(tradeBlockReason);
  const isStale = usePerpsStaleness(isMarketStale, Boolean(asset));

  const handleLongClick = useLastCallback(() => {
    startPerpsTrade({ kind: 'open', assetId, side: 'long' });
  });

  const handleShortClick = useLastCallback(() => {
    startPerpsTrade({ kind: 'open', assetId, side: 'short' });
  });

  return (
    <Screen
      title={renderedAsset ? lang('$perps_market_title', { asset: getPerpsAssetName(renderedAsset) }) as string : ''}
      onBackClick={onBackClick}
    >
      {renderedAsset && (
        <>
          {/* A view account cannot sign anything, so only a reason that another wallet fixes needs an explanation */}
          {tradeBlockReason && (!isViewMode || isWalletSwitchRequired) && (
            <TradeNotice
              message={getPerpsErrorText(lang, tradeBlockReason)}
              isInformational={isWalletSwitchRequired}
              className={styles.tradeBlockNotice}
            />
          )}
          <div className={styles.tiles}>
            <ActionTile
              icon="iconLong"
              label={lang('Long')}
              isDisabled={isTradingDisabled}
              onClick={handleLongClick}
            />
            <ActionTile
              icon="iconShort"
              label={lang('Short')}
              isDisabled={isTradingDisabled}
              onClick={handleShortClick}
            />
          </div>

          <div className={buildClassName(styles.panels, styles.dimmable, isStale && styles.stale)}>
            <Chart
              key={renderedAsset.id}
              assetId={renderedAsset.id}
              token={token}
              isActive={isActive}
              className={styles.panel}
            />
            <Info key={renderedAsset.id} asset={renderedAsset} description={description} className={styles.panel} />
          </div>
        </>
      )}

      <MarketActivity assetId={assetId} isActive={isActive} />
    </Screen>
  );
}

export default memo(withGlobal<OwnProps>((global, { assetId }): StateProps => {
  return {
    asset: selectPerpsMarketAsset(global, assetId),
    description: selectPerpsAssetDescription(global, assetId),
    tradeBlockReason: selectPerpsTradeBlockReason(global, assetId, 'open'),
    isViewMode: selectIsCurrentAccountViewMode(global),
    isMarketStale: selectIsPerpsMarketStale(global),
  };
})(MarketCard));
