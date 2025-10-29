import React, { memo, type TeactNode } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { IS_CAPACITOR } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  error?: string;
  children?: TeactNode;
  onSubmit: (password: string) => void;
  onBack: NoneToVoidFunction;
}

function SwapPassword({
  isActive,
  isLoading,
  error,
  children,
  onSubmit,
  onBack,
}: OwnProps) {
  const { cancelSwap, clearSwapError } = getActions();

  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack,
  });

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang('Confirm Swap')} onClose={cancelSwap} />}
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        withCloseButton={IS_CAPACITOR}
        error={error}
        operationType="swap"
        submitLabel={lang('Swap')}
        cancelLabel={lang('Back')}
        onSubmit={onSubmit}
        onCancel={onBack}
        onUpdate={clearSwapError}
      >
        {children}
      </PasswordForm>
    </>
  );
}

export default memo(SwapPassword);
