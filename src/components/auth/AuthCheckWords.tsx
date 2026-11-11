import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useInactivityTimeout from '../../hooks/useInactivityTimeout';
import useLang from '../../hooks/useLang';

import CheckWordsContent from '../common/backup/CheckWordsContent';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive: boolean;
  mnemonic?: string[];
  checkIndexes?: number[];
}

const AuthCheckWords = ({ isActive, mnemonic, checkIndexes }: OwnProps) => {
  const { openMnemonicPage, openAuthBackupWalletModal } = getActions();

  const lang = useLang();
  const headerRef = useRef<HTMLDivElement>();
  const title = lang('Let\'s Check!');

  useHistoryBack({ isActive, onBack: openMnemonicPage });
  // The word options are taken from the mnemonic. Going back would show the secret words again, so the flow
  // returns to the safety rules instead.
  useInactivityTimeout(openAuthBackupWalletModal, isActive);

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={title}
        topTargetRef={headerRef}
        onBackClick={openMnemonicPage}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <CheckWordsContent
          isActive={isActive}
          headerRef={headerRef}
          stickerClassName={styles.topSticker}
          mnemonic={mnemonic}
          checkIndexes={checkIndexes}
        />
      </div>
    </div>
  );
};

export default memo(AuthCheckWords);
