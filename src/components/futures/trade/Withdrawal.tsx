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
import ErrorText from './ErrorText';
import WithdrawalSummary from './WithdrawalSummary';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  isActive: boolean;
  trade: PerpsTradeState;
}

/** The review of a withdrawal that did not complete after a reduce or a close */
function Withdrawal({ isActive, trade }: OwnProps) {
  const { setPerpsTradeStep, cancelPerpsTrade } = getActions();
  const lang = useLang();

  const handleBack = useLastCallback(() => {
    setPerpsTradeStep({ step: 'status' });
  });

  const handleConfirm = useLastCallback(() => {
    vibrate();
    setPerpsTradeStep({ step: 'withdrawalPassword' });
  });

  useHistoryBack({ isActive, onBack: handleBack });

  return (
    <>
      <ModalHeader title={lang('PerpsWithdrawReleased')} onBackButtonClick={handleBack} onClose={cancelPerpsTrade} />
      <div className={buildClassName(modalStyles.transitionContent, styles.content)}>
        <WithdrawalSummary amount={trade.withdrawalAmount} />
        {trade.error && <ErrorText error={trade.error} />}
        <ModalFooter>
          <div className={styles.footer}>
            <Button isPrimary className={modalStyles.buttonFullWidth} onClick={handleConfirm}>
              {lang('Confirm')}
            </Button>
          </div>
        </ModalFooter>
      </div>
    </>
  );
}

export default memo(Withdrawal);
