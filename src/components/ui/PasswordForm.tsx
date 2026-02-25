import type { RefObject, TeactNode } from '../../lib/teact/teact';
import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { AuthConfig } from '../../util/authApi/types';

import {
  AUTO_CONFIRM_DURATION_MINUTES,
  PIN_LENGTH,
  SUPPORT_USERNAME,
  WRONG_ATTEMPTS_BEFORE_LOG_OUT_SUGGESTION,
} from '../../config';
import { selectIsBiometricAuthEnabled, selectIsNativeBiometricAuthEnabled } from '../../global/selectors';
import authApi from '../../util/authApi';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../util/authApi/inMemoryPasswordStore';
import { getDoesUsePinPad, getIsFaceIdAvailable, getIsTouchIdAvailable } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { stopEvent } from '../../util/domEvents';
import { getTranslation } from '../../util/langProvider';
import { pause } from '../../util/schedulers';
import { createSignal } from '../../util/signals';
import { IS_ANDROID_APP } from '../../util/windowEnvironment';
import { callApi } from '../../api';
import { ANIMATED_STICKERS_PATHS } from './helpers/animatedAssets';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useMatchCount } from '../../hooks/useMatchCount';

import LogOutModal from '../main/modals/LogOutModal';
import AnimatedIconWithPreview from './AnimatedIconWithPreview';
import Button from './Button';
import Checkbox from './Checkbox';
import Input from './Input';
import Modal from './Modal';
import PinPad from './PinPad';

import modalStyles from './Modal.module.scss';
import styles from './PasswordForm.module.scss';

type OperationType = 'transfer' | 'sending' | 'staking' | 'unstaking' | 'swap'
  | 'unfreeze' | 'passcode' | 'unlock' | 'claim' | 'turnOnBiometrics' | 'mintCard';

interface OwnProps {
  isActive: boolean;
  isLoading?: boolean;
  operationType?: OperationType;
  cancelLabel?: string;
  submitLabel: string | TeactNode[];
  stickerSize?: number;
  placeholder?: string;
  error?: string;
  help?: string;
  resetStateDelayMs?: number;
  containerClassName?: string;
  pinPadClassName?: string;
  withCloseButton?: boolean;
  isFullWidthButton?: boolean;
  children?: TeactNode;
  noAnimatedIcon?: boolean;
  inputWrapperClassName?: string;
  forceBiometricsInMain?: boolean;
  noAutoConfirm?: boolean;
  onCancel?: NoneToVoidFunction;
  onUpdate: NoneToVoidFunction;
  onSubmit: (password: string) => void;
}

interface StateProps {
  isPasswordNumeric?: boolean;
  isBiometricAuthEnabled: boolean;
  isNativeBiometricAuthEnabled: boolean;
  authConfig?: AuthConfig;
  isAutoConfirmEnabled?: boolean;
}

const STICKER_SIZE = 180;
const APPEAR_ANIMATION_DURATION_MS = 300;

const [getHandleBiometricsSignal, setHandleBiometricsSignal] = createSignal(Date.now());

export function triggerPasswordFormHandleBiometrics(e?: MouseEvent | KeyboardEvent) {
  if (e) {
    stopEvent(e);
  }
  setHandleBiometricsSignal(Date.now());
}

function useInMemoryPassword(inMemoryPasswordRef: RefObject<string | undefined>) {
  const hasInMemoryPassword = useMemo(() => getHasInMemoryPassword(), []);
  if (hasInMemoryPassword && !inMemoryPasswordRef.current) {
    void getInMemoryPassword().then((password) => {
      inMemoryPasswordRef.current = password;
    });
  }
  return hasInMemoryPassword;
}

function useStorageClearedDialog(operationType?: OperationType) {
  const { showDialog } = getActions();

  return useLastCallback(() => {
    showDialog({
      title: '$storage_cleared_title',
      message: getTranslation('$storage_cleared_message', {
        support_link: (
          <a href={`https://t.me/${SUPPORT_USERNAME}`} target="_blank" rel="noreferrer">
            @{SUPPORT_USERNAME}
          </a>
        ),
      }),
      buttons: {
        cancel: { title: 'Cancel' },
        confirm: { title: 'Remove', isDestructive: true, action: 'signOutAll' },
      },
      noBackdropClose: true,
      isInAppLock: operationType === 'unlock',
    });
  });
}

