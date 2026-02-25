import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { selectCurrentAccountId, selectIsHardwareAccount, selectIsMultichainAccount } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { IS_IOS_APP } from '../../util/windowEnvironment';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';

import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Content from './Content';

import styles from './ReceiveModal.module.scss';

type StateProps = {
  isOpen?: boolean;
  isLedger?: boolean;
  isTestnet?: boolean;
  isSwapDisabled: boolean;
  isOnRampDisabled: boolean;
  isMultichainAccount: boolean;
};

function ReceiveModal({
  isOpen,
  isTestnet,
  isLedger,
  isSwapDisabled,
  isOnRampDisabled,
  isMultichainAccount,
}: StateProps) {
  const { closeReceiveModal } = getActions();

  const lang = useLang();

  const { isLandscape } = useDeviceScreen();
  const isSwapAllowed = !isTestnet && !isLedger && !isSwapDisabled;
  const isOnRampAllowed = !isTestnet && !isOnRampDisabled;
  const modalTitle = lang(isSwapAllowed || isOnRampAllowed ? 'Fund' : 'Add');

  useEffect(() => {
    if (isOpen && isLandscape) {
      closeReceiveModal();
    }
  }, [isLandscape, isOpen]);

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={IS_IOS_APP ? styles.iosModalDialog : styles.modalDialog}
      onClose={closeReceiveModal}
    >
      <ModalHeader
        title={modalTitle}
        className={buildClassName(styles.receiveHeader, !isMultichainAccount && styles.receiveHeaderNoTabs)}
        onClose={closeReceiveModal}
      />
      <Content
        isOpen={isOpen}
        onClose={closeReceiveModal}
      />
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { isSwapDisabled, isOnRampDisabled } = global.restrictions;
  const currentAccountId = selectCurrentAccountId(global);
  const isLedger = selectIsHardwareAccount(global);
  const isMultichainAccount = selectIsMultichainAccount(global, currentAccountId!);

  return {
    isOpen: global.isReceiveModalOpen,
    isTestnet: global.settings.isTestnet,
    isSwapDisabled,
    isOnRampDisabled,
    isLedger,
    isMultichainAccount,
  };
})(ReceiveModal));
