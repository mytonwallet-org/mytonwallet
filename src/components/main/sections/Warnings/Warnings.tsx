import React, { memo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { IS_EXPLORER, IS_EXTENSION, IS_TELEGRAM_APP } from '../../../../config';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsMnemonicAccount,
} from '../../../../global/selectors';
import { IS_ANDROID, IS_ELECTRON, IS_IOS, IS_LEGACY_APP_HOST } from '../../../../util/windowEnvironment';

import useHeightChange from '../../../../hooks/useHeightChange';

import BackupWarning from './BackupWarning';
import DeprecatedWebsiteWarning from './DeprecatedWebsiteWarning';
import RenewDomainWarning from './RenewDomainWarning';
import ScamWalletWarning from './ScamWalletWarning';
import SecurityWarning from './SecurityWarning';

import styles from './Warnings.module.scss';

interface OwnProps {
  onOpenBackupWallet: NoneToVoidFunction;
  onHeightChange: (prevHeight: number, nextHeight: number) => void;
}

interface StateProps {
  isBackupRequired: boolean;
  isViewMode: boolean;
  isMnemonicAccount: boolean;
}

const IS_UNSAFE_WEB = !IS_ELECTRON && !IS_EXTENSION && !IS_IOS && !IS_ANDROID && !IS_TELEGRAM_APP;

function Warnings({
  isBackupRequired,
  isViewMode,
  isMnemonicAccount,
  onOpenBackupWallet,
  onHeightChange,
}: OwnProps & StateProps) {
  const ref = useRef<HTMLDivElement>();

  useHeightChange(ref, onHeightChange);

  return (
    <div ref={ref} className={styles.warnings}>
      {IS_LEGACY_APP_HOST && (
        <DeprecatedWebsiteWarning isMnemonicAccount={isMnemonicAccount} onOpenBackupWallet={onOpenBackupWallet} />
      )}
      {!isViewMode && (
        <>
          <RenewDomainWarning />
          <ScamWalletWarning />
          <BackupWarning isRequired={isBackupRequired} onOpenBackupWallet={onOpenBackupWallet} />
        </>
      )}
      {/* On the legacy host, the native-app notice competes with the migration notice */}
      {IS_UNSAFE_WEB && !IS_EXPLORER && !IS_LEGACY_APP_HOST && <SecurityWarning />}
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      return {
        isBackupRequired: Boolean(selectCurrentAccountState(global)?.isBackupRequired),
        isViewMode: selectIsCurrentAccountViewMode(global),
        isMnemonicAccount: selectIsMnemonicAccount(global),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Warnings),
);
