import React, { memo, useMemo } from '../../../lib/teact/teact';

import type { ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../api/types';

import buildClassName from '../../../util/buildClassName';
import { formatPercent } from '../../../util/formatNumber';
import { buildPerpsToken } from '../helpers/buildPerpsSections';
import {
  formatLeverage,
  formatPerpsMoney,
  formatPerpsSignedMoney,
  getPerpsRatioPercent,
  getPerpsValueTone,
  getSideLabel,
} from '../helpers/formatPerps';
import { PERPS_ROW_AMOUNT_MASK, PERPS_ROW_PNL_MASK } from '../helpers/sensitiveDataMasks';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TokenIcon from '../../common/TokenIcon';
import SensitiveData from '../../ui/SensitiveData';

import styles from './PositionRow.module.scss';

interface OwnProps {
  position: ApiPerpsAccountPosition;
  /** Absent until the catalogue loads, so the row falls back to the wire name and a letter icon */
  asset?: ApiPerpsMarketAsset;
  isSensitiveDataHidden?: true;
  onClick: (assetId: string) => void;
}

function PositionRow({
  position, asset, isSensitiveDataHidden, onClick,
}: OwnProps) {
  const lang = useLang();

  const { assetId, side, raw } = position;
  const token = useMemo(
    () => buildPerpsToken(asset ?? { id: assetId, symbol: raw.coin, chain: 'hyperliquid' }),
    [asset, assetId, raw.coin],
  );
  const pnlPercent = getPerpsRatioPercent(position.returnOnEquity);
  const pnlTone = getPerpsValueTone(raw.unrealizedPnl);

  const handleClick = useLastCallback(() => {
    onClick(assetId);
  });

  return (
    <button type="button" className={styles.root} onClick={handleClick}>
      <TokenIcon token={token} size="large" />
      <span className={styles.primary}>
        <span className={styles.name}>{token.name}</span>
        <span className={styles.subtitle}>{`${getSideLabel(lang, side)} ${formatLeverage(raw.leverage.value)}`}</span>
      </span>
      <span className={styles.secondary}>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          {...PERPS_ROW_AMOUNT_MASK}
          seed={assetId}
          align="right"
          className={styles.value}
        >
          {formatPerpsMoney(position.equity)}
        </SensitiveData>
        <span className={styles.pnlRow}>
          {position.isNearLiquidation && (
            <i
              className={buildClassName(styles.warning, 'icon-exclamation')}
              aria-label={lang('Liquidation Risk')}
              role="img"
            />
          )}
          <SensitiveData
            isActive={isSensitiveDataHidden}
            {...PERPS_ROW_PNL_MASK}
            seed={assetId}
            align="right"
            className={buildClassName(
              styles.pnl,
              pnlTone === 'positive' && styles.pnlPositive,
              pnlTone === 'negative' && styles.pnlNegative,
            )}
          >
            {formatPerpsSignedMoney(raw.unrealizedPnl)}
            {pnlPercent !== undefined && ` (${formatPercent(Math.abs(pnlPercent))})`}
          </SensitiveData>
        </span>
      </span>
    </button>
  );
}

export default memo(PositionRow);
