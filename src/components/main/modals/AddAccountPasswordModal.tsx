import React, { memo } from '../../../lib/teact/teact';

import { IS_CAPACITOR } from '../../../config';
import { getDoesUsePinPad } from '../../../util/biometrics';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';

import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  error?: string;
  onClearError: NoneToVoidFunction;
  onSubmit: (password: string) => void;
  onBack: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function AddAccountPasswordModal({
  isActive,
  isLoading,
  error,
  onClearError,
  onSubmit,
  onBack,
  onClose,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack,
  });

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang('Enter Password')} onClose={onClose} />}
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        error={error}
        operationType="passcode"
        withCloseButton={IS_CAPACITOR}
        submitLabel={lang('Confirm')}
        cancelLabel={lang('Back')}
        noAutoConfirm
        onSubmit={onSubmit}
        onCancel={onBack}
        onUpdate={onClearError}
      />
    </>
  );
}

export default memo(AddAccountPasswordModal);
