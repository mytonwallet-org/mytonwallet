import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AuthMethod } from '../../global/types';

import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import PasswordForm from '../ui/PasswordForm';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  isBiometricAuthEnabled?: boolean;
  method?: AuthMethod;
  error?: string;
}

function AuthCheckPassword({
  isActive, isLoading, error, method, isBiometricAuthEnabled,
}: OwnProps) {
  const { cancelCheckPassword, cleanAuthError, addAccount } = getActions();

  const lang = useLang();
  const headerRef = useRef<HTMLDivElement>();

  const isImporting = method !== 'createAccount';
  const canUsePinPad = getDoesUsePinPad();
  const fullClassName = buildClassName(
    styles.container,
    canUsePinPad && styles.containerFullSize,
    !canUsePinPad && styles.container_scrollable,
    !canUsePinPad && 'custom-scroll',
  );

  const handleSubmit = useLastCallback((password: string) => {
    addAccount({ method: isImporting ? 'importMnemonic' : 'createAccount', password, isAuthFlow: true });
  });

  function renderTitle() {
    if (canUsePinPad) return undefined;

    if (isBiometricAuthEnabled) {
      return <div ref={headerRef} />;
    }

    return (
      <div ref={headerRef} className={styles.title}>
        {lang('Enter your password')}
      </div>
    );
  }

  return (
    <div className={styles.wrapper}>
      {!canUsePinPad && (
        <Header
          isActive={isActive}
          title={lang('Enter your password')}
          topTargetRef={headerRef}
          onBackClick={cancelCheckPassword}
        />
      )}
      <div className={fullClassName}>
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          error={error}
          containerClassName={styles.passwordForm}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Back')}
          noAutoConfirm
          onSubmit={handleSubmit}
          onCancel={cancelCheckPassword}
          onUpdate={cleanAuthError}
        >
          {renderTitle()}
        </PasswordForm>
      </div>
    </div>
  );
}

export default memo(AuthCheckPassword);
