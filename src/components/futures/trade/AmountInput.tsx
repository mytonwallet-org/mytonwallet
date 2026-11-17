import React, { memo } from '../../../lib/teact/teact';

import { PERPS_AMOUNT_DECIMALS } from '../../../global/helpers/perps';
import buildClassName from '../../../util/buildClassName';
import { PERPS_CURRENCY_SYMBOL } from '../helpers/formatPerps';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';

import TradeAmountInput from '../../swap/TradeAmountInput';

import tradeStyles from '../../swap/TokenTrade.module.scss';
import styles from './TradeForm.module.scss';

interface OwnProps {
  value?: string;
  /** The collateral converted to the coins of the market, as in "0.0012 BTC". Absent while the coins are unknown. */
  coinText?: string;
  /** Shows a button that restores the amount the form started with */
  canReset?: boolean;
  /**
   * Shows the clear button while the field has a value. The edit form keeps it off, since its reset button restores
   * the current amount.
   */
  canClear?: boolean;
  onChange: (value?: string) => void;
  onSubmit: (e: React.FormEvent | React.UIEvent) => void;
  onClear: NoneToVoidFunction;
  onReset?: NoneToVoidFunction;
}

/** The collateral field of the trade forms. The collateral is in dollars, and the coins show above it. */
function AmountInput({
  value, coinText, canReset, canClear, onChange, onSubmit, onClear, onReset,
}: OwnProps) {
  // The chip keeps its place and its last coins while it fades out, so the amount below does not move
  const renderedCoinText = useCurrentOrPrev(coinText, true);

  return (
    <div className={tradeStyles.amountBlock}>
      <span
        className={buildClassName(styles.coinChip, !coinText && styles.coinChipHidden)}
        aria-hidden={!coinText || undefined}
      >
        {renderedCoinText}
      </span>
      <TradeAmountInput
        id="perps-trade-amount"
        value={value}
        prefix={PERPS_CURRENCY_SYMBOL}
        decimals={PERPS_AMOUNT_DECIMALS}
        canReset={canReset}
        noClear={!canClear}
        onChange={onChange}
        onPressEnter={onSubmit}
        onClear={onClear}
        onReset={onReset}
      />
    </div>
  );
}

export default memo(AmountInput);
