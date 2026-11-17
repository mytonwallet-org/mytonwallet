import React, { memo, useMemo } from '../../../lib/teact/teact';

import type { ApiPerpsMarketAsset, ApiPerpsQuote } from '../../../api/types';

import { buildPerpsToken } from '../helpers/buildPerpsSections';
import { formatPositionLabel, PERPS_CURRENCY_SYMBOL } from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';

import TradeSummary from './TradeSummary';

interface OwnProps {
  quote: ApiPerpsQuote;
  asset?: ApiPerpsMarketAsset;
  /** The market icon goes above the amount, which then goes without its gray box */
  hasIcon?: boolean;
  /** A line below names the position, so the label would repeat it */
  isLabelHidden?: boolean;
  className?: string;
}

/**
 * The amount of a reviewed operation: the estimated collateral of a new position, the old and the new collateral of
 * an edited one, or the profit or loss of a closed one
 */
function PositionSummary({
  quote, asset, hasIcon, isLabelHidden, className,
}: OwnProps) {
  const lang = useLang();

  const token = useMemo(() => (hasIcon && asset ? buildPerpsToken(asset) : undefined), [asset, hasIcon]);
  const isClose = quote.kind === 'close';

  return (
    <TradeSummary
      amount={isClose ? quote.profitLoss : quote.estimatedCollateral ?? quote.collateral}
      prevAmount={quote.kind === 'open' || isClose ? undefined : quote.previousCollateral}
      currency={PERPS_CURRENCY_SYMBOL}
      token={token}
      label={isLabelHidden ? undefined : formatPositionLabel(lang, asset?.symbol ?? '', quote.leverage, quote.side)}
      side={quote.side}
      withSign={isClose}
      isEstimated={!isClose}
      className={className}
    />
  );
}

export default memo(PositionSummary);
