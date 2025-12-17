import React, { memo, useMemo, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type {
  ApiActivity,
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiNft,
  ApiStakingState,
  ApiSwapActivity,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../../../api/types';
import type { Account, SavedAddress, Theme } from '../../../../global/types';
import { TransactionInfoState } from '../../../../global/types';

import {
  selectAccountStakingStatesBySlug,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsHardwareAccount,
  selectNetworkAccounts,
} from '../../../../global/selectors';
import { getDoesUsePinPad } from '../../../../util/biometrics';
import buildClassName from '../../../../util/buildClassName';
import resolveSlideTransitionName from '../../../../util/resolveSlideTransitionName';

import useAppTheme from '../../../../hooks/useAppTheme';
import useEncryptedComment from '../../../../hooks/useEncryptedComment';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import PasswordSlide from '../../../common/PasswordSlide';
import SwapActivityInfo from '../../../common/SwapActivityInfo';
import TransactionHeader from '../../../common/TransactionHeader';
import Modal from '../../../ui/Modal';
import ModalHeader from '../../../ui/ModalHeader';
import Spinner from '../../../ui/Spinner';
import Transition from '../../../ui/Transition';
import Activity from '../../sections/Content/Activity';
import TransactionInfo from './TransactionInfo';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './TransactionInfoModal.module.scss';

interface StateProps {
  state: TransactionInfoState;
  txId?: string;
  activities?: ApiActivity[];
  selectedActivityIndex?: number;
  error?: string;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  theme: Theme;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  nftsByAddress?: Record<string, ApiNft>;
  currentAccountId: string;
  stakingStateBySlug: Record<string, ApiStakingState>;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  isMediaViewerOpen?: boolean;
  isSensitiveDataHidden?: true;
  isTestnet?: boolean;
  isHardwareAccount: boolean;
  isViewMode: boolean;
}

const enum SLIDES {
  loading = -1,
  list,
  detail,
  password,
}

function TransactionInfoModal({
  state,
  activities,
  selectedActivityIndex,
  tokensBySlug,
  swapTokensBySlug,
  theme,
  baseCurrency,
  currencyRates,
  nftsByAddress,
  currentAccountId,
  stakingStateBySlug,
  savedAddresses,
  accounts,
  isMediaViewerOpen,
  isSensitiveDataHidden,
  isTestnet,
  isHardwareAccount,
  isViewMode,
}: StateProps) {
  const {
    closeTransactionInfo,
    selectTransactionInfoActivity,
    setIsPinAccepted,
    clearIsPinAccepted,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);

  const isOpen = state !== TransactionInfoState.None && !isMediaViewerOpen;
  const isLoading = state === TransactionInfoState.Loading;
  const showDetail = state === TransactionInfoState.ActivityDetail;

  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.detail);

  const selectedActivity = useMemo(() => {
    if (selectedActivityIndex === undefined || !activities) return undefined;
    return activities[selectedActivityIndex];
  }, [activities, selectedActivityIndex]);

  const selectedTransactionActivity = selectedActivity?.kind === 'transaction'
    ? selectedActivity
    : undefined;

  const selectedSwapActivity = selectedActivity?.kind === 'swap'
    ? selectedActivity
    : undefined;

  const encryptedComment = selectedTransactionActivity?.encryptedComment;
  const canDecryptComment = !isViewMode && !isHardwareAccount && Boolean(encryptedComment);

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
    transaction: selectedTransactionActivity,
    encryptedComment,
    onPinAccepted: setIsPinAccepted,
  });

  // Sync slide state with hook's `isPasswordSlideOpen`
  useSyncEffect(() => {
    if (isPasswordSlideOpen && currentSlide !== SLIDES.password) {
      setCurrentSlide(SLIDES.password);
    } else if (!isPasswordSlideOpen && currentSlide === SLIDES.password) {
      setCurrentSlide(SLIDES.detail);
    }
  }, [isPasswordSlideOpen, currentSlide]);

  useSyncEffect(() => {
    if (selectedTransactionActivity) {
      resetDecryptedComment();
      setCurrentSlide(SLIDES.detail);
    }
  }, [selectedTransactionActivity, resetDecryptedComment]);

  const closePasswordSlide = useLastCallback(() => {
    closePasswordSlideBase();
    setCurrentSlide(SLIDES.detail);
  });

  const handleClose = useLastCallback(() => {
    closeTransactionInfo();
    if (getDoesUsePinPad()) {
      clearIsPinAccepted();
    }
  });

  const handleActivityClick = useLastCallback((id: string) => {
    const index = activities?.findIndex((a) => a.id === id);
    if (index !== undefined && index >= 0) {
      selectTransactionInfoActivity({ index });
    }
  });

  const handleBackClick = useLastCallback(() => {
    selectTransactionInfoActivity({ index: -1 });
  });

  function renderLoading() {
    return (
      <>
        <ModalHeader title={lang('Transaction Info')} onClose={handleClose} />
        <div className={styles.loadingContainer}>
          <Spinner />
        </div>
      </>
    );
  }

  function renderActivityList() {
    if (!activities?.length) {
      return (
        <>
          <ModalHeader title={lang('Transaction Info')} onClose={handleClose} />
          <div className={styles.emptyState}>
            {lang('No activities found')}
          </div>
        </>
      );
    }

    return (
      <>
        <ModalHeader title={lang('Transaction Info')} onClose={handleClose} />
        <div className={buildClassName(modalStyles.transitionContent, styles.activityList)}>
          <div className={styles.activityListContainer}>
            {activities.map((activity, index) => (
              <div key={activity.id} className={styles.activityItem}>
                <Activity
                  activity={activity}
                  isLast={index === activities.length - 1}
                  className={styles.activity}
                  tokensBySlug={tokensBySlug}
                  swapTokensBySlug={swapTokensBySlug}
                  appTheme={appTheme}
                  nftsByAddress={nftsByAddress}
                  currentAccountId={currentAccountId}
                  stakingStateBySlug={stakingStateBySlug}
                  savedAddresses={savedAddresses}
                  accounts={accounts}
                  baseCurrency={baseCurrency}
                  currencyRates={currencyRates}
                  isSensitiveDataHidden={isSensitiveDataHidden}
                  onClick={handleActivityClick}
                />
                <div className={styles.activityArrow}>
                  <i className="icon-chevron-right" aria-hidden />
                </div>
              </div>
            ))}
          </div>
        </div>
      </>
    );
  }

  function renderActivityDetail() {
    if (!selectedActivity) return undefined;

    const backButton = activities && activities.length > 1 ? handleBackClick : undefined;

    if (selectedSwapActivity) {
      return renderSwapActivityDetail(selectedSwapActivity, backButton);
    }

    if (selectedTransactionActivity) {
      return (
        <>
          <TransactionHeader
            transaction={selectedTransactionActivity}
            appTheme={appTheme}
            isModalOpen={isOpen}
            onBackClick={backButton}
            onClose={handleClose}
          />
          <TransactionInfo
            transaction={selectedTransactionActivity}
            tokensBySlug={tokensBySlug}
            savedAddresses={savedAddresses}
            nftsByAddress={nftsByAddress}
            accounts={accounts}
            currentAccountId={currentAccountId}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            theme={theme}
            isTestnet={isTestnet}
            isOpen={isOpen}
            isSensitiveDataHidden={isSensitiveDataHidden}
            forceShowAddress
            showBothAddresses
            encryptedComment={encryptedComment}
            decryptedComment={decryptedComment}
            canDecryptComment={canDecryptComment}
            onDecryptComment={openHiddenComment}
          />
        </>
      );
    }

    return undefined;
  }

  function renderSwapActivityDetail(activity: ApiSwapActivity, backButton?: NoneToVoidFunction) {
    return (
      <>
        <ModalHeader
          title={lang('Swap Details')}
          onBackButtonClick={backButton}
          onClose={handleClose}
        />
        <div className={modalStyles.transitionContent}>
          <SwapActivityInfo
            activity={activity}
            tokensBySlug={swapTokensBySlug}
            isSensitiveDataHidden={isSensitiveDataHidden}
          />
        </div>
      </>
    );
  }

  function renderPasswordSlideContent(isActive: boolean) {
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

  function renderContent(isActive: boolean, isFrom: boolean, slideKey: SLIDES) {
    switch (slideKey) {
      case SLIDES.loading:
        return renderLoading();
      case SLIDES.list:
        return renderActivityList();
      case SLIDES.detail:
        return renderActivityDetail();
      case SLIDES.password:
        return renderPasswordSlideContent(isActive);
    }
  }

  const baseSlide = isLoading ? SLIDES.loading : showDetail ? SLIDES.detail : SLIDES.list;
  const activeSlide = currentSlide === SLIDES.password ? SLIDES.password : baseSlide;

  return (
    <Modal
      isOpen={isOpen}
      hasCloseButton
      nativeBottomSheetKey="transaction-info"
      forceFullNative={currentSlide === SLIDES.password}
      dialogClassName={styles.modalDialog}
      onClose={handleClose}
      onCloseAnimationEnd={closePasswordSlide}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={activeSlide}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { currentTransactionInfo } = global;
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectCurrentAccountState(global);
  const accounts = selectNetworkAccounts(global);

  return {
    state: currentTransactionInfo.state,
    txId: currentTransactionInfo.txId,
    activities: currentTransactionInfo.activities,
    selectedActivityIndex: currentTransactionInfo.selectedActivityIndex,
    error: currentTransactionInfo.error,
    tokensBySlug: global.tokenInfo.bySlug,
    swapTokensBySlug: global.swapTokenInfo.bySlug,
    theme: global.settings.theme,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    nftsByAddress: accountState?.nfts?.byAddress,
    currentAccountId: accountId,
    stakingStateBySlug: selectAccountStakingStatesBySlug(global, accountId),
    savedAddresses: accountState?.savedAddresses,
    accounts,
    isMediaViewerOpen: Boolean(global.mediaViewer.mediaId),
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
    isTestnet: global.settings.isTestnet,
    isHardwareAccount: selectIsHardwareAccount(global),
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(TransactionInfoModal));
