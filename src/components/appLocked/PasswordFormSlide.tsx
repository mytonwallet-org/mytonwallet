import React, { type ElementRef, memo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { APP_NAME } from '../../config';
import { getDoesUsePinPad, getIsNativeBiometricAuthSupported } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { vibrateOnSuccess } from '../../util/haptics';
import { callApi } from '../../api';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import PasswordForm from '../ui/PasswordForm';

import styles from './AppLocked.module.scss';

const PINPAD_RESET_DELAY = 300;

interface OwnProps {
  isActive: boolean;
  ref: ElementRef<HTMLDivElement>;
  innerContentTopPosition?: number;
  shouldHideBiometrics: boolean;
  onSubmit: NoneToVoidFunction;
}

function PasswordFormSlide({
  isActive,
  ref,
  innerContentTopPosition = 0,
  shouldHideBiometrics,
  onSubmit,
}: OwnProps) {
  const lang = useLang();
  const { setIsPinAccepted } = getActions();
  const [passwordError, setPasswordError] = useState('');

  const handleSubmitPassword = useLastCallback(async (password: string) => {
    const result = await callApi('verifyPassword', password);

    if (!result) {
      const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
      setPasswordError(error);
      return;
    }

    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
    }
    onSubmit();
  });

  const handlePasswordChange = useLastCallback(() => setPasswordError(''));

  return (
    <div
      ref={ref}
      className={styles.innerContent}
      style={`--position-top: ${innerContentTopPosition}px;`}
    >
      <PasswordForm
        isActive={!isActive ? false : getIsNativeBiometricAuthSupported() ? !shouldHideBiometrics : true}
        noAnimatedIcon
        error={passwordError}
        resetStateDelayMs={PINPAD_RESET_DELAY}
        operationType="unlock"
        containerClassName={buildClassName(styles.passwordFormContent, 'custom-scroll')}
        pinPadClassName={styles.pinPadContent}
        inputWrapperClassName={styles.passwordInputWrapper}
        errorClassName={styles.passwordError}
        submitLabel={lang('Unlock')}
        noAutoConfirm
        onSubmit={handleSubmitPassword}
        onUpdate={handlePasswordChange}
      >
        <span className={buildClassName(styles.title, 'rounded-font')}>{APP_NAME}</span>
      </PasswordForm>
    </div>
  );
}

export default memo(PasswordFormSlide);
