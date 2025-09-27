import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import {
  ANIMATED_STICKER_MIDDLE_SIZE_PX,
  APP_NAME,
  MYTONWALLET_PRIVACY_POLICY_URL,
  MYTONWALLET_TERMS_OF_USE_URL,
} from '../../config';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { handleUrlClick } from '../../util/openUrl';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Header from './Header';

import settingsStyles from '../settings/Settings.module.scss';
import styles from './Auth.module.scss';

import lockImg from '../../assets/settings/settings_lock.svg';
import listImg from '../../assets/settings/settings_secret-words.svg';

interface OwnProps {
  isActive?: boolean;
}

function AuthDisclaimer({ isActive }: OwnProps) {
  const { closeDisclaimer } = getActions();

  const lang = useLang();
  const triggerElementRef = useRef<HTMLDivElement>();

  useHistoryBack({
    isActive,
    onBack: closeDisclaimer,
  });

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={lang('Use Responsibly')}
        topTargetRef={triggerElementRef}
        onBackClick={closeDisclaimer}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.snitch}
          previewUrl={ANIMATED_STICKERS_PATHS.snitchPreview}
          noLoop={false}
          nonInteractive
          size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
          className={styles.topSticker}
        />
        <div ref={triggerElementRef} className={styles.title}>{lang('Use Responsibly')}</div>
        <div className={styles.infoBlock}>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description1', { app_name: APP_NAME }))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description2'))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description3', { app_name: APP_NAME }))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description4'))}</p>
        </div>
        <div className={buildClassName(settingsStyles.block, styles.lawBlock)}>
          <a
            href={MYTONWALLET_TERMS_OF_USE_URL}
            target="_blank"
            rel="noreferrer"
            className={settingsStyles.item}
            onClick={handleUrlClick}
          >
            <img className={settingsStyles.menuIcon} src={listImg} alt={lang('Terms of Use')} />
            {lang('Terms of Use')}
            <i className={buildClassName(settingsStyles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </a>
          <a
            href={MYTONWALLET_PRIVACY_POLICY_URL}
            target="_blank"
            rel="noreferrer"
            className={settingsStyles.item}
            onClick={handleUrlClick}
          >
            <img className={settingsStyles.menuIcon} src={lockImg} alt={lang('Privacy Policy')} />
            {lang('Privacy Policy')}
            <i className={buildClassName(settingsStyles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </a>
        </div>
      </div>
    </div>
  );
}

export default memo(AuthDisclaimer);
