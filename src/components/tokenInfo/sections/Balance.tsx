import React, { memo, useLayoutEffect, useRef } from '../../../lib/teact/teact';
import { withGlobal } from '../../../global';

import type { ApiBaseCurrency } from '../../../api/types';
import type { UserToken } from '../../../global/types';
import type { TokenPricePoint } from './Chart';

import { selectCurrentAccountId, selectIsMultichainAccount } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { calcBigChangeValue } from '../../../util/calcChangeValue';
import { toBig, toDecimal } from '../../../util/decimals';
import { formatCurrency, formatNumber, formatPercent, getShortCurrencySymbol } from '../../../util/formatNumber';

import useFlag from '../../../hooks/useFlag';
import useFontScale from '../../../hooks/useFontScale';
import useLastCallback from '../../../hooks/useLastCallback';

import TokenIcon from '../../common/TokenIcon';
import SensitiveData from '../../ui/SensitiveData';

import styles from './Balance.module.scss';

interface OwnProps {
  token: UserToken;
  /** Follows the chart: the price under the cursor, or the last one of the shown period */
  pricePoint?: TokenPricePoint;
}

interface StateProps {
  baseCurrency: ApiBaseCurrency;
  isSensitiveDataHidden?: true;
  isMultichainAccount: boolean;
}

// The mask sizes match the text they cover: `rows * cellSize` is the line height, `cols * cellSize` the width
const AMOUNT_MIN_COLS = 8;
const AMOUNT_MAX_COLS = 12;
const AMOUNT_ROWS = 3;
const AMOUNT_CELL_SIZE = 13;
const VALUE_COLS = 14;
const VALUE_ROWS = 2;
const VALUE_CELL_SIZE = 10;

function Balance({
  token, pricePoint, baseCurrency, isSensitiveDataHidden, isMultichainAccount,
}: OwnProps & StateProps) {
  const amountRef = useRef<HTMLDivElement>();
  const [isFullAmount, showFullAmount, hideFullAmount] = useFlag();
  const { updateFontScale } = useFontScale(amountRef);

  const { amount, decimals, symbol, price, change24h } = token;
  const currencySymbol = getShortCurrencySymbol(baseCurrency);

  const amountBig = toBig(amount, decimals);
  const valueBig = amountBig.mul(pricePoint?.price ?? price);
  // With no chart point, only the 24h change ratio is known, and the amount is restored from it by
  // dividing by `1 + change24h`. A point carries both prices, so the amount is a subtraction, which
  // covers a zero price as well.
  const changeValue = pricePoint
    ? amountBig.mul(pricePoint.price - pricePoint.initialPrice).toNumber()
    : calcBigChangeValue(valueBig, change24h).toNumber();
  const changePercent = (pricePoint ? pricePoint.price / pricePoint.initialPrice - 1 : change24h) * 100;

  const decimalAmount = toDecimal(amount, decimals);
  const [wholePart, fractionPart] = (isFullAmount
    ? formatNumber(decimalAmount, decimals, undefined, true)
    : formatNumber(decimalAmount)
  ).split('.');

  useLayoutEffect(updateFontScale, [wholePart, fractionPart, symbol, updateFontScale]);

  // The mask reveal takes the first tap, so the full amount comes on the second one, and the third one
  // returns the mask (the click is handed back to `SensitiveData` by returning a falsy value)
  const handleAmountClick = useLastCallback(() => {
    if (isFullAmount) {
      hideFullAmount();
      return false;
    }

    showFullAmount();
    return true;
  });

  return (
    <div className={styles.root}>
      <TokenIcon token={token} size="xx-large" withChainIcon={isMultichainAccount} className={styles.icon} />

      <div ref={amountRef} className={styles.amountWrapper}>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          align="center"
          min={AMOUNT_MIN_COLS}
          max={AMOUNT_MAX_COLS}
          seed={symbol}
          rows={AMOUNT_ROWS}
          cellSize={AMOUNT_CELL_SIZE}
          className={buildClassName(styles.amount, 'rounded-font')}
          onClick={handleAmountClick}
          onContentHidden={hideFullAmount}
        >
          {wholePart}
          <span className={styles.amountSecondary}>
            {fractionPart && `.${fractionPart}`}
            {' '}
            {symbol}
          </span>
        </SensitiveData>
      </div>

      <SensitiveData
        isActive={isSensitiveDataHidden}
        align="center"
        cols={VALUE_COLS}
        rows={VALUE_ROWS}
        cellSize={VALUE_CELL_SIZE}
        className={styles.value}
      >
        {formatCurrency(valueBig, currencySymbol)}
        {Boolean(changeValue) && (
          <span className={buildClassName(styles.change, changeValue > 0 ? styles.positive : styles.negative)}>
            {' · '}
            {changeValue > 0 ? '↑' : '↓'}&thinsp;
            {formatCurrency(Math.abs(changeValue), currencySymbol)}
            {` (${formatPercent(Math.abs(changePercent))})`}
          </span>
        )}
      </SensitiveData>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    return {
      baseCurrency: global.settings.baseCurrency,
      isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
      isMultichainAccount: selectIsMultichainAccount(global, selectCurrentAccountId(global)!),
    };
  })(Balance),
);
