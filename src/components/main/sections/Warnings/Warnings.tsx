import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { IS_CORE_WALLET, IS_EXPLORER, IS_EXTENSION, IS_TELEGRAM_APP } from '../../../../config';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsMnemonicAccount,
} from '../../../../global/selectors';
import { IS_ANDROID, IS_ELECTRON, IS_IOS, IS_LEGACY_APP_HOST } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';

import BackupWarning from './BackupWarning';
import LegacyDomainWarning from './LegacyDomainWarning';
import RenewDomainWarning from './RenewDomainWarning';
import ScamWalletWarning from './ScamWalletWarning';
import SecurityWarning from './SecurityWarning';

import styles from './Warnings.module.scss';

type OwnProps = {
  onOpenBackupWallet: () => void;
};

type StateProps = {
  isTestnet?: boolean;
  isBackupRequired: boolean;
  isViewMode: boolean;
  isMnemonicAccount: boolean;
};

const IS_UNSAFE_WEB = !IS_CORE_WALLET && !IS_ELECTRON && !IS_EXTENSION && !IS_IOS && !IS_ANDROID && !IS_TELEGRAM_APP;

function Warnings({
  isBackupRequired,
  isTestnet,
  isViewMode,
  isMnemonicAccount,
  onOpenBackupWallet,
}: OwnProps & StateProps) {
  const { isPortrait } = useDeviceScreen();
  const lang = useLang();

  return (
    <>
      {isTestnet && (
        <div className={isPortrait ? styles.portraitContainer : styles.container}>
          <div className={styles.testnetWarning}>{lang('Testnet Version')}</div>
        </div>
      )}

      {IS_LEGACY_APP_HOST && (
        <LegacyDomainWarning isMnemonicAccount={isMnemonicAccount} onOpenBackupWallet={onOpenBackupWallet} />
      )}

      {!isViewMode && (
        <>
          <BackupWarning isRequired={isBackupRequired} onOpenBackupWallet={onOpenBackupWallet} />
          <RenewDomainWarning />
          <ScamWalletWarning />
        </>
      )}
      {/* On the legacy host, "install the native app" only competes with the migration notice above */}
      {IS_UNSAFE_WEB && !IS_EXPLORER && !IS_LEGACY_APP_HOST && <SecurityWarning />}
    </>
  );
}

export default memo(
  withGlobal(
    (global): StateProps => {
      return {
        isBackupRequired: Boolean(selectCurrentAccountState(global)?.isBackupRequired),
        isTestnet: global.settings.isTestnet,
        isViewMode: selectIsCurrentAccountViewMode(global),
        isMnemonicAccount: selectIsMnemonicAccount(global),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Warnings),
);
