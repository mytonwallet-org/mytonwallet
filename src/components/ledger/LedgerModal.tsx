import React, {
  memo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { Account } from '../../global/types';
import type { LedgerWalletInfo } from '../../util/ledger/types';

import { selectNetworkAccounts } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useLastCallback from '../../hooks/useLastCallback';

import Modal from '../ui/Modal';
import Transition from '../ui/Transition';
import LedgerConnect from './LedgerConnect';
import LedgerSelectWallets from './LedgerSelectWallets';

import modalStyles from '../ui/Modal.module.scss';
import styles from './LedgerModal.module.scss';

type OwnProps = {
  isOpen?: boolean;
  noBackdropClose?: boolean;
  onClose: () => void;
};

type StateProps = {
  hardwareWallets?: LedgerWalletInfo[];
  accounts?: Record<string, Account>;
  areSettingsOpen?: boolean;
};

enum LedgerModalState {
  Password,
  Connect,
  SelectWallets,
}

function LedgerModal({
  isOpen,
  noBackdropClose,
  onClose,
  hardwareWallets,
  accounts,
  areSettingsOpen,
}: OwnProps & StateProps) {
  const { afterSelectHardwareWallets } = getActions();

  const [currentSlide, setCurrentSlide] = useState<LedgerModalState>(
    LedgerModalState.Connect,
  );
  const [nextKey] = useState<LedgerModalState | undefined>(
    LedgerModalState.SelectWallets,
  );

  const handleAddLedgerWallet = useLastCallback(() => {
    afterSelectHardwareWallets({ hardwareSelectedIndices: [hardwareWallets![0].index] });
    onClose();
  });

  const handleConnected = useLastCallback((isSingleWallet: boolean) => {
    if (isSingleWallet) {
      handleAddLedgerWallet();
      return;
    }
    setCurrentSlide(LedgerModalState.SelectWallets);
  });

  const handleLedgerModalClose = useLastCallback(() => {
    setCurrentSlide(LedgerModalState.Connect);
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: LedgerModalState) {
    switch (currentKey) {
      case LedgerModalState.Connect:
        return (
          <LedgerConnect
            isActive={isActive}
            doLoadWallets
            onConnected={handleConnected}
            onClose={onClose}
          />
        );
      case LedgerModalState.SelectWallets:
        return (
          <LedgerSelectWallets
            isActive={isActive}
            accounts={accounts}
            hardwareWallets={hardwareWallets}
            onClose={onClose}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      hasCloseButton
      onClose={onClose}
      onCloseAnimationEnd={handleLedgerModalClose}
      dialogClassName={buildClassName(styles.modalDialog, areSettingsOpen && styles.modalDialogInsideSettings)}
      noBackdropClose={noBackdropClose}
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

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accounts = selectNetworkAccounts(global);

  const { hardwareWallets } = global.hardware;

  return {
    accounts,
    hardwareWallets,
    areSettingsOpen: global.areSettingsOpen,
  };
})(LedgerModal));
