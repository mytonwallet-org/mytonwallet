import React, { memo } from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiToken } from '../../api/types';
import type { UserSwapToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import FiatCurrencyIcon from '../common/FiatCurrencyIcon';
import TokenIcon from '../common/TokenIcon';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  token?: UserSwapToken | ApiToken;
  /** A card payment shows its currency in place of a token */
  currency?: ApiBaseCurrency;
  label: string;
  /** The formatted amount, absent until it is known */
  amount?: string;
  isAmountLoading?: boolean;
  symbol: string;
  badge?: string;
  isLabelMuted?: boolean;
  hasCaret?: boolean;
  /** Without it, the row is not a button */
  onClick?: NoneToVoidFunction;
}

/** The other side of a trade form: what the user pays or receives for the amount */
function TradeCounterRow({
  token, currency, label, amount, isAmountLoading, symbol, badge, isLabelMuted, hasCaret, onClick,
}: OwnProps) {
  function renderContent() {
    return (
      <>
        {currency ? (
          <FiatCurrencyIcon currency={currency} size="small" className={styles.counterIcon} />
        ) : token && (
          <TokenIcon
            token={token}
            withChainIcon
            className={styles.counterIcon}
            iconClassName={styles.counterIconImage}
          />
        )}
        <span className={buildClassName(styles.counterLabel, isLabelMuted && styles.counterLabelMuted)}>{label}</span>
        <span className={styles.counterValue}>
          {amount !== undefined && (
            <span className={buildClassName(styles.counterAmount, isAmountLoading && styles.loading)}>{amount}</span>
          )}
          <span className={styles.counterSymbol}>{symbol}</span>
          {Boolean(badge) && <span className={styles.counterBadge}>{badge}</span>}
          {hasCaret && <i className={buildClassName(styles.counterCaret, 'icon-expand')} aria-hidden />}
        </span>
      </>
    );
  }

  if (!onClick) {
    return <div className={buildClassName(styles.counterRow, styles.counterRowStatic)}>{renderContent()}</div>;
  }

  return (
    <button type="button" className={styles.counterRow} onClick={onClick}>
      {renderContent()}
    </button>
  );
}

export default memo(TradeCounterRow);
