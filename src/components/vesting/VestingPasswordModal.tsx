import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiTokenWithPrice, ApiVestingInfo } from '../../api/types';
import type { UserToken } from '../../global/types';
import { VestingUnfreezeState } from '../../global/types';

import { CLAIM_AMOUNT, TONCOIN } from '../../config';
import renderText from '../../global/helpers/renderText';
import {
  selectAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
  selectIsHardwareAccount,
  selectIsMultichainAccount,
  selectMycoin,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { toBig } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { shortenAddress } from '../../util/shortenAddress';
import { calcVestingAmountByStatus } from '../main/helpers/calcVestingAmountByStatus';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import TransactionBanner from '../common/TransactionBanner';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Modal from '../ui/Modal';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './VestingModal.module.scss';

interface StateProps {
  isOpen?: boolean;
  tokens?: UserToken[];
  vesting?: ApiVestingInfo[];
  isLoading?: boolean;
  address?: string;
  error?: string;
  state?: VestingUnfreezeState;
  mycoin?: ApiTokenWithPrice;
  isHardwareAccount?: boolean;
  isMultichainAccount: boolean;
  isViewMode?: boolean;
}

function VestingPasswordModal({
  isOpen,
  vesting,
  tokens,
  isLoading,
  address,
  error,
  mycoin,
  state = VestingUnfreezeState.Password,
  isHardwareAccount,
  isMultichainAccount,
  isViewMode,
}: StateProps) {
  const { submitClaimingVesting, cancelClaimingVesting, clearVestingError } = getActions();

  const lang = useLang();
  const {
    amount: balance,
  } = useMemo(() => tokens?.find(({ slug }) => slug === TONCOIN.slug), [tokens]) || {};
  const claimAmount = toBig(CLAIM_AMOUNT);
  const hasAmountError = !balance || balance < CLAIM_AMOUNT;
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, Boolean(isOpen));
  const withModalHeader = !isHardwareAccount && !getDoesUsePinPad();

  const currentlyReadyToUnfreezeAmount = useMemo(() => {
    if (!vesting) return '0';

    return calcVestingAmountByStatus(vesting, ['ready']);
  }, [vesting]);

  const handleSubmit = useLastCallback((password: string) => {
    if (isViewMode || hasAmountError) return;
    submitClaimingVesting({ password });
  });

  const handleHardwareSubmit = useLastCallback(() => {
    if (isViewMode || hasAmountError) return;
    submitClaimingVesting();
  });

  if (!mycoin) {
    return undefined;
  }

  function renderInfo() {
    const feeClassName = buildClassName(
      styles.operationInfoFee,
      !getDoesUsePinPad() && styles.operationInfoFeeWithGap,
    );

    return (
      <>
        <TransactionBanner
          tokenIn={mycoin}
          withChainIcon={isMultichainAccount}
          text={formatCurrency(currentlyReadyToUnfreezeAmount, mycoin!.symbol, mycoin!.decimals)}
          className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
          secondText={address && shortenAddress(address)}
        />
        <div className={feeClassName}>
          {renderText(lang('$fee_value_bold', { fee: formatCurrency(claimAmount, TONCOIN.symbol) }))}
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: VestingUnfreezeState) {
    switch (currentKey) {
      case VestingUnfreezeState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleHardwareSubmit}
            onClose={cancelClaimingVesting}
          />
        );

      case VestingUnfreezeState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelClaimingVesting}
            onTryAgain={handleHardwareSubmit}
          />
        );

      case VestingUnfreezeState.Password:
        return (
          <PasswordForm
            isActive={Boolean(isOpen)}
            isLoading={isLoading}
            withCloseButton
            operationType="unfreeze"
            error={hasAmountError ? lang('Insufficient Balance for Fee') : error}
            submitLabel={lang('Confirm')}
            noAutoConfirm
            onSubmit={handleSubmit}
            onCancel={cancelClaimingVesting}
            onUpdate={clearVestingError}
          >
            {renderInfo()}
          </PasswordForm>
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      title={withModalHeader ? lang('Confirm Unfreezing') : undefined}
      hasCloseButton={withModalHeader}
      contentClassName={styles.passwordModalDialog}
      onClose={cancelClaimingVesting}
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
  const currentAccountId = selectCurrentAccountId(global)!;
  const { byChain } = selectAccount(global, currentAccountId) || {};
  const accountState = selectCurrentAccountState(global);
  const isHardwareAccount = selectIsHardwareAccount(global);

  const {
    isConfirmRequested: isOpen,
    info: vesting,
    isLoading,
    error,
    unfreezeState,
  } = accountState?.vesting || {};
  const tokens = selectCurrentAccountTokens(global);

  return {
    isOpen,
    vesting,
    tokens,
    isLoading,
    error,
    address: byChain?.ton?.address,
    state: unfreezeState,
    mycoin: selectMycoin(global),
    isHardwareAccount,
    isMultichainAccount: selectIsMultichainAccount(global, currentAccountId),
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(VestingPasswordModal));
