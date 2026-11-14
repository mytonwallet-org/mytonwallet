import type { TeactNode } from '../../../lib/teact/teact';
import React, { memo, useMemo } from '../../../lib/teact/teact';

import type { ApiSwapHint } from '../../../api/types';
import type { TradeDirection, UserSwapToken } from '../../../global/types';

import { Big } from '../../../lib/big.js';
import buildClassName from '../../../util/buildClassName';
import { formatCurrency, formatCurrencySimple } from '../../../util/formatNumber';
import { toNativeDigits } from '../../../util/nativeDigits';
import { openUrl } from '../../../util/openUrl';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import styles from './SwapHint.module.scss';

interface OwnProps {
  hint: ApiSwapHint;
  tokens?: UserSwapToken[];
  tokenIn?: UserSwapToken;
  /** The token being received */
  tokenOut?: UserSwapToken;
  /** On the Buy / Sell screen the hint speaks of an exchange and has its own look */
  tradeDirection?: TradeDirection;
  className?: string;
  /** The token to get first goes in place of the token being received */
  onIntermediateClick: (tokenSlug: string) => void;
}

/** The way around a pair the backend cannot swap directly */
function SwapHint({
  hint,
  tokens,
  tokenIn,
  tokenOut,
  tradeDirection,
  className,
  onIntermediateClick,
}: OwnProps) {
  const lang = useLang();

  const intermediateToken = useMemo(() => (
    hint.type === 'intermediate' ? tokens?.find(({ slug }) => slug === hint.token) : undefined
  ), [hint, tokens]);

  const handleActionClick = useLastCallback(() => {
    if (hint.type === 'external') {
      void openUrl(hint.url, { isExternal: true, title: hint.providerName });
    } else if (intermediateToken) {
      onIntermediateClick(intermediateToken.slug);
    }
  });

  if (hint.type === 'oneToOne' || hint.type === 'betterRate' || hint.type === 'betterRateMinimum') {
    let message: TeactNode;
    if (hint.type === 'oneToOne') {
      if (!tokenIn) return undefined;
      const minimum = Big(hint.minimumAmount).round(2, Big.roundUp);
      const value = toNativeDigits(formatCurrency(minimum, tokenIn.symbol));
      message = lang('$swap_one_to_one', { value });
    } else if (hint.type === 'betterRateMinimum') {
      const value = toNativeDigits(formatCurrencySimple(hint.minimumAmount, hint.symbol));
      message = lang('$swap_better_rate_minimum', { value });
    } else {
      message = lang('Better rate is available if you add %amount% %symbol% for network fee.', {
        amount: Big(hint.additionalAmount).prec(2, Big.roundUp).toFixed(),
        symbol: hint.symbol,
      });
    }
    return (
      <div className={buildClassName(styles.root, tradeDirection && styles.trade, className)}>
        <span className={styles.message}>{message}</span>
      </div>
    );
  }

  let title: TeactNode;
  let message: TeactNode;
  let actionTitle: TeactNode;

  if (hint.type === 'external') {
    title = lang('Swap on an external service');
    message = lang('Open %provider% to swap this pair in the browser.', { provider: hint.providerName });
    actionTitle = lang('Open %provider%', { provider: hint.providerName });
  } else {
    if (!intermediateToken || !tokenOut) return undefined;

    const symbols = { buy_token: tokenOut.symbol, token: intermediateToken.symbol };
    const isSell = tradeDirection === 'sell';

    title = lang(tradeDirection ? 'Direct exchange unavailable' : 'Direct swap unavailable');
    message = isSell
      ? lang('To receive %buy_token%, first receive %token%, then exchange it for %buy_token%.', symbols)
      : lang('To buy %buy_token%, first buy %token%, then swap it for %buy_token%.', symbols);
    actionTitle = isSell
      ? lang('Receive %value%', { value: intermediateToken.symbol })
      : lang('Buy %token%', { token: intermediateToken.symbol });
  }

  return (
    <div className={buildClassName(styles.root, tradeDirection && styles.trade, className)}>
      <div className={styles.text}>
        <span className={styles.title}>{title}</span>
        <span className={styles.message}>{message}</span>
      </div>
      <button type="button" className={styles.action} onClick={handleActionClick}>
        {actionTitle}
      </button>
    </div>
  );
}

export default memo(SwapHint);
