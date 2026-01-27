import React, { memo } from '../../lib/teact/teact';

import { IS_CAPACITOR } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

import styles from './PasswordSlide.module.scss';

interface OwnProps {
  isActive: boolean;
  error?: string;
  childClassName?: string;
  onSubmit: (password: string) => void;
  onCancel: NoneToVoidFunction;
  onUpdate: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function PasswordSlide({
  isActive,
  error,
  childClassName,
  onSubmit,
  onCancel,
  onUpdate,
  onClose,
}: OwnProps) {
  const lang = useLang();

  return (
    <>
      {!getDoesUsePinPad() && (
        <ModalHeader className={childClassName} title={lang('Enter Password')} onClose={onClose} />
      )}
      <PasswordForm
        isActive={isActive}
        error={error}
        withCloseButton={IS_CAPACITOR}
        containerClassName={buildClassName(
          IS_CAPACITOR ? styles.passwordFormContent : styles.passwordFormContentInModal,
          childClassName,
        )}
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
