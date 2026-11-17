import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsBalanceWithdrawalQuote } from '../../../api/types';

import { shortenAddress } from '../../../util/shortenAddress';
import { formatPerpsUsdc } from '../helpers/formatPerps';
import { buildPerpsFeeHint, buildPerpsWithdrawalFee } from '../helpers/perpsFees';

import useLang from '../../../hooks/useLang';

import DetailRow from '../DetailRow';

import styles from './TradeModal.module.scss';

interface OwnProps {
  withdrawal: ApiPerpsBalanceWithdrawalQuote;
}

/** Where a withdrawal from the Hyperliquid balance takes the USDC, and what it charges on the way */
function WithdrawalDetails({ withdrawal }: OwnProps) {
  const lang = useLang();

  const { total, lines } = buildPerpsWithdrawalFee(lang, withdrawal);

  return (
    <div className={styles.card}>
      <DetailRow label={lang('PerpsWithdrawalFromHyperliquid')} value={formatPerpsUsdc(withdrawal.amount)} />
      <DetailRow label={lang('Fee')} hint={buildPerpsFeeHint(lang, { lines })} value={total} />
      <DetailRow label={lang('PerpsWithdrawalToWallet')} value={shortenAddress(withdrawal.destination)} />
    </div>
  );
}

export default memo(WithdrawalDetails);
