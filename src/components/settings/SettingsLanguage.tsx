import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { LangCode } from '../../global/types';

import { LANG_LIST } from '../../config';
import buildClassName from '../../util/buildClassName';
import { setLanguage } from '../../util/langProvider';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import Spinner from '../ui/Spinner';
import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

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
  const [pendingLangCode, setPendingLangCode] = useState<LangCode>();
  const pendingLangCodeRef = useRef<LangCode>();

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const handleLanguageChange = useLastCallback(async (newLangCode: LangCode) => {
    // The state update reaches the callback only on the next render pass, so the ref is what
    // rejects the clicks made within a single frame
    if (pendingLangCodeRef.current || newLangCode === langCode) return;

    pendingLangCodeRef.current = newLangCode;
    setPendingLangCode(newLangCode);

    await setLanguage(newLangCode, () => {
      changeLanguage({ langCode: newLangCode });
    });

    pendingLangCodeRef.current = undefined;
    setPendingLangCode(undefined);
  });

  function renderLanguages() {
    return LANG_LIST.map(({ name, nativeName, langCode: lc }) => {
      const isPending = pendingLangCode === lc;

      return (
        <div
          key={lc}
          className={buildClassName(styles.item, styles.item_lang)}
          onClick={() => handleLanguageChange(lc)}
        >
          <div className={styles.languageInfo}>
            <span className={styles.languageMain}>{name}</span>
            <span className={styles.languageNative}>{nativeName}</span>
          </div>

          {(isPending || langCode === lc) && (
            <div className={styles.languageStatus}>
              <Spinner
                className={buildClassName(styles.languageStatusIcon, !isPending && styles.languageStatusHidden)}
              />
              <i
                className={buildClassName(
                  'icon-check',
                  styles.languageStatusIcon,
                  isPending && styles.languageStatusHidden,
                )}
                aria-hidden
              />
            </div>
          )}
        </div>
      );
    });
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
