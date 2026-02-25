import React, { memo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiStakingState, ApiTokenWithPrice } from '../../api/types';
import type { GlobalState } from '../../global/types';
import { StakingState } from '../../global/types';

import { IS_CAPACITOR } from '../../config';
import {
  selectAccountStakingState,
  selectCurrentAccountId,
  selectIsMultichainAccount,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import TransactionBanner from '../common/TransactionBanner';
import TransferResult from '../common/TransferResult';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Button from '../ui/Button';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import StakingInitial from './StakingInitial';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Staking.module.scss';

type StateProps = GlobalState['currentStaking'] & {
  stakingState?: ApiStakingState;
  tokenBySlug?: Record<string, ApiTokenWithPrice>;
  isMultichainAccount: boolean;
};

const IS_OPEN_STATES = new Set([
  StakingState.StakeInitial,
  StakingState.StakePassword,
  StakingState.StakeConnectHardware,
  StakingState.StakeConfirmHardware,
  StakingState.StakeComplete,
]);

function StakeModal({
  state,
  stakingState,
  isLoading,
  amount,
  error,
  tokenBySlug,
  isMultichainAccount,
}: StateProps) {
  const {
    startStaking,
    setStakingScreen,
    cancelStaking,
    clearStakingError,
    submitStaking,
    openStakingInfo,
  } = getActions();

  const { tokenSlug } = stakingState ?? {};

  const token = tokenSlug && tokenBySlug ? tokenBySlug[tokenSlug] : undefined;

  const lang = useLang();
  const isOpen = IS_OPEN_STATES.has(state);
  const [renderedStakingAmount, setRenderedStakingAmount] = useState(amount);

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const handleBackClick = useLastCallback(() => {
    if (state === StakingState.StakePassword) {
      clearStakingError();
      setStakingScreen({ state: StakingState.StakeInitial });
    }
  });

  const handleLedgerConnect = useLastCallback(() => {
    setRenderedStakingAmount(amount);
    submitStaking();
  });

  const handleTransferSubmit = useLastCallback((password: string) => {
    setRenderedStakingAmount(amount);
    submitStaking({ password });
  });

  const handleViewStakingInfoClick = useLastCallback(() => {
    cancelStaking();
    openStakingInfo();
  });

  function renderTransactionBanner() {
    if (!token || !amount) return undefined;

    return (
      <TransactionBanner
        tokenIn={token}
        withChainIcon={isMultichainAccount}
        color="purple"
        text={formatCurrency(toDecimal(amount, token.decimals), token.symbol)}
        className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
      />
    );
  }

  function renderPassword(isActive: boolean) {
    const placeholder = getDoesUsePinPad()
      ? 'Confirm action with your passcode'
      : 'Confirm action with your password';

    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader title={lang('Confirm Staking')} onClose={cancelStaking} />
        )}
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          error={error}
          withCloseButton={IS_CAPACITOR}
          operationType="staking"
          placeholder={lang(placeholder)}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Back')}
          onSubmit={handleTransferSubmit}
          onCancel={handleBackClick}
          onUpdate={clearStakingError}
        >
          {renderTransactionBanner()}
        </PasswordForm>
      </>
    );
  }

  function renderComplete(isActive: boolean) {
    return (
      <>
        <ModalHeader title={lang('Coins have been staked!')} onClose={cancelStaking} />

        <div className={modalStyles.transitionContent}>
          <TransferResult
            color="purple"
            playAnimation={isActive}
            amount={renderedStakingAmount}
            decimals={token?.decimals}
            tokenSymbol={token?.symbol}
            noSign
            firstButtonText={lang('View')}
            secondButtonText={lang('Stake More')}
            onFirstButtonClick={handleViewStakingInfoClick}
            onSecondButtonClick={startStaking}
          />

          <div className={modalStyles.buttons}>
            <Button onClick={cancelStaking} isPrimary>{lang('Close')}</Button>
          </div>
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: StakingState) {
    switch (currentKey) {
      case StakingState.StakeInitial:
        return (
          <>
            <ModalHeader title={lang('$stake_asset', { symbol: token?.symbol })} onClose={cancelStaking} />
            <StakingInitial isActive={isActive} />
          </>
        );

      case StakingState.StakePassword:
        return renderPassword(isActive);

      case StakingState.StakeConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleLedgerConnect}
            onClose={cancelStaking}
          />
        );

      case StakingState.StakeConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelStaking}
            onTryAgain={handleLedgerConnect}
          />
        );

      case StakingState.StakeComplete:
        return renderComplete(isActive);
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      hasCloseButton
      noBackdropClose
      dialogClassName={styles.modalDialog}
      onClose={cancelStaking}
      onCloseAnimationEnd={updateNextKey}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountId = selectCurrentAccountId(global)!;
  const isMultichainAccount = selectIsMultichainAccount(global, accountId);
  const stakingState = selectAccountStakingState(global, accountId);
  const tokenBySlug = global.tokenInfo.bySlug;

  return {
    ...global.currentStaking,
    stakingState,
    tokenBySlug,
    isMultichainAccount,
  };
})(StakeModal));
