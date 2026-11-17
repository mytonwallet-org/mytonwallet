import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsFill, ApiPerpsMarketAsset } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import buildClassName from '../../../util/buildClassName';
import { formatShortDay, formatTime, isToday } from '../../../util/dateFormat';
import {
  formatLeverageDirection,
  formatPerpsMoney,
  formatPerpsSignedMoney,
  getPerpsValueTone,
  getSideLabel,
} from '../helpers/formatPerps';
import { PERPS_ROW_AMOUNT_MASK } from '../helpers/sensitiveDataMasks';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import SensitiveData from '../../ui/SensitiveData';

import styles from './ActivityRow.module.scss';

interface OwnProps {
  fill: ApiPerpsFill;
  asset?: ApiPerpsMarketAsset;
  isSensitiveDataHidden?: true;
  onClick: (fill: ApiPerpsFill) => void;
}

function ActivityRow({
  fill, asset, isSensitiveDataHidden, onClick,
}: OwnProps) {
  const lang = useLang();

  const handleClick = useLastCallback(() => {
    onClick(fill);
  });

  const symbol = asset?.symbol ?? fill.coin;
  const badge = getFillBadge(lang, fill);

  return (
    <button type="button" className={styles.row} onClick={handleClick}>
      <span
        className={buildClassName(styles.icon, fill.eventKind === 'liquidated' && styles.iconLiquidated)}
        aria-hidden
      >
        <i className={getIconGlyph(fill)} />
      </span>
      <span className={styles.text}>
        <span className={styles.titleRow}>
          <span className={styles.title}>{getFillTitle(lang, fill, symbol)}</span>
          {badge && <span className={styles.badge}>{badge}</span>}
        </span>
        <span className={styles.date}>{formatActivityDate(lang, fill.time)}</span>
      </span>
      <span className={styles.amountColumn}>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          {...PERPS_ROW_AMOUNT_MASK}
          seed={String(fill.time)}
          align="right"
          className={styles.amount}
        >
          {renderFillAmount(fill)}
        </SensitiveData>
        <span className={styles.amountDetail}>{lang(isRealizingPnl(fill) ? 'Profit and Loss' : 'Trade Size')}</span>
      </span>
    </button>
  );
}

export default memo(ActivityRow);

// A reduce, a close or a liquidation shows the profit or the loss it realized, and other trades show their size, as on
// iOS. The collateral before and after a trade shows in its receipt.
function renderFillAmount(fill: ApiPerpsFill) {
  if (!isRealizingPnl(fill)) return formatPerpsMoney(fill.notional);

  const tone = getPerpsValueTone(fill.netPnl);

  return (
    <span className={tone && styles[tone]}>
      {formatPerpsSignedMoney(fill.netPnl)}
    </span>
  );
}

function isRealizingPnl({ eventKind }: ApiPerpsFill) {
  return eventKind === 'reduced' || eventKind === 'closed' || eventKind === 'liquidated';
}

/** The leverage and the side of the position, as in "5x Long". A trade without the leverage shows only the side. */
function getFillBadge(lang: LangFn, { positionSide, leverage }: ApiPerpsFill) {
  if (!positionSide) return undefined;

  return leverage ? formatLeverageDirection(lang, leverage, positionSide) : getSideLabel(lang, positionSide);
}

function getFillTitle(lang: LangFn, fill: ApiPerpsFill, symbol: string) {
  return fill.eventKind ? lang(`$perps_activity_${fill.eventKind}`, { asset: symbol }) as string : symbol;
}

function getIconGlyph({ eventKind }: ApiPerpsFill) {
  switch (eventKind) {
    case 'liquidated':
      return 'icon-exclamation';
    case 'reduced':
    case 'closed':
      return 'icon-receive-alt';
    default:
      return 'icon-send-alt';
  }
}

/** The day and the time of a row, as in "Aug 11 · 14:20" or "Today · 14:20" */
function formatActivityDate(lang: LangFn, time: number) {
  const day = isToday(time) ? lang('Today') : formatShortDay(lang.code!, time);

  return `${day} · ${formatTime(time)}`;
}
