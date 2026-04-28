import React, { memo, useEffect, useState } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useScrolledState from '../../../hooks/useScrolledState';

import SecretWordsContent from '../../common/backup/SecretWordsContent';
import SettingsHeader from '../SettingsHeader';

import settingsStyles from '../Settings.module.scss';
import styles from './Backup.module.scss';

interface OwnProps {
  isActive?: boolean;
  currentAccountId: string;
  enteredPassword?: string;
  isBackupSlideActive?: boolean;
  onBackClick: NoneToVoidFunction;
  onSubmit: NoneToVoidFunction;
}

function BackupSecretWords({
  isActive,
  currentAccountId,
  enteredPassword,
  isBackupSlideActive,
  onBackClick,
  onSubmit,
}: OwnProps) {
  const lang = useLang();

  const [mnemonic, setMnemonic] = useState<string[] | undefined>(undefined);
  const wordsCount = mnemonic?.length || 0;

  useEffect(() => {
    async function loadMnemonic() {
      if (isBackupSlideActive && enteredPassword) {
        const mnemonicResult = await callApi('fetchMnemonic', currentAccountId, enteredPassword);

        setMnemonic(mnemonicResult);
      } else {
        setMnemonic(undefined);
      }
    }
    void loadMnemonic();
  }, [currentAccountId, enteredPassword, isBackupSlideActive]);

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  return (
    <div className={settingsStyles.slide}>
      <SettingsHeader
        title={lang('%1$d Secret Words', wordsCount) as string}
        isScrolled={isScrolled}
        onBackClick={onBackClick}
      />
      <div
        className={buildClassName(settingsStyles.content, styles.content)}
        onScroll={handleContentScroll}
      >
        <SecretWordsContent
          isActive={isActive}
          mnemonic={mnemonic}
          onSubmit={onSubmit}
          buttonText={lang('Close')}
        />
      </div>
    </div>
  );
}

export default memo(BackupSecretWords);
