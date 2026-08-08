import React, { type ElementRef, memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { APP_NAME } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { vibrateOnSuccess } from '../../util/haptics';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import PasswordForm from '../ui/PasswordForm';
import Logo from './Logo';

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

  const handleAuthorize = useLastCallback(async () => {
    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
    }
    onSubmit();
  });

  return (
    <div
      ref={ref}
      className={styles.innerContent}
      style={`--position-top: ${innerContentTopPosition}px;`}
    >
      <PasswordForm
        isActive={isActive && !shouldHideBiometrics}
        noAnimatedIcon
        forceBiometricsInMain
        resetStateDelayMs={PINPAD_RESET_DELAY}
        operationType="unlock"
        containerClassName={buildClassName(styles.passwordFormContent, 'custom-scroll')}
        pinPadClassName={styles.pinPadContent}
        inputWrapperClassName={styles.passwordInputWrapper}
        errorClassName={styles.passwordError}
        submitLabel={lang('Unlock')}
        noAutoConfirm
        onAuthorize={handleAuthorize}
      >
        <Logo />
        <span className={buildClassName(styles.title, 'brand-font')}>{APP_NAME}</span>
      </PasswordForm>
    </div>
  );
}

export default memo(PasswordFormSlide);
