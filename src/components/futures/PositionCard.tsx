import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../api/types';

import { Big } from '../../lib/big.js';
import {
  isPerpsSnapshotStale,
  isPerpsTradeDisabledBy,
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsPosition,
  selectIsCurrentAccountViewMode,
  selectPerpsAssetDescription,
  selectPerpsMarketAsset,
  selectPerpsTradeBlockReason,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { formatCurrency, formatNumber, formatPercent } from '../../util/formatNumber';
import { buildPerpsToken } from './helpers/buildPerpsSections';
import {
  formatLeverage,
  formatPerpsMoney,
  formatPerpsQuantity,
  formatPerpsSignedMoney,
  getPerpsCoinSymbol,
  getPerpsErrorText,
  getPerpsRatioPercent,
  getPerpsValueTone,
  getSideLabel,
  MISSING_VALUE,
  PERPS_CURRENCY_SYMBOL,
} from './helpers/formatPerps';
import { PERPS_AMOUNT_MASK, PERPS_CHANGE_MASK, PERPS_ROW_AMOUNT_MASK } from './helpers/sensitiveDataMasks';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePerpsStaleness from './hooks/usePerpsStaleness';

import TokenIcon from '../common/TokenIcon';
import TradeNotice from '../swap/TradeNotice';
import SensitiveData from '../ui/SensitiveData';
import Skeleton from '../ui/Skeleton';
import ActionTile from './ActionTile';
import MarketActivity from './activity/MarketActivity';
import Chart from './Chart';
import DetailRow from './DetailRow';
import Info from './Info';
import Screen from './Screen';

import futuresStyles from './Futures.module.scss';
import styles from './PositionCard.module.scss';

interface OwnProps {
  assetId: string;
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  asset?: ApiPerpsMarketAsset;
  description?: string;
  position?: ApiPerpsAccountPosition;
  isSnapshotLoaded: boolean;
  isSnapshotStale: boolean;
  /** The close of this position prepares its quote, and its Review screen opens with it */
  isClosePreparing: boolean;
  tradeBlockReason?: string;
  isViewMode: boolean;
  isSensitiveDataHidden?: true;
}

function PositionCard({
  assetId,
  isActive,
  asset,
  description,
  position,
  isSnapshotLoaded,
  isSnapshotStale,
  isClosePreparing,
  tradeBlockReason,
  isViewMode,
  isSensitiveDataHidden,
  onBackClick,
}: OwnProps & StateProps) {
  const { startPerpsTrade } = getActions();
  const lang = useLang();

  // The header keeps naming the position after it closes or gets liquidated
  const renderedPosition = useCurrentOrPrev(position, true);
  const isClosed = isSnapshotLoaded && !position;
  const symbol = asset?.symbol ?? getPerpsCoinSymbol(renderedPosition?.raw.coin ?? '');
  const token = useMemo(() => asset && buildPerpsToken(asset), [asset]);
  const isTradingDisabled = isClosed || isPerpsTradeDisabledBy(tradeBlockReason);
  const isStale = usePerpsStaleness(isSnapshotStale, isSnapshotLoaded);

  const title = renderedPosition ? (
    <>
      {symbol}{' '}
      <span className={renderedPosition.side === 'long' ? styles.positive : styles.negative}>
        {formatLeverage(renderedPosition.raw.leverage.value)} {getSideLabel(lang, renderedPosition.side)}
      </span>
    </>
  ) : symbol;

  const handleEditClick = useLastCallback(() => {
    startPerpsTrade({ kind: 'edit', assetId });
  });

  const handleCloseClick = useLastCallback(() => {
    startPerpsTrade({ kind: 'close', assetId });
  });

  // A closed position keeps its last metrics, while its value is gone
  function renderSummary(shownPosition: ApiPerpsAccountPosition) {
    const [wholePart, fractionPart] = isClosed ? [MISSING_VALUE] : formatNumber(shownPosition.equity).split('.');
    const pnl = shownPosition.raw.unrealizedPnl;
    const pnlPercent = getPerpsRatioPercent(shownPosition.returnOnEquity);
    const pnlTone = getPerpsValueTone(pnl);

    return (
      <div className={buildClassName(styles.summary, futuresStyles.dimmable, isStale && futuresStyles.stale)}>
        {/* The market can arrive after the position, so a placeholder keeps the room of its icon */}
        {token
          ? <TokenIcon token={token} size="xx-large" className={styles.icon} />
          : <Skeleton className={buildClassName(styles.icon, styles.iconSkeleton)} />}

        <SensitiveData
          isActive={isSensitiveDataHidden}
          withDust
          align="center"
          {...PERPS_AMOUNT_MASK}
          className={buildClassName(styles.amount, 'rounded-font')}
        >
          {!isClosed && <span className={styles.amountCurrency}>{PERPS_CURRENCY_SYMBOL}</span>}
          {wholePart}
          {fractionPart && <span className={styles.amountFraction}>.{fractionPart}</span>}
        </SensitiveData>

        {pnlTone && (
          <SensitiveData
            isActive={isSensitiveDataHidden}
            withDust
            align="center"
            {...PERPS_CHANGE_MASK}
            className={buildClassName(styles.change, styles[pnlTone])}
          >
            {pnlTone === 'positive' ? '↑' : '↓'}&thinsp;
            {pnlPercent !== undefined && `${formatPercent(Math.abs(pnlPercent))} · `}
            {formatCurrency(Big(pnl).abs().toString(), PERPS_CURRENCY_SYMBOL)}
          </SensitiveData>
        )}
      </div>
    );
  }

  function renderDetails(shownPosition: ApiPerpsAccountPosition) {
    const { raw } = shownPosition;
    const fundingTone = getPerpsValueTone(shownPosition.funding);

    return (
      <div className={buildClassName(futuresStyles.card, futuresStyles.dimmable, isStale && futuresStyles.stale)}>
        <DetailRow
          label={lang('Invested')}
          hint={lang('$perps_invested_hint')}
          value={renderSensitiveValue('invested', formatPerpsMoney(shownPosition.collateral))}
          className={styles.detailsRow}
          labelClassName={styles.detailsLabel}
        />
        <DetailRow
          label={lang('Entry Price')}
          hint={lang('$perps_entry_price_hint')}
          value={formatPerpsMoney(raw.entryPx ?? undefined)}
          className={styles.detailsRow}
          labelClassName={styles.detailsLabel}
        />
        <DetailRow
          label={lang('Liquidation Price')}
          hint={lang('$perps_liquidation_price_hint')}
          value={formatPerpsMoney(raw.liquidationPx ?? undefined)}
          className={styles.detailsRow}
          labelClassName={styles.detailsLabel}
        />
        <DetailRow
          label={lang('Position Size')}
          hint={lang('$perps_position_size_details_hint')}
          value={renderSensitiveValue(
            'size',
            `${formatPerpsMoney(raw.positionValue)} · ${formatPerpsQuantity(symbol, shownPosition.size)}`,
          )}
          className={styles.detailsRow}
          labelClassName={styles.detailsLabel}
        />
        {/* A positive value is funding the position received */}
        <DetailRow
          label={lang('Funding Payments')}
          hint={lang('$perps_funding_payments_hint')}
          value={renderSensitiveValue('funding', formatPerpsSignedMoney(shownPosition.funding))}
          className={styles.detailsRow}
          labelClassName={styles.detailsLabel}
          valueClassName={fundingTone && styles[fundingTone]}
        />
      </div>
    );
  }

  // Prices stay visible, since they do not tell how much the account holds
  function renderSensitiveValue(name: string, value: string) {
    return (
      <SensitiveData
        isActive={isSensitiveDataHidden}
        {...PERPS_ROW_AMOUNT_MASK}
        seed={`${assetId}:${name}`}
        align="right"
      >
        {value}
      </SensitiveData>
    );
  }

  return (
    <Screen title={title} onBackClick={onBackClick}>
      {renderedPosition && renderSummary(renderedPosition)}

      {/* Until the market loads, the tiles stay disabled without a reason, which is unknown yet */}
      {tradeBlockReason && asset && !isClosed && !isViewMode && (
        <TradeNotice message={getPerpsErrorText(lang, tradeBlockReason)} className={futuresStyles.tradeBlockNotice} />
      )}

      {/* The tiles wait for the snapshot, and a closed or liquidated position shows them disabled */}
      {(position || isClosed) && (
        <div className={futuresStyles.tiles}>
          <ActionTile
            icon="iconAdjust"
            label={lang('$perps_edit_action')}
            isDisabled={isTradingDisabled || isClosePreparing}
            onClick={handleEditClick}
          />
          <ActionTile
            icon="iconClose"
            label={lang('Close')}
            isDisabled={isTradingDisabled}
            isLoading={isClosePreparing}
            onClick={handleCloseClick}
          />
        </div>
      )}

      {renderedPosition && renderDetails(renderedPosition)}

      <div className={futuresStyles.panels}>
        <Chart key={assetId} assetId={assetId} isActive={isActive} className={futuresStyles.panel} />
        <Info key={assetId} asset={asset} description={description} className={futuresStyles.panel} />
      </div>

      <MarketActivity assetId={assetId} isActive={isActive} />
    </Screen>
  );
}

export default memo(withGlobal<OwnProps>((global, { assetId }): StateProps => {
  const accountPerps = selectCurrentAccountPerps(global);
  const { trade } = global.perps;

  return {
    asset: selectPerpsMarketAsset(global, assetId),
    description: selectPerpsAssetDescription(global, assetId),
    position: selectCurrentAccountPerpsPosition(global, assetId),
    isSnapshotLoaded: Boolean(accountPerps?.snapshot),
    isSnapshotStale: isPerpsSnapshotStale(accountPerps?.snapshot),
    isClosePreparing: trade?.kind === 'close' && trade.assetId === assetId && !trade.quote,
    // Both tiles check the block reason of a close, so a filled close or reduce of another market that waits for its
    // withdrawal does not disable them. Confirmation checks the kind of the actual quote, so an increase still waits
    // for that withdrawal.
    tradeBlockReason: selectPerpsTradeBlockReason(global, assetId, 'close'),
    isViewMode: selectIsCurrentAccountViewMode(global),
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(PositionCard));
