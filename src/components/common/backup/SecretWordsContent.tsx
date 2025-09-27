import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../../../config';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import SecretWordsList from './SecretWordsList';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './BackUpContent.module.scss';

interface OwnProps {
  isActive?: boolean;
  mnemonic?: string[];
  canSkipMnemonicCheck?: boolean;
  stickerClassName?: string;
  customButtonWrapperClassName?: string;
  buttonText: string;
  onSubmit: NoneToVoidFunction;
}

function SecretWordsContent({
  isActive,
  mnemonic,
  canSkipMnemonicCheck,
  stickerClassName,
  customButtonWrapperClassName,
  buttonText,
  onSubmit,
}: OwnProps) {
  const { skipCheckMnemonic } = getActions();

  const lang = useLang();
  const [isWarningOpen, showWarning, hideWarning] = useFlag();

  const handleSkipCheckMnemonic = useLastCallback(() => {
    hideWarning();

    skipCheckMnemonic();
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

      <SecretWordsList mnemonic={mnemonic} />

      <div className={customButtonWrapperClassName || styles.buttonWrapper}>
        <Button
          isPrimary
          onClick={onSubmit}
          className={styles.footerButton}
        >
          {buttonText}
        </Button>
        {canSkipMnemonicCheck && (
          <Button
            isText
            className={styles.footerButton}
            onClick={showWarning}
          >
            {lang('Open wallet without checking')}
          </Button>
        )}
      </div>

      <Modal
        isOpen={isWarningOpen}
        isCompact
        title={lang('Security Warning')}
        onClose={hideWarning}
      >
        <p className={styles.text}>{lang('Make sure you have your recovery phrase securely saved.')}</p>
        <p className={buildClassName(styles.text, styles.warningText)}>
          {lang('Without it, you won\'t be able to access your wallet.')}
        </p>

        <div className={buildClassName(modalStyles.footerButtons, modalStyles.footerButtonsVertical)}>
          <Button isPrimary onClick={hideWarning} className={modalStyles.buttonFullWidth}>
            {lang('Go back to Words')}
          </Button>
          <Button isDestructive onClick={handleSkipCheckMnemonic} className={modalStyles.buttonFullWidth}>
            {lang('I’m sure. Continue')}
          </Button>
        </div>
      </Modal>
    </>
  );
}

export default memo(SecretWordsContent);