function PasswordForm({
  isActive,
  isLoading,
  operationType,
  isPasswordNumeric,
  isBiometricAuthEnabled,
  isNativeBiometricAuthEnabled,
  authConfig,
  cancelLabel,
  submitLabel,
  stickerSize = STICKER_SIZE,
  placeholder = getDoesUsePinPad() ? 'Enter your passcode' : 'Enter your password',
  error,
  help,
  resetStateDelayMs,
  containerClassName,
  pinPadClassName,
  children,
  withCloseButton,
  isFullWidthButton,
  noAnimatedIcon,
  inputWrapperClassName,
  forceBiometricsInMain,
  isAutoConfirmEnabled,
  noAutoConfirm,
  onUpdate,
  onCancel,
  onSubmit,
}: OwnProps & StateProps) {
  const { openSettings, setInMemoryPassword, setIsAutoConfirmEnabled } = getActions();

  const lang = useLang();

  const memoizedPasswordRef = useRef<string>();
  const hasInMemoryPassword = useInMemoryPassword(memoizedPasswordRef);
  const withConfirmScreenOnly = !noAutoConfirm && hasInMemoryPassword;

  const passwordRef = useRef<HTMLInputElement>();
  const [password, setPassword] = useState<string>('');
  const [localError, setLocalError] = useState<string>('');
  const [wrongAttempts, setWrongAttempts] = useState(0);
  const [isResetBiometricsWarningOpen, openResetBiometricsWarning, closeResetBiometricsWarning] = useFlag(false);
  const { isSmallHeight, isPortrait } = useDeviceScreen();
  const isSubmitDisabled = !password.length && !withConfirmScreenOnly;
  const canUsePinPad = getDoesUsePinPad();
  const [isLogOutModalOpened, openLogOutModal, closeLogOutModal] = useFlag(false);
  const shouldSuggestLogout = useMatchCount(!!error || !!localError, WRONG_ATTEMPTS_BEFORE_LOG_OUT_SUGGESTION);
  const showStorageClearedDialog = useStorageClearedDialog(operationType);

  useEffect(() => {
    if (isActive) {
      setLocalError('');
      setPassword('');
      setWrongAttempts(0);
    }
  }, [isActive]);

  const submitCallback = useLastCallback(async (enteredPassword: string) => {
    const passwordToReturn = withConfirmScreenOnly ? memoizedPasswordRef.current! : enteredPassword;
    onSubmit(passwordToReturn);

    if (withConfirmScreenOnly) return;

    const isVerified = await callApi('verifyPassword', passwordToReturn);
    if (!isVerified) {
      // Password verification failed - check if it's due to storage corruption
      const isStorageOk = await callApi('checkWorkerStorageIntegrity');
      if (!isStorageOk) {
        return showStorageClearedDialog();
      }

      return;
    }

    setInMemoryPassword({ password: passwordToReturn });
  });

  const handleSubmit = useLastCallback(() => {
    void submitCallback(password);
  });

  const handleBiometrics = useLastCallback(async () => {
    try {
      setLocalError('');
      const biometricPassword = await authApi.getPassword(authConfig!);
      if (!biometricPassword) {
        setWrongAttempts(wrongAttempts + 1);
        setLocalError('Biometric confirmation failed');

        if (IS_ANDROID_APP && wrongAttempts > 2) {
          openResetBiometricsWarning();
        }
      } else {
        void submitCallback(biometricPassword);
      }
    } catch (err: any) {
      setLocalError(err.message || lang('Something went wrong.'));
    }
  });

  useEffect(() => {
    if (
      !isActive
      || !isBiometricAuthEnabled
      || withConfirmScreenOnly
    ) {
      return;
    }

    void pause(APPEAR_ANIMATION_DURATION_MS).then(handleBiometrics);
  }, [forceBiometricsInMain, handleBiometrics, isActive, isBiometricAuthEnabled, withConfirmScreenOnly]);

  useEffectOnce(() => {
    return getHandleBiometricsSignal.subscribe(handleBiometrics);
  });

  useFocusAfterAnimation(passwordRef, !isActive || isBiometricAuthEnabled);

  const handleClearError = useLastCallback(() => {
    setLocalError('');
    onUpdate();
  });

  const handleOpenSettings = useLastCallback(() => {
    closeResetBiometricsWarning();
    onCancel?.();
    openSettings();
  });

  const handleInput = useLastCallback((value: string) => {
    setPassword(value);
    if (error) {
      onUpdate();
    }
  });

  const handleAutoConfirmChange = useLastCallback((isEnabled: boolean) => {
    setIsAutoConfirmEnabled({ isEnabled });
  });

  const handleOpenLogOutModal = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);
    openLogOutModal();
  });

  useEffect(() => {
    return isSubmitDisabled || isLoading
      ? undefined
      : captureKeyboardListeners({ onEnter: handleSubmit });
  }, [handleSubmit, isLoading, isSubmitDisabled]);

  function getPinPadTitle() {
    switch (operationType) {
      case 'unfreeze':
        return 'Confirm Unfreezing';
      case 'passcode':
      case 'turnOnBiometrics':
        return 'Confirm Passcode';
      case 'transfer':
      case 'sending':
        return 'Confirm Sending';
      case 'staking':
        return 'Confirm Staking';
      case 'unstaking':
        return 'Confirm Unstaking';
      case 'swap':
        return 'Confirm Swap';
      case 'unlock':
        return undefined;
      case 'claim':
        return 'Confirm Rewards Claim';
      case 'mintCard':
        return 'Confirm Upgrading';
      default:
        return 'Confirm Action';
    }
  }

  const shouldRenderFullWidthButton = operationType === 'unlock';
  const footerButtonsClassName = buildClassName(
    modalStyles.footerButtons,
    shouldRenderFullWidthButton && modalStyles.footerButtonFullWidth,
  );

  function renderFooterButtons() {
    return (
      <div className={footerButtonsClassName}>
        {onCancel && (
          <Button
            isLoading={isLoading && isBiometricAuthEnabled}
            isDisabled={isLoading && !isBiometricAuthEnabled}
            className={modalStyles.buttonHalfWidth}
            onClick={onCancel}
          >
            {cancelLabel || lang('Cancel')}
          </Button>
        )}
        {isBiometricAuthEnabled && Boolean(localError) && (
          <Button
            isPrimary
            isLoading={isLoading}
            isDisabled={isLoading}
            className={modalStyles.buttonHalfWidth}
            onClick={!isLoading ? handleBiometrics : undefined}
            shouldStopPropagation
          >
            {lang('Try Again')}
          </Button>
        )}
        {(!isBiometricAuthEnabled || withConfirmScreenOnly) && (
          <Button
            isPrimary
            isLoading={isLoading}
            isDisabled={isSubmitDisabled}
            className={(shouldRenderFullWidthButton || isFullWidthButton)
              ? modalStyles.buttonFullWidth : modalStyles.buttonHalfWidth}
            onClick={!isLoading ? handleSubmit : undefined}
          >
            {submitLabel || lang('Send')}
          </Button>
        )}
      </div>
    );
  }

  function renderAutoConfirmCheckbox() {
    return (
      <Checkbox
        checked={!!isAutoConfirmEnabled}
        onChange={handleAutoConfirmChange}
        className={styles.autoConfirmCheckbox}
      >
        {lang('Remember for %1$d minutes', AUTO_CONFIRM_DURATION_MINUTES)}
      </Checkbox>
    );
  }

  const shouldRenderAutoConfirmCheckbox = operationType !== 'turnOnBiometrics' && !isBiometricAuthEnabled;

  if (canUsePinPad) {
    const hasError = Boolean(localError || error);
    const title = getPinPadTitle();
    const actionName = lang(
      !isNativeBiometricAuthEnabled
        ? 'Enter code'
        : getIsFaceIdAvailable()
          ? 'Enter code or use Face ID'
          : getIsTouchIdAvailable()
            ? 'Enter code or use Touch ID'
            : 'Enter code or use biometrics',
    );

    const content = (
      <>
        {withCloseButton && (
          <Button
            isRound
            className={buildClassName(modalStyles.closeButton, styles.closeButton)}
            ariaLabel={lang('Close')}
            onClick={onCancel}
          >
            <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
          </Button>
        )}
        <div className={styles.pinPadHeader}>
          {isPortrait && !noAnimatedIcon && (
            <AnimatedIconWithPreview
              play={isActive}
              tgsUrl={ANIMATED_STICKERS_PATHS.guard}
              previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
              noLoop={false}
              nonInteractive
            />
          )}
          {!isSmallHeight && title && <div className={styles.title}>{lang(title)}</div>}
          {children}
        </div>

        {withConfirmScreenOnly ? renderFooterButtons() : (
          <PinPad
            isActive={isActive}
            title={lang(hasError ? (localError || error!) : (isSmallHeight && title ? title : actionName))}
            type={hasError ? 'error' : undefined}
            length={PIN_LENGTH}
            resetStateDelayMs={resetStateDelayMs}
            value={password}
            topContent={shouldRenderAutoConfirmCheckbox ? renderAutoConfirmCheckbox() : undefined}
            className={pinPadClassName}
            onBiometricsClick={isNativeBiometricAuthEnabled ? handleBiometrics : undefined}
            onLogOutClick={operationType === 'unlock' ? openLogOutModal : undefined}
            onChange={setPassword}
            onClearError={handleClearError}
            onSubmit={submitCallback}
          />
        )}
        {operationType === 'unlock' && (
          <LogOutModal isOpen={isLogOutModalOpened} onClose={closeLogOutModal} isInAppLock />
        )}
      </>
    );

    return withConfirmScreenOnly ? (
      <div className={modalStyles.transitionContent}>
        {content}
      </div>
    ) : content;
  }

  function renderBiometricPrompt() {
    const renderingError = localError || error;
    if (renderingError) {
      return (
        <div className={styles.error}>{lang(renderingError)}</div>
      );
    }

    return (
      <div className={styles.verify}>
        {lang(operationType === 'transfer'
          ? 'Please confirm transfer using biometrics' : 'Please confirm action using biometrics')}
      </div>
    );
  }

  function renderPasswordForm() {
    return (
      <>
        <Input
          ref={passwordRef}
          type="password"
          isRequired
          id="first-password"
          wrapperClassName={inputWrapperClassName}
          inputMode={isPasswordNumeric ? 'numeric' : undefined}
          error={error ? lang(error) : localError}
          placeholder={lang(placeholder)}
          value={password}
          onInput={handleInput}
          maxLength={isPasswordNumeric ? PIN_LENGTH : undefined}
        />
        {localError && (
          <div className={styles.errorMessage}>{lang(localError)}</div>
        )}
        {help && !error && (
          <div className={styles.label}>{help}</div>
        )}
        {shouldRenderAutoConfirmCheckbox && renderAutoConfirmCheckbox()}
      </>
    );
  }

  return (
    <div className={buildClassName(modalStyles.transitionContent, containerClassName)}>
      {!noAnimatedIcon && (
        <AnimatedIconWithPreview
          tgsUrl={ANIMATED_STICKERS_PATHS.holdTon}
          previewUrl={ANIMATED_STICKERS_PATHS.holdTonPreview}
          play={isActive}
          size={stickerSize}
          nonInteractive
          noLoop={false}
          className={styles.sticker}
        />
      )}

      {children}

      {!withConfirmScreenOnly && (isBiometricAuthEnabled ? renderBiometricPrompt() : renderPasswordForm())}

      {shouldSuggestLogout && operationType === 'unlock' && (
        <div className={styles.logOutWrapper}>
          {lang('Can\'t confirm?')}
          <span
            role="button"
            tabIndex={0}
            className={styles.logOutButton}
            onClick={handleOpenLogOutModal}
          >
            {lang('Exit all wallets')}
            <i className={buildClassName('icon-chevron-right', styles.detailsIcon)} aria-hidden />
          </span>
        </div>
      )}

      {renderFooterButtons()}

      <Modal
        isOpen={isResetBiometricsWarningOpen}
        isCompact
        title={lang('Biometric authentication failed')}
        onClose={closeResetBiometricsWarning}
      >
        <p className={modalStyles.text}>
          {lang('Reinstall biometrics in your device\'s system settings, or use a passcode.')}
        </p>

        <div className={modalStyles.buttons}>
          <Button className={modalStyles.button} onClick={closeResetBiometricsWarning}>{lang('Close')}</Button>
          <Button isPrimary className={modalStyles.button} onClick={handleOpenSettings}>
            {lang('Settings')}
          </Button>
        </div>
      </Modal>
      {operationType === 'unlock' && (
        <LogOutModal isOpen={isLogOutModalOpened} onClose={closeLogOutModal} isInAppLock />
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { isPasswordNumeric, authConfig, isAutoConfirmEnabled } = global.settings;
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  const isNativeBiometricAuthEnabled = selectIsNativeBiometricAuthEnabled(global);

  return {
    isPasswordNumeric,
    isBiometricAuthEnabled,
    isNativeBiometricAuthEnabled,
    authConfig,
    isAutoConfirmEnabled,
  };
})(PasswordForm));
