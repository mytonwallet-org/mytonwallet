import React, { memo } from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiTokenWithPrice } from '../../api/types';

import { UNKNOWN_TOKEN } from '../../config';
import { bigintAbs } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatBaseCurrencyAmount, formatCurrencyExtended } from '../../util/formatNumber';

import SensitiveData from '../ui/SensitiveData';

import styles from './TransactionAmount.module.scss';

interface OwnProps {
  amount: bigint;
  token?: Pick<ApiTokenWithPrice, 'decimals' | 'symbol' | 'priceUsd' | 'slug'>;
  isIncoming?: boolean;
  isScam?: boolean;
  isFailed?: boolean;
  status?: string;
  noSign?: boolean;
  isSensitiveDataHidden?: true;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  onTokenClick?: (slug: string) => void;
}

function TransactionAmount({
  isIncoming,
  isScam,
  isFailed,
  amount,
  token,
  status,
  noSign = false,
  isSensitiveDataHidden,
  baseCurrency,
  currencyRates,
  onTokenClick,
}: OwnProps) {
  const typeClass = isFailed || isScam
    ? styles.operationNegative
    : isIncoming ? styles.operationPositive : undefined;

  function handleClick() {
    if (onTokenClick && token?.slug) {
      onTokenClick(token.slug);
    }
  }

  function renderAmount() {
    const { decimals, symbol } = token ?? UNKNOWN_TOKEN;
    const amountString = toDecimal(noSign ? bigintAbs(amount) : amount, decimals);
    const [wholePart, fractionPart]
      = formatCurrencyExtended(amountString, '', noSign, decimals, !isIncoming).split('.');
    const withStatus = Boolean(status);
    const isClickable = Boolean(onTokenClick && token?.slug);

    return (
      <SensitiveData
        isActive={isSensitiveDataHidden}
        cols={12}
        rows={withStatus ? 7 : 4}
        align="center"
        cellSize={withStatus ? 17 : 18}
        className={buildClassName(styles.amountSensitiveData, status && styles.withStatus)}
      >
        <div
          className={buildClassName(
            styles.amount,
            status && styles.withStatus,
            typeClass,
            'rounded-font',
            isClickable && styles.clickable,
          )}
          onClick={isClickable ? handleClick : undefined}
        >
          {wholePart.trim().replace('\u202F', '')}
          {fractionPart && <span className={styles.amountFraction}>.{fractionPart.trim()}</span>}
          <span className={styles.amountSymbol}>{symbol}</span>
        </div>
        {withStatus && (
          <div className={buildClassName(styles.status, typeClass)}>
            {status}
          </div>
        )}
      </SensitiveData>
    );
  }

  function renderBaseCurrencyAmount() {
    if (!token) {
      return undefined;
    }

    return (
      <SensitiveData
        isActive={isSensitiveDataHidden}
        cols={10}
        rows={3}
        align="center"
        cellSize={12}
        className={styles.baseCurrencyAmountSensitiveData}
        contentClassName={buildClassName(styles.baseCurrencyAmount, 'rounded-font', typeClass)}
      >
        {formatBaseCurrencyAmount(amount, baseCurrency, token, currencyRates)}
      </SensitiveData>
    );
  }

  return (
    <>
      {renderAmount()}
      {renderBaseCurrencyAmount()}
    </>
  );
}

export default memo(TransactionAmount);
