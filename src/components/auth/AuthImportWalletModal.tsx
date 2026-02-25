import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { IS_CORE_WALLET, MNEMONIC_COUNTS } from '../../config';
import { getChainsSupportingLedger } from '../../util/chain';
import { IS_LEDGER_SUPPORTED } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import ListItem from '../ui/ListItem';
import Modal from '../ui/Modal';

import styles from './Auth.module.scss';

interface StateProps {
  isOpen?: boolean;
}

function AuthImportWalletModal({ isOpen }: StateProps) {
  const {
    startImportingWallet,
    startImportViewAccount,
    openHardwareWalletModal,
    closeAuthImportWalletModal,
  } = getActions();

  const lang = useLang();

  const handleSecretWordsClick = useLastCallback(() => {
    closeAuthImportWalletModal();
    startImportingWallet();
  });

  const handleImportHardwareWalletClick = useLastCallback(() => {
    closeAuthImportWalletModal();
    openHardwareWalletModal({ chain: getChainsSupportingLedger()[0] }); // todo: Add a chain selector screen for Ledger auth
  });

  const handleImportViewAccountClick = useLastCallback(() => {
    closeAuthImportWalletModal();
    startImportViewAccount();
  });

  return (
    <Modal
      isOpen={isOpen}
      title={lang('Import Wallet')}
      hasCloseButton
      forceBottomSheet

      contentClassName={styles.importModalContent}
      onClose={closeAuthImportWalletModal}
    >
      <div className={styles.actionsSection}>
        <ListItem
          icon="key"
          label={lang('%counts% Secret Words', { counts: MNEMONIC_COUNTS.join('/') })}
          onClick={handleSecretWordsClick}
        />
        {IS_LEDGER_SUPPORTED && (
          <ListItem
            icon="ledger-alt"
            label={lang('Ledger')}
            onClick={handleImportHardwareWalletClick}
          />
        )}
      </div>

      {!IS_CORE_WALLET && (
        <div className={styles.actionsSection}>
          <ListItem
            icon="wallet-view"
            label={lang('View Any Address')}
            onClick={handleImportViewAccountClick}
          />
        </div>
      )}
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isOpen: global.auth.isImportModalOpen,
  };
})(AuthImportWalletModal));
