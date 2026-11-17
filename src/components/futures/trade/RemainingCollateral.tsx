import React, { memo } from '../../../lib/teact/teact';

import { Big } from '../../../lib/big.js';
import { isPerpsNumber } from '../../../global/helpers/perps';
import { formatPerpsUsdc, formatPerpsUsdcEstimate } from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';

import DetailRow from '../DetailRow';

import styles from './TradeModal.module.scss';

interface OwnProps {
  /** USDC of the deposit that stays outside the position after rounding to the trade size of the market */
  amount: string;
  isEstimated?: boolean;
}

/** The deposit left outside the position, shown only when something is left */
function RemainingCollateral({ amount, isEstimated }: OwnProps) {
  const lang = useLang();

  if (!isPerpsNumber(amount) || Big(amount).lte(0)) return undefined;

  return (
    <div className={styles.card}>
      <DetailRow
        label={lang('PerpsUnallocatedCollateral')}
        hint={lang('PerpsUnallocatedCollateralHint')}
        value={isEstimated ? formatPerpsUsdcEstimate(amount) : formatPerpsUsdc(amount)}
      />
    </div>
  );
}

export default memo(RemainingCollateral);
