import React, {
  memo, useState,
} from '../../lib/teact/teact';
import { withGlobal } from '../../global';

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
  areSettingsOpen,
}: OwnProps & StateProps) {
  const [currentSlide, setCurrentSlide] = useState<LedgerModalState>(
    LedgerModalState.Connect,
  );
  const [nextKey] = useState<LedgerModalState | undefined>(
    LedgerModalState.SelectWallets,
  );

  const handleConnected = useLastCallback(() => {
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
            onConnected={handleConnected}
            onBackButtonClick={onClose}
            onClose={onClose}
          />
        );
      case LedgerModalState.SelectWallets:
        return (
          <LedgerSelectWallets
            isActive={isActive}
            onBackButtonClick={onClose}
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
  return {
    areSettingsOpen: global.areSettingsOpen,
  };
})(LedgerModal));
