import React, { memo } from '../../../lib/teact/teact';

import type { ApiBaseCurrency } from '../../../api/types';
import type { PortfolioPnlChange } from '../../../global/types';

import buildClassName from '../../../util/buildClassName';
import {
  formatCurrency, formatCurrencyExtended, formatSignedPercent, getShortCurrencySymbol,
} from '../../../util/formatNumber';

import useLang from '../../../hooks/useLang';

import styles from './Balance.module.scss';

interface OwnProps {
  totalAmount: number;
  baseCurrency: ApiBaseCurrency;
  pnlChange?: PortfolioPnlChange;
  isPnlChangeUpdating?: boolean;
}

function Balance({ totalAmount, baseCurrency, pnlChange, isPnlChangeUpdating }: OwnProps) {
  const lang = useLang();
  const shortSymbol = getShortCurrencySymbol(baseCurrency);

  const hasPnlChange = pnlChange !== undefined && Number.isFinite(pnlChange.amount);
  const isPositive = hasPnlChange && pnlChange.amount > 0;
  const isNegative = hasPnlChange && pnlChange.amount < 0;

  return (
    <section className={styles.root}>
      <div className={styles.column}>
        <div className={styles.value}>{formatCurrency(totalAmount, shortSymbol)}</div>
        <div className={styles.label}>{lang('Total Balance')}</div>
      </div>

      <div className={styles.column}>
        <div className={buildClassName(styles.value, isPnlChangeUpdating && 'glare-text')}>
          {hasPnlChange ? (
            <>
              <span className={styles.valueChange}>{formatCurrencyExtended(pnlChange.amount, shortSymbol)}</span>
              {pnlChange.percent !== undefined && (
                <span
                  className={buildClassName(
                    styles.pill,
                    isPositive && styles.pillPositive,
                    isNegative && styles.pillNegative,
                  )}
                >
                  {formatSignedPercent(pnlChange.percent)}
                </span>
              )}
            </>
          ) : (
            <span>&mdash;</span>
          )}
        </div>
        <div className={styles.label}>{lang('P&L Change')}</div>
      </div>
    </section>
  );
}

export default memo(Balance);
