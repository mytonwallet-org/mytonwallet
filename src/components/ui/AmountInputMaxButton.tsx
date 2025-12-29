import React, { memo } from '../../lib/teact/teact';

import type { ApiToken } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, formatCurrencySimple } from '../../util/formatNumber';

import useLang from '../../hooks/useLang';
import { useTransitionActiveKey } from '../../hooks/useTransitionActiveKey';

import Transition from './Transition';

import styles from './AmountInputMaxButton.module.scss';

interface OwnProps {
  maxAmount?: bigint;
  token?: Pick<ApiToken, 'symbol' | 'decimals'>;
  isLoading?: boolean;
  isSensitiveDataHidden?: boolean;
  /** If true, the label will say "All" instead of "Max" and all the amount digits will be shown (made for unstaking) */
  isAllMode?: boolean;
  isDisabled?: boolean;
  onAmountClick(maxAmount?: bigint): void;
}

/**
 * Put the element right above a <RichNumberInput />, it will take the space right to the input label without moving the
 * around content.
 */
function AmountInputMaxButton({
  maxAmount,
  token,
  isLoading,
  isSensitiveDataHidden,
  isAllMode,
  isDisabled,
  onAmountClick,
}: OwnProps) {
  const lang = useLang();

  const content = isLoading
    ? lang('Loading...')
    : !token || maxAmount === undefined
      ? ''
      : isSensitiveDataHidden
        ? `*** ${token.symbol}`
        : isAllMode
          ? formatCurrencySimple(maxAmount, token.symbol, token.decimals)
          : formatCurrency(toDecimal(maxAmount, token.decimals), token.symbol);

  const transitionKey = useTransitionActiveKey([!content, token?.symbol, isLoading, isSensitiveDataHidden]);

  return (
    <Transition
      name="fade"
      activeKey={transitionKey}
      shouldCleanup
      className={styles.container}
    >
      {content && (
        <span className={styles.content}>
          {lang(isAllMode ? '$all_balance' : '$max_balance', {
            balance: isDisabled ? <div className={styles.amount}>{content}</div>
              : (
                <div
                  role="button"
                  tabIndex={0}
                  onClick={() => onAmountClick(maxAmount)}
                  className={buildClassName(styles.amount, styles.link)}
                >
                  {content}
                </div>
              ),
          })}
        </span>
      )}
    </Transition>
  );
}

export default memo(AmountInputMaxButton);
