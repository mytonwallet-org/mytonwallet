import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { PerpsTradeState } from '../../../global/types';

import buildClassName from '../../../util/buildClassName';
import { vibrate } from '../../../util/haptics';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import ModalFooter from '../../ui/ModalFooter';
import ModalHeader from '../../ui/ModalHeader';
import WarningMessage from '../../ui/WarningMessage';
import BalanceWithdrawalSummary from './BalanceWithdrawalSummary';
import ErrorText from './ErrorText';
import WithdrawalDetails from './WithdrawalDetails';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  isActive: boolean;
  trade: PerpsTradeState;
}

/**
 * Reviews a withdrawal of the largest amount a single withdrawal can move from the Hyperliquid balance to the wallet
 */
function BalanceWithdrawal({ isActive, trade }: OwnProps) {
  const { confirmPerpsBalanceWithdrawal, cancelPerpsTrade } = getActions();
  const lang = useLang();

  const {
    balanceWithdrawal, isPreparing, reviewNotice, error,
  } = trade;

  const handleConfirm = useLastCallback(() => {
    vibrate();
    confirmPerpsBalanceWithdrawal();
  });

  useHistoryBack({ isActive, onBack: cancelPerpsTrade });

  return (
    <>
      <ModalHeader title={lang('PerpsBalanceWithdrawalTitle')} onClose={cancelPerpsTrade} />
      {balanceWithdrawal && (
        <div className={buildClassName(modalStyles.transitionContent, styles.content)}>
          <BalanceWithdrawalSummary withdrawal={balanceWithdrawal} />

          <div className={styles.cardGroup}>
            <WithdrawalDetails withdrawal={balanceWithdrawal} />
            <p className={styles.cardNote}>{lang('PerpsBalanceWithdrawalNote')}</p>
          </div>

          {reviewNotice && !error && <WarningMessage>{lang(reviewNotice)}</WarningMessage>}
          {error && <ErrorText error={error} />}

          <ModalFooter>
            <div className={styles.footer}>
              <Button
                isPrimary
                isLoading={isPreparing}
                isDisabled={isPreparing || Boolean(error)}
                className={modalStyles.buttonFullWidth}
                onClick={handleConfirm}
              >
                {lang('Confirm')}
              </Button>
            </div>
          </ModalFooter>
        </div>
      )}
    </>
  );
}

export default memo(BalanceWithdrawal);
