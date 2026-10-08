import React, { memo } from '../../lib/teact/teact';

import type { ApiBaseCurrency } from '../../api/types';

import { CURRENCIES } from '../../config';
import buildClassName from '../../util/buildClassName';

import styles from './FiatCurrencyIcon.module.scss';

interface OwnProps {
  currency: ApiBaseCurrency;
  size?: 'small' | 'large';
  className?: string;
}

function FiatCurrencyIcon({ currency, size = 'large', className }: OwnProps) {
  return (
    <div className={buildClassName(styles.icon, styles[size], 'rounded-font', className)} aria-hidden>
      {CURRENCIES[currency].shortSymbol ?? currency}
    </div>
  );
}

export default memo(FiatCurrencyIcon);
