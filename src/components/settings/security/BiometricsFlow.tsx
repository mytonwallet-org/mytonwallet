import React, { memo } from '../../../lib/teact/teact';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../../config';
import buildClassName from '../../../util/buildClassName';
import { IS_ELECTRON } from '../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

export const enum BiometricsSlide {
  Registration,
  Verification,
}

interface OwnProps {
  isSlideActive: boolean;
  currentSlide?: BiometricsSlide;
  isInsideModal?: boolean;
  biometricsError?: string;
  onClose: NoneToVoidFunction;
}

function BiometricsFlow({
  isSlideActive,
  currentSlide,
  isInsideModal,
  biometricsError,
  onClose,
}: OwnProps) {
  const lang = useLang();

  function renderHeader(title: string, onBack: NoneToVoidFunction) {
    if (isInsideModal) {
      return (
        <ModalHeader
          title={lang(title)}
          onBackButtonClick={onBack}
          className={styles.modalHeader}
        />
      );
    }

    return (
      <div className={styles.header}>
        <Button isSimple isText onClick={onBack} className={styles.headerBack}>
          <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
        <span className={styles.headerTitle}>{lang(title)}</span>
      </div>
    );
  }

  switch (currentSlide) {
    case BiometricsSlide.Registration:
      return (
        <>
          {renderHeader('Biometric Registration', onClose)}
          <div className={styles.content}>
            <AnimatedIconWithPreview
              tgsUrl={ANIMATED_STICKERS_PATHS.holdTon}
              previewUrl={ANIMATED_STICKERS_PATHS.holdTonPreview}
              play={isSlideActive}
              size={ANIMATED_STICKER_BIG_SIZE_PX}
              nonInteractive
              noLoop={false}
              className={styles.sticker}
            />
            {biometricsError ? (
              <p className={styles.biometricsError}>{lang(biometricsError)}</p>
            ) : (
              <p className={styles.biometricsStep}>{lang('Step 1 of 2. Registration')}</p>
            )}
            <div className={modalStyles.buttons}>
              <Button onClick={onClose} className={modalStyles.customCancelButton}>
                {lang('Cancel')}
              </Button>
            </div>
          </div>
        </>
      );

    case BiometricsSlide.Verification:
      return (
        <>
          {renderHeader('Biometric Registration', onClose)}
          <div className={styles.content}>
            <AnimatedIconWithPreview
              tgsUrl={ANIMATED_STICKERS_PATHS.holdTon}
              previewUrl={ANIMATED_STICKERS_PATHS.holdTonPreview}
              play={isSlideActive}
              size={ANIMATED_STICKER_BIG_SIZE_PX}
              nonInteractive
              noLoop={false}
              className={styles.sticker}
            />
            <p className={styles.biometricsStep}>
              {lang(IS_ELECTRON ? 'Verification' : 'Step 2 of 2. Verification')}
            </p>
            <div className={modalStyles.buttons}>
              <Button onClick={onClose} className={modalStyles.customCancelButton}>
                {lang('Cancel')}
              </Button>
            </div>
          </div>
        </>
      );

    default:
      return undefined;
  }
}

export default memo(BiometricsFlow);
