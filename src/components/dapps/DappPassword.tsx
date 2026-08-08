import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { getDoesUsePinPad } from '../../util/biometrics';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

interface OwnProps {
  isActive: boolean;
  error?: string;
  extraAuthUsages?: number;
  onAuthorize: (enclaveToken: string) => void;
  onCancel: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function DappPassword({
  isActive,
  error,
  extraAuthUsages,
  onAuthorize,
  onCancel,
  onClose,
}: OwnProps) {
  const { clearDappConnectRequestError } = getActions();

  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang('Enter Password')} onClose={onClose} />}
      <PasswordForm
        isActive={isActive}
        error={error}
        submitLabel={lang('Connect')}
        cancelLabel={lang('Cancel')}
        noAutoConfirm
        extraAuthUsages={extraAuthUsages}
        onAuthorize={onAuthorize}
        onCancel={onCancel}
        onUpdate={clearDappConnectRequestError}
      />
    </>
  );
}

export default memo(DappPassword);
