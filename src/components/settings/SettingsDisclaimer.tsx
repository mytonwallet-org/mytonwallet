import React, { memo } from '../../lib/teact/teact';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX, APP_NAME } from '../../config';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive: boolean;
  onBackClick: NoneToVoidFunction;
}

function SettingsDisclaimer({ isActive, onBackClick }: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const { isScrolled, handleScroll } = useScrolledState();

  return (
    <div className={styles.slide}>
      <SettingsHeader isScrolled={isScrolled} onBackClick={onBackClick} />

      <div
        className={buildClassName(styles.content, styles.content_noScroll)}
      >
        <div className={styles.stickerAndTitle}>
          <AnimatedIconWithPreview
            play={isActive}
            tgsUrl={ANIMATED_STICKERS_PATHS.snitch}
            previewUrl={ANIMATED_STICKERS_PATHS.snitchPreview}
            noLoop={false}
            nonInteractive
            size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
          />
          <div className={styles.sideTitle}>{lang('Use Responsibly')}</div>
        </div>
        <div className={buildClassName(styles.blockAbout, 'custom-scroll')} onScroll={handleScroll}>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description1', { app_name: APP_NAME }))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description2'))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description3', { app_name: APP_NAME }))}</p>
          <p className={styles.text}>{renderText(lang('$auth_responsibly_description4'))}</p>
        </div>
      </div>
    </div>
  );
}

export default memo(SettingsDisclaimer);
