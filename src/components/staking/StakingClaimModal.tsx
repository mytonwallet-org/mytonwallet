import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiEthenaStakingState, ApiJettonStakingState } from '../../api/types';
import type { UserToken } from '../../global/types';
import { StakingState } from '../../global/types';

import { SHORT_FRACTION_DIGITS, TONCOIN } from '../../config';
import renderText from '../../global/helpers/renderText';
import {
  selectAccount,
  selectAccountStakingState,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
  selectHasMultipleAccounts,
  selectIsHardwareAccount,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { getTonStakingFees } from '../../util/fee/getTonOperationFees';
import { formatCurrency } from '../../util/formatNumber';
import { getIsViewAccountDisabled } from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { shortenAddress } from '../../util/shortenAddress';

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
import Fee from '../ui/Fee';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import stakingStyles from './Staking.module.scss';
import styles from './StakingClaimModal.module.scss';

interface StateProps {
  stakingState?: ApiJettonStakingState | ApiEthenaStakingState;
  isOpen?: boolean;
  tokens?: UserToken[];
  isLoading?: boolean;
  address?: string;
  error?: string;
  state?: StakingState;
  mfaRequestHash?: string;
  isHardwareAccount?: boolean;
  isSensitiveDataHidden?: true;
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
}

const IS_OPEN_STATES = new Set([
  StakingState.ClaimPassword,
  StakingState.ClaimConfirmHardware,
  StakingState.ClaimConnectHardware,
  StakingState.ClaimConfirmMfa,
  StakingState.ClaimComplete,
  StakingState.ClaimSelectAccount,
]);

function StakingClaimModal({
  stakingState,
  isOpen,
  tokens,
  isLoading,
  address,
  error,
  state = StakingState.ClaimPassword,
  mfaRequestHash,
  isHardwareAccount,
  isSensitiveDataHidden,
  accountId,
  accountTitle,
  hasMultipleAccounts,
}: StateProps) {
  const {
    submitStakingClaim,
    cancelStakingClaim,
    clearStakingError,
    updateStakingMfaRequestStatus,
    setStakingScreen,
    startStakingClaim,
    switchStakingAccount,
  } = getActions();

  const {
    tokenSlug,
  } = stakingState ?? {};

  const rewardAmount = stakingState && 'unclaimedRewards' in stakingState
    ? stakingState.unclaimedRewards
    : stakingState?.unstakeRequestAmount ?? 0n;

  const lang = useLang();

  const token = useMemo(() => tokens?.find(({ slug }) => slug === tokenSlug), [tokens, tokenSlug]);
  const nativeToken = useMemo(() => tokens?.find(({ slug }) => slug === TONCOIN.slug), [tokens]);
  const nativeBalance = nativeToken?.amount ?? 0n;

  const { gas: networkFee, real: realNetworkFee } = getTonStakingFees(stakingState?.type).claim!;
  const isNativeEnough = nativeBalance > networkFee;
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, Boolean(isOpen));
  const confirmTitle = lang(stakingState?.type === 'ethena' ? 'Confirm Unstaking' : 'Confirm Rewards Claim');

  useInterval(() => {
    if (state === StakingState.ClaimConfirmMfa && mfaRequestHash) {
      updateStakingMfaRequestStatus();
    }
  }, state === StakingState.ClaimConfirmMfa ? 1000 : undefined);

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    if (!isNativeEnough) return;
    submitStakingClaim({ enclaveToken });
  });

  const handleHardwareSubmit = useLastCallback(() => {
    if (!isNativeEnough) return;
    submitStakingClaim();
  });

  const handleOpenAccountSelector = useLastCallback(() => {
    setStakingScreen({ state: StakingState.ClaimSelectAccount });
  });

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    switchStakingAccount({ accountId: nextAccountId, mode: 'claim' });
  });

  const handleSelectAccountBack = useLastCallback(() => {
    startStakingClaim();
  });

  function renderInfo() {
    const feeClassName = buildClassName(
      styles.operationInfoFee,
      !getDoesUsePinPad() && styles.operationInfoFeeWithGap,
    );
    const content = isSensitiveDataHidden
      ? `*** ${token!.symbol}`
      : formatCurrency(toDecimal(rewardAmount, token!.decimals), token!.symbol, SHORT_FRACTION_DIGITS);

    return (
      <>
        <TransactionBanner
          tokenIn={token}
          withChainIcon
          text={content}
          className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
          secondText={address && shortenAddress(address)}
        />
        <div className={feeClassName}>
          {token && renderText(lang('$fee_value_bold', {
            fee: (
              <Fee
                terms={{ native: isNativeEnough ? realNetworkFee : networkFee }}
                precision={isNativeEnough ? 'approximate' : 'lessThan'}
                token={token}
              />
            ),
          }))}
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: StakingState) {
    switch (currentKey) {
      case StakingState.ClaimConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleHardwareSubmit}
            onClose={cancelStakingClaim}
          />
        );

      case StakingState.ClaimConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelStakingClaim}
            onTryAgain={handleHardwareSubmit}
          />
        );

      case StakingState.ClaimPassword:
        return (
          <>
            {!getDoesUsePinPad() && (
              <div
                className={buildClassName(
                  stakingStyles.initialHeader,
                  hasMultipleAccounts && stakingStyles.initialHeaderWithSwitcher,
                )}
              >
                <ModalHeader title={confirmTitle} onClose={cancelStakingClaim} />
                {hasMultipleAccounts && accountId && (
                  <AccountSwitcherPill
                    accountId={accountId}
                    title={accountTitle}
                    className={stakingStyles.accountPill}
                    onClick={!isLoading ? handleOpenAccountSelector : undefined}
                  />
                )}
              </div>
            )}
            <PasswordForm
              isActive={Boolean(isOpen)}
              isLoading={isLoading}
              withCloseButton
              operationType="claim"
              error={!isNativeEnough ? lang('Insufficient Balance for Fee') : error}
              submitLabel={lang('Confirm')}
              onAuthorize={handleAuthorize}
              onCancel={cancelStakingClaim}
              onUpdate={clearStakingError}
            >
              {renderInfo()}
            </PasswordForm>
          </>
        );

      case StakingState.ClaimSelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsViewAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={handleSelectAccountBack}
            onClose={cancelStakingClaim}
          />
        );

      case StakingState.ClaimConfirmMfa:
        return (
          <>
            {!isHardwareAccount && !getDoesUsePinPad() && (
              <ModalHeader title={confirmTitle} onClose={cancelStakingClaim} />
            )}
            <MfaConfirm
              onClose={cancelStakingClaim}
              mfaRequestHash={mfaRequestHash}
            />
          </>
        );

      case StakingState.ClaimComplete:
        return (
          <>
            <ModalHeader title={lang('Unstaked')} onClose={cancelStakingClaim} />
            <div className={modalStyles.transitionContent}>
              <TransferResult
                isSensitiveDataHidden={isSensitiveDataHidden}
                color="green"
                playAnimation={isActive}
                amount={rewardAmount}
                tokenSymbol={token?.symbol}
                decimals={token?.decimals}
                noSign
              />

              <div className={styles.unstakeInfo}>
                {lang('$unstake_information_instantly')}
              </div>

              <div className={modalStyles.buttons}>
                <Button onClick={cancelStakingClaim} isPrimary>{lang('Close')}</Button>
              </div>
            </div>
          </>
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      contentClassName={styles.passwordModalDialog}
      onClose={cancelStakingClaim}
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
  const accountId = selectCurrentAccountId(global);
  const { byChain, title: accountTitle } = selectAccount(global, accountId!) || {};
  const isHardwareAccount = selectIsHardwareAccount(global);

  const {
    state,
    isLoading,
    error,
  } = global?.currentStaking || {};
  const { mfaRequestHash } = global.currentStaking;

  const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;
  const tokens = selectCurrentAccountTokens(global);
  const canBeClaimed = stakingState?.type === 'jetton' || stakingState?.type === 'ethena';

  return {
    stakingState: canBeClaimed ? stakingState : undefined,
    isOpen: IS_OPEN_STATES.has(state),
    state,
    mfaRequestHash,
    tokens,
    isLoading,
    error,
    address: byChain?.ton?.address,
    isHardwareAccount,
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
    accountId,
    accountTitle,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(StakingClaimModal));
