import React, { memo } from '../../lib/teact/teact';

import { IS_CAPACITOR } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';

import useLang from '../../hooks/useLang';

import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

import styles from './PasswordSlide.module.scss';

interface OwnProps {
  isActive: boolean;
  error?: string;
  onSubmit: (password: string) => void;
  onCancel: NoneToVoidFunction;
  onUpdate: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function PasswordSlide({
  isActive,
  error,
  onSubmit,
  onCancel,
  onUpdate,
  onClose,
}: OwnProps) {
  const lang = useLang();

  return (
    <>
      {!getDoesUsePinPad() && (
        <ModalHeader title={lang('Enter Password')} onClose={onClose} />
      )}
      <PasswordForm
        isActive={isActive}
        error={error}
        withCloseButton={IS_CAPACITOR}
        containerClassName={IS_CAPACITOR ? styles.passwordFormContent : styles.passwordFormContentInModal}
        submitLabel={lang('Confirm')}
        noAutoConfirm
        onSubmit={onSubmit}
        onCancel={onCancel}
        onUpdate={onUpdate}
      />
    </>
  );
}

export default memo(PasswordSlide);
