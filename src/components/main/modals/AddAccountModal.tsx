import React, { memo, useEffect, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { LedgerWalletInfo } from '../../../util/ledger/types';
import { type Account, SettingsState } from '../../../global/types';

import { IS_CORE_WALLET } from '../../../config';
import { selectIsPasswordPresent, selectNetworkAccounts } from '../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../../util/buildClassName';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { IS_LEDGER_SUPPORTED } from '../../../util/windowEnvironment';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AuthImportViewAccount from '../../auth/AuthImportViewAccount';
import LedgerConnect from '../../ledger/LedgerConnect';
import LedgerSelectWallets from '../../ledger/LedgerSelectWallets';
import ListItem from '../../ui/ListItem';
import Modal from '../../ui/Modal';
import ModalHeader from '../../ui/ModalHeader';
import Transition from '../../ui/Transition';
import AddAccountPasswordModal from './AddAccountPasswordModal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './AddAccountModal.module.scss';

interface StateProps {
  isOpen?: boolean;
  isLoading?: boolean;
  error?: string;
  isPasswordPresent: boolean;
  hardwareWallets?: LedgerWalletInfo[];
  accounts?: Record<string, Account>;
  withOtherWalletVersions?: boolean;
  forceAddingTonOnlyAccount?: boolean;
}

const enum RenderingState {
  Initial,
  Password,

  ConnectHardware,
  SelectAccountsHardware,

  ViewMode,
}

function AddAccountModal({
  isOpen,
  isLoading,
  error,
  hardwareWallets,
  isPasswordPresent,
  accounts,
  withOtherWalletVersions,
  forceAddingTonOnlyAccount,
}: StateProps) {
  const {
    addAccount,
    clearAccountError,
    closeAddAccountModal,
    afterSelectHardwareWallets,
    openSettingsWithState,
    resetHardwareWalletConnect,
    clearAccountLoading,
  } = getActions();

  const lang = useLang();
  const [renderingKey, setRenderingKey] = useState<RenderingState>(RenderingState.Initial);

  const [isNewAccountImporting, setIsNewAccountImporting] = useState<boolean>(false);

  const handleBackClick = useLastCallback(() => {
    setRenderingKey(RenderingState.Initial);
    clearAccountError();
  });

  const handleModalClose = useLastCallback(() => {
    setRenderingKey(RenderingState.Initial);
    setIsNewAccountImporting(false);
    clearAccountLoading();
  });

  const handleNewAccountClick = useLastCallback(() => {
    if (!isPasswordPresent) {
      addAccount({
        method: 'createAccount',
        password: '',
      });
      return;
    }

    if (getHasInMemoryPassword()) {
      void getInMemoryPassword().then((password) => addAccount({
        method: 'createAccount',
        password: password!,
      }));
    } else {
      setRenderingKey(RenderingState.Password);
      setIsNewAccountImporting(false);
    }
  });
  useEffect(() => {
    if (forceAddingTonOnlyAccount) {
      handleNewAccountClick();
    }
  }, [forceAddingTonOnlyAccount]);

  const handleImportAccountClick = useLastCallback(() => {
    if (!isPasswordPresent) {
      addAccount({
        method: 'importMnemonic',
        password: '',
      });
      return;
    }

    setIsNewAccountImporting(true);

    if (getHasInMemoryPassword()) {
      void getInMemoryPassword().then((password) => addAccount({
        method: 'importMnemonic',
        password: password!,
      }));
    } else {
      setRenderingKey(RenderingState.Password);
    }
  });

  const handleViewModeWalletClick = useLastCallback(() => {
    setRenderingKey(RenderingState.ViewMode);
  });

  const handleImportHardwareWalletClick = useLastCallback(() => {
    resetHardwareWalletConnect();
    setRenderingKey(RenderingState.ConnectHardware);
  });

  const handleAddLedgerWallet = useLastCallback(() => {
    afterSelectHardwareWallets({ hardwareSelectedIndices: [hardwareWallets![0].index] });
    closeAddAccountModal();
  });

  const handleHardwareWalletConnected = useLastCallback((isSingleWallet: boolean) => {
    if (isSingleWallet) {
      handleAddLedgerWallet();
      return;
    }
    setRenderingKey(RenderingState.SelectAccountsHardware);
  });

  const handleSubmit = useLastCallback((password: string) => {
    addAccount({ method: isNewAccountImporting ? 'importMnemonic' : 'createAccount', password });
  });

  const handleOpenSettingWalletVersion = useLastCallback(() => {
    closeAddAccountModal();
    openSettingsWithState({ state: SettingsState.WalletVersion });
  });

  function renderSelector() {
    return (
      <>
        <ModalHeader title={lang('Add Wallet')} onClose={closeAddAccountModal} />

        <div className={buildClassName(styles.actionsSection, styles.actionsSectionShift)}>
          <ListItem
            icon="wallet-add"
            label={lang('Create New Wallet')}
            onClick={handleNewAccountClick}
            isLoading={!isNewAccountImporting && isLoading}
          />
        </div>

        <span className={styles.importText}>{lang('or import from')}</span>

        <div className={styles.actionsSection}>
          <ListItem
            icon="key"
            label={lang(IS_CORE_WALLET ? '24 Secret Words' : '12/24 Secret Words')}
            onClick={handleImportAccountClick}
            isLoading={isNewAccountImporting && isLoading}
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
              onClick={handleViewModeWalletClick}
            />
          </div>
        )}

        {withOtherWalletVersions && (
          <div className={styles.walletVersionBlock}>
            <span>
              {lang('$wallet_switch_version_1', {
                action: (
                  <div
                    role="button"
                    tabIndex={0}
                    onClick={handleOpenSettingWalletVersion}
                    className={styles.walletVersionText}
                  >
                    {lang('$wallet_switch_version_2')}
                  </div>
                ),
              })}
            </span>
          </div>
        )}
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: RenderingState) {
    switch (currentKey) {
      case RenderingState.Initial:
        return renderSelector();
      case RenderingState.Password:
        return (
          <AddAccountPasswordModal
            isActive={isActive}
            isLoading={isLoading}
            error={error}
            onClearError={clearAccountError}
            onSubmit={handleSubmit}
            onBack={handleBackClick}
            onClose={closeAddAccountModal}
          />
        );
      case RenderingState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            doLoadWallets
            onConnected={handleHardwareWalletConnected}
            onCancel={handleBackClick}
            onClose={closeAddAccountModal}
          />
        );
      case RenderingState.SelectAccountsHardware:
        return (
          <LedgerSelectWallets
            accounts={accounts}
            hardwareWallets={hardwareWallets}
            onCancel={handleBackClick}
            onClose={closeAddAccountModal}
          />
        );
      case RenderingState.ViewMode:
        return (
          <AuthImportViewAccount
            isActive={isActive}
            isLoading={isLoading}
            onCancel={handleBackClick}
            onClose={closeAddAccountModal}
          />
        );
    }
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen}
      noBackdropClose
      dialogClassName={styles.modalDialog}
      contentClassName={styles.modalContent}
      nativeBottomSheetKey="add-account"
      forceFullNative={renderingKey === RenderingState.Password}
      onCloseAnimationEnd={handleModalClose}
      onClose={closeAddAccountModal}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={
          renderingKey === RenderingState.Initial && !getHasInMemoryPassword() ? RenderingState.Password : undefined
        }
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accounts = selectNetworkAccounts(global);
  const isPasswordPresent = selectIsPasswordPresent(global);
  const { byId: versionById } = global.walletVersions ?? {};
  const versions = versionById?.[global.currentAccountId!];
  const withOtherWalletVersions = !!versions?.length;

  const { auth: { forceAddingTonOnlyAccount }, hardware: { hardwareWallets } } = global;

  return {
    isOpen: global.isAddAccountModalOpen,
    isLoading: global.accounts?.isLoading,
    error: global.accounts?.error,
    accounts,
    isPasswordPresent,
    hardwareWallets,
    withOtherWalletVersions,
    forceAddingTonOnlyAccount,
  };
})(AddAccountModal));
