import React, { memo, useLayoutEffect, useRef } from '../../../lib/teact/teact';
import { withGlobal } from '../../../global';

import type { ApiBaseCurrency } from '../../../api/types';
import type { UserToken } from '../../../global/types';
import type { TokenBalanceChange } from '../helpers/resolveBalanceChange';

import { selectCurrentAccountId, selectIsMultichainAccount } from '../../../global/selectors';
import { getAssetAmountPrecision } from '../../../util/assetPrecision';
import buildClassName from '../../../util/buildClassName';
import { calcBigChangeValue } from '../../../util/calcChangeValue';
import { toBig, toDecimal } from '../../../util/decimals';
import { formatCurrency, formatPercent, getShortCurrencySymbol } from '../../../util/formatNumber';

import useFontScale from '../../../hooks/useFontScale';
import useFullAmountToggle from '../../../hooks/useFullAmountToggle';

import TokenIcon from '../../common/TokenIcon';
import SensitiveData from '../../ui/SensitiveData';
import Skeleton from '../../ui/Skeleton';

import styles from './Balance.module.scss';

interface OwnProps {
  token: UserToken;
  change?: TokenBalanceChange;
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
  token, change, baseCurrency, isSensitiveDataHidden, isMultichainAccount,
}: OwnProps & StateProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { updateFontScale } = useFontScale(amountRef);

  const { amount, decimals, symbol, price, change24h } = token;
  const currencySymbol = getShortCurrencySymbol(baseCurrency);
  // The chart reports a frame or two after mounting, and a skeleton shown until then would blink before a ready change
  const isChangeUnknown = !change;
  const isChangeLoading = isChangeUnknown || change.type === 'loading';
  const chartChange = change?.type === 'chart' ? change : undefined;

  const amountBig = toBig(amount, decimals);
  const valueBig = amountBig.mul(chartChange?.price ?? price);
  // With no chart point, only the 24h change ratio is known, and the amount is restored from it by
  // dividing by `1 + change24h`. A point carries both prices, so the amount is a subtraction, which
  // covers a zero price as well.
  const changeValue = chartChange
    ? amountBig.mul(chartChange.price - chartChange.initialPrice).toNumber()
    : calcBigChangeValue(valueBig, change24h).toNumber();
  const changePercent = (chartChange ? chartChange.price / chartChange.initialPrice - 1 : change24h) * 100;

  const { wholePart, fractionPart, handleAmountClick, hideFullAmount } = useFullAmountToggle(
    toDecimal(amount, decimals), decimals, getAssetAmountPrecision(token),
  );

  useLayoutEffect(updateFontScale, [wholePart, fractionPart, symbol, updateFontScale]);

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
        {isChangeLoading ? (
          <span className={isChangeUnknown ? styles.changeUnknown : undefined}>
            {' · '}
            <Skeleton className={styles.changeSkeleton} />
          </span>
        ) : change.type !== 'empty' && Boolean(changeValue) && (
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
