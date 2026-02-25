import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useCallback, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiStakingState } from '../../api/types';
import type { GlobalState, Theme, UserToken } from '../../global/types';
import { ApiTransactionDraftError } from '../../api/types';
import { StakingState } from '../../global/types';

import {
  ANIMATED_STICKER_TINY_ICON_PX,
  DEFAULT_PRICE_CURRENCY,
  IS_CAPACITOR,
  TONCOIN,
  VALIDATION_PERIOD_MS,
} from '../../config';
import renderText from '../../global/helpers/renderText';
import {
  selectAccountStakingState,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
  selectIsMultichainAccount,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { formatRelativeHumanDateTime } from '../../util/dateFormat';
import { toBig, toDecimal } from '../../util/decimals';
import { getTonStakingFees } from '../../util/fee/getTonOperationFees';
import { formatCurrency } from '../../util/formatNumber';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { getIsLongUnstake, getUnstakeTime } from '../../util/staking';
import { getIsMobileTelegramApp } from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useAppTheme from '../../hooks/useAppTheme';
import useForceUpdate from '../../hooks/useForceUpdate';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import useSyncEffect from '../../hooks/useSyncEffect';
import { useAmountInputState } from '../ui/hooks/useAmountInputState';

import TransactionBanner from '../common/TransactionBanner';
import TransferResult from '../common/TransferResult';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import AmountInput from '../ui/AmountInput';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Fee from '../ui/Fee';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Staking.module.scss';

type StateProps = GlobalState['currentStaking'] & {
  isViewMode: boolean;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
  isNominators?: boolean;
  theme: Theme;
  isMultichainAccount: boolean;
  stakingState?: ApiStakingState;
  isSensitiveDataHidden?: true;
};

const IS_OPEN_STATES = new Set([
  StakingState.UnstakeInitial,
  StakingState.UnstakePassword,
  StakingState.UnstakeConnectHardware,
  StakingState.UnstakeConfirmHardware,
  StakingState.UnstakeComplete,
]);

const UPDATE_UNSTAKE_DATE_INTERVAL_MS = 30000; // 30 sec

function UnstakeModal({
  state,
  isViewMode,
  isLoading,
  error,
  tokens,
  baseCurrency,
  isNominators,
  isMultichainAccount,
  theme,
  amount,
  stakingState,
  isSensitiveDataHidden,
}: StateProps) {
  const {
    setStakingScreen,
    cancelStaking,
    clearStakingError,
    submitStakingInitial,
    submitStaking,
    fetchStakingHistory,
  } = getActions();

  const {
    type: stakingType,
    tokenSlug,
    balance: stakingBalance,
  } = stakingState ?? {};

  const lang = useLang();
  const isOpen = IS_OPEN_STATES.has(state);

  const { gas: networkFee, real: realFee } = getTonStakingFees(stakingState?.type).unstake;

  const nativeToken = useMemo(() => tokens?.find(({ slug }) => slug === TONCOIN.slug), [tokens]);
  const isNativeEnough = nativeToken && nativeToken.amount >= networkFee;
  const instantAvailable = stakingState?.type === 'liquid' ? stakingState.instantAvailable : undefined;

  const token = useMemo(() => {
    return tokenSlug ? tokens?.find(({ slug }) => slug === tokenSlug) : undefined;
  }, [tokenSlug, tokens]);

  const isOnlyFullAmount = isNominators;
  const [unstakeAmount, setUnstakeAmount] = useState(isOnlyFullAmount ? stakingBalance : undefined);
  const [successUnstakeAmount, setSuccessUnstakeAmount] = useState<bigint | undefined>(undefined);

  const unstakeTime = getUnstakeTime(stakingState);
  const isLongUnstake = stakingState ? getIsLongUnstake(stakingState, unstakeAmount) : undefined;

  const [unstakeDate, setUnstakeDate] = useState<number>(unstakeTime ?? Date.now() + VALIDATION_PERIOD_MS);
  const forceUpdate = useForceUpdate();
  const appTheme = useAppTheme(theme);

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const hasAmountError = unstakeAmount !== undefined
    && (unstakeAmount < 0 || !stakingBalance || unstakeAmount > stakingBalance);

  const isInsufficientBalance = error === ApiTransactionDraftError.InsufficientBalance
    || (unstakeAmount !== undefined && (!stakingBalance || unstakeAmount > stakingBalance));

  const isUnstakeDisabled = !isNativeEnough || isInsufficientBalance || !unstakeAmount;

  useEffect(() => {
    if (isOpen) {
      fetchStakingHistory();
      setUnstakeAmount(isOnlyFullAmount ? stakingBalance : undefined);
    }
  }, [isOpen, fetchStakingHistory, isOnlyFullAmount, stakingBalance]);

  useSyncEffect(() => {
    if (unstakeTime) {
      setUnstakeDate(unstakeTime);
    }
  }, [unstakeTime]);

  const refreshUnstakeDate = useLastCallback(() => {
    if (unstakeDate < Date.now()) {
      fetchStakingHistory();
    }
    forceUpdate();
  });

  useInterval(refreshUnstakeDate, UPDATE_UNSTAKE_DATE_INTERVAL_MS);

  const handleBackClick = useLastCallback(() => {
    if (state === StakingState.UnstakePassword) {
      setStakingScreen({ state: StakingState.UnstakeInitial });
    }
  });

  const handleStartUnstakeClick = useLastCallback(() => {
    submitStakingInitial({ isUnstaking: true, amount: unstakeAmount });
  });

  const handleTransferSubmit = useLastCallback((password: string) => {
    setSuccessUnstakeAmount(amount);

    submitStaking({ password, isUnstaking: true });
  });

  const handleLedgerConnect = useLastCallback(() => {
    setSuccessUnstakeAmount(amount);
    submitStaking({ isUnstaking: true });
  });

  function renderTransactionBanner() {
    if (!token || !unstakeAmount) return undefined;

    return (
      <TransactionBanner
        tokenIn={token}
        withChainIcon={isMultichainAccount}
        color="green"
        text={formatCurrency(toDecimal(unstakeAmount, token.decimals), token.symbol)}
        className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
      />
    );
  }

  const amountInputProps = useAmountInputState({
    amount: unstakeAmount,
    token,
    baseCurrency,
    isAmountReadonly: isOnlyFullAmount,
    onAmountChange: setUnstakeAmount,
  });

  // Wa want to render just the token name, not a token select button. To achieve that, we rely on the fact that
  // `Dropdown` renders with no button border when there is only 1 item.
  const selectableTokens = useMemo(() => token && [token], [token]);

  // It is necessary to use useCallback instead of useLastCallback here
  const renderBottomRight = useCallback((className?: string) => {
    const activeKey = isInsufficientBalance ? 0
      : !isNativeEnough ? 1
        : instantAvailable ? 2
          : 3;

    let content: string | React.JSX.Element | TeactNode[] = token ? lang('$fee_value', {
      fee: <Fee terms={{ native: realFee }} precision="approximate" token={token} />,
    }) : '';

    if (token) {
      if (isInsufficientBalance) {
        content = <span className={styles.balanceError}>{lang('Insufficient balance')}</span>;
      } else if (!isNativeEnough) {
        content = (
          <span className={styles.balanceError}>
            {lang('$insufficient_fee', {
              fee: formatCurrency(toBig(networkFee), nativeToken?.symbol ?? ''),
            })}
          </span>
        );
      } else if (instantAvailable) {
        content = lang('$unstake_up_to_information', {
          value: formatCurrency(toDecimal(instantAvailable, token.decimals), token.symbol),
        });
      }
    }

    return (
      <Transition
        className={buildClassName(styles.amountBottomRight, className)}
        slideClassName={styles.amountBottomRight_slide}
        name="semiFade"
        activeKey={activeKey}
      >
        {content}
      </Transition>
    );
  }, [instantAvailable, isInsufficientBalance, isNativeEnough, lang, nativeToken?.symbol, networkFee, realFee, token]);

  function renderUnstakeTimer() {
    const unstakeDateText = stakingType === 'ethena'
      ? renderText(lang('$unstaking_when_receive_ethena'))
      : lang('$unstaking_when_receive', {
        time: (
          <strong>{formatRelativeHumanDateTime(lang.code, unstakeDate)}</strong>
        ),
      });

    return (
      <div className={buildClassName(styles.unstakeTime)}>
        <AnimatedIconWithPreview
          play={isOpen}
          size={ANIMATED_STICKER_TINY_ICON_PX}
          className={styles.unstakeTimeIcon}
          nonInteractive
          noLoop={false}
          tgsUrl={ANIMATED_STICKERS_PATHS[appTheme].iconClockGray}
          previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview.iconClockGray}
        />
        <div>{unstakeDateText}</div>
      </div>
    );
  }

  function renderUnstakeInfo() {
    const shouldShowInfo = !isInsufficientBalance && unstakeAmount;

    return (
      <Transition
        name="fade"
        activeKey={!shouldShowInfo ? 0 : !isLongUnstake ? 1 : 2}
        className={styles.unstakeInfoTransition}
      >
        {!shouldShowInfo ? undefined
          : (
            !isLongUnstake
              ? (
                <div className={styles.unstakeInfo}>
                  {lang('$unstake_information_instantly')}
                </div>
              )
              : renderUnstakeTimer()
          )}
      </Transition>
    );
  }

  function renderInitial() {
    return (
      <>
        <ModalHeader title={lang('$unstake_asset', { symbol: token?.symbol })} onClose={cancelStaking} />
        <div className={modalStyles.transitionContent}>
          <AmountInput
            {...amountInputProps}
            labelText={lang('Amount to unstake')}
            maxAmount={stakingBalance}
            token={token}
            allTokens={selectableTokens}
            hasError={hasAmountError}
            isMaxAmountLoading={stakingBalance === undefined || !token}
            isMaxAmountAllMode
            isSensitiveDataHidden={isSensitiveDataHidden}
            renderBottomRight={renderBottomRight}
          />

          {renderUnstakeInfo()}

          {!isViewMode && (
            <div className={modalStyles.buttons}>
              <Button
                isPrimary
                isLoading={isLoading}
                isDisabled={isUnstakeDisabled}
                onClick={handleStartUnstakeClick}
              >
                {lang('Unstake')}
              </Button>
            </div>
          )}
        </div>
      </>
    );
  }

  function renderPassword(isActive: boolean) {
    const placeholder = getDoesUsePinPad()
      ? 'Confirm action with your passcode'
      : 'Confirm action with your password';

    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader title={lang('Confirm Unstaking')} onClose={cancelStaking} />
        )}
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          withCloseButton={IS_CAPACITOR}
          operationType="unstaking"
          error={error}
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
    const title = getIsMobileTelegramApp()
      ? lang('Request is sent!')
      : isLongUnstake
        ? lang('Request for unstaking is sent!')
        : lang('Coins have been unstaked!');

    return (
      <>
        <ModalHeader
          title={title}
          onClose={cancelStaking}
        />

        <div className={modalStyles.transitionContent}>
          <TransferResult
            color={!isLongUnstake ? 'green' : undefined}
            playAnimation={isActive}
            amount={successUnstakeAmount}
            tokenSymbol={token?.symbol}
            decimals={token?.decimals}
            noSign
          />

          {isLongUnstake && renderUnstakeTimer()}

          <div className={modalStyles.buttons}>
            <Button onClick={cancelStaking} isPrimary>{lang('Close')}</Button>
          </div>
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: StakingState) {
    switch (currentKey) {
      case StakingState.UnstakeInitial:
        return renderInitial();

      case StakingState.UnstakePassword:
        return renderPassword(isActive);

      case StakingState.UnstakeConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleLedgerConnect}
            onClose={cancelStaking}
          />
        );

      case StakingState.UnstakeConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelStaking}
            onTryAgain={handleLedgerConnect}
          />
        );

      case StakingState.UnstakeComplete:
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
  const tokens = selectCurrentAccountTokens(global);
  const { baseCurrency = DEFAULT_PRICE_CURRENCY, isSensitiveDataHidden } = global.settings;
  const isMultichainAccount = selectIsMultichainAccount(global, accountId);
  const stakingState = selectAccountStakingState(global, accountId);
  const isNominators = stakingState?.type === 'nominators';

  return {
    ...global.currentStaking,
    tokens,
    baseCurrency,
    isNominators,
    theme: global.settings.theme,
    isMultichainAccount,
    stakingState,
    isSensitiveDataHidden,
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(UnstakeModal));
