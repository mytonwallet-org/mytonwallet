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
  onSubmit: (password: string) => void;
  onCancel: NoneToVoidFunction;
  isGaslessWithStars?: boolean;
}

function TransferPassword({
  isActive, isLoading, isBurning, error, children, onSubmit, onCancel, isGaslessWithStars,
}: OwnProps) {
  const {
    cancelTransfer,
    clearTransferError,
  } = getActions();

  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

  const title = isBurning ? 'Confirm Burning' : 'Confirm Sending';
  const submitLabel = isGaslessWithStars
    ? lang('Pay fee with %stars_symbol%', { stars_symbol: STARS_SYMBOL })
    : lang('Confirm');

  return (
    <>
      {!getDoesUsePinPad() && <ModalHeader title={lang(title)} onClose={cancelTransfer} />}
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        withCloseButton={Boolean(children)}
        operationType="transfer"
        error={error}
        submitLabel={submitLabel}
        cancelLabel={lang('Back')}
        noAutoConfirm
        onSubmit={onSubmit}
        onCancel={onCancel}
        onUpdate={clearTransferError}
      >
        {children}
      </PasswordForm>
    </>
  );
}

export default memo(TransferPassword);
