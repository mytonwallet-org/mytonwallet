import React, { memo, useEffect, useState } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useScrolledState from '../../../hooks/useScrolledState';

import PrivateKeyContent from '../../common/backup/PrivateKeyContent';
import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';

import settingsStyles from '../Settings.module.scss';
import styles from './Backup.module.scss';

interface OwnProps {
  isActive?: boolean;
  currentAccountId: string;
  enteredPassword?: string;
  isBackupSlideActive?: boolean;
  isInsideModal?: boolean;
  onBackClick: () => void;
  onSubmit: () => void;
}

function BackupPrivateKey({
  isActive,
  currentAccountId,
  enteredPassword,
  isBackupSlideActive,
  isInsideModal,
  onBackClick,
  onSubmit,
}: OwnProps) {
  const lang = useLang();

  const [privateKey, setPrivateKey] = useState<string | undefined>(undefined);

  useEffect(() => {
    async function loadPrivateKey() {
      if (isBackupSlideActive && enteredPassword) {
        // todo: Add a UI for choosing the chain to export the private key from
        const privateKeyResult = await callApi('fetchPrivateKey', currentAccountId, 'ton', enteredPassword);

        setPrivateKey(privateKeyResult);
      } else {
        setPrivateKey(undefined);
      }
    }
    void loadPrivateKey();
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
      {isInsideModal ? (
        <ModalHeader
          title={lang('Private Key')}
          withNotch={isScrolled}
          onBackButtonClick={onBackClick}
          className={settingsStyles.modalHeader}
        />
      ) : (
        <div className={buildClassName(settingsStyles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={onBackClick} className={settingsStyles.headerBack}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={settingsStyles.headerTitle}>{lang('Private Key')}</span>
        </div>
      )}
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
