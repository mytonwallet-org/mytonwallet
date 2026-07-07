import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { formatNumber } from '../../util/formatNumber';

import useFontScale from '../../hooks/useFontScale';

import styles from './WalletConnectPay.module.scss';

interface OwnProps {
  value: string;
  decimals: number;
  prefix?: string;
  suffix?: string;
  baseCurrencyValue?: string;
}

function WalletConnectPayAmount({
  value, decimals, prefix, suffix, baseCurrencyValue,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { updateFontScale } = useFontScale(amountRef);

  const [wholePart, fractionPart] = formatNumber(value, decimals).split('.');

  useLayoutEffect(updateFontScale, [value, decimals, prefix, suffix, updateFontScale]);

  return (
    <div className={styles.paymentAmountBlock}>
      <div ref={amountRef} className={buildClassName(styles.paymentAmount, 'rounded-font')}>
        {prefix && <span className={styles.paymentAmountSymbol}>{prefix}</span>}
        {wholePart}
        {fractionPart && <span className={styles.paymentAmountFraction}>.{fractionPart}</span>}
        {suffix && <span className={styles.paymentAmountSymbol}>&thinsp;{suffix}</span>}
      </div>
      {baseCurrencyValue && (
        <div className={styles.paymentAmountSecondary}>≈&thinsp;{baseCurrencyValue}</div>
      )}
    </div>
  );
}

export default memo(WalletConnectPayAmount);
