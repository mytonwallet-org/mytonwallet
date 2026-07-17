import React, { memo } from '../../../../lib/teact/teact';

import { getDoesUsePinPad } from '../../../../util/biometrics';

import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';

import ModalHeader from '../../../ui/ModalHeader';
import PasswordForm from '../../../ui/PasswordForm';

import modalStyles from '../../../ui/Modal.module.scss';

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
  const canUsePinPad = getDoesUsePinPad();

  useHistoryBack({
    isActive,
    onBack,
  });

  return (
    <div className={modalStyles.transitionContentWrapper}>
      {!canUsePinPad && (
        <ModalHeader
          title={lang('Enter Password')}
          onBackButtonClick={onBack}
          onClose={onClose}
        />
      )}
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        error={error}
        operationType="passcode"
        submitLabel={lang('Confirm')}
        noAutoConfirm
        isFullWidthButton
        onSubmit={onSubmit}
        onUpdate={onClearError}
      />
    </div>
  );
}

export default memo(AddAccountPasswordModal);
