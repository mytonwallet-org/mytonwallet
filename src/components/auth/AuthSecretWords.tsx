import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { IS_PRODUCTION } from '../../config';
import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import SecretWordsContent from '../common/backup/SecretWordsContent';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive: boolean;
  mnemonic?: string[];
}

const AuthSecretWords = ({ isActive, mnemonic }: OwnProps) => {
  const { openAuthBackupWalletModal, openCheckWordsPage } = getActions();

  const lang = useLang();

  const wordsCount = mnemonic?.length || 0;
  const canSkipMnemonicCheck = !IS_PRODUCTION;

  useHistoryBack({ isActive, onBack: openAuthBackupWalletModal });
  const { isScrolled, handleScroll } = useScrolledState();

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={lang('%1$d Secret Words', wordsCount) as string}
        withBorder={isScrolled}
        onBackClick={openAuthBackupWalletModal}
      />

      <div
        className={buildClassName(
          styles.container,
          styles.containerWithHeader,
          styles.container_scrollable,
          'custom-scroll')}
        onScroll={handleScroll}
      >
        <SecretWordsContent
          isActive={isActive}
          mnemonic={mnemonic}
          stickerClassName={styles.topSticker}
          customButtonWrapperClassName={buildClassName(styles.buttons, styles.buttonsPush)}
          canSkipMnemonicCheck={canSkipMnemonicCheck}
          buttonText={lang('Let\'s Check')}
          onSubmit={openCheckWordsPage}
        />
      </div>
    </div>
  );
};

export default memo(AuthSecretWords);
