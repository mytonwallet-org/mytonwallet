import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useEffect, useRef, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { MigrationErrorPresentation } from '../../global/types';

import {
  AUTO_CONFIRM_DURATION_MINUTES,
  PIN_LENGTH,
  SUPPORT_USERNAME,
  WRONG_ATTEMPTS_BEFORE_LOG_OUT_SUGGESTION,
} from '../../config';
import {
  selectHasLegacyBiometrics,
  selectIsBiometricAuthEnabled,
  selectLegacyAuthConfig,
  selectShouldMigrate,
} from '../../global/selectors';
import { selectAuthUsageCountRequest, selectEnclaveToken } from '../../global/selectors/enclave';
import { getDoesUsePinPad, getIsFaceIdAvailable, getIsTouchIdAvailable } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { stopEvent } from '../../util/domEvents';
import { getTranslation } from '../../util/langProvider';
import { toNativeDigits } from '../../util/nativeDigits';
import { pause } from '../../util/schedulers';
import { createSignal } from '../../util/signals';
import { enclave, type LegacyAuthConfig } from '../../enclave';
import { ANIMATED_STICKERS_PATHS } from './helpers/animatedAssets';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useMatchCount } from '../../hooks/useMatchCount';
import useTimeout from '../../hooks/useTimeout';
import useToggleClass from '../../hooks/useToggleClass';

import LogOutModal from '../main/modals/LogOutModal';
import AnimatedIconWithPreview from './AnimatedIconWithPreview';
import Button from './Button';
import Checkbox from './Checkbox';
import Input from './Input';
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
  submitLabel?: string | TeactNode[];
  stickerSize?: number;
  placeholder?: string;
  error?: string;
  pinPadTitle?: string;
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
  noBiometrics?: boolean;
  errorClassName?: string;
  noAutoConfirm?: boolean;
  /**
   * Secret reads this flow needs beyond the single one every operation gets. A usage is spent when
   * the private key is read, not when an API call is made, so only a flow that reads the key in more
   * than one step has to ask for more; the session dies on the last read it granted. A flow that has
   * to name the largest count it might need gives back what it did not spend when it ends.
   */
  extraAuthUsages?: number;
  onCancel?: NoneToVoidFunction;
  onUpdate?: NoneToVoidFunction;
  onAuthorize: (enclaveToken: string) => void;
  onError?: (error?: string) => void;
}

