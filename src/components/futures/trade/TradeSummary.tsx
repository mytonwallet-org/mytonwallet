import React, { memo, useLayoutEffect, useRef } from '../../../lib/teact/teact';

import type { ApiPerpsPositionSide, ApiToken } from '../../../api/types';

import { Big } from '../../../lib/big.js';
import buildClassName from '../../../util/buildClassName';
import { formatNumber, getIsCurrencySymbolAtStart } from '../../../util/formatNumber';
import { getPerpsValueTone, MISSING_VALUE } from '../helpers/formatPerps';

import useFontScale from '../../../hooks/useFontScale';

import TokenIcon from '../../common/TokenIcon';

import styles from './TradeSummary.module.scss';

interface OwnProps {
  /** Absent when the SDK does not know it, and a dash shows instead */
  amount?: string;
  /** The amount before the operation, shown with an arrow to `amount` */
  prevAmount?: string;
  /** Defaults to the symbol of `token` */
  currency?: string;
  /** Shown above the amount, which then goes without its gray box */
  token?: ApiToken;
  /** Names the amount, as in "Profit and Loss" */
  caption?: string;
  /** The position, as in "BTC 5x Long" */
  label?: string;
  side?: ApiPerpsPositionSide;
  /** The amount is a profit or a loss, so it gets a plus or a minus */
  withSign?: boolean;
  /** The amount is an estimate, so it gets "≈" */
  isEstimated?: boolean;
  /** An unknown amount is left out instead of showing a dash */
  shouldHideMissingAmount?: boolean;
  className?: string;
}

// The signs match `formatCurrencyExtended`
const SIGN_BY_TONE = {
  positive: '+ ',
  negative: '− ',
} as const;

function TradeSummary({
  amount,
  prevAmount,
  currency: currencyProp,
  token,
  caption,
  label,
  side,
  withSign,
  isEstimated,
  shouldHideMissingAmount,
  className,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { updateFontScale } = useFontScale(amountRef);

  const currency = currencyProp ?? token?.symbol ?? '';
  const isSymbolAtStart = getIsCurrencySymbolAtStart(currency);
  const isBoxed = !token;

  // A long change, as in "$12,345.67 → ≈ $12,400.12", shrinks to fit the width, as on iOS
  useLayoutEffect(updateFontScale, [amount, prevAmount, currency, withSign, isEstimated, isBoxed, updateFontScale]);

  function renderAmount(value: string) {
    const sign = withSign ? getSign(value) : '';
    const [wholePart, fractionPart] = formatNumber(Big(value).abs().toString()).split('.');
    const prefix = `${sign}${isSymbolAtStart ? currency : ''}`;

    return (
      <>
        {prefix && <span className={styles.symbol}>{prefix}</span>}
        {wholePart}
        {fractionPart && <span className={styles.fraction}>.{fractionPart}</span>}
        {!isSymbolAtStart && <span className={styles.symbol}>&thinsp;{currency}</span>}
      </>
    );
  }

  return (
    <div className={buildClassName(styles.root, className)}>
      {token && <TokenIcon token={token} size="xxx-large" className={styles.icon} />}
      {(amount !== undefined || !shouldHideMissingAmount) && (
        <div ref={amountRef} className={buildClassName(styles.amount, isBoxed && styles.amountBoxed, 'rounded-font')}>
          {prevAmount !== undefined && (
            <>
              {renderAmount(prevAmount)}
              <span className={styles.arrow}>→</span>
            </>
          )}
          {amount !== undefined ? (
            <>
              {isEstimated && <span className={styles.symbol}>≈&nbsp;</span>}
              {renderAmount(amount)}
            </>
          ) : MISSING_VALUE}
        </div>
      )}
      {caption && <div className={styles.caption}>{caption}</div>}
      {label && (
        <div
          className={buildClassName(
            styles.label,
            side === 'short' && styles.labelShort,
            side === 'long' && styles.labelLong,
          )}
        >
          {label}
        </div>
      )}
    </div>
  );
}

export default memo(TradeSummary);

function getSign(value: string) {
  const tone = getPerpsValueTone(value);

  return tone ? SIGN_BY_TONE[tone] : '';
}
