import React, { memo } from '../../../lib/teact/teact';
import { withGlobal } from '../../../global';

import type { ApiBaseCurrency } from '../../../api/types';
import type { UserToken } from '../../../global/types';
import type { TokenPricePoint } from './Chart';

import buildClassName from '../../../util/buildClassName';
import { calcBigChangeValue } from '../../../util/calcChangeValue';
import { toBig, toDecimal } from '../../../util/decimals';
import { formatCurrency, formatNumber, formatPercent, getShortCurrencySymbol } from '../../../util/formatNumber';

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
}

const SENSITIVE_DATA_COLS = 10;
const SENSITIVE_DATA_ROWS = 2;
const SENSITIVE_DATA_CELL_SIZE = 10;

function Balance({ token, pricePoint, baseCurrency, isSensitiveDataHidden }: OwnProps & StateProps) {
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

  const [wholePart, fractionPart] = formatNumber(toDecimal(amount, decimals)).split('.');

  return (
    <div className={styles.root}>
      <TokenIcon token={token} size="xx-large" className={styles.icon} />

      <SensitiveData
        isActive={isSensitiveDataHidden}
        align="center"
        cols={SENSITIVE_DATA_COLS}
        rows={SENSITIVE_DATA_ROWS}
        cellSize={SENSITIVE_DATA_CELL_SIZE}
        className={buildClassName(styles.amount, 'rounded-font')}
      >
        {wholePart}
        <span className={styles.amountSecondary}>
          {fractionPart && `.${fractionPart}`}
          {' '}
          {symbol}
        </span>
      </SensitiveData>

      <SensitiveData
        isActive={isSensitiveDataHidden}
        align="center"
        cols={SENSITIVE_DATA_COLS}
        rows={SENSITIVE_DATA_ROWS}
        cellSize={SENSITIVE_DATA_CELL_SIZE}
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
    };
  })(Balance),
);
