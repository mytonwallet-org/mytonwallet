import React, {
  memo, useEffect, useState,
} from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type {
  ApiBaseCurrency,
  ApiChain,
  ApiCurrencyRates,
  ApiNft,
  ApiStakingState,
  ApiTokenWithPrice,
  ApiToncoinStakingState,
  ApiTransactionActivity,
} from '../../../../api/types';
import type { Account, SavedAddress, Theme } from '../../../../global/types';
import { ActiveTab } from '../../../../global/types';

import {
  ANIMATION_END_DELAY,
  ANIMATION_LEVEL_MIN,
  TONCOIN,
  VALIDATION_PERIOD_MS,
} from '../../../../config';
import {
  selectAccounts,
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsHardwareAccount,
} from '../../../../global/selectors';
import {
  getIsActivityWithHash,
  isOurStakingTransaction,
  parseTxId,
} from '../../../../util/activities';
import { bigintAbs } from '../../../../util/bigint';
import { getDoesUsePinPad } from '../../../../util/biometrics';
import buildClassName from '../../../../util/buildClassName';
import resolveSlideTransitionName from '../../../../util/resolveSlideTransitionName';
import { shareUrl } from '../../../../util/share';
import { getStakingStateStatus } from '../../../../util/staking';
import { getChainBySlug } from '../../../../util/tokens';
import { getExplorerTransactionUrl, getViewTransactionUrl } from '../../../../util/url';