interface StateProps {
  isPasswordNumeric?: boolean;
  isAutoConfirmEnabled?: boolean;
  enclaveSessionValidUntil?: number;
  isBiometricAuthEnabled: boolean;
  shouldMigrate?: boolean;
  hasLegacyBiometrics?: boolean;
  legacyAuthConfig?: LegacyAuthConfig;
  authUsageCountRequest?: number;
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

function useMigrationFailureDialog(operationType?: OperationType) {
  const { showDialog } = getActions();

  return useLastCallback((titleKey: string, messageKey: string, errorCode?: string) => {
    showDialog({
      title: titleKey,
      message: getTranslation(messageKey, {
        support_link: (
          <a href={`https://t.me/${SUPPORT_USERNAME}`} target="_blank" rel="noreferrer">
            @{SUPPORT_USERNAME}
          </a>
        ),
        error_code: errorCode,
      }),
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
  isBiometricAuthEnabled: isBiometricAuthEnabledProp,
  cancelLabel,
  submitLabel,
  stickerSize = STICKER_SIZE,
  placeholder = getDoesUsePinPad() ? 'Enter your passcode' : 'Enter your password',
  error,
  pinPadTitle,
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
  noBiometrics,
  errorClassName,
  isAutoConfirmEnabled,
  enclaveSessionValidUntil,
  noAutoConfirm,
  shouldMigrate,
  hasLegacyBiometrics,
  legacyAuthConfig,
  authUsageCountRequest,
  extraAuthUsages,
  onUpdate,
  onCancel,
  onAuthorize,
  onError,
}: OwnProps & StateProps) {
  const {
    setIsAutoConfirmEnabled,
    setEnclaveSession,
    enableBiometrics,
    migrateLegacyAuth,
    migrateLegacyBiometricAuth,
    upgradeMultichainAccounts,
  } = getActions();

  const lang = useLang();

  const isBiometricAuthEnabled = isBiometricAuthEnabledProp && !noBiometrics;

  const inputRef = useRef<HTMLInputElement>();
  const [inputValue, setInputValue] = useState<string>('');
  const [localError, setLocalError] = useState<string>('');
  const { isSmallHeight, isPortrait } = useDeviceScreen();
  const withAutoConfirm = useCanAutoConfirm(enclaveSessionValidUntil, noAutoConfirm);
  const isSubmitDisabled = !inputValue.length && !withAutoConfirm;
  const canUsePinPad = getDoesUsePinPad();
  const [isLogOutModalOpened, openLogOutModal, closeLogOutModal] = useFlag(false);
  // The biometric screen offers its retry only while something failed, and the dialog paths clear the
  // inline error the retry used to be keyed on, which would leave that screen without a single control
  const [hasMigrationFailed, markMigrationFailed, clearMigrationFailure] = useFlag(false);
  const shouldSuggestLogout = useMatchCount(!!error || !!localError, WRONG_ATTEMPTS_BEFORE_LOG_OUT_SUGGESTION);
  const showMigrationFailureDialog = useMigrationFailureDialog(operationType);
  const isAuthorizingRef = useRef(false);

  /**
   * Both migration entry points report through here, so a diagnosis that needs the dialog cannot end
   * up in the inline error slot on one path while getting the dialog on the other. The inline slot is
   * a single line under the input, which would leave the "do not reinstall" part of the answer unsaid.
   */
  const handleMigrationError = useLastCallback((presentation: MigrationErrorPresentation) => {
    isAuthorizingRef.current = false;

    if (presentation.kind === 'inline') {
      setLocalError(presentation.text);
      onError?.(presentation.text);
      return;
    }

    // An earlier attempt may have left "Wrong password" under the input, and leaving it there next to
    // an answer that says the password is not the problem contradicts what is being said. It is
    // cleared on both sides, because the parent owns a slot of its own that outranks the local one.
    setLocalError('');
    onError?.(undefined);
    markMigrationFailed();

    // A dismissed prompt is not a failure to report. The mark above is what puts the retry control
    // back on the biometric screen, which is all this path owes the user.
    if (presentation.kind === 'silent') return;

    // The pinpad holds its digits until the value is cleared, so a full pinpad behind the dialog
    // reads as a frozen screen
    setInputValue('');
    showMigrationFailureDialog(presentation.titleKey, presentation.messageKey, presentation.errorCode);
  });

  // One usage for the operation itself plus the extra usages it asked for
  const operationUsageCount = 1 + (extraAuthUsages ?? 0);
  const extraUsages = (authUsageCountRequest ?? 0) + (extraAuthUsages ?? 0);
  const usageCount = extraUsages ? 1 + extraUsages : undefined;

  const handleAuthorized = useLastCallback((enclaveToken: string) => {
    // The handler is a no-op when there is nothing to upgrade
    upgradeMultichainAccounts({ enclaveToken });
    onAuthorize(enclaveToken);
  });

  useEffect(() => {
    if (isActive) {
      setLocalError('');
      setInputValue('');
      clearMigrationFailure();
      isAuthorizingRef.current = false;
    }
  }, [isActive]);

  const handleSubmit = useLastCallback(async (pin?: string) => {
    // Prevent double authorization (e.g., race between PIN input and biometrics)
    if (isAuthorizingRef.current || isLoading) return;
    isAuthorizingRef.current = true;

    if (withAutoConfirm) {
      handleAuthorized(selectEnclaveToken(getGlobal())!);
      return;
    }

    const password = pin ?? inputValue;

    // Migration from legacy auth to Enclave
    if (shouldMigrate) {
      migrateLegacyAuth({
        password,
        isLongSession: !noAutoConfirm && Boolean(isAutoConfirmEnabled),
        // A migration hands its session straight to the operation and never starts the multichain
        // upgrade, so budgeting for the upgrade would leave those reads unspent - and unspent means
        // available for good, since a counted session has no expiry. Turning biometrics back on does
        // read the key, and that read comes out of this same session.
        usageCount: operationUsageCount + (hasLegacyBiometrics ? 1 : 0),
        onSuccess: (token) => {
          if (hasLegacyBiometrics) {
            enableBiometrics({});
          }
          onAuthorize(token);
        },
        onError: handleMigrationError,
      });
      return;
    }

    // Normal authorization
    const enclaveSession = await enclave.authorize(
      'passcode',
      !noAutoConfirm && Boolean(isAutoConfirmEnabled),
      password,
      usageCount,
    );

    if (!enclaveSession) {
      isAuthorizingRef.current = false;
      const errorMessage = 'Wrong password, please try again.';
      setLocalError(errorMessage);
      onError?.(errorMessage);
      return;
    }

    setEnclaveSession(enclaveSession);
    handleAuthorized(enclaveSession.token);
  });

  const handleBiometrics = useLastCallback(async () => {
    // Prevent double authorization (e.g., race between PIN input and biometrics)
    if (isAuthorizingRef.current || isLoading) return;
    isAuthorizingRef.current = true;

    try {
      setLocalError('');

      const enclaveSession = await enclave.authorize('biometric', false, undefined, usageCount);
      if (!enclaveSession) {
        isAuthorizingRef.current = false;
        const errorMessage = 'Biometric confirmation failed';
        setLocalError(errorMessage);
        onError?.(errorMessage);
        return;
      }

      setEnclaveSession(enclaveSession);
      handleAuthorized(enclaveSession.token);
    } catch (err: any) {
      isAuthorizingRef.current = false;
      const errorMessage = err.message || lang('Something went wrong.');
      setLocalError(errorMessage);
      onError?.(errorMessage);
    }
  });

  // Handle legacy biometrics migration
  const handleLegacyBiometricsMigration = useLastCallback(() => {
    if (!legacyAuthConfig || legacyAuthConfig.kind === 'password') {
      return;
    }

    // Prevent double authorization
    if (isAuthorizingRef.current || isLoading) return;
    isAuthorizingRef.current = true;

    setLocalError('');

    migrateLegacyBiometricAuth({
      legacyAuthConfig,
      isLongSession: !noAutoConfirm && Boolean(isAutoConfirmEnabled),
      // The upgrade is left out for the same reason as in the passcode migration above
      usageCount: operationUsageCount,
      onSuccess: onAuthorize,
      onError: handleMigrationError,
    });
  });

  useEffect(() => {
    if (
      !isActive
      || !isBiometricAuthEnabled
      || withAutoConfirm
    ) {
      return;
    }

    // If migration is needed, use legacy biometrics instead
    if (shouldMigrate && hasLegacyBiometrics && legacyAuthConfig) {
      void pause(APPEAR_ANIMATION_DURATION_MS).then(handleLegacyBiometricsMigration);
      return;
    }

    // Only use new biometric system if migration is not needed
    if (!shouldMigrate) {
      void pause(APPEAR_ANIMATION_DURATION_MS).then(handleBiometrics);
    }
  }, [
    forceBiometricsInMain, handleBiometrics, handleLegacyBiometricsMigration, isActive,
    isBiometricAuthEnabled, withAutoConfirm, shouldMigrate, hasLegacyBiometrics, legacyAuthConfig,
  ]);

  useEffectOnce(() => {
    // When signal is triggered, use legacy or new biometrics based on migration state
    return getHandleBiometricsSignal.subscribe(() => {
      if (shouldMigrate && hasLegacyBiometrics && legacyAuthConfig) {
        void handleLegacyBiometricsMigration();
      } else if (!shouldMigrate) {
        void handleBiometrics();
      }
    });
  });

  useFocusAfterAnimation(inputRef, !isActive || isBiometricAuthEnabled);

  useToggleClass({ className: 'is-password-form-visible', isActive });

  const handleClearError = useLastCallback(() => {
    setLocalError('');
    clearMigrationFailure();
    onUpdate?.();
    onError?.(undefined);
  });

  const handleInput = useLastCallback((value: string) => {
    setInputValue(value);
    handleClearError();
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
      : captureKeyboardListeners({ onEnter: () => handleSubmit() });
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
        {isBiometricAuthEnabled && (Boolean(localError) || hasMigrationFailed) && (
          <Button
            isPrimary
            isLoading={isLoading}
            isDisabled={isLoading}
            className={modalStyles.buttonHalfWidth}
            onClick={!isLoading
              ? (shouldMigrate && hasLegacyBiometrics ? handleLegacyBiometricsMigration : handleBiometrics)
              : undefined}
            shouldStopPropagation
          >
            {lang('Try Again')}
          </Button>
        )}
        {(!isBiometricAuthEnabled || withAutoConfirm) && (
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
        {toNativeDigits(lang('Remember for %1$d minutes', AUTO_CONFIRM_DURATION_MINUTES) as string)}
      </Checkbox>
    );
  }

  const shouldRenderAutoConfirmCheckbox = operationType !== 'turnOnBiometrics' && !isBiometricAuthEnabled;

  if (canUsePinPad) {
    const hasError = Boolean(localError || error);
    const title = getPinPadTitle();
    const actionName = lang(
      !isBiometricAuthEnabled
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

        {withAutoConfirm ? renderFooterButtons() : (
          <PinPad
            isActive={isActive}
            title={lang(hasError
              ? (localError || error!)
              : (pinPadTitle || (isSmallHeight && title ? title : actionName)),
            )}
            type={hasError ? 'error' : undefined}
            length={PIN_LENGTH}
            resetStateDelayMs={resetStateDelayMs}
            value={inputValue}
            topContent={shouldRenderAutoConfirmCheckbox ? renderAutoConfirmCheckbox() : undefined}
            className={pinPadClassName}
            onBiometricsClick={isBiometricAuthEnabled
              ? (shouldMigrate && hasLegacyBiometrics ? handleLegacyBiometricsMigration : handleBiometrics)
              : undefined}
            onLogOutClick={operationType === 'unlock' ? openLogOutModal : undefined}
            onChange={setInputValue}
            onClearError={handleClearError}
            onSubmit={handleSubmit}
          />
        )}
        {operationType === 'unlock' && (
          <LogOutModal isOpen={isLogOutModalOpened} onClose={closeLogOutModal} isInAppLock />
        )}
      </>
    );

    return withAutoConfirm ? (
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
          ref={inputRef}
          type="password"
          isRequired
          id="first-password"
          wrapperClassName={inputWrapperClassName}
          errorClassName={errorClassName}
          inputMode={isPasswordNumeric ? 'numeric' : undefined}
          error={error ? lang(error) : localError}
          placeholder={lang(placeholder)}
          value={inputValue}
          onInput={handleInput}
          maxLength={isPasswordNumeric ? PIN_LENGTH : undefined}
        />
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

      {!withAutoConfirm && (isBiometricAuthEnabled ? renderBiometricPrompt() : renderPasswordForm())}

      {operationType === 'unlock' && (
        <div className={buildClassName(styles.logOutWrapper, !shouldSuggestLogout && styles.logOutWrapperHidden)}>
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

      {operationType === 'unlock' && (
        <LogOutModal isOpen={isLogOutModalOpened} onClose={closeLogOutModal} isInAppLock />
      )}
    </div>
  );
}

function useCanAutoConfirm(enclaveSessionValidUntil?: number, isDisabled?: boolean) {
  if (isDisabled) return false;

  const autoConfirmTtl = enclaveSessionValidUntil ? enclaveSessionValidUntil - Date.now() : undefined;
  const [canAutoConfirm, setCanAutoConfirm] = useState(
    autoConfirmTtl !== undefined && autoConfirmTtl > 0,
  );

  useEffect(() => {
    const currentTtl = enclaveSessionValidUntil ? enclaveSessionValidUntil - Date.now() : undefined;
    const isValid = currentTtl !== undefined && currentTtl > 0;
    setCanAutoConfirm(isValid);
  }, [enclaveSessionValidUntil]);

  useTimeout(() => {
    setCanAutoConfirm(false);
  }, autoConfirmTtl && autoConfirmTtl > 0 ? autoConfirmTtl : undefined);

  return canAutoConfirm;
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { isPasswordNumeric, isAutoConfirmEnabled } = global.settings;
  const enclaveSessionValidUntil = global.enclaveSession?.validUntil;
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  const shouldMigrate = selectShouldMigrate(global);
  const hasLegacyBiometrics = shouldMigrate ? selectHasLegacyBiometrics(global) : undefined;
  const legacyAuthConfig = shouldMigrate ? selectLegacyAuthConfig(global) : undefined;

  return {
    isPasswordNumeric,
    isAutoConfirmEnabled,
    enclaveSessionValidUntil,
    isBiometricAuthEnabled,
    shouldMigrate,
    hasLegacyBiometrics,
    legacyAuthConfig,
    authUsageCountRequest: selectAuthUsageCountRequest(global),
  };
})(PasswordForm));
