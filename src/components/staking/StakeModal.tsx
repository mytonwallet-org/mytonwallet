import React, { memo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiStakingState, ApiTokenWithPrice } from '../../api/types';
import type { GlobalState } from '../../global/types';
import { StakingState } from '../../global/types';

import {
  selectAccountStakingState,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectHasMultipleAccounts,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { getIsViewAccountDisabled } from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { getIsNewStakeAllowed } from '../../util/staking';

import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import MfaConfirm from '../common/MfaConfirm';
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
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
};

const IS_OPEN_STATES = new Set([
  StakingState.StakeInitial,
  StakingState.StakePassword,
  StakingState.StakeConnectHardware,
  StakingState.StakeConfirmHardware,
  StakingState.StakeConfirmMfa,
  StakingState.StakeComplete,
  StakingState.StakeSelectAccount,
]);

function StakeModal({
  state,
  stakingState,
  isLoading,
  amount,
  error,
  tokenBySlug,
  mfaRequestHash,
  accountId,
  accountTitle,
  hasMultipleAccounts,
}: StateProps) {
  const {
    startStaking,
    setStakingScreen,
    cancelStaking,
    clearStakingError,
    submitStaking,
    openStakingInfo,
    updateStakingMfaRequestStatus,
    switchStakingAccount,
  } = getActions();

  const { tokenSlug } = stakingState ?? {};

  const token = tokenSlug && tokenBySlug ? tokenBySlug[tokenSlug] : undefined;

  const lang = useLang();
  const isOpen = IS_OPEN_STATES.has(state);
  const [renderedStakingAmount, setRenderedStakingAmount] = useState(amount);

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  useInterval(() => {
    if (state === StakingState.StakeConfirmMfa && mfaRequestHash) {
      updateStakingMfaRequestStatus();
    }
  }, state === StakingState.StakeConfirmMfa ? 1000 : undefined);

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

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    setRenderedStakingAmount(amount);
    submitStaking({ enclaveToken });
  });

  const handleViewStakingInfoClick = useLastCallback(() => {
    cancelStaking();
    openStakingInfo();
  });

  const handleOpenAccountSelector = useLastCallback(() => {
    setStakingScreen({ state: StakingState.StakeSelectAccount });
  });

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    switchStakingAccount({ accountId: nextAccountId, mode: 'stake' });
  });

  const handleSelectAccountBack = useLastCallback(() => {
    setStakingScreen({ state: StakingState.StakeInitial });
  });

  function renderTransactionBanner() {
    if (!token || !amount) return undefined;

    return (
      <TransactionBanner
        tokenIn={token}
        withChainIcon
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
          operationType="staking"
          placeholder={lang(placeholder)}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Back')}
          onAuthorize={handleAuthorize}
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
        <ModalHeader title={lang('Staked')} onClose={cancelStaking} />

        <div className={modalStyles.transitionContent}>
          <TransferResult
            color="purple"
            playAnimation={isActive}
            amount={renderedStakingAmount}
            decimals={token?.decimals}
            tokenSymbol={token?.symbol}
            noSign
            firstButtonText={lang('View')}
            secondButtonText={getIsNewStakeAllowed(tokenSlug) ? lang('Stake More') : undefined}
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
            <div
              className={buildClassName(styles.initialHeader, hasMultipleAccounts && styles.initialHeaderWithSwitcher)}
            >
              <ModalHeader
                title={lang('Add Stake')}
                titleClassName={styles.modalTitle}
                onClose={cancelStaking}
              />
              {hasMultipleAccounts && accountId && (
                <AccountSwitcherPill
                  accountId={accountId}
                  title={accountTitle}
                  className={styles.accountPill}
                  onClick={handleOpenAccountSelector}
                />
              )}
            </div>
            <StakingInitial />
          </>
        );

      case StakingState.StakeSelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsViewAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={handleSelectAccountBack}
            onClose={cancelStaking}
          />
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

      case StakingState.StakeConfirmMfa:
        return (
          <>
            <ModalHeader onClose={cancelStaking} />
            <MfaConfirm
              onClose={cancelStaking}
              mfaRequestHash={mfaRequestHash}
            />
          </>
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
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
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
  const stakingState = selectAccountStakingState(global, accountId);
  const tokenBySlug = global.tokenInfo.bySlug;

  return {
    ...global.currentStaking,
    stakingState,
    tokenBySlug,
    accountId,
    accountTitle: selectCurrentAccount(global)?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(StakeModal));
