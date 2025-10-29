import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AuthMethod } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import PasswordForm from '../ui/PasswordForm';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  method?: AuthMethod;
  error?: string;
}

function AuthCheckPassword({
  isActive, isLoading, error, method,
}: OwnProps) {
  const { resetAuth, cleanAuthError, addAccount } = getActions();
  const lang = useLang();

  const isImporting = method !== 'createAccount';

  const handleSubmit = useLastCallback((password: string) => {
    addAccount({ method: isImporting ? 'importMnemonic' : 'createAccount', password, isAuthFlow: true });
  });

  return (
    <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
      <PasswordForm
        isActive={isActive}
        isLoading={isLoading}
        error={error}
        containerClassName={styles.passwordForm}
        submitLabel={lang('Confirm')}
        cancelLabel={lang('Back')}
        noAutoConfirm
        onSubmit={handleSubmit}
        onCancel={resetAuth}
        onUpdate={cleanAuthError}
      >
        <div className={styles.title}>{lang('Enter your password')}</div>
      </PasswordForm>
    </div>
  );
}

export default memo(AuthCheckPassword);
