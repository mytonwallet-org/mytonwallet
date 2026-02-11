import React, { memo } from '../../../../lib/teact/teact';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { IS_LEDGER_SUPPORTED } from '../../../../util/windowEnvironment';

import useLang from '../../../../hooks/useLang';

import ListItem from '../../../ui/ListItem';
import ModalHeader from '../../../ui/ModalHeader';
import WalletVersionSection from './WalletVersionSection';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './AccountSelectorModal.module.scss';

type OwnProps = {
  isNewAccountImporting?: boolean;
  isLoading?: boolean;
  isTestnet?: boolean;
  withOtherWalletVersions?: boolean;
  shouldHideBackButton?: boolean;
  onBack: NoneToVoidFunction;
  onNewAccountClick: NoneToVoidFunction;
  onImportAccountClick: NoneToVoidFunction;
  onImportHardwareWalletClick: NoneToVoidFunction;
  onViewModeWalletClick: NoneToVoidFunction;
  onOpenSettingWalletVersion: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
};

function AddAccountSelector({
  isNewAccountImporting,
  isLoading,
  isTestnet,
  withOtherWalletVersions,
  shouldHideBackButton,
  onBack,
  onNewAccountClick,
  onImportAccountClick,
  onImportHardwareWalletClick,
  onViewModeWalletClick,
  onOpenSettingWalletVersion,
  onClose,
}: OwnProps) {
  const lang = useLang();

  return (
    <div className={buildClassName(modalStyles.transitionContentWrapper, styles.compensateSafeArea)}>
      <ModalHeader
        title={lang('Add Wallet')}
        onBackButtonClick={shouldHideBackButton ? undefined : onBack}
        onClose={onClose}
      />

      <div className={buildClassName(styles.actionsSection, styles.actionsSectionShift)}>
        <ListItem
          icon="wallet-add"
          label={lang('Create New Wallet')}
          isLoading={!isNewAccountImporting && isLoading}
          onClick={onNewAccountClick}
        />
      </div>

      <span className={styles.importText}>{lang('or import from')}</span>

      <div className={styles.actionsSection}>
        <ListItem
          icon="key"
          label={lang(IS_CORE_WALLET ? '24 Secret Words' : '12/24 Secret Words')}
          onClick={onImportAccountClick}
          isLoading={isNewAccountImporting && isLoading}
        />
        {IS_LEDGER_SUPPORTED && !isTestnet && (
          <ListItem
            icon="ledger-alt"
            label={lang('Ledger')}
            onClick={onImportHardwareWalletClick}
          />
        )}
      </div>

      {!IS_CORE_WALLET && (
        <div className={styles.actionsSection}>
          <ListItem
            icon="wallet-view"
            label={lang('View Any Address')}
            onClick={onViewModeWalletClick}
          />
        </div>
      )}

      <WalletVersionSection
        isVisible={withOtherWalletVersions}
        onClick={onOpenSettingWalletVersion}
      />
    </div>
  );
}

export default memo(AddAccountSelector);
