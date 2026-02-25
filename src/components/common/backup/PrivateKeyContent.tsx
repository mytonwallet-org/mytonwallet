import React, { memo } from '../../../lib/teact/teact';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../../../config';
import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import InteractiveTextField from '../../ui/InteractiveTextField';

import styles from './BackUpContent.module.scss';

interface OwnProps {
  isActive?: boolean;
  privateKey?: string;
  onSubmit: () => void;
  buttonText: string;
}

function SecretWordsContent({
  isActive,
  privateKey,
  onSubmit,
  buttonText,
}: OwnProps) {
  const lang = useLang();

  return (
    <>
      <AnimatedIconWithPreview
        tgsUrl={ANIMATED_STICKERS_PATHS.bill}
        previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
        size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
        play={isActive}
        nonInteractive
        noLoop={false}
        className={styles.modalSticker}
      />
      <p className={buildClassName(styles.info, styles.small)}>
        {renderText(lang('$private_key_description'))}
      </p>
      <p className={styles.warning}>
        {renderText(lang('$mnemonic_warning'))}
      </p>
      <InteractiveTextField
        noExplorer
        text={privateKey}
        copyNotification={lang('Private Key Copied')}
      />

      <div className={styles.buttonWrapper}>
        <Button
          isPrimary
          className={styles.footerButton}
          onClick={onSubmit}
        >
          {buttonText}
        </Button>
      </div>
    </>
  );
}

export default memo(SecretWordsContent);
