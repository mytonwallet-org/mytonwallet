import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';

import useLang from '../../../hooks/useLang';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
}

function TurnOffWaning({ isOpen, onClose }: OwnProps) {
  const { openBiometricsTurnOff } = getActions();

  const lang = useLang();

  const description = getDoesUsePinPad()
    ? 'If you turn off biometric protection, you will need to create a passcode.'
    : 'If you turn off biometric protection, you will need to create a password.';

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={lang('Turn Off Biometrics')}
      onClose={onClose}
    >
      <p className={modalStyles.text}>
        {lang(description)}
      </p>

      <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsNoExtraSpace)}>
        <Button className={modalStyles.button} onClick={onClose}>
          {lang('Cancel')}
        </Button>
        <Button isPrimary className={modalStyles.button} onClick={openBiometricsTurnOff}>
          {lang('Continue')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(TurnOffWaning);
