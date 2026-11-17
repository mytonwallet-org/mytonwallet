import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsBalanceWithdrawalQuote } from '../../../api/types';

import { ARBITRUM_USDC_MAINNET } from '../../../config';

import useLang from '../../../hooks/useLang';

import TradeSummary from './TradeSummary';

interface OwnProps {
  withdrawal: ApiPerpsBalanceWithdrawalQuote;
}

/** The USDC that a withdrawal from the Hyperliquid balance brings to the wallet */
function BalanceWithdrawalSummary({ withdrawal }: OwnProps) {
  const lang = useLang();

  return (
    <TradeSummary amount={withdrawal.receiveAmount} token={ARBITRUM_USDC_MAINNET} label={lang('You Receive')} />
  );
}

export default memo(BalanceWithdrawalSummary);
