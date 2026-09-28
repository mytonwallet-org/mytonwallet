import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiToken } from '../../api/types';
import type { GlobalState } from '../../global/types';
import { TransferState } from '../../global/types';

import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import DappMfaConfirm from './DappMfaConfirm';
import DappTransaction from './DappTransaction';
import DappTransferInitial from './DappTransferInitial';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface StateProps {
  currentDappTransfer: GlobalState['currentDappTransfer'];
  tokensBySlug: Record<string, ApiToken>;
  isMediaViewerOpen?: boolean;
}

function DappTransferModal({
  currentDappTransfer: {
    isLoading,
    viewTransactionOnIdx,
    state,
    transactions,
    error,
  },
  tokensBySlug,
  isMediaViewerOpen,
}: StateProps) {
  const {
    setDappTransferScreen,
    clearDappTransferError,
    submitDappTransfer,
    closeDappTransfer,
    cancelDappTransfer,
  } = getActions();

  const lang = useLang();

  const isOpen = state !== TransferState.None;

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const handleBackClick = useLastCallback(() => {
    if (state === TransferState.Confirm || state === TransferState.Password) {
      setDappTransferScreen({ state: TransferState.Initial });
    }
  });

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    submitDappTransfer({ enclaveToken });
  });

  const handleLedgerConnect = useLastCallback(() => {
    submitDappTransfer();
  });

  const handleResetTransfer = useLastCallback(() => {
    cancelDappTransfer();
    updateNextKey();
  });

  function renderPassword(isActive: boolean) {
    const title = (transactions?.length ?? 0) > 1
      ? '$classic_confirm_actions'
      : 'Confirm Action';

    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader title={lang(title)} onClose={closeDappTransfer} />
        )}
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          error={error}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Back')}
          noAutoConfirm
          onAuthorize={handleAuthorize}
          onCancel={handleBackClick}
          onUpdate={clearDappTransferError}
        />
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: TransferState) {
    switch (currentKey) {
      case TransferState.Initial:
        return <DappTransferInitial isActive={isActive} onClose={closeDappTransfer} />;

      case TransferState.Confirm:
        return (
          <DappTransaction
            transaction={viewTransactionOnIdx !== undefined ? transactions?.[viewTransactionOnIdx] : undefined}
            tokensBySlug={tokensBySlug}
            isActive={isActive}
            onBack={handleBackClick}
            onClose={closeDappTransfer}
          />
        );

      case TransferState.Password:
        return renderPassword(isActive);

      case TransferState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleLedgerConnect}
            onClose={closeDappTransfer}
          />
        );

      case TransferState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm transfer on your Ledger')}
            error={error}
            onTryAgain={handleLedgerConnect}
            onClose={closeDappTransfer}
          />
        );

      case TransferState.ConfirmMfa:
        return (
          <DappMfaConfirm
            isActive={isActive}
            onClose={closeDappTransfer}
          />
        );
    }
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen && !isMediaViewerOpen}
      noBackdropClose
      dialogClassName={styles.modalDialog}
      onClose={closeDappTransfer}
      onCloseAnimationEnd={handleResetTransfer}
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
  return {
    currentDappTransfer: global.currentDappTransfer,
    tokensBySlug: global.tokenInfo.bySlug,
    isMediaViewerOpen: Boolean(global.mediaViewer.mediaId),
  };
})(DappTransferModal));
