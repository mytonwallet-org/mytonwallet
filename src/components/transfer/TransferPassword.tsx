import React, { memo, type TeactNode } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { STARS_SYMBOL } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  isBurning?: boolean;
  error?: string;
  children?: TeactNode;
  extraAuthUsages?: number;
  isGaslessWithStars?: boolean;
  onAuthorize: (enclaveToken: string) => void;
  onCancel: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function TransferPassword({
  isActive,
  isLoading,
  isBurning,
  error,
  children,
  extraAuthUsages,
  isGaslessWithStars,
  onAuthorize,
  onCancel,
  onClose,
}: OwnProps) {
  const { clearTransferError } = getActions();

  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

  const title = isBurning ? 'Confirm Burning' : 'Confirm';
  const submitLabel = isGaslessWithStars
    ? lang('Pay fee with %stars_symbol%', { stars_symbol: STARS_SYMBOL })
    : lang('Confirm');

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang(title)} onClose={onClose} />}
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        withCloseButton={Boolean(children)}
        operationType="transfer"
        operationTitle={title}
        noAnimatedIcon
        error={error}
        submitLabel={submitLabel}
        cancelLabel={lang('Back')}
        noAutoConfirm
        extraAuthUsages={extraAuthUsages}
        onAuthorize={onAuthorize}
        onCancel={onCancel}
        onClose={onClose}
        onUpdate={clearTransferError}
      >
        {children}
      </PasswordForm>
    </>
  );
}

export default memo(TransferPassword);
