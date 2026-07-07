import React, { memo, useState } from '../../lib/teact/teact';

import type { ApiWalletPermission } from '../../api/types/misc';

import { getDoesUsePinPad } from '../../util/biometrics';
import { shortenAddress } from '../../util/shortenAddress';
import { callApi } from '../../api';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TransactionBanner from '../common/TransactionBanner';
import Button from '../ui/Button';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';

import disconnectStyles from '../main/modals/DisconnectDappModal.module.scss';
import styles from './SettingsPermissions.module.scss';

enum RevokePermissionModalState {
  Confirm,
  Password,
}

interface OwnProps {
  isOpen?: boolean;
  accountId?: string;
  permission?: ApiWalletPermission;
  onClose: NoneToVoidFunction;
  onSuccess: (permission: ApiWalletPermission) => void;
}

function RevokeApprovalModal({
  isOpen,
  accountId,
  permission,
  onClose,
  onSuccess,
}: OwnProps) {
  const lang = useLang();

  const [modalState, setModalState] = useState(RevokePermissionModalState.Confirm);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | undefined>();

  const handleClose = useLastCallback(() => {
    onClose();
  });

  const handleCloseAnimationEnd = useLastCallback(() => {
    setModalState(RevokePermissionModalState.Confirm);
    setError(undefined);
    setIsLoading(false);
  });

  const handleClearError = useLastCallback(() => {
    setError(undefined);
  });

  const handleStartRevoke = useLastCallback(() => {
    setModalState(RevokePermissionModalState.Password);
  });

  const handleBackToConfirm = useLastCallback(() => {
    setModalState(RevokePermissionModalState.Confirm);
    setError(undefined);
  });

  const handlePasswordSubmit = useLastCallback((password: string) => {
    if (!accountId || !permission) return;

    setIsLoading(true);
    setError(undefined);

    const revokeOptions = permission.kind === 'delegation'
      ? {
        accountId,
        password,
        kind: 'delegation' as const,
        delegateAddress: permission.delegateAddress,
      }
      : {
        accountId,
        password,
        kind: 'approval' as const,
        tokenAddress: permission.tokenAddress,
        spenderAddress: permission.spenderAddress,
      };

    void callApi('revokeWalletPermission', permission.chain, revokeOptions).then((result) => {
      setIsLoading(false);

      if (!result || 'error' in result) {
        setError(result?.error ?? 'Unexpected');
        return;
      }

      onSuccess(permission);
      handleClose();
    });
  });

  function renderContent() {
    if (!permission) return undefined;

    if (permission.kind === 'delegation') {
      const delegateLabel = permission.delegateName ?? shortenAddress(permission.delegateAddress);

      if (modalState === RevokePermissionModalState.Password) {
        return (
          <>
            {!getDoesUsePinPad() && (
              <ModalHeader title={lang('Confirm Revoking')} onClose={handleClose} />
            )}
            <PasswordForm
              isActive={Boolean(isOpen)}
              isLoading={isLoading}
              error={error}
              submitLabel={lang('Revoke')}
              cancelLabel={lang('Back')}
              noAutoConfirm
              onSubmit={handlePasswordSubmit}
              onCancel={handleBackToConfirm}
              onUpdate={handleClearError}
            >
              <TransactionBanner
                imageUrl={permission.delegateIcon}
                text={lang('Wallet Delegation to %name%', { name: delegateLabel })}
                className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
              />
            </PasswordForm>
          </>
        );
      }

      return (
        <>
          <ModalHeader title={lang('Revoke Delegation')} onClose={handleClose} />
          <p className={disconnectStyles.description}>
            {lang('Are you sure you want to revoke delegation for %name%?', {
              name: <strong>{delegateLabel}</strong>,
            })}
          </p>
          <div className={disconnectStyles.buttons}>
            <Button onClick={handleClose} className={disconnectStyles.button}>{lang('Cancel')}</Button>
            <Button isDestructive onClick={handleStartRevoke} className={disconnectStyles.button}>
              {lang('Revoke')}
            </Button>
          </div>
        </>
      );
    }

    const spenderLabel = permission.spenderName ?? shortenAddress(permission.spenderAddress);

    if (modalState === RevokePermissionModalState.Password) {
      return (
        <>
          {!getDoesUsePinPad() && (
            <ModalHeader title={lang('Confirm Revoking')} onClose={handleClose} />
          )}
          <PasswordForm
            isActive={Boolean(isOpen)}
            isLoading={isLoading}
            error={error}
            submitLabel={lang('Revoke')}
            cancelLabel={lang('Back')}
            noAutoConfirm
            onSubmit={handlePasswordSubmit}
            onCancel={handleBackToConfirm}
            onUpdate={handleClearError}
          >
            <TransactionBanner
              imageUrl={permission.tokenImage}
              text={lang('Approved to %name%', { name: spenderLabel })}
              className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
            />
          </PasswordForm>
        </>
      );
    }

    return (
      <>
        <ModalHeader title={lang('Revoke Approval')} onClose={handleClose} />
        <p className={disconnectStyles.description}>
          {lang('Are you sure you want to revoke approval for %token%?', {
            token: <strong>{permission.tokenName}</strong>,
          })}
        </p>
        <div className={disconnectStyles.buttons}>
          <Button onClick={handleClose} className={disconnectStyles.button}>{lang('Cancel')}</Button>
          <Button isDestructive onClick={handleStartRevoke} className={disconnectStyles.button}>
            {lang('Revoke')}
          </Button>
        </div>
      </>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      onClose={handleClose}
      onCloseAnimationEnd={handleCloseAnimationEnd}
      contentClassName={disconnectStyles.content}
    >
      {renderContent()}
    </Modal>
  );
}

export default memo(RevokeApprovalModal);
