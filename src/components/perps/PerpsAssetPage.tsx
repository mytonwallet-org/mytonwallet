import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  ApiHistoryList,
  ApiPerpsAssetActivity,
  ApiPerpsAssetDetail,
  ApiPerpsListedAsset,
  ApiPriceHistoryPeriod,
} from '../../api/types';
import type { PerpsAssetDetailState } from '../../global/types';

import { selectPerpsAssetChart, selectPerpsAssetDetail, selectPerpsListedAsset } from '../../global/selectors';
import { DEFAULT_PRICE_HISTORY_PERIOD } from '../../util/priceHistory';
import usePerpsAssetPage from './usePerpsAssetPage';

import useLastCallback from '../../hooks/useLastCallback';

import TimeRangeSelector from '../common/TimeRangeSelector';
import Plot from '../tokenInfo/sections/Plot';
import Button from '../ui/Button';
import Spinner from '../ui/Spinner';

import styles from './PerpsAssetPage.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  assetId?: string;
  period: ApiPriceHistoryPeriod;
  detail?: PerpsAssetDetailState;
  history?: ApiHistoryList;
  listed?: ApiPerpsListedAsset;
}

const ACTIVITY_PREVIEW_LIMIT = 40;
const NO_SELECTION = -1;

function PerpsAssetPage({
  isActive,
  assetId,
  period,
  detail,
  history,
  listed,
}: OwnProps & StateProps) {
  const { closePerpsAsset, setCurrentPerpsAssetPeriod } = getActions();
  const [selectedIndex, setSelectedIndex] = useState(NO_SELECTION);

  useEffect(() => {
    setSelectedIndex(NO_SELECTION);
  }, [assetId, period]);

  usePerpsAssetPage({
    assetId,
    period,
    isActive,
    hasDetailError: detail?.hasError,
  });

  const marketAsset = detail?.data?.asset;
  const activities = useMemo(
    () => sortActivities(detail?.data?.activities),
    [detail?.data?.activities],
  );
  const shownActivities = activities.slice(0, ACTIVITY_PREVIEW_LIMIT);
  const selectedPrice = selectedIndex >= 0 ? history?.[selectedIndex]?.[1] : undefined;
  const title = marketAsset?.displayName || marketAsset?.symbol || listed?.symbol || assetId;
  const mark = selectedPrice ?? formatMark(marketAsset ?? listed);

  const handlePeriodChange = useLastCallback((nextPeriod: ApiPriceHistoryPeriod) => {
    setCurrentPerpsAssetPeriod({ period: nextPeriod });
  });

  const handleBack = useLastCallback(() => {
    closePerpsAsset();
  });

  return (
    <div className={styles.root}>
      <div className={styles.header}>
        <Button isSmall isSecondary onClick={handleBack}>
          Back
        </Button>
        <div className={styles.identity}>
          <div className={styles.title}>{title}</div>
          <div className={styles.subtitle}>{assetId}</div>
        </div>
        <div className={styles.mark}>{mark}</div>
      </div>

      {renderChart(history, selectedIndex, setSelectedIndex)}
      <TimeRangeSelector value={period} isPlain onChange={handlePeriodChange} />

      {detail?.hasError && !detail.data && (
        <div className={styles.error}>Could not load this asset. Retrying…</div>
      )}

      {!detail?.data && !detail?.hasError && (
        <div className={styles.chartState}>
          <Spinner />
        </div>
      )}

      {detail?.data && renderPosition(detail.data)}
      {detail?.data && renderActivities(shownActivities, activities.length)}
    </div>
  );
}

function renderChart(
  history: ApiHistoryList | undefined,
  selectedIndex: number,
  onSelectIndex: (index: number) => void,
) {
  if (!history) {
    return (
      <div className={styles.chartState}>
        <Spinner />
      </div>
    );
  }

  if (!history.length) {
    return <div className={styles.chartState}>No price data</div>;
  }

  return (
    <Plot
      prices={history}
      selectedIndex={selectedIndex}
      className={styles.chart}
      onSelectIndex={onSelectIndex}
    />
  );
}

function renderPosition(detail: ApiPerpsAssetDetail) {
  const { position } = detail;
  if (!position) {
    return <div className={styles.hint}>No open position.</div>;
  }

  return (
    <div className={styles.summary}>
      <Metric label="Side" value={`${position.side}${position.leverage ? ` ${position.leverage}x` : ''}`} />
      <Metric label="Size" value={position.size} />
      <Metric label="Entry" value={position.entryPrice} />
      <Metric label="Mark" value={position.markPrice} />
      <Metric label="Liquidation" value={position.liquidationPrice} />
      <Metric label="PnL" value={position.unrealizedPnl} />
      <Metric label="Margin" value={position.marginUsed} />
      <Metric label="ROE" value={position.returnOnEquity} />
    </div>
  );
}

function renderActivities(activities: ApiPerpsAssetActivity[], total: number) {
  return (
    <div className={styles.activities}>
      <div className={styles.sectionTitle}>Activity</div>
      {activities.length === 0 && <div className={styles.hint}>No activity for this asset.</div>}
      {activities.map((activity) => (
        <div key={activity.id} className={styles.activity}>
          <div>
            {activity.kind} {activity.side}
            {activity.size ? ` · ${activity.size}` : ''}
            {activity.positionSizeBefore !== undefined && activity.positionSizeAfter !== undefined
              ? ` · ${activity.positionSizeBefore} → ${activity.positionSizeAfter}`
              : ''}
            {activity.transferredAmount ? ` · ${activity.transferredAmount} USDC` : ''}
            {activity.realizedPnl ? ` · pnl ${activity.realizedPnl}` : ''}
          </div>
          <div className={styles.activityMeta}>{formatActivityTime(activity.timestamp)}</div>
        </div>
      ))}
      {total > activities.length && (
        <div className={styles.hint}>
          Showing first {activities.length} of {total}.
        </div>
      )}
    </div>
  );
}

function Metric({ label, value }: { label: string; value?: string }) {
  return (
    <div>
      <div className={styles.summaryLabel}>{label}</div>
      <div>{value || '—'}</div>
    </div>
  );
}

function formatMark(asset?: ApiPerpsListedAsset) {
  const mark = asset?.context.markPx || asset?.context.midPx || asset?.context.oraclePx;
  return mark ? `$${mark}` : '—';
}

function formatActivityTime(timestamp: number) {
  if (!timestamp) return '—';

  const millis = timestamp < 1e11 ? timestamp * 1000 : timestamp;
  return new Date(millis).toLocaleString();
}

function sortActivities(activities: ApiPerpsAssetActivity[] | undefined) {
  return [...(activities ?? [])].sort((left, right) => right.timestamp - left.timestamp);
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = global.currentAccountId;
  const accountState = accountId ? global.byAccountId[accountId] : undefined;
  const assetId = accountState?.currentPerpsAssetId;
  const period = accountState?.currentPerpsAssetPeriod ?? DEFAULT_PRICE_HISTORY_PERIOD;

  return {
    assetId,
    period,
    detail: selectPerpsAssetDetail(global, accountId, assetId),
    history: selectPerpsAssetChart(global, assetId, period),
    listed: assetId ? selectPerpsListedAsset(global, assetId) : undefined,
  };
})(PerpsAssetPage));
