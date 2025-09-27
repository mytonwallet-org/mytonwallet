import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import { PIN_LENGTH } from '../../config';
import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { IS_ANDROID, IS_IOS } from '../../util/windowEnvironment';

import useFlag from '../../hooks/useFlag';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { usePasswordValidation } from '../../hooks/usePasswordValidation';

import Button from './Button';
import Input from './Input';
import Modal from './Modal';

import styles from '../auth/Auth.module.scss';
import modalStyles from './Modal.module.scss';

interface OwnProps {
  isActive?: boolean;
  isLoading?: boolean;
  containerClassName?: string;
  formId: string;
  onCancel: NoneToVoidFunction;
  onSubmit: (password: string, isPasswordNumeric: boolean) => void;
}

function CreatePasswordForm({
  isActive, isLoading, formId, onCancel, onSubmit, containerClassName,
}: OwnProps) {
  const lang = useLang();
  const isMobile = IS_IOS || IS_ANDROID;

  const firstInputRef = useRef<HTMLInputElement>();

  const [isJustSubmitted, setIsJustSubmitted] = useState<boolean>(false);
  const [firstPassword, setFirstPassword] = useState<string>('');
  const [secondPassword, setSecondPassword] = useState<string>('');
  const [isPasswordFocused, markPasswordFocused, unmarkPasswordFocused] = useFlag(false);
  const [isWeakPasswordModalOpen, openWeakPasswordModal, closeWeakPasswordModal] = useFlag(false);

  const [hasError, setHasError] = useState<boolean>(false);
  const [isPasswordsNotEqual, setIsPasswordsNotEqual] = useState<boolean>(false);
  const [isSecondPasswordFocused, markSecondPasswordFocused, unmarkSecondPasswordFocused] = useFlag(false);
  const canSubmit = isActive && firstPassword.length > 0 && secondPassword.length > 0 && !hasError;

  const shouldRenderError = hasError && !isPasswordFocused;

  const validation = usePasswordValidation({
    firstPassword,
    secondPassword,
    isOnlyNumbers: isMobile,
    requiredLength: isMobile ? PIN_LENGTH : undefined,
  });

  useFocusAfterAnimation(firstInputRef, !isActive);

  useEffect(() => {
    setIsPasswordsNotEqual(false);
    if (firstPassword === '' || !isActive || isPasswordFocused) {
      setHasError(false);
      return;
    }

    const { noEqual, invalidLength } = validation;

    if ((!isSecondPasswordFocused || isJustSubmitted) && noEqual && secondPassword !== '') {
      setHasError(true);
      setIsPasswordsNotEqual(true);
    } else if (!noEqual || secondPassword === '' || (isSecondPasswordFocused && !isJustSubmitted)) {
      setHasError(false);
    }
    if (isMobile && invalidLength && !isJustSubmitted) {
      setHasError(true);
    }
  }, [
    isActive, firstPassword, secondPassword, validation, isSecondPasswordFocused, isPasswordFocused, isJustSubmitted,
    isMobile,
  ]);

  const handleFirstPasswordChange = useLastCallback((value: string) => {
    setFirstPassword(value);
    if (isJustSubmitted) {
      setIsJustSubmitted(false);
    }
  });

  const handleSecondPasswordChange = useLastCallback((value: string) => {
    setSecondPassword(value);
    if (isJustSubmitted) {
      setIsJustSubmitted(false);
    }
  });

  const handleSubmit = useLastCallback((e: React.FormEvent) => {
    stopEvent(e);

    if (!canSubmit) {
      return;
    }

    if (firstPassword !== secondPassword) {
      setIsJustSubmitted(true);
      setHasError(true);
      setIsPasswordsNotEqual(true);
      return;
    }

    const isWeakPassword = Object.values(validation).find((rule) => rule);

    if (!isMobile && isWeakPassword && !isWeakPasswordModalOpen) {
      openWeakPasswordModal();
      return;
    }

    if (isWeakPasswordModalOpen) {
      closeWeakPasswordModal();
    }

    onSubmit(firstPassword, isMobile);
  });

  function renderErrors() {
    if (isPasswordsNotEqual) {
      return (
        <div className={buildClassName(styles.errors, styles.error)}>
          {lang('Passwords must be equal.')}
        </div>
      );
    }

    const {
      invalidLength,
      noUpperCase,
      noLowerCase,
      noNumber,
      noSpecialChar,
    } = validation;

    if (isMobile) {
      return (
        <div className={styles.passwordRules}>
          <span className={getValidationRuleClass(shouldRenderError, invalidLength || noNumber)}>
            {lang('Password must contain %length% digits.', { length: PIN_LENGTH })}
          </span>
        </div>
      );
    }

    return (
      <div className={styles.passwordRules}>
        {lang('To protect your wallet as much as possible, use a password with')}
        <span className={getValidationRuleClass(shouldRenderError, invalidLength)}>
          {' '}{lang('$auth_password_rule_8chars')},
        </span>
        <span className={getValidationRuleClass(shouldRenderError, noLowerCase)}>
          {' '}{lang('$auth_password_rule_one_small_char')},
        </span>
        <span className={getValidationRuleClass(shouldRenderError, noUpperCase)}>
          {' '}{lang('$auth_password_rule_one_capital_char')},
        </span>
        <span className={getValidationRuleClass(shouldRenderError, noNumber)}>
          {' '}{lang('$auth_password_rule_one_digit')},
        </span>
        <span className={getValidationRuleClass(shouldRenderError, noSpecialChar)}>
          {' '}{lang('$auth_password_rule_one_special_char')}
        </span>.
      </div>
    );
  }

  return (
    <>
      <form id={formId} className={buildClassName(styles.form, containerClassName)} onSubmit={handleSubmit}>
        <div className={styles.formWidgets}>
          <Input
            ref={firstInputRef}
            type="password"
            isRequired
            id="first-password"
            inputMode={isMobile ? 'numeric' : undefined}
            hasError={shouldRenderError}
            placeholder={lang('Enter your password...')}
            value={firstPassword}
            autoComplete="new-password"
            onInput={handleFirstPasswordChange}
            onFocus={markPasswordFocused}
            onBlur={unmarkPasswordFocused}
            maxLength={isMobile ? PIN_LENGTH : undefined}
            enterKeyHint="next"
          />
          <Input
            type="password"
            isRequired
            id="second-password"
            inputMode={isMobile ? 'numeric' : undefined}
            placeholder={lang('...and repeat it')}
            hasError={isPasswordsNotEqual}
            value={secondPassword}
            autoComplete="new-password"
            onInput={handleSecondPasswordChange}
            onFocus={markSecondPasswordFocused}
            onBlur={unmarkSecondPasswordFocused}
            maxLength={isMobile ? PIN_LENGTH : undefined}
            enterKeyHint="next"
          />
        </div>

        {renderErrors()}

        <div className={styles.buttons}>
          <Button
            isSubmit
            isPrimary
            isDisabled={isPasswordsNotEqual || firstPassword === ''}
            isLoading={isLoading}
            className={styles.btn}
          >
            {lang('Continue')}
          </Button>
        </div>
      </form>

      <Modal
        isOpen={isWeakPasswordModalOpen}
        isCompact
        onClose={closeWeakPasswordModal}
        title={lang('Insecure Password')}
      >
        <p className={modalStyles.text}>
          {lang('Your have entered an insecure password, which can be easily guessed by scammers.')}
        </p>
        <p className={modalStyles.text}>
          {lang('Continue or change password to something more secure?')}
        </p>
        <div className={buildClassName(modalStyles.footerButtons, modalStyles.footerButtonsVertical)}>
          <Button isPrimary onClick={closeWeakPasswordModal} className={modalStyles.buttonFullWidth}>
            {lang('Change')}
          </Button>
          <Button isDestructive forFormId={formId} isSubmit className={modalStyles.buttonFullWidth}>
            {lang('Continue')}
          </Button>
        </div>
      </Modal>
    </>
  );
}

export default memo(CreatePasswordForm);

function getValidationRuleClass(shouldRenderError: boolean, ruleHasError: boolean) {
  return buildClassName(
    styles.passwordRule,
    !ruleHasError ? styles.valid : shouldRenderError ? styles.invalid : undefined,
  );
}
