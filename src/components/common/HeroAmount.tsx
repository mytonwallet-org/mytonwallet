import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { formatNumber } from '../../util/formatNumber';

import useFontScale from '../../hooks/useFontScale';

import SensitiveData from '../ui/SensitiveData';

import styles from './HeroAmount.module.scss';

interface OwnProps {
  value: string;
  decimals: number;
  prefix?: string;
  suffix?: string;
  baseCurrencyValue?: string;
  isSensitiveDataHidden?: true;
}

function HeroAmount({
  value, decimals, prefix, suffix, baseCurrencyValue, isSensitiveDataHidden,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { updateFontScale } = useFontScale(amountRef);

  const [wholePart, fractionPart] = formatNumber(value, decimals).split('.');

  useLayoutEffect(updateFontScale, [value, decimals, prefix, suffix, isSensitiveDataHidden, updateFontScale]);

  return (
    <div className={styles.block}>
      <SensitiveData
        isActive={isSensitiveDataHidden}
        rows={2}
        cols={8}
        cellSize={19}
        align="center"
        className={styles.sensitiveData}
        contentClassName={styles.sensitiveDataContent}
      >
        <div ref={amountRef} className={buildClassName(styles.amount, 'rounded-font')}>
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
