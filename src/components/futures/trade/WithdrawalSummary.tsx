import React, { memo } from '../../../lib/teact/teact';

import { ARBITRUM_USDC_MAINNET } from '../../../config';

import useLang from '../../../hooks/useLang';

import TradeSummary from './TradeSummary';

import styles from './TradeModal.module.scss';

interface OwnProps {
  /** Absent until the SDK tells how much a reduce or a close released */
  amount?: string;
}

/** The withdrawal that did not complete after a reduce or a close */
function WithdrawalSummary({ amount }: OwnProps) {
  const lang = useLang();

  return (
    <>
      {amount && <TradeSummary amount={amount} token={ARBITRUM_USDC_MAINNET} />}
      <p className={styles.operation}>{lang('PerpsWithdrawDescription')}</p>
    </>
  );
}

export default memo(WithdrawalSummary);
