import React, { memo } from '../../../lib/teact/teact';

import type { ApiBaseCurrency } from '../../../api/types';
import type { NetChange } from '../helpers/computeNetChange';

import buildClassName from '../../../util/buildClassName';
import {
  formatCurrency, formatCurrencyExtended, formatPercent, getShortCurrencySymbol,
} from '../../../util/formatNumber';

import useLang from '../../../hooks/useLang';

import styles from './Balance.module.scss';

interface OwnProps {
  totalAmount: number;
  baseCurrency: ApiBaseCurrency;
  netChange?: NetChange;
}

function Balance({ totalAmount, baseCurrency, netChange }: OwnProps) {
  const lang = useLang();
  const shortSymbol = getShortCurrencySymbol(baseCurrency);

  const hasNetChange = netChange !== undefined && Number.isFinite(netChange.absolute);
  const isPositive = hasNetChange && netChange.absolute > 0;
  const isNegative = hasNetChange && netChange.absolute < 0;

  return (
    <section className={styles.root}>
      <div className={styles.column}>
        <div className={styles.value}>{formatCurrency(totalAmount, shortSymbol)}</div>
        <div className={styles.label}>{lang('Total Balance')}</div>
      </div>

      <div className={styles.column}>
        {hasNetChange ? (
          <div className={styles.value}>
            <span>{formatCurrencyExtended(netChange.absolute, shortSymbol)}</span>
            {netChange.percent !== undefined && (
              <span
                className={buildClassName(
                  styles.pill,
                  isPositive && styles.pillPositive,
                  isNegative && styles.pillNegative,
                )}
              >
                {formatSignedPercent(netChange.percent)}
              </span>
            )}
          </div>
        ) : (
          <div className={styles.value}>&mdash;</div>
        )}
        <div className={styles.label}>{lang('Net Change')}</div>
      </div>
    </section>
  );
}

export default memo(Balance);

function formatSignedPercent(percent: number): string {
  const sign = percent > 0 ? '+' : percent < 0 ? '−' : '';
  return `${sign}${formatPercent(Math.abs(percent))}`;
}
