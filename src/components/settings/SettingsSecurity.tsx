import React, { memo, useEffect, useLayoutEffect, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { AutolockValueType, GlobalState } from '../../global/types';
import { BiometricsState } from '../../global/types';

import {
  APP_ENV,
  DEFAULT_AUTOLOCK_OPTION,
  IS_GRAM_WALLET,
} from '../../config';
import {
  selectAccount,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsAllowSuspiciousActions,
  selectIsBiometricAuthEnabled,
  selectIsEnclaveSessionValid,
  selectIsMnemonicAccount,
  selectIsMultichainAccount,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { vibrateOnSuccess } from '../../util/haptics';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY } from '../../util/windowEnvironment';
import { getTokenAuthType } from '../../enclave';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious from '../../hooks/usePrevious';

import Button from '../ui/Button';
import CreatePasswordForm from '../ui/CreatePasswordForm';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import Mfa from './mfa/Mfa';
import MfaInstalled from './mfa/MfaInstalled';
import MfaPassword from './mfa/MfaPassword';
import BackupFlow, { BackupSlide } from './security/BackupFlow';
import BiometricsFlow, { BiometricsSlide } from './security/BiometricsFlow';
import BiometricsWarningModal from './security/BiometricsWarningModal';
import ChangePasscodeFlow, { ChangePasscodeSlide } from './security/ChangePasscodeFlow';
import SecuritySettingsMain from './security/SecurityMain';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Settings.module.scss';

const enum SLIDES {
  settings,
  password,
  changePasscode,
  backup,
  biometrics,
  disableBiometricsCreatePassword,
  mfa,
  confirmMfaInstallation,
  mfaInstalled,
}

const SHOULD_FORCE_SHOW_MFA_IN_DEV = APP_ENV === 'development';
interface OwnProps {
  isActive: boolean;
  isInsideModal?: boolean;
  isAutoUpdateEnabled: boolean;
  onBackClick: NoneToVoidFunction;
  onAutoUpdateEnabledToggle: NoneToVoidFunction;
  onSettingsClose: NoneToVoidFunction;
}

interface StateProps {
  isBiometricAuthEnabled: boolean;
  isPasswordNumeric?: boolean;
  isMultichainAccount: boolean;
  isAppLockEnabled?: boolean;
  autolockValue?: AutolockValueType;
  isAutoConfirmEnabled?: boolean;
  isAllowSuspiciousActions?: boolean;
  shouldShowBackup: boolean;
  isLoading?: boolean;
  currentAccountId: string;
  biometricsState: BiometricsState;
  biometricsError?: string;
  isMfaEnabled: boolean;
  hasCurrentAccountMfa: boolean;
}

function SettingsSecurity({
  isActive,
  isInsideModal,
  isBiometricAuthEnabled,
  isPasswordNumeric,
  isMultichainAccount,
  isAppLockEnabled,
  autolockValue = DEFAULT_AUTOLOCK_OPTION,
  isAutoConfirmEnabled,
  isAllowSuspiciousActions,
  isAutoUpdateEnabled,
  currentAccountId,
  onBackClick: navigateBackToSettings,
  onSettingsClose,
  onAutoUpdateEnabledToggle,
  isLoading,
  shouldShowBackup,
  biometricsState,
  biometricsError,
  isMfaEnabled,
  hasCurrentAccountMfa,
}: OwnProps & StateProps) {
  const {
    setIsPinAccepted,
    clearIsPinAccepted,
    openBiometricsTurnOffWarning,
    enableBiometrics,
    disableBiometrics,
    closeBiometricSettings,
    setAppLockValue,
    setIsAutoConfirmEnabled,
    setIsAllowSuspiciousActions,
  } = getActions();

  const lang = useLang();

  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.settings);
  const previousSlide = usePrevious(currentSlide);
  const [nextKey, setNextKey] = useState<SLIDES | undefined>(SLIDES.settings);
  const [backupSlide, setBackupSlide] = useState(BackupSlide.Menu);
  const [backupInitialType, setBackupInitialType] = useState<'key' | 'words'>('words');
  const [hasBackupMnemonic, setBackupHasMnemonic] = useState(false);

  const [passwordError, setPasswordError] = useState<string>();
  const [pinPadTitle, setPinPadTitle] = useState<string>();
  // Callback to execute after the user has entered the password or biometrics
  const [pendingProceedCb, setPendingProceedCb] = useState<(() => void | Promise<void>) | undefined>(undefined);
  const [passwordPurpose, setPasswordPurpose] = useState<'default' | 'biometricsTurnOn' | 'changePasscode'>('default');

  const [isTurnOnWarningOpen, setIsTurnOnWarningOpen] = useState(false);

  // Sub-flow slide states
  const [changePasscodeSlide, setChangePasscodeSlide] = useState(ChangePasscodeSlide.NewPassword);
  const [biometricsSlide, setBiometricsSlide] = useState<BiometricsSlide | undefined>(undefined);

  const cleanup = useLastCallback(() => {
    setPinPadTitle(undefined);
    setPasswordError(undefined);
    setPendingProceedCb(undefined);
    setPasswordPurpose('default');
    clearIsPinAccepted();
  });

  // `forcePasscode` ensures the user re-authenticates with their passcode even when a valid
  // biometric session exists. This is critical for `changePasscode`: `migrateAuth` resolves the
  // current auth type from the token prefix, so passing a biometric token while replacing
  // passcode would destroy the biometric auth on the native side instead of the old passcode.
  const ensureAuthenticatedAction = useLastCallback((
    proceedCb: () => void | Promise<void>,
    options?: { forcePasscode?: boolean },
  ) => {
    if (currentSlide === SLIDES.password) return;

    const global = getGlobal();
    const isSessionValid = selectIsEnclaveSessionValid(global);
    const isPasscodeSession = global.enclaveSession?.token
      ? getTokenAuthType(global.enclaveSession.token) === 'passcode'
      : false;

    if (isSessionValid && (!options?.forcePasscode || isPasscodeSession)) {
      void proceedCb();
    } else {
      setPendingProceedCb(() => proceedCb);
      setCurrentSlide(SLIDES.password);
      setNextKey(SLIDES.settings);
    }
  });

  const openSettingsSlide = useLastCallback(() => {
    setCurrentSlide(SLIDES.settings);
    setNextKey(undefined);
    cleanup();
  });

  const handleBackToSettingsClick = useLastCallback(() => {
    navigateBackToSettings();
    cleanup();
  });

  const handleBiometricsClose = useLastCallback(() => {
    closeBiometricSettings();
    openSettingsSlide();
  });

  const handleHistoryBack = useLastCallback(() => {
    if (currentSlide === SLIDES.settings) {
      handleBackToSettingsClick();
    } else if (currentSlide === SLIDES.biometrics) {
      handleBiometricsClose();
    } else {
      openSettingsSlide();
    }
  });

  useLayoutEffect(() => {
    if (!isActive) cleanup();
  }, [isActive]);

  useHistoryBack({ isActive, onBack: handleHistoryBack });

  // Sync biometrics global state → local slides
  useEffect(() => {
    if (biometricsState === BiometricsState.TurnOnComplete
      || biometricsState === BiometricsState.TurnOffComplete) {
      handleBiometricsClose();
      return;
    }

    const biometricsSlideMap: Partial<Record<BiometricsState, BiometricsSlide>> = {
      [BiometricsState.TurnOnRegistration]: BiometricsSlide.Registration,
      [BiometricsState.TurnOnVerification]: BiometricsSlide.Verification,
    };

    const targetSlide = biometricsSlideMap[biometricsState];
    if (targetSlide !== undefined) {
      setBiometricsSlide(targetSlide);
      setCurrentSlide(SLIDES.biometrics);
      setNextKey(SLIDES.settings);
    }
  }, [biometricsState]);

  const handleAuthorize = useLastCallback(async () => {
    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
    }

    const proceed = pendingProceedCb;
    const purpose = passwordPurpose;
    setPendingProceedCb(undefined);

    if (proceed) {
      if (purpose === 'biometricsTurnOn') {
        setBiometricsSlide(BiometricsSlide.Registration);
        setCurrentSlide(SLIDES.biometrics);
        setNextKey(SLIDES.settings);
      }
      void proceed();
    } else {
      openSettingsSlide();
    }
  });

  const handleChangePasswordClick = useLastCallback(() => {
    setPasswordPurpose('changePasscode');
    const initialSlide = getDoesUsePinPad()
      ? ChangePasscodeSlide.CreateNewPin
      : ChangePasscodeSlide.NewPassword;
    setChangePasscodeSlide(initialSlide);
    ensureAuthenticatedAction(() => {
      setCurrentSlide(SLIDES.changePasscode);
      setNextKey(SLIDES.settings);
    }, { forcePasscode: true });
  });

  const handleOpenBackupWallet = useLastCallback(() => {
    ensureAuthenticatedAction(() => {
      const { slide, backupType, hasMnemonicWallet } = getInitialBackupState(
        getGlobal(), currentAccountId, isMultichainAccount,
      );
      setBackupSlide(slide);
      setBackupInitialType(backupType);
      setBackupHasMnemonic(hasMnemonicWallet);
      setCurrentSlide(SLIDES.backup);
      setNextKey(SLIDES.settings);
    });
  });

  const handleOpenMfa = useLastCallback(() => {
    setCurrentSlide(SLIDES.mfa);
  });

  const handleOpenInstallConfirmation = useLastCallback(() => {
    setCurrentSlide(SLIDES.confirmMfaInstallation);
  });

  const handleOpenMfaInstalled = useLastCallback(() => {
    setCurrentSlide(SLIDES.mfaInstalled);
    setNextKey(SLIDES.mfa);
  });

  const handleAppLockToggle = useLastCallback(() => {
    ensureAuthenticatedAction(() => {
      setAppLockValue({ value: autolockValue, isEnabled: !isAppLockEnabled });
      openSettingsSlide();
    });
  });

  const handleAutolockChange = useLastCallback((value: AutolockValueType) => {
    ensureAuthenticatedAction(() => {
      setAppLockValue({ value, isEnabled: true });
      openSettingsSlide();
    });
  });

  const handleAutoConfirmToggle = useLastCallback(() => {
    ensureAuthenticatedAction(() => {
      setIsAutoConfirmEnabled({ isEnabled: !isAutoConfirmEnabled });
      openSettingsSlide();
    });
  });

  const handleAllowSuspiciousActionsToggle = useLastCallback(() => {
    ensureAuthenticatedAction(() => {
      setIsAllowSuspiciousActions({ isEnabled: !isAllowSuspiciousActions });
      openSettingsSlide();
    });
  });

  const handleAutoUpdateToggle = useLastCallback(() => {
    ensureAuthenticatedAction(() => {
      onAutoUpdateEnabledToggle();
      openSettingsSlide();
    });
  });

  const handleDisableBiometricsProceed = useLastCallback(() => {
    closeBiometricSettings();
    if (CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY) {
      ensureAuthenticatedAction(() => {
        setCurrentSlide(SLIDES.disableBiometricsCreatePassword);
        setNextKey(SLIDES.settings);
      });
    } else {
      disableBiometrics();
    }
  });

  const handleDisableBiometricsCreatePassword = useLastCallback((password: string, isNumeric?: boolean) => {
    disableBiometrics({ newPassword: password, isPasswordNumeric: isNumeric });
  });

  const handleBiometricTurnOnConfirm = useLastCallback(() => {
    setIsTurnOnWarningOpen(false);
    setPasswordPurpose('biometricsTurnOn');
    ensureAuthenticatedAction(() => {
      enableBiometrics();
    });
  });

  const handleBiometricAuthToggle = useLastCallback(() => {
    if (isBiometricAuthEnabled) {
      openBiometricsTurnOffWarning();
    } else if (CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY) {
      setIsTurnOnWarningOpen(true);
    } else {
      setPasswordPurpose('biometricsTurnOn');
      ensureAuthenticatedAction(() => {
        enableBiometrics();
      });
    }
  });

  function renderContent(isSlideActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.settings:
        return (
          <SecuritySettingsMain
            isInsideModal={isInsideModal}
            isBiometricAuthEnabled={isBiometricAuthEnabled}
            isAppLockEnabled={isAppLockEnabled}
            autolockValue={autolockValue}
            isAutoConfirmEnabled={isAutoConfirmEnabled}
            isAllowSuspiciousActions={isAllowSuspiciousActions}
            isAutoUpdateEnabled={isAutoUpdateEnabled}
            shouldShowBackup={shouldShowBackup}
            isMfaVisible={SHOULD_FORCE_SHOW_MFA_IN_DEV || (IS_GRAM_WALLET && isMfaEnabled) || hasCurrentAccountMfa}
            onBackClick={handleBackToSettingsClick}
            onChangePasswordClick={handleChangePasswordClick}
            onOpenBackupWallet={handleOpenBackupWallet}
            onOpenMfa={handleOpenMfa}
            onBiometricAuthToggle={handleBiometricAuthToggle}
            onAppLockToggle={handleAppLockToggle}
            onAutolockChange={handleAutolockChange}
            onAutoConfirmToggle={handleAutoConfirmToggle}
            onAllowSuspiciousActionsToggle={handleAllowSuspiciousActionsToggle}
            onAutoUpdateToggle={handleAutoUpdateToggle}
          />
        );

      case SLIDES.password: {
        const isBiometricsTurnOn = passwordPurpose === 'biometricsTurnOn';
        const isChangePasscode = passwordPurpose === 'changePasscode';
        const passwordTitle = isBiometricsTurnOn
          ? lang('Turn On Biometrics')
          : (isPasswordNumeric || getDoesUsePinPad()
            ? lang('Confirm Passcode')
            : lang('Confirm Password'));
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                title={passwordTitle}
                onBackButtonClick={openSettingsSlide}
                className={styles.modalHeader}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={openSettingsSlide} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
                <span className={styles.headerTitle}>{passwordTitle}</span>
              </div>
            )}
            <PasswordForm
              isActive={isSlideActive && isActive}
              error={passwordError}
              pinPadTitle={pinPadTitle}
              containerClassName={styles.passwordFormWithHeaderOffset}
              forceBiometricsInMain={isBiometricsTurnOn ? false : !isInsideModal}
              noBiometrics={isChangePasscode}
              operationType={isBiometricsTurnOn ? 'turnOnBiometrics' : undefined}
              placeholder={lang('Enter your current password')}
              submitLabel={lang('Continue')}
              noAutoConfirm
              onAuthorize={handleAuthorize}
              onError={setPasswordError}
              onCancel={openSettingsSlide}
            />
          </>
        );
      }

      case SLIDES.changePasscode:
        return (
          <ChangePasscodeFlow
            isActive={isActive}
            isSlideActive={isSlideActive}
            currentSlide={changePasscodeSlide}
            isInsideModal={isInsideModal}
            isLoading={isLoading}
            onSlideChange={setChangePasscodeSlide}
            onComplete={openSettingsSlide}
            onCancel={openSettingsSlide}
          />
        );

      case SLIDES.backup:
        return (
          <BackupFlow
            isActive={isActive}
            isSlideActive={isSlideActive}
            currentSlide={backupSlide}
            isInsideModal={isInsideModal}
            isMultichainAccount={isMultichainAccount}
            currentAccountId={currentAccountId}
            initialBackupType={backupInitialType}
            initialHasMnemonicWallet={hasBackupMnemonic}
            onSlideChange={setBackupSlide}
            onClose={openSettingsSlide}
            onSettingsClose={onSettingsClose}
          />
        );

      case SLIDES.biometrics:
        return (
          <BiometricsFlow
            isSlideActive={isSlideActive}
            currentSlide={biometricsSlide}
            isInsideModal={isInsideModal}
            biometricsError={biometricsError}
            onClose={handleBiometricsClose}
          />
        );

      case SLIDES.disableBiometricsCreatePassword: {
        const createPasswordTitle = lang('Create Password');
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                title={createPasswordTitle}
                onBackButtonClick={openSettingsSlide}
                className={styles.modalHeader}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={openSettingsSlide} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
                <span className={styles.headerTitle}>{createPasswordTitle}</span>
              </div>
            )}
            <CreatePasswordForm
              isActive={isSlideActive && isActive}
              isLoading={isLoading}
              formId="settings_disable_biometrics_create_password"
              containerClassName={styles.passwordFormWithHeaderOffset}
              onCancel={openSettingsSlide}
              onSubmit={handleDisableBiometricsCreatePassword}
            />
          </>
        );
      }

      case SLIDES.mfa:
        return (
          <Mfa
            isActive={isActive}
            isInsideModal={isInsideModal}
            onBackClick={openSettingsSlide}
            currentAccountId={currentAccountId}
            isSlideActive={isSlideActive}
            openMfaPassword={handleOpenInstallConfirmation}
            openMfaInstalled={handleOpenMfaInstalled}
          />
        );
      case SLIDES.confirmMfaInstallation:
        return (
          <MfaPassword
            isActive={isActive}
            isInsideModal={isInsideModal}
            onBackClick={handleOpenMfa}
            openMfaInstalled={handleOpenMfaInstalled}
            openMfa={handleOpenMfa}
          />
        );
      case SLIDES.mfaInstalled:
        return (
          <MfaInstalled
            isSlideActive={isSlideActive}
            onClick={handleOpenMfa}
          />
        );

      default:
        return undefined;
    }
  }

  return (
    <>
      <Transition
        direction={previousSlide === SLIDES.password && currentSlide === SLIDES.settings ? -1 : 'auto'}
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={buildClassName(styles.slide, isInsideModal && modalStyles.transitionSlide)}
        activeKey={currentSlide}
        nextKey={nextKey}
        shouldCleanup
      >
        {renderContent}
      </Transition>
      <BiometricsWarningModal
        isOpen={biometricsState === BiometricsState.TurnOffWarning}
        title={lang('Turn Off Biometrics')}
        description={CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
          ? lang(getDoesUsePinPad()
            ? 'If you turn off biometric protection, you will need to create a passcode.'
            : 'If you turn off biometric protection, you will need to create a password.')
          : lang('Are you sure you want to disable biometric authentication?')}
        onClose={handleBiometricsClose}
        onConfirm={handleDisableBiometricsProceed}
      />
      <BiometricsWarningModal
        isOpen={isTurnOnWarningOpen}
        title={lang('Turn On Biometrics')}
        description={lang(getDoesUsePinPad()
          ? 'Enabling biometric confirmation will reset the passcode.'
          : 'Enabling biometric confirmation will reset the password.')}
        onClose={() => setIsTurnOnWarningOpen(false)}
        onConfirm={handleBiometricTurnOnConfirm}
      />
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isPasswordNumeric, autolockValue, isAppLockEnabled, isAutoConfirmEnabled,
  } = global.settings;

  const currentAccountId = selectCurrentAccountId(global)!;
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  const isAllowSuspiciousActions = selectIsAllowSuspiciousActions(global, currentAccountId);
  const isMultichainAccount = selectIsMultichainAccount(global, currentAccountId);
  const isMnemonicAccount = selectIsMnemonicAccount(global);
  const currentAccount = selectCurrentAccount(global);
  const hasCurrentAccountMfa = Boolean(currentAccount?.byChain.ton?.mfa);
  const isMfaEnabled = selectCurrentAccountState(global)?.config?.isMfaEnabled ?? false;

  return {
    isBiometricAuthEnabled,
    isMultichainAccount,
    isPasswordNumeric,
    isAppLockEnabled,
    autolockValue,
    isAutoConfirmEnabled,
    isAllowSuspiciousActions,
    shouldShowBackup: isMnemonicAccount,
    isLoading: global.auth.isLoading,
    currentAccountId,
    biometricsState: global.biometrics.state,
    biometricsError: global.biometrics.error,
    isMfaEnabled,
    hasCurrentAccountMfa,
  };
})(SettingsSecurity));

function getInitialBackupState(
  global: GlobalState,
  currentAccountId: string,
  isMultichainAccount: boolean,
): { slide: BackupSlide; backupType: 'key' | 'words'; hasMnemonicWallet: boolean } {
  const account = selectAccount(global, currentAccountId);
  const hasMnemonicWallet = !account?.isPrivateKeyBased;

  if (!isMultichainAccount) {
    return {
      slide: BackupSlide.SafetyRules,
      backupType: hasMnemonicWallet ? 'words' : 'key',
      hasMnemonicWallet,
    };
  }

  return {
    slide: BackupSlide.Menu,
    backupType: 'words',
    hasMnemonicWallet,
  };
}
