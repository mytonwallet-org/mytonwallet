import React, { memo, useEffect, useState } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useScrolledState from '../../../hooks/useScrolledState';

import SecretWordsContent from '../../common/backup/SecretWordsContent';
import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';

import settingsStyles from '../Settings.module.scss';
import styles from './Backup.module.scss';

interface OwnProps {
  isActive?: boolean;
  currentAccountId: string;
  enteredPassword?: string;
  isInsideModal?: boolean;
  isBackupSlideActive?: boolean;
  onBackClick: NoneToVoidFunction;
  onSubmit: NoneToVoidFunction;
}

function BackupSecretWords({
  isActive,
  currentAccountId,
  enteredPassword,
  isBackupSlideActive,
  isInsideModal,
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
      {isInsideModal ? (
        <ModalHeader
          title={lang('%1$d Secret Words', wordsCount) as string}
          withNotch={isScrolled}
          className={settingsStyles.modalHeader}
          onBackButtonClick={onBackClick}
        />
      ) : (
        <div className={buildClassName(settingsStyles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText className={settingsStyles.headerBack} onClick={onBackClick}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={settingsStyles.headerTitle}>{lang('%1$d Secret Words', wordsCount) as string}</span>
        </div>
      )}
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
