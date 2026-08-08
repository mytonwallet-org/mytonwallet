import React, { memo } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';

import useLang from '../../../hooks/useLang';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';

interface OwnProps {
  isOpen: boolean;
  title: string;
  description: string;
  onClose: NoneToVoidFunction;
  onConfirm: NoneToVoidFunction;
}

function BiometricsWarningModal({
  isOpen, title, description, onClose, onConfirm,
}: OwnProps) {
  const lang = useLang();

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={title}
      onClose={onClose}
    >
      <p className={modalStyles.text}>{description}</p>
      <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsNoExtraSpace)}>
        <Button className={modalStyles.button} onClick={onClose}>
          {lang('Cancel')}
        </Button>
        <Button isPrimary className={modalStyles.button} onClick={onConfirm}>
          {lang('Continue')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(BiometricsWarningModal);
