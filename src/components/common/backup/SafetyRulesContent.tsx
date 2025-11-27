import type { ElementRef, TeactNode } from '../../../lib/teact/teact';
import React, { memo } from '../../../lib/teact/teact';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../../../config';
import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import Checkbox from '../../ui/Checkbox';

import styles from './BackUpContent.module.scss';

interface OwnProps {
  customStickerClassName?: string;
  customButtonWrapperClassName?: string;
  isFullSizeButton?: boolean;
  isActive?: boolean;
  withHeader?: boolean;
  headerRef?: ElementRef<HTMLDivElement>;
  isFirstCheckboxSelected: boolean;
  isSecondCheckboxSelected: boolean;
  isThirdCheckboxSelected: boolean;
  onFirstCheckboxClick: (isChecked: boolean) => void;
  onSecondCheckboxClick: (isChecked: boolean) => void;
  onThirdCheckboxClick: (isChecked: boolean) => void;
  textFirst: TeactNode;
  textSecond: TeactNode;
  textThird: TeactNode;
  onSubmit: () => void;
}

function SafetyRulesContent({
  customStickerClassName,
  customButtonWrapperClassName,
  isFullSizeButton,
  isActive,
  withHeader,
  headerRef,
  isFirstCheckboxSelected,
  isSecondCheckboxSelected,
  isThirdCheckboxSelected,
  textFirst,
  textSecond,
  textThird,
  onFirstCheckboxClick,
  onSecondCheckboxClick,
  onThirdCheckboxClick,
  onSubmit,
}: OwnProps) {
  const lang = useLang();

  const canSubmit = isFirstCheckboxSelected && isSecondCheckboxSelected && isThirdCheckboxSelected;

  const handleFirstCheckboxChange = useLastCallback((isChecked: boolean) => {
    if (isChecked) {
      onFirstCheckboxClick(true);
    } else {
      onFirstCheckboxClick(false);
      onSecondCheckboxClick(false);
      onThirdCheckboxClick(false);
    }
  });

  const handleSecondCheckboxChange = useLastCallback((isChecked: boolean) => {
    if (isChecked) {
      onSecondCheckboxClick(true);
    } else {
      onSecondCheckboxClick(false);
      onThirdCheckboxClick(false);
    }
  });

  const handleSubmit = useLastCallback(() => {
    if (!canSubmit) {
      return;
    }

    onSubmit();
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
        className={customStickerClassName || styles.modalSticker}
      />
      {withHeader && (
        <div ref={headerRef} className={styles.title}>
          {lang('Create Backup')}
        </div>
      )}

      <Checkbox
        checked={isFirstCheckboxSelected}
        className={buildClassName(styles.checkboxBlock, styles.accessible)}
        contentClassName={styles.checkbox}
        onChange={handleFirstCheckboxChange}
      >
        {renderText(textFirst)}
      </Checkbox>

      <Checkbox
        isDisabled={!isFirstCheckboxSelected}
        checked={isSecondCheckboxSelected}
        className={buildClassName(styles.checkboxBlock, isFirstCheckboxSelected && styles.accessible)}
        contentClassName={styles.checkbox}
        onChange={handleSecondCheckboxChange}
      >
        {renderText(textSecond)}
      </Checkbox>

      <Checkbox
        isDisabled={!isSecondCheckboxSelected}
        checked={isThirdCheckboxSelected}
        className={buildClassName(styles.checkboxBlock, isSecondCheckboxSelected && styles.accessible)}
        contentClassName={styles.checkbox}
        onChange={onThirdCheckboxClick}
      >
        {renderText(textThird)}
      </Checkbox>

      <div className={customButtonWrapperClassName || styles.buttonWrapper}>
        <Button
          isPrimary
          isDisabled={!canSubmit}
          className={isFullSizeButton ? styles.footerButton : undefined}
          onClick={handleSubmit}
        >
          {lang('Go to Words')}
        </Button>
      </div>
    </>
  );
}

export default memo(SafetyRulesContent);
