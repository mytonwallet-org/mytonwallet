import React, { memo, useEffect, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { SettingsState } from '../../../global/types';

import { IS_CORE_WALLET, MNEMONIC_COUNTS } from '../../../config';
import { selectCurrentAccountId, selectIsPasswordPresent } from '../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../../util/buildClassName';
import { getChainsSupportingLedger } from '../../../util/chain';
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
  withOtherWalletVersions?: boolean;
  forceAddingTonOnlyAccount?: boolean;
  initialState?: RenderingState;
}

const enum RenderingState {
  Initial,
  Password,

  ConnectHardware,
  SelectAccountsHardware,

  ViewMode,
}

export const ADD_LEDGER_ACCOUNT = RenderingState.ConnectHardware;
export const ADD_VIEW_ACCOUNT = RenderingState.ViewMode;

function AddAccountModal({
  isOpen,
  isLoading,
  error,
  isPasswordPresent,
  withOtherWalletVersions,
  forceAddingTonOnlyAccount,
  initialState = RenderingState.Initial,
}: StateProps) {
  const {
    addAccount,
    clearAccountError,
    closeAddAccountModal,
    openSettingsWithState,
    resetHardwareWalletConnect,
    clearAccountLoading,
  } = getActions();

  const lang = useLang();
  const [renderingKey, setRenderingKey] = useState<RenderingState>(initialState);
  const [isNewAccountImporting, setIsNewAccountImporting] = useState<boolean>(false);

  const handleImportHardwareWalletClick = useLastCallback(() => {
    resetHardwareWalletConnect({
      chain: getChainsSupportingLedger()[0], // todo: Add a chain selector screen for Ledger auth
      shouldLoadWallets: true,
    });
    setRenderingKey(RenderingState.ConnectHardware);
  });

  useEffect(() => {
    // Initialize Ledger wallet flow if requested and supported
    if (initialState === RenderingState.ConnectHardware) {
      if (IS_LEDGER_SUPPORTED) {
        handleImportHardwareWalletClick();
      } else {
        setRenderingKey(RenderingState.Initial);
      }
      return;
    }

    setRenderingKey(initialState);
  }, [initialState]);

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

  const handleHardwareWalletConnected = useLastCallback(() => {
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
            label={lang('%counts% Secret Words', { counts: MNEMONIC_COUNTS.join('/') })}
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
            onConnected={handleHardwareWalletConnected}
            onCancel={handleBackClick}
            onClose={closeAddAccountModal}
          />
        );
      case RenderingState.SelectAccountsHardware:
        return (
          <LedgerSelectWallets
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
  const isPasswordPresent = selectIsPasswordPresent(global);
  const { byId: versionById } = global.walletVersions ?? {};
  const currentAccountId = selectCurrentAccountId(global);
  const versions = currentAccountId ? versionById?.[currentAccountId] : undefined;
  const withOtherWalletVersions = !!versions?.length;

  const { auth: { forceAddingTonOnlyAccount, initialState } } = global;

  return {
    isOpen: global.isAddAccountModalOpen,
    isLoading: global.accounts?.isLoading,
    error: global.accounts?.error,
    isPasswordPresent,
    withOtherWalletVersions,
    forceAddingTonOnlyAccount,
    initialState,
  };
})(AddAccountModal));
