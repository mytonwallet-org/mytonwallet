import React, { memo } from '../../../../lib/teact/teact';

import { IS_CAPACITOR } from '../../../../config';
import { getDoesUsePinPad } from '../../../../util/biometrics';
import buildClassName from '../../../../util/buildClassName';

import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';

import ModalHeader from '../../../ui/ModalHeader';
import PasswordForm from '../../../ui/PasswordForm';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './AccountSelectorModal.module.scss';

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
    <div className={buildClassName(
      modalStyles.transitionContentWrapper,
      styles.compensateSafeArea,
      canUsePinPad && styles.compensateSafeAreaPinPad,
    )}
    >
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
        withCloseButton={IS_CAPACITOR}
        submitLabel={lang('Confirm')}
        noAutoConfirm
        isFullWidthButton
        onCancel={IS_CAPACITOR ? onClose : undefined}
        onSubmit={onSubmit}
        onUpdate={onClearError}
      />
    </div>
  );
}

export default memo(AddAccountPasswordModal);
