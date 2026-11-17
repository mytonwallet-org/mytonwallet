import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';

import buildClassName from '../../../util/buildClassName';

import useLang from '../../../hooks/useLang';

import Spinner from '../../ui/Spinner';
import BalanceWithdrawalSummary from './BalanceWithdrawalSummary';
import PositionSummary from './PositionSummary';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

// The modal has no close button here: the operation cannot be stopped, and the user waits for its result
function TradeProgress({ trade, asset }: OwnProps) {
  const lang = useLang();

  const { quote, balanceWithdrawal } = trade;

  return (
    <div className={buildClassName(modalStyles.transitionContent, styles.progress)}>
      {quote && quote.kind !== 'unchanged' && <PositionSummary quote={quote} asset={asset} hasIcon />}
      {balanceWithdrawal && <BalanceWithdrawalSummary withdrawal={balanceWithdrawal} />}
      <Spinner className={styles.spinner} />
      <p className={styles.progressText}>{lang('PerpsProcessing')}</p>
    </div>
  );
}

export default memo(TradeProgress);
