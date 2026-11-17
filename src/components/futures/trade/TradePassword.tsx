import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';

import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { formatPositionLabel, getOperationTitle } from '../helpers/formatPerps';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';
import BalanceWithdrawalSummary from './BalanceWithdrawalSummary';
import PositionSummary from './PositionSummary';
import WithdrawalSummary from './WithdrawalSummary';

import styles from './TradeModal.module.scss';

interface OwnProps {
  isActive: boolean;
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

function TradePassword({ isActive, trade, asset }: OwnProps) {
  const {
    submitPerpsTrade, submitPerpsWithdrawal, submitPerpsBalanceWithdrawal, setPerpsTradeStep, cancelPerpsTrade,
  } = getActions();
  const lang = useLang();

  const {
    quote, operationId, withdrawalAmount, balanceWithdrawal,
  } = trade;
  const isWithdrawal = trade.step === 'withdrawalPassword';
  const isBalanceWithdrawal = trade.step === 'balanceWithdrawalPassword';

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    if (isWithdrawal) {
      submitPerpsWithdrawal({ operationId: operationId!, enclaveToken });
    } else if (isBalanceWithdrawal) {
      submitPerpsBalanceWithdrawal({ enclaveToken });
    } else {
      submitPerpsTrade({ enclaveToken });
    }
  });

  const handleBack = useLastCallback(() => {
    setPerpsTradeStep({ step: isWithdrawal ? 'withdrawal' : isBalanceWithdrawal ? 'balanceWithdrawal' : 'review' });
  });

  useHistoryBack({ isActive, onBack: handleBack });

  function renderSummary() {
    if (isBalanceWithdrawal) {
      return balanceWithdrawal && <BalanceWithdrawalSummary withdrawal={balanceWithdrawal} />;
    }

    if (isWithdrawal) {
      return withdrawalAmount && <WithdrawalSummary amount={withdrawalAmount} />;
    }

    return quote && quote.kind !== 'unchanged' && (
      <>
        <PositionSummary quote={quote} asset={asset} hasIcon isLabelHidden />
        <p className={styles.operation}>
          {getOperationTitle(lang, quote.kind)}{' '}
          <span className={buildClassName(styles.operationLabel, quote.side === 'short' && styles.operationLabelShort)}>
            {formatPositionLabel(lang, asset?.symbol ?? '', quote.leverage, quote.side)}
          </span>
        </p>
      </>
    );
  }

  const summary = renderSummary();

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang('Confirm')} onClose={cancelPerpsTrade} />}
      {/* Every order and withdrawal needs a fresh password or biometrics, as on iOS */}
      <PasswordForm
        isActive={isActive}
        noAutoConfirm
        noAnimatedIcon
        operationTitle="Confirm"
        submitLabel={lang('Confirm')}
        cancelLabel={lang('Back')}
        onAuthorize={handleAuthorize}
        onCancel={handleBack}
      >
        {summary && <div className={styles.authSummary}>{summary}</div>}
      </PasswordForm>
    </>
  );
}

export default memo(TradePassword);
