import React, { memo, useState } from '../../../lib/teact/teact';

import useLastCallback from '../../../hooks/useLastCallback';

import Backup from '../backup/Backup';
import BackupPrivateKey from '../backup/BackupPrivateKey';
import BackupSafetyRules from '../backup/BackupSafetyRules';
import BackupSecretWords from '../backup/BackupSecretWords';

export const enum BackupSlide {
  Menu,
  SafetyRules,
  SecretWords,
  PrivateKey,
}

interface OwnProps {
  isActive: boolean;
  isSlideActive: boolean;
  currentSlide: BackupSlide;
  isInsideModal?: boolean;
  isMultichainAccount: boolean;
  currentAccountId: string;
  initialBackupType: 'key' | 'words';
  initialHasMnemonicWallet: boolean;
  onSlideChange: (slide: BackupSlide) => void;
  onClose: NoneToVoidFunction;
  onSettingsClose: NoneToVoidFunction;
}

function BackupFlow({
  isActive,
  isSlideActive,
  currentSlide,
  isInsideModal,
  isMultichainAccount,
  currentAccountId,
  initialBackupType,
  initialHasMnemonicWallet,
  onSlideChange,
  onClose,
  onSettingsClose,
}: OwnProps) {
  const [backupType, setBackupType] = useState<'key' | 'words'>(initialBackupType);
  const [hasMnemonicWallet] = useState(initialHasMnemonicWallet);

  const handleOpenSecretWordsSafetyRules = useLastCallback(() => {
    setBackupType('words');
    onSlideChange(BackupSlide.SafetyRules);
  });

  const handleOpenPrivateKeySafetyRules = useLastCallback(() => {
    setBackupType('key');
    onSlideChange(BackupSlide.SafetyRules);
  });

  const handleOpenSecretWords = useLastCallback(() => {
    onSlideChange(BackupSlide.SecretWords);
  });

  const handleOpenPrivateKey = useLastCallback(() => {
    onSlideChange(BackupSlide.PrivateKey);
  });

  const isBackupDataSlideActive = currentSlide === BackupSlide.SecretWords
    || currentSlide === BackupSlide.PrivateKey
    || currentSlide === BackupSlide.SafetyRules;

  switch (currentSlide) {
    case BackupSlide.Menu:
      return (
        <Backup
          isActive={isActive && isSlideActive}
          isMultichainAccount={isMultichainAccount}
          hasMnemonicWallet={hasMnemonicWallet}
          isInsideModal={isInsideModal}
          onBackClick={onClose}
          onOpenPrivateKeySafetyRules={handleOpenPrivateKeySafetyRules}
          onOpenSecretWordsSafetyRules={handleOpenSecretWordsSafetyRules}
          onOpenSettingsSlide={onClose}
        />
      );

    case BackupSlide.SafetyRules:
      return (
        <BackupSafetyRules
          isActive={isActive && isSlideActive}
          isInsideModal={isInsideModal}
          backupType={backupType}
          onBackClick={onClose}
          onSubmit={backupType === 'key' ? handleOpenPrivateKey : handleOpenSecretWords}
        />
      );

    case BackupSlide.SecretWords:
      return (
        <BackupSecretWords
          isActive={isActive && isSlideActive}
          isBackupSlideActive={isBackupDataSlideActive}
          isInsideModal={isInsideModal}
          currentAccountId={currentAccountId}
          onBackClick={onClose}
          onSubmit={onSettingsClose}
        />
      );

    case BackupSlide.PrivateKey:
      return (
        <BackupPrivateKey
          isActive={isActive && isSlideActive}
          isBackupSlideActive={isBackupDataSlideActive}
          isInsideModal={isInsideModal}
          currentAccountId={currentAccountId}
          onBackClick={onClose}
          onSubmit={onSettingsClose}
        />
      );

    default:
      return undefined;
  }
}

export default memo(BackupFlow);
