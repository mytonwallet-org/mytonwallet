import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsBalanceWithdrawalPreview } from '../../../api/types';

import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { selectCurrentAccountPerps } from '../../../global/selectors';
import { formatPerpsMoney } from '../helpers/formatPerps';
import { PERPS_ROW_AMOUNT_MASK } from '../helpers/sensitiveDataMasks';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TokenIcon from '../../common/TokenIcon';
import Button from '../../ui/Button';
import SensitiveData from '../../ui/SensitiveData';

import styles from './BalanceRow.module.scss';

interface OwnProps {
  withdrawal: ApiPerpsBalanceWithdrawalPreview;
}

interface StateProps {
  canWithdraw: boolean;
  isPreparing: boolean;
  isSensitiveDataHidden?: true;
}

/** The USDC on the Hyperliquid balance that one withdrawal can send to the wallet */
function BalanceRow({
  withdrawal, canWithdraw, isPreparing, isSensitiveDataHidden,
}: OwnProps & StateProps) {
  const { startPerpsBalanceWithdrawal } = getActions();
  const lang = useLang();

  const handleWithdrawClick = useLastCallback(() => {
    startPerpsBalanceWithdrawal();
  });

  return (
    <div className={styles.root}>
      <TokenIcon token={ARBITRUM_USDC_MAINNET} size="large" />
      <span className={styles.primary}>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          {...PERPS_ROW_AMOUNT_MASK}
          seed="perps-balance"
          className={styles.value}
        >
          {formatPerpsMoney(withdrawal.balance)}
        </SensitiveData>
        <span className={styles.subtitle}>{`${lang('PerpsAvailable')} · ${ARBITRUM_USDC_MAINNET.symbol}`}</span>
      </span>
      <Button
        isSmall
        isText
        isLoading={isPreparing}
        isDisabled={!canWithdraw || isPreparing}
        className={styles.button}
        onClick={handleWithdrawClick}
      >
        {lang('PerpsWithdraw')}
      </Button>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { trade } = global.perps;

  return {
    // View and Ledger accounts cannot sign the withdrawal
    canWithdraw: selectCurrentAccountPerps(global)?.snapshot?.tradingAvailability?.isAvailable === true,
    isPreparing: trade?.step === 'balanceWithdrawal' && !trade.balanceWithdrawal,
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(BalanceRow));
