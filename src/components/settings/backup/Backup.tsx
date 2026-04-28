import React, { memo } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useScrolledState from '../../../hooks/useScrolledState';

import SettingsHeader from '../SettingsHeader';

import styles from '../Settings.module.scss';

import privateKeyImg from '../../../assets/settings/settings_private-key.svg';
import secretWordsImg from '../../../assets/settings/settings_secret-words.svg';

interface OwnProps {
  isActive?: boolean;
  isMultichainAccount: boolean;
  hasMnemonicWallet?: boolean;
  onBackClick: NoneToVoidFunction;
  onOpenSecretWordsSafetyRules: NoneToVoidFunction;
  onOpenPrivateKeySafetyRules: NoneToVoidFunction;
  onOpenSettingsSlide: NoneToVoidFunction;
}

function Backup({
  isActive,
  isMultichainAccount,
  hasMnemonicWallet,
  onBackClick,
  onOpenSecretWordsSafetyRules,
  onOpenPrivateKeySafetyRules,
  onOpenSettingsSlide,
}: OwnProps) {
  const lang = useLang();
  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const { handleScroll: handleContentScroll } = useScrolledState();

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('$back_up_security')} onBackClick={onOpenSettingsSlide} />

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {hasMnemonicWallet && (
          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={buildClassName(styles.item)} onClick={onOpenSecretWordsSafetyRules}>
                <img className={styles.menuIcon} src={secretWordsImg} alt={lang('View Secret Words')} />
                {lang('View Secret Words')}

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
            {isMultichainAccount && (
              <p className={styles.blockDescription}>
                {lang('Can be imported to any multichain wallet supporting %chain%.', { chain: getChainTitle('ton') })}
              </p>
            )}
          </>
        )}

        {(isMultichainAccount || !hasMnemonicWallet) && (
          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={buildClassName(styles.item)} onClick={onOpenPrivateKeySafetyRules}>
                <img
                  className={styles.menuIcon}
                  src={privateKeyImg}
                  alt={lang('View %chain% Private Key').replace('%chain%', getChainTitle('ton'))}
                />
                {lang('View %chain% Private Key', { chain: getChainTitle('ton') })}

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
            <p className={styles.blockDescription}>
              {lang('Can be imported to non-multichain wallets for %chain%.', { chain: getChainTitle('ton') })}
            </p>
          </>
        )}
      </div>
    </div>
  );
}

export default memo(Backup);
