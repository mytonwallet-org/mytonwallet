import React, { memo, type TeactNode } from '../../lib/teact/teact';
import { getActions } from '../../global';

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
  onAuthorize: (enclaveToken: string) => void;
  onBack: NoneToVoidFunction;
}

function SwapPassword({
  isActive,
  isLoading,
  error,
  children,
  onAuthorize,
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
        error={error}
        operationType="swap"
        submitLabel={lang('Swap')}
        cancelLabel={lang('Back')}
        // A swap builds the transfer and submits it in two separate API calls. The first one derives
        // the backend auth token from the private key until it is cached, so the very first swap of
        // an account reads the secret twice and would otherwise fail on a single-use session. Later
        // swaps read once and hand the spare read back when the flow ends.
        extraAuthUsages={1}
        onAuthorize={onAuthorize}
        onCancel={onBack}
        onUpdate={clearSwapError}
      >
        {children}
      </PasswordForm>
    </>
  );
}

export default memo(SwapPassword);
