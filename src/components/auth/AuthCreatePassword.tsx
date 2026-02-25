import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AuthMethod } from '../../global/types';

import { getDoesUsePinPad, getIsBiometricAuthSupported } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import CreatePasswordForm from '../ui/CreatePasswordForm';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive?: boolean;
  method?: AuthMethod;
  isLoading?: boolean;
}

const AuthCreatePassword = ({
  isActive,
  method,
  isLoading,
}: OwnProps) => {
  const { afterCreatePassword, resetAuth } = getActions();

  const lang = useLang();
  const headerRef = useRef<HTMLDivElement>();
  const isImporting = method !== 'createAccount';
  const formId = getFormId(method!);
  const withDescription = !getIsBiometricAuthSupported();
  const title = lang(withDescription ? 'Congratulations!' : getDoesUsePinPad() ? 'Create Passcode' : 'Create Password');

  useHistoryBack({
    isActive,
    onBack: resetAuth,
  });

  const handleSubmit = useLastCallback((password: string, isPasswordNumeric: boolean) => {
    afterCreatePassword({ password, isPasswordNumeric });
  });

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={title}
        topTargetRef={headerRef}
        onBackClick={resetAuth}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.guard}
          previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
          noLoop={false}
          nonInteractive
          className={styles.sticker}
        />
        <div ref={headerRef} className={buildClassName(styles.title, !withDescription && styles.titleSmallMargin)}>
          {title}
        </div>
        {withDescription && (
          <>
            <p className={styles.info}>
              <b>{lang(isImporting ? 'The wallet is imported' : 'The wallet is ready')}.</b>
            </p>
            <p className={styles.info}>
              {lang(getDoesUsePinPad() ? 'Create a passcode to protect it.' : 'Create a password to protect it.')}
            </p>
          </>
        )}

        <CreatePasswordForm
          isActive={isActive}
          isLoading={isLoading}
          formId={formId}
          onCancel={resetAuth}
          onSubmit={handleSubmit}
        />
      </div>
    </div>
  );
};

function getFormId(method: AuthMethod) {
  switch (method) {
    case 'createAccount':
      return 'auth_create_password';
    case 'importMnemonic':
      return 'auth_import_mnemonic_password';
    case 'importHardwareWallet':
      return 'auth_import_hardware_password';
  }
}

export default memo(AuthCreatePassword);
