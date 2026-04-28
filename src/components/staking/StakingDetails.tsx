import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiStakingState } from '../../api/types';
import type { UserToken } from '../../global/types';

import { SHORT_FRACTION_DIGITS } from '../../config';
import { Big } from '../../lib/big.js';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, formatNumber, getShortCurrencySymbol } from '../../util/formatNumber';

import useLang from '../../hooks/useLang';

import styles from './Staking.module.scss';

interface OwnProps {
  stakingState: ApiStakingState;
  symbol: string;
  amount: bigint | undefined;
  decimals: number;
  annualYieldText: string;
  isBaseCurrency: boolean;
  token: UserToken | undefined;
  baseCurrency: ApiBaseCurrency;
  onSafeInfoClick: () => void;
}

function StakingDetails({
  stakingState,
  symbol,
  amount,
  decimals,
  annualYieldText,
  isBaseCurrency,
  token,
  baseCurrency,
  onSafeInfoClick,
}: OwnProps) {
  const lang = useLang();

  const annualEarnings = useMemo(
    () => Big(toDecimal(amount ?? 0n, decimals, true)).mul(stakingState.annualYield).div(100),
    [amount, decimals, stakingState.annualYield],
  );

  const earningsValue = useMemo(() => {
    if (isBaseCurrency && token?.price != undefined) {
      return `+\u202F${formatCurrency(
        annualEarnings.mul(token.price), getShortCurrencySymbol(baseCurrency), SHORT_FRACTION_DIGITS,
      )}`;
    }
    return `+\u202F${formatCurrency(annualEarnings, symbol, SHORT_FRACTION_DIGITS)}`;
  }, [annualEarnings, isBaseCurrency, token?.price, baseCurrency, symbol]);

  return (
    <section className={styles.detailsSection}>
      <div className={styles.detailsSectionTitle}>{lang('Staking Details')}</div>

      <div className={styles.detailsCard}>
        <div className={styles.detailsRow}>
          <span className={styles.detailsLabel}>
            {lang('Current APY')}
          </span>
          <span className={buildClassName(styles.detailsValue, styles.detailsValue_highlightBlock)}>
            {annualYieldText}
          </span>
        </div>

        <div className={styles.detailsRow}>
          <span className={styles.detailsLabel}>{lang('Est. Yearly Earnings')}</span>
          <span className={buildClassName(styles.detailsValue, styles.detailsValue_highlight)}>
            {earningsValue}
          </span>
        </div>

        {stakingState.type === 'liquid' && (
          <>
            <div className={styles.detailsRow}>
              <span className={styles.detailsLabel}>{lang('Total Staked')}</span>
              <span className={styles.detailsValue}>
                {formatCurrency(toDecimal(stakingState.tvl, decimals), symbol, 0)}
              </span>
            </div>
            <div className={styles.detailsRow}>
              <span className={styles.detailsLabel}>{lang('Total Stakers')}</span>
              <span className={styles.detailsValue}>
                {formatNumber(stakingState.totalStakers, 0, true)}
              </span>
            </div>
          </>
        )}

        <button
          type="button"
          className={buildClassName(styles.detailsRow, styles.detailsRow_button)}
          onClick={onSafeInfoClick}
        >
          <span className={styles.detailsLabel}>{lang('Why this is safe')}</span>
        </button>
      </div>
    </section>
  );
}

export default memo(StakingDetails);
