import { AirAppLauncher } from '@mytonwallet/air-app-launcher';
import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { LangCode } from '../../global/types';

import { IS_CAPACITOR, LANG_LIST } from '../../config';
import buildClassName from '../../util/buildClassName';
import { setLanguage } from '../../util/langProvider';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

import checkmarkImg from '../../assets/settings/settings_checkmark.svg';

interface OwnProps {
  isActive?: boolean;
  langCode: LangCode;
  onBackClick: NoneToVoidFunction;
}

function SettingsLanguage({
  isActive,
  langCode,
  onBackClick,
}: OwnProps) {
  const {
    changeLanguage,
  } = getActions();
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const handleLanguageChange = useLastCallback((newLangCode: LangCode) => {
    void setLanguage(newLangCode, () => {
      changeLanguage({ langCode: newLangCode });
      if (IS_CAPACITOR) void AirAppLauncher.setLanguage({ langCode: newLangCode });
    });
  });

  function renderLanguages() {
    return LANG_LIST.map(({ name, nativeName, langCode: lc }) => (
      <div
        key={lc}
        className={buildClassName(styles.item, styles.item_lang)}
        onClick={() => handleLanguageChange(lc)}
      >
        <div className={styles.languageInfo}>
          <span className={styles.languageMain}>{name}</span>
          <span className={styles.languageNative}>{nativeName}</span>
        </div>

        {langCode === lc && <img src={checkmarkImg} alt={name} />}
      </div>
    ));
  }

  const { isScrolled, handleScroll: handleContentScroll } = useScrolledState();

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Language')} isScrolled={isScrolled} onBackClick={onBackClick} />

      <div className={buildClassName(styles.content, 'custom-scroll')} onScroll={handleContentScroll}>
        <div className={styles.block}>
          {renderLanguages()}
        </div>
      </div>
    </div>
  );
}

export default memo(SettingsLanguage);
