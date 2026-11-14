import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { getChainsSupportingLedger } from '../../util/chain';
import getTestId from '../../util/getTestId';
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
          testId={getTestId('add_wallet_secret_words')}
          label={lang('$secret_words')}
          description={lang('Restore wallet from 12 or 24 words')}
          onClick={handleSecretWordsClick}
        />
        {IS_LEDGER_SUPPORTED && (
          <ListItem
            icon="ledger-alt"
            testId={getTestId('add_wallet_ledger')}
            label={lang('Ledger')}
            description={lang('Connect your hardware wallet')}
            onClick={handleImportHardwareWalletClick}
          />
        )}
      </div>

      <div className={styles.actionsSection}>
        <ListItem
          icon="wallet-view"
          testId={getTestId('add_wallet_view')}
          label={lang('View Any Address')}
          description={lang('Watch wallet in read-only mode')}
          onClick={handleImportViewAccountClick}
        />
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isOpen: global.auth.isImportModalOpen,
  };
})(AuthImportWalletModal));
