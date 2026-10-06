import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useFontScale from '../../hooks/useFontScale';
import useFullAmountToggle from '../../hooks/useFullAmountToggle';

import SensitiveData from '../ui/SensitiveData';

import styles from './HeroAmount.module.scss';

interface OwnProps {
  value: string;
  decimals: number;
  prefix?: string;
  suffix?: string;
  baseCurrencyValue?: string;
  isPositive?: boolean;
  isNegative?: boolean;
  isSensitiveDataHidden?: true;
  className?: string;
}

function HeroAmount({
  value, decimals, prefix, suffix, baseCurrencyValue, isPositive, isNegative, isSensitiveDataHidden, className,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { updateFontScale } = useFontScale(amountRef);
  const { wholePart, fractionPart, handleAmountClick, hideFullAmount } = useFullAmountToggle(value, decimals);

  useLayoutEffect(updateFontScale, [
    wholePart, fractionPart, prefix, suffix, isPositive, isNegative, isSensitiveDataHidden, updateFontScale,
  ]);

  return (
    <div className={buildClassName(styles.block, className)}>
      <SensitiveData
        isActive={isSensitiveDataHidden}
        rows={2}
        cols={8}
        cellSize={19}
        align="center"
        className={styles.sensitiveData}
        contentClassName={styles.sensitiveDataContent}
        onClick={handleAmountClick}
        onContentHidden={hideFullAmount}
      >
        <div ref={amountRef} className={buildClassName(styles.amount, 'rounded-font')}>
          {isPositive && <>+&#8239;</>}
          {isNegative && <>&minus;&#8239;</>}
          {prefix && <span className={styles.symbol}>{prefix}</span>}
          {wholePart}
          {fractionPart && <span className={styles.fraction}>.{fractionPart}</span>}
          {suffix && <span className={styles.symbol}>&thinsp;{suffix}</span>}
        </div>
      </SensitiveData>
      {baseCurrencyValue && (
        <div className={styles.secondary}>
          <SensitiveData isActive={isSensitiveDataHidden} rows={2} cols={10} cellSize={8} align="center">
            ≈&thinsp;{baseCurrencyValue}
          </SensitiveData>
        </div>
      )}
    </div>
  );
}

export default memo(HeroAmount);
