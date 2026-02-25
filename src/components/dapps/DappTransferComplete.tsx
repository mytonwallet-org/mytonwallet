import React, { memo, useEffect } from '../../lib/teact/teact';

import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';

import styles from '../common/TransferResult.module.scss';
import modalStyles from '../ui/Modal.module.scss';

interface OwnProps {
  isActive: boolean;
  onClose: NoneToVoidFunction;
  type?: 'transfer' | 'signData';
}

function DappTransferComplete({
  isActive,
  onClose,
  type = 'transfer',
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  useEffect(() => {
    return isActive
      ? captureKeyboardListeners({ onEnter: onClose })
      : undefined;
  }, [isActive, onClose]);

  const title = type === 'signData' ? lang('Data Signed!') : lang('Transfer Sent!');

  return (
    <>
      <ModalHeader title={title} onClose={onClose} />

      <div className={modalStyles.transitionContent}>
        <AnimatedIconWithPreview
          play={isActive}
          noLoop={false}
          nonInteractive
          className={styles.sticker}
          tgsUrl={ANIMATED_STICKERS_PATHS.thumbUp}
          previewUrl={ANIMATED_STICKERS_PATHS.thumbUpPreview}
        />

        <div className={modalStyles.buttons}>
          <Button onClick={onClose} isPrimary>{lang('Close')}</Button>
        </div>
      </div>
    </>
  );
}

export default memo(DappTransferComplete);