import useAppTheme from '../../../../hooks/useAppTheme';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useEncryptedComment from '../../../../hooks/useEncryptedComment';
import useLastCallback from '../../../../hooks/useLastCallback';
import usePrevDuringAnimation from '../../../../hooks/usePrevDuringAnimation';
import useShowTransition from '../../../../hooks/useShowTransition';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import PasswordSlide from '../../../common/PasswordSlide';
import TransactionHeader from '../../../common/TransactionHeader';
import Modal, { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../ui/Modal';
import Transition from '../../../ui/Transition';
import TransactionInfo from './TransactionInfo';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './TransactionModal.module.scss';

type StateProps = {
  transaction?: ApiTransactionActivity;
  tokensBySlug?: Record<string, ApiTokenWithPrice>;
  savedAddresses?: SavedAddress[];
  isHardwareAccount: boolean;
  isTestnet?: boolean;
  isViewMode: boolean;
  stakingStates?: ApiStakingState[];
  isLongUnstakeRequested?: boolean;
  isMediaViewerOpen?: boolean;
  theme: Theme;
  isSensitiveDataHidden?: true;
  nftsByAddress?: Record<string, ApiNft>;
  accounts?: Record<string, Account>;
  currentAccountId: string;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
};

const enum SLIDES {
  initial,
  password,
}

function TransactionModal({
  transaction,
  tokensBySlug,
  savedAddresses,
  isTestnet,
  isHardwareAccount,
  isViewMode,
  stakingStates,
  isLongUnstakeRequested,
  isMediaViewerOpen,
  theme,
  isSensitiveDataHidden,
  nftsByAddress,
  accounts,
  currentAccountId,
  baseCurrency,
  currencyRates,
  selectedExplorerIds,
}: StateProps) {
  const {
    fetchActivityDetails,
    startTransfer,
    startStaking,
    startUnstaking,
    closeActivityInfo,
    setIsPinAccepted,
    clearIsPinAccepted,
    setLandscapeActionsActiveTabIndex,
    selectToken,
  } = getActions();

  const { isPortrait } = useDeviceScreen();
  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.initial);
  const [nextKey, setNextKey] = useState<SLIDES | undefined>(SLIDES.password);
  const animationLevel = getGlobal().settings.animationLevel;
  const animationDuration = animationLevel === ANIMATION_LEVEL_MIN
    ? 0
    : (isPortrait ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION) + ANIMATION_END_DELAY;
  const renderedTransaction = usePrevDuringAnimation(transaction, animationDuration);
  const [unstakeDate, setUnstakeDate] = useState<number>(Date.now() + VALIDATION_PERIOD_MS);
  const appTheme = useAppTheme(theme);

  const {
    id,
    isIncoming,
    slug,
    shouldLoadDetails,
    encryptedComment,
    amount,
    comment,
  } = renderedTransaction || {};

  const token = slug ? tokensBySlug?.[slug] : undefined;
  const address = isIncoming ? renderedTransaction?.fromAddress : renderedTransaction?.toAddress;
  const isModalOpen = Boolean(transaction) && !isMediaViewerOpen;
  const canDecryptComment = !isViewMode && !isHardwareAccount;

  const [
    { decryptedComment, passwordError, isPasswordSlideOpen },
    {
      closePasswordSlide: closePasswordSlideBase,
      clearPasswordError,
      handlePasswordSubmit,
      openHiddenComment,
      resetDecryptedComment,
    },
  ] = useEncryptedComment({
    transaction: renderedTransaction,
    encryptedComment,
    onPinAccepted: setIsPinAccepted,
  });

  const stakingState = stakingStates?.find((staking): staking is ApiToncoinStakingState => {
    return staking.tokenSlug === TONCOIN.slug && staking.balance > 0n;
  });
  const stakingStatus = stakingState && getStakingStateStatus(stakingState);
  const startOfStakingCycle = stakingState?.start;
  const endOfStakingCycle = stakingState?.end;

  const transactionHash = token?.chain && id ? parseTxId(id).hash : undefined;
  const transactionUrl = token?.chain
    ? getExplorerTransactionUrl(
      token.chain,
      transactionHash,
      isTestnet,
      selectedExplorerIds?.[token.chain],
    )
    : undefined;
  const isActivityWithHash = renderedTransaction && getIsActivityWithHash(renderedTransaction);

  const {
    shouldRender: shouldRenderTransactionId,
    ref: transactionIdRef,
  } = useShowTransition({
    isOpen: Boolean(isActivityWithHash && transactionUrl),
    withShouldRender: true,
  });

  const {
    shouldRender: shouldRenderUnstakeTimer,
    ref: unstakeTimerRef,
  } = useShowTransition({
    isOpen: transaction?.type === 'unstakeRequest'
      && startOfStakingCycle !== undefined
      && (stakingStatus === 'unstakeRequested' || isLongUnstakeRequested)
      && transaction.timestamp >= startOfStakingCycle,
    withShouldRender: true,
  });

  // Sync slide state with hook's `isPasswordSlideOpen`
  useSyncEffect(() => {
    if (isPasswordSlideOpen && currentSlide !== SLIDES.password) {
      setCurrentSlide(SLIDES.password);
      setNextKey(undefined);
    } else if (!isPasswordSlideOpen && currentSlide === SLIDES.password) {
      setCurrentSlide(SLIDES.initial);
      setNextKey(SLIDES.password);
    }
  }, [isPasswordSlideOpen, currentSlide]);

  useSyncEffect(() => {
    if (renderedTransaction) {
      resetDecryptedComment();
    }
  }, [renderedTransaction, resetDecryptedComment]);

  useSyncEffect(() => {
    if (endOfStakingCycle) {
      setUnstakeDate(endOfStakingCycle);
    }
  }, [endOfStakingCycle]);

  useEffect(() => {
    if (id && shouldLoadDetails) fetchActivityDetails({ id });
  }, [id, shouldLoadDetails]);

  const closePasswordSlide = useLastCallback(() => {
    closePasswordSlideBase();
    setCurrentSlide(SLIDES.initial);
    setNextKey(SLIDES.password);
  });

  const handleSendClick = useLastCallback(() => {
    closeActivityInfo({ id: id! });
    startTransfer({
      isPortrait,
      tokenSlug: slug || TONCOIN.slug,
      toAddress: address,
      amount: bigintAbs(amount!),
      comment: !isIncoming ? comment : undefined,
    });
  });

  const handleStartStakingClick = useLastCallback(() => {
    closeActivityInfo({ id: id! });

    if (!isPortrait) {
      setLandscapeActionsActiveTabIndex({ index: ActiveTab.Stake });
      return;
    }

    startStaking();
  });

  const handleUnstakeMoreClick = useLastCallback(() => {
    closeActivityInfo({ id: id! });

    if (!isPortrait) {
      setLandscapeActionsActiveTabIndex({ index: ActiveTab.Stake });
    }

    startUnstaking();
  });

  const handleClose = useLastCallback(() => {
    closeActivityInfo({ id: id! });
    if (getDoesUsePinPad()) {
      clearIsPinAccepted();
    }
  });

  const handleTokenClick = useLastCallback((tokenSlug: string) => {
    closeActivityInfo({ id: id! });
    selectToken({ slug: tokenSlug });
  });

  const transactionChain = slug ? getChainBySlug(slug) : undefined;

  const handleShareClick = useLastCallback(() => {
    const url = getViewTransactionUrl(transactionChain!, transactionHash!, isTestnet);
    void shareUrl(url);
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.initial:
        return (
          <>
            {renderedTransaction && (
              <TransactionHeader
                transaction={renderedTransaction}
                appTheme={appTheme}
                isModalOpen={isModalOpen}
                onShareClick={transactionChain && transactionHash ? handleShareClick : undefined}
                onClose={handleClose}
              />
            )}
            <TransactionInfo
              transaction={renderedTransaction}
              tokensBySlug={tokensBySlug}
              savedAddresses={savedAddresses}
              nftsByAddress={nftsByAddress}
              accounts={accounts}
              currentAccountId={currentAccountId}
              baseCurrency={baseCurrency}
              currencyRates={currencyRates}
              theme={theme}
              isTestnet={isTestnet}
              isOpen={isModalOpen}
              isSensitiveDataHidden={isSensitiveDataHidden}
              isViewMode={isViewMode}
              stakingStates={stakingStates}
              isLongUnstakeRequested={isLongUnstakeRequested}
              encryptedComment={encryptedComment}
              decryptedComment={decryptedComment}
              canDecryptComment={canDecryptComment}
              onDecryptComment={openHiddenComment}
              unstakeDate={unstakeDate}
              shouldRenderUnstakeTimer={shouldRenderUnstakeTimer}
              unstakeTimerRef={unstakeTimerRef}
              shouldRenderTransactionId={shouldRenderTransactionId}
              transactionIdRef={transactionIdRef}
              onSendClick={handleSendClick}
              onStartStakingClick={handleStartStakingClick}
              onUnstakeMoreClick={handleUnstakeMoreClick}
              onTokenClick={handleTokenClick}
              selectedExplorerIds={selectedExplorerIds}
            />
          </>
        );
      case SLIDES.password:
        if (!encryptedComment) return undefined;

        return (
          <PasswordSlide
            isActive={isActive}
            error={passwordError}
            onSubmit={handlePasswordSubmit}
            onCancel={closePasswordSlide}
            onUpdate={clearPasswordError}
            onClose={handleClose}
          />
        );
    }
  }

  const isOurUnstaking = renderedTransaction
    && isOurStakingTransaction(renderedTransaction)
    && renderedTransaction.type === 'unstake';

  return (
    <Modal
      isOpen={isModalOpen}
      hasCloseButton
      dialogClassName={buildClassName(styles.modalDialog, isOurUnstaking && styles.unstakeModal)}
      onClose={handleClose}
      onCloseAnimationEnd={closePasswordSlide}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={currentSlide}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(
  withGlobal((global): StateProps => {
    const accountId = selectCurrentAccountId(global)!;
    const accountState = selectCurrentAccountState(global);

    const txId = accountState?.currentActivityId;
    const activity = txId ? accountState?.activities?.byId[txId] : undefined;
    const savedAddresses = accountState?.savedAddresses;
    const { byAddress } = accountState?.nfts || {};

    const stakingStates = selectAccountStakingStates(global, accountId);
    const { isTestnet, theme, isSensitiveDataHidden } = global.settings;
    const accounts = selectAccounts(global);
    const isHardwareAccount = selectIsHardwareAccount(global);

    return {
      transaction: activity?.kind === 'transaction' ? activity : undefined,
      tokensBySlug: global.tokenInfo?.bySlug,
      savedAddresses,
      isHardwareAccount,
      isTestnet,
      isViewMode: selectIsCurrentAccountViewMode(global),
      isLongUnstakeRequested: accountState?.isLongUnstakeRequested,
      isMediaViewerOpen: Boolean(global.mediaViewer.mediaId),
      theme,
      stakingStates,
      isSensitiveDataHidden,
      nftsByAddress: byAddress,
      accounts,
      currentAccountId: accountId,
      baseCurrency: global.settings.baseCurrency,
      currencyRates: global.currencyRates,
      selectedExplorerIds: global.settings.selectedExplorerIds,
    };
  })(TransactionModal),
);
