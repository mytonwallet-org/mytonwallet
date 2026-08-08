import React, { memo, useEffect, useState } from '../../../lib/teact/teact';
import { getGlobal } from '../../../global';

import { selectEnclaveToken } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useScrolledState from '../../../hooks/useScrolledState';

import PrivateKeyContent from '../../common/backup/PrivateKeyContent';
import SettingsHeader from '../SettingsHeader';

import settingsStyles from '../Settings.module.scss';
import styles from './Backup.module.scss';

interface OwnProps {
  isActive?: boolean;
  currentAccountId: string;
  isInsideModal?: boolean;
  isBackupSlideActive?: boolean;
  onBackClick: NoneToVoidFunction;
  onSubmit: NoneToVoidFunction;
}

function BackupPrivateKey({
  isActive,
  currentAccountId,
  isBackupSlideActive,
  onBackClick,
  onSubmit,
}: OwnProps) {
  const lang = useLang();

  const [privateKey, setPrivateKey] = useState<string | undefined>(undefined);

  useEffect(() => {
    async function loadPrivateKey() {
      if (isBackupSlideActive) {
        // todo: Add a UI for choosing the chain to export the private key from
        const privateKeyResult = await callApi(
          'fetchPrivateKey', currentAccountId, 'ton', selectEnclaveToken(getGlobal())!,
        );

        setPrivateKey(privateKeyResult);
      } else {
        setPrivateKey(undefined);
      }
    }
    void loadPrivateKey();
  }, [currentAccountId, isBackupSlideActive]);

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
      <SettingsHeader title={lang('Private Key')} isScrolled={isScrolled} onBackClick={onBackClick} />
      <div
        className={buildClassName(settingsStyles.content, styles.content)}
        onScroll={handleContentScroll}
      >
        <PrivateKeyContent
          isActive={isActive}
          privateKey={privateKey}
          buttonText={lang('Close')}
          onSubmit={onSubmit}
        />
      </div>
    </div>
  );
}

export default memo(BackupPrivateKey);
