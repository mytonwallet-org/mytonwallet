import type { ElementRef } from '../../../lib/teact/teact';
import React, { memo, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../../../config';
import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import { useTransitionActiveKey } from '../../../hooks/useTransitionActiveKey';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Transition from '../../ui/Transition';
import CheckWordsForm from './CheckWordsForm';

import styles from './BackUpContent.module.scss';

interface OwnProps {
  isActive?: boolean;
  headerRef?: ElementRef<HTMLDivElement>;
  stickerClassName?: string;
  checkIndexes?: number[];
  mnemonic?: string[];
}

function CheckWordsContent({
  isActive,
  headerRef,
  stickerClassName,
  checkIndexes,
  mnemonic,
}: OwnProps) {
  const { closeCheckWordsPage } = getActions();

  const onSubmit = useLastCallback(() => {
    closeCheckWordsPage({ isBackupCreated: true });
  });

  const lang = useLang();
  const activeKey = useTransitionActiveKey([mnemonic, checkIndexes]);

  const [hasValidationError, setHasValidationError] = useState(false);

  const handleValidationComplete = useLastCallback((isCorrect: boolean) => {
    setHasValidationError(!isCorrect);
  });

  const handleUserInteraction = useLastCallback(() => {
    setHasValidationError(false);
  });

  return (
    <>
      <AnimatedIconWithPreview
        tgsUrl={ANIMATED_STICKERS_PATHS.bill}
        previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
        size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
        play={isActive}
        nonInteractive
        noLoop={false}
        className={buildClassName(styles.modalSticker, stickerClassName)}
      />
      <div ref={headerRef} className={styles.title}>{lang('Let\'s Check')}</div>

      <p className={buildClassName(styles.info, styles.small)}>
        {renderText(lang('$check_words_description'))}
      </p>

      <Transition activeKey={activeKey} name="fade" slideClassName={styles.checkWordsSlide}>
        <CheckWordsForm
          descriptionClassName={buildClassName(styles.info, styles.small)}
          formClassName={styles.checkMnemonicForm}
          isActive={isActive}
          mnemonic={mnemonic}
          checkIndexes={checkIndexes}
          isErrorVisible={hasValidationError}
          onSubmit={onSubmit}
          onValidationComplete={handleValidationComplete}
          onUserInteraction={handleUserInteraction}
        />
      </Transition>
    </>
  );
}

export default memo(CheckWordsContent);
