import { Dialog } from '@capacitor/dialog';
import { AndroidSettings, IOSSettings, NativeSettings } from 'capacitor-native-settings';
import React, { memo, useEffect, useLayoutEffect, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { AutolockValueType } from '../../global/types';
import { SettingsState } from '../../global/types';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  ANIMATED_STICKER_HUGE_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  APP_NAME,
  AUTO_CONFIRM_DURATION_MINUTES,
  AUTOLOCK_OPTIONS_LIST,
  DEFAULT_AUTOLOCK_OPTION,
  IS_CAPACITOR,
  PIN_LENGTH,
} from '../../config';
import {
  selectCurrentAccountId,
  selectIsAllowSuspiciousActions,
  selectIsBiometricAuthEnabled,
  selectIsMnemonicAccount,
  selectIsMultichainAccount,
  selectIsNativeBiometricAuthEnabled,
} from '../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../util/authApi/inMemoryPasswordStore';
import { getDoesUsePinPad, getIsNativeBiometricAuthSupported } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { vibrateOnSuccess } from '../../util/haptics';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { pause } from '../../util/schedulers';
import { getIsTelegramBiometricsRestricted } from '../../util/telegram';
import { IS_BIOMETRIC_AUTH_SUPPORTED, IS_ELECTRON, IS_IOS, IS_IOS_APP } from '../../util/windowEnvironment';
import { callApi } from '../../api';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious from '../../hooks/usePrevious';
import useScrolledState from '../../hooks/useScrolledState';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Collapsible from '../ui/Collapsible';
import CreatePasswordForm from '../ui/CreatePasswordForm';
import Dropdown, { type DropdownItem } from '../ui/Dropdown';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import PinPad from '../ui/PinPad';
import Switcher from '../ui/Switcher';
import Transition from '../ui/Transition';
import Backup from './backup/Backup';
import BackupPrivateKey from './backup/BackupPrivateKey';
import BackupSafetyRules from './backup/BackupSafetyRules';
import BackupSecretWords from './backup/BackupSecretWords';
import NativeBiometricsToggle from './biometrics/NativeBiometricsToggle';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Settings.module.scss';

import backupImg from '../../assets/settings/settings_backup.svg';
import biometricsImg from '../../assets/settings/settings_biometrics.svg';

export const enum SLIDES {
  password,
  settings,
  newPassword,
  createNewPin,
  confirmNewPin,
  passwordChanged,
  backup,
  safetyRules,
  privateKey,
  secretWords,
}

const SWITCH_CONFIRM_PASSCODE_PAUSE_MS = 500;
const CHANGE_PASSWORD_PAUSE_MS = 1500;

interface OwnProps {
  isActive: boolean;
  handleBackClick: NoneToVoidFunction;
  isInsideModal?: boolean;
  isAutoUpdateEnabled: boolean;
  onAutoUpdateEnabledToggle: VoidFunction;
  onSettingsClose: VoidFunction;
}

interface StateProps {
  isBiometricAuthEnabled: boolean;
  isNativeBiometricAuthEnabled: boolean;
  isPasswordNumeric?: boolean;
  isMultichainAccount: boolean;
  isAppLockEnabled?: boolean;
  autolockValue?: AutolockValueType;
  isAutoConfirmEnabled?: boolean;
  isAllowSuspiciousActions?: boolean;
  shouldShowBackup: boolean;
  isLoading?: boolean;
  currentAccountId: string;
}

const INITIAL_CHANGE_PASSWORD_SLIDE = getDoesUsePinPad() ? SLIDES.createNewPin : SLIDES.newPassword;

function SettingsSecurity({
  isActive,
  handleBackClick: navigateBackToSettings,
  isInsideModal,
  isBiometricAuthEnabled,
  isNativeBiometricAuthEnabled,
  isPasswordNumeric,
  isMultichainAccount,
  isAppLockEnabled,
  autolockValue = DEFAULT_AUTOLOCK_OPTION,
  isAutoConfirmEnabled,
  isAllowSuspiciousActions,
  isAutoUpdateEnabled,
  currentAccountId,
  onSettingsClose,
  onAutoUpdateEnabledToggle,
  isLoading,
  shouldShowBackup,
}: OwnProps & StateProps) {
  const {
    setIsPinAccepted,
    clearIsPinAccepted,
    disableNativeBiometrics,
    enableNativeBiometrics,
    openBiometricsTurnOffWarning,
    openBiometricsTurnOn,
    setSettingsState,
    setAppLockValue,
    setIsAutoConfirmEnabled,
    setIsAllowSuspiciousActions,
    setIsAuthLoading,
    setInMemoryPassword,
  } = getActions();

  const lang = useLang();
  const {
    isScrolled,
    handleScroll: handleContentScroll,
  } = useScrolledState();

  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.password);
  const previousSlide = usePrevious(currentSlide);
  const [nextKey, setNextKey] = useState<SLIDES | undefined>(SLIDES.settings);
  const [passwordError, setPasswordError] = useState<string>();
  const [password, setPassword] = useState<string>();
  const [backupType, setBackupType] = useState<'key' | 'words' | undefined>(undefined);
  const [hasMnemonicWallet, setHasMnemonicWallet] = useState<boolean>(false);

  // For Capacitor only
  const [pinValue, setPinValue] = useState<string>('');
  const [confirmPinValue, setConfirmPinValue] = useState<string>('');

  const clearPasswordError = useLastCallback(() => {
    setPasswordError(undefined);
  });

  const cleanup = useLastCallback((shouldKeepCurrentPassword?: boolean) => {
    if (!shouldKeepCurrentPassword) setPassword(undefined);
    setPinValue('');
    setConfirmPinValue('');
    clearPasswordError();
    clearIsPinAccepted();
  });

  const handleBackToSettingsClick = useLastCallback(() => {
    navigateBackToSettings();
    cleanup();
  });

  const openConfirmNewPinSlide = useLastCallback(() => {
    setCurrentSlide(SLIDES.confirmNewPin);
    setNextKey(SLIDES.settings);
  });

  const openSettingsSlide = useLastCallback(() => {
    setCurrentSlide(SLIDES.settings);
    setNextKey(undefined);
    cleanup(true);
  });

  const openBackupPage = useLastCallback(() => {
    if (!isMultichainAccount) {
      openSettingsSlide();
      return;
    }

    setCurrentSlide(SLIDES.backup);
    setNextKey(SLIDES.safetyRules);
  });

  const openNewPasswordSlide = useLastCallback(() => {
    setCurrentSlide(INITIAL_CHANGE_PASSWORD_SLIDE);
    setNextKey(SLIDES.settings);
  });

  const openPasswordChangedSlide = useLastCallback(() => {
    setCurrentSlide(SLIDES.passwordChanged);
    setNextKey(SLIDES.settings);
  });

  useLayoutEffect(() => {
    if (password === undefined && isActive) {
      setCurrentSlide(SLIDES.password);
    } else if (!isActive) cleanup();
  }, [password, isActive]);

  useHistoryBack({ isActive, onBack: handleBackToSettingsClick });

  const handlePasswordSubmit = useLastCallback(async (enteredPassword: string) => {
    const result = await callApi('verifyPassword', enteredPassword);

    if (!result) {
      const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
      setPasswordError(error);
      return;
    }

    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
    }

    openSettingsSlide();
    setPassword(enteredPassword);
  });

  const handleNewPasswordSubmit = useLastCallback(async (enteredPassword: string) => {
    await callApi('changePassword', password!, enteredPassword);
    setIsAuthLoading({ isLoading: true });
    setPassword(enteredPassword);
    setInMemoryPassword({ password: enteredPassword });
    if (isNativeBiometricAuthEnabled) {
      disableNativeBiometrics();
      enableNativeBiometrics({ password: enteredPassword });
    }
    if (getDoesUsePinPad()) {
      openSettingsSlide();
    } else {
      openPasswordChangedSlide();
    }
    setIsAuthLoading({ isLoading: undefined });
  });

  const handlePinSubmit = useLastCallback(async (enteredPassword: string) => {
    setPinValue(enteredPassword);
    await vibrateOnSuccess(true);
    await pause(SWITCH_CONFIRM_PASSCODE_PAUSE_MS);
    openConfirmNewPinSlide();
  });

  const handleConfirmPinSubmit = useLastCallback(async (enteredPassword: string) => {
    if (enteredPassword === pinValue) {
      setPasswordError(lang('New code set successfully'));
      await pause(CHANGE_PASSWORD_PAUSE_MS);
      await handleNewPasswordSubmit(enteredPassword);
    } else {
      setPasswordError(lang('Codes don’t match'));
      await pause(CHANGE_PASSWORD_PAUSE_MS);
      cleanup(true);
      setCurrentSlide(SLIDES.createNewPin);
    }
  });

  const handleChangePasswordClick = useLastCallback(() => {
    setNextKey(INITIAL_CHANGE_PASSWORD_SLIDE);
    openNewPasswordSlide();
  });

  const handleOpenPrivateKeySafetyRules = useLastCallback(() => {
    setBackupType('key');
    setCurrentSlide(SLIDES.safetyRules);
    setNextKey(SLIDES.privateKey);
  });

  const handleOpenSecretWordsSafetyRules = useLastCallback(() => {
    setBackupType('words');
    setCurrentSlide(SLIDES.safetyRules);
    setNextKey(SLIDES.secretWords);
  });

  const handleOpenBackupWallet = useLastCallback(() => {
    if (!isMultichainAccount) {
      if (hasMnemonicWallet) {
        handleOpenSecretWordsSafetyRules();
      } else {
        handleOpenPrivateKeySafetyRules();
      }
      return;
    }

    setCurrentSlide(SLIDES.backup);
    // Resetting next key to undefined unmounts and destroys components with mnemonic and private key
    setNextKey(undefined);
  });

  const handleOpenPrivateKey = useLastCallback(() => {
    setCurrentSlide(SLIDES.privateKey);
    setNextKey(SLIDES.backup);
  });

  const handleOpenSecretWords = useLastCallback(() => {
    setCurrentSlide(SLIDES.secretWords);
    setNextKey(SLIDES.backup);
  });

  const handleAppLockToggle = useLastCallback(() => {
    setAppLockValue({ value: autolockValue, isEnabled: !isAppLockEnabled });
  });

  const handleAutolockChange = useLastCallback((value: AutolockValueType) => {
    setAppLockValue({ value, isEnabled: true });
  });

  const handleAutoConfirmToggle = useLastCallback(() => {
    setIsAutoConfirmEnabled({ isEnabled: !isAutoConfirmEnabled });
  });

  const handleAllowSuspiciousActionsToggle = useLastCallback(() => {
    setIsAllowSuspiciousActions({ isEnabled: !isAllowSuspiciousActions });
  });

  // Biometrics
  const handleBiometricAuthToggle = useLastCallback(() => {
    if (isBiometricAuthEnabled) {
      openBiometricsTurnOffWarning();
    } else {
      openBiometricsTurnOn();
    }
  });
  const handleNativeBiometricsTurnOnOpen = useLastCallback(async () => {
    if (getIsNativeBiometricAuthSupported()) {
      setSettingsState({ state: SettingsState.NativeBiometricsTurnOn });
      return;
    }

    const warningDescription = IS_IOS
      ? 'To use this feature, first enable Face ID in your phone settings.'
      : 'To use this feature, first enable biometrics in your phone settings.';

    const { value } = await Dialog.confirm({
      title: lang('Warning!'),
      message: lang(warningDescription),
      okButtonTitle: lang('Open Settings'),
      cancelButtonTitle: lang('Cancel'),
    });
    if (value) {
      await NativeSettings.open({
        optionAndroid: AndroidSettings.ApplicationDetails,
        optionIOS: IOSSettings.App,
      });
    }
  });

  useEffect(() => {
    if (!password) return;

    void callApi('fetchMnemonic', currentAccountId, password).then((mnemonic) => {
      setHasMnemonicWallet(Boolean(mnemonic && !isMnemonicPrivateKey(mnemonic)));
    });
  }, [hasMnemonicWallet, currentAccountId, password]);

  // The `getIsTelegramBiometricsRestricted` case is required to display a toggle switch.
  // When activated, it will show a warning to the user indicating that they need to grant
  // the appropriate permissions for biometric authentication to function properly.
  const shouldRenderNativeBiometrics = (
    getIsNativeBiometricAuthSupported() || IS_IOS_APP || getIsTelegramBiometricsRestricted()
  );
  const shouldRenderMinifiedPinPad = isInsideModal && getDoesUsePinPad();

  const isAutoConfirmAvailable = !isBiometricAuthEnabled;

  function renderSettings() {
    return (
      <div className={styles.slide}>
        {isInsideModal ? (
          <ModalHeader
            title={lang('Security')}
            withNotch={isScrolled}
            onBackButtonClick={handleBackToSettingsClick}
            className={styles.modalHeader}
          />
        ) : (
          <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
            <Button isSimple isText onClick={handleBackToSettingsClick} className={styles.headerBack}>
              <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
              <span>{lang('Back')}</span>
            </Button>
            <span className={styles.headerTitle}>{lang('Security')}</span>
          </div>
        )}
        <div
          className={buildClassName(styles.content, 'custom-scroll')}
          onScroll={handleContentScroll}
        >
          {shouldShowBackup && (
            <div className={styles.settingsBlock}>
              <div className={buildClassName(styles.item)} onClick={handleOpenBackupWallet}>
                <img className={styles.menuIcon} src={backupImg} alt={lang('$back_up_security')} />
                {lang('$back_up_security')}

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
          )}

          {shouldRenderNativeBiometrics && (
            <NativeBiometricsToggle
              onEnable={handleNativeBiometricsTurnOnOpen}
            />
          )}
          {IS_BIOMETRIC_AUTH_SUPPORTED && (
            <>
              <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
                <div className={styles.item} onClick={handleBiometricAuthToggle}>
                  <img className={styles.menuIcon} src={biometricsImg} alt={lang('Biometric Authentication')} />
                  {lang('Biometric Authentication')}

                  <Switcher
                    className={styles.menuSwitcher}
                    label={lang('Biometric Authentication')}
                    checked={isBiometricAuthEnabled}
                  />
                </div>
              </div>
              <p className={styles.blockDescription}>{
                lang(getDoesUsePinPad()
                  ? 'To avoid entering the passcode every time, you can use biometrics.'
                  : 'To avoid entering the password every time, you can use biometrics.')
              }
              </p>
            </>
          )}

          {!(isBiometricAuthEnabled && !isNativeBiometricAuthEnabled) && (
            <>
              <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
                <Button
                  className={styles.changePasswordButton}
                  isSimple
                  onClick={handleChangePasswordClick}
                >
                  {getDoesUsePinPad() ? lang('Change Passcode') : lang('Change Password')}
                </Button>
              </div>
              <p className={styles.blockDescription}>{
                lang(getDoesUsePinPad()
                  ? 'The passcode will be changed for all your wallets.'
                  : 'The password will be changed for all your wallets.')
              }
              </p>
            </>
          )}

          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={buildClassName(styles.item, styles.itemSmall)} onClick={handleAppLockToggle}>
                {lang('App Lock')}

                <Switcher
                  className={styles.menuSwitcher}
                  label={lang('Allow App Lock')}
                  checked={isAppLockEnabled}
                />
              </div>
              <Collapsible isShown={!!isAppLockEnabled}>
                <Dropdown
                  label={lang('Auto-Lock')}
                  items={AUTOLOCK_OPTIONS_LIST as unknown as DropdownItem<AutolockValueType>[]}
                  selectedValue={autolockValue}
                  theme="light"
                  shouldTranslateOptions
                  className={buildClassName(styles.item, styles.item_small, styles.itemAutoLock)}
                  onChange={handleAutolockChange}
                />
              </Collapsible>
            </div>
            <p className={styles.blockDescription}>{lang('$app_lock_description', { app_name: APP_NAME })}</p>

            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div
                className={buildClassName(
                  styles.item,
                  styles.itemSmall,
                  !isAutoConfirmAvailable && styles.itemDisabled,
                )}
                onClick={isAutoConfirmAvailable ? handleAutoConfirmToggle : undefined}
              >
                {getDoesUsePinPad() ? lang('Remember Passcode') : lang('Remember Password')}

                <Switcher
                  className={styles.menuSwitcher}
                  label={getDoesUsePinPad() ? lang('Remember Passcode') : lang('Remember Password')}
                  checked={isAutoConfirmAvailable && isAutoConfirmEnabled}
                />
              </div>
            </div>
            <p className={styles.blockDescription}>
              {
                lang(
                  'App will not ask for signature for %1$d minutes after last entry.',
                  AUTO_CONFIRM_DURATION_MINUTES,
                )
              }
              {!isAutoConfirmAvailable && ` ${lang('Not available with biometrics.')}`}
            </p>
          </>

          {IS_ELECTRON && (
            <>
              <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
                <div className={buildClassName(styles.item, styles.item_small)} onClick={onAutoUpdateEnabledToggle}>
                  {lang('Auto-Updates')}

                  <Switcher
                    className={styles.menuSwitcher}
                    label={lang('Auto-Updates')}
                    checked={isAutoUpdateEnabled}
                  />
                </div>
              </div>
              <p className={styles.blockDescription}>
                {lang('Turn this off so you can manually download updates and verify signatures.')}
              </p>
            </>
          )}

          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div
                className={buildClassName(styles.item, styles.itemSmall)}
                onClick={handleAllowSuspiciousActionsToggle}
              >
                {lang('Allow Suspicious Actions')}

                <Switcher
                  className={styles.menuSwitcher}
                  label={lang('Allow Suspicious Actions')}
                  checked={isAllowSuspiciousActions}
                />
              </div>
            </div>
            <p className={styles.blockDescription}>
              {lang('$allow_suspicious_actions_description')}
            </p>
          </>
        </div>
      </div>
    );
  }

  function renderContent(isSlideActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.settings:
        return renderSettings();
      case SLIDES.password:
        if (getHasInMemoryPassword()) {
          setCurrentSlide(SLIDES.settings);
          void getInMemoryPassword().then((memoizedPassword) => setPassword(memoizedPassword));

          return undefined;
        }
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                title={isPasswordNumeric ? lang('Confirm Passcode') : lang('Confirm Password')}
                onBackButtonClick={handleBackToSettingsClick}
                className={styles.modalHeader}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={handleBackToSettingsClick} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
                <span className={styles.headerTitle}>{lang('Enter Password')}</span>
              </div>
            )}
            <PasswordForm
              isActive={isSlideActive && isActive}
              error={passwordError}
              containerClassName={IS_CAPACITOR ? styles.passwordFormContent : styles.passwordFormContentInModal}
              forceBiometricsInMain={!isInsideModal}
              placeholder={lang('Enter your current password')}
              submitLabel={lang('Continue')}
              noAutoConfirm
              onCancel={handleBackToSettingsClick}
              onSubmit={handlePasswordSubmit}
              onUpdate={clearPasswordError}
            />
          </>
        );
      case SLIDES.newPassword:
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                title={lang('Change Password')}
                onBackButtonClick={openSettingsSlide}
                className={styles.modalHeader}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={openSettingsSlide} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
                <span className={styles.headerTitle}>{lang('Change Password')}</span>
              </div>
            )}
            <div className={buildClassName(
              modalStyles.transitionContent,
              styles.content,
              isInsideModal && styles.contentInModal,
            )}
            >
              <AnimatedIconWithPreview
                tgsUrl={ANIMATED_STICKERS_PATHS.guard}
                previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
                play={isSlideActive}
                size={ANIMATED_STICKER_BIG_SIZE_PX}
                nonInteractive
                noLoop={false}
                className={styles.sticker}
              />
              <CreatePasswordForm
                isActive={isSlideActive}
                isLoading={isLoading}
                onSubmit={handleNewPasswordSubmit}
                onCancel={openSettingsSlide}
                formId="auth-create-password"
              />
            </div>
          </>
        );
      case SLIDES.createNewPin:
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                onBackButtonClick={openSettingsSlide}
                className={styles.modalHeader}
                title={shouldRenderMinifiedPinPad && lang('Change Passcode')}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={openSettingsSlide} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
              </div>
            )}

            <div
              className={buildClassName(styles.pinPadHeader, shouldRenderMinifiedPinPad && styles.pinPadHeaderMinified)}
            >
              <AnimatedIconWithPreview
                play={isActive}
                tgsUrl={ANIMATED_STICKERS_PATHS.guard}
                previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
                noLoop={false}
                size={shouldRenderMinifiedPinPad ? ANIMATED_STICKER_SMALL_SIZE_PX : ANIMATED_STICKER_HUGE_SIZE_PX}
                nonInteractive
              />
              {!shouldRenderMinifiedPinPad && <div className={styles.pinPadTitle}>{lang('Change Passcode')}</div>}
            </div>
            <PinPad
              isActive={isActive}
              title={lang('Enter your new code')}
              length={PIN_LENGTH}
              value={pinValue}
              onChange={setPinValue}
              onSubmit={handlePinSubmit}
              isMinified={shouldRenderMinifiedPinPad}
            />
          </>
        );
      case SLIDES.confirmNewPin:
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                onBackButtonClick={openSettingsSlide}
                className={styles.modalHeader}
                title={shouldRenderMinifiedPinPad && (
                  passwordError && pinValue === confirmPinValue
                    ? lang('Passcode Changed!')
                    : lang('Change Passcode')
                )}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={openSettingsSlide} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
              </div>
            )}

            <div
              className={buildClassName(styles.pinPadHeader, shouldRenderMinifiedPinPad && styles.pinPadHeaderMinified)}
            >
              <AnimatedIconWithPreview
                play={isActive}
                tgsUrl={ANIMATED_STICKERS_PATHS.guard}
                previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
                noLoop={false}
                size={shouldRenderMinifiedPinPad ? ANIMATED_STICKER_SMALL_SIZE_PX : ANIMATED_STICKER_HUGE_SIZE_PX}
                nonInteractive
              />
              {
                !shouldRenderMinifiedPinPad && (
                  <div className={styles.pinPadTitle}>
                    {
                      passwordError && pinValue === confirmPinValue
                        ? lang('Passcode Changed!')
                        : lang('Change Passcode')
                    }
                  </div>
                )
              }
            </div>

            <PinPad
              isActive={isActive}
              title={!passwordError ? lang('Re-enter your new code') : passwordError}
              type={passwordError ? (pinValue === confirmPinValue ? 'success' : 'error') : undefined}
              length={PIN_LENGTH}
              value={confirmPinValue}
              onChange={setConfirmPinValue}
              onSubmit={handleConfirmPinSubmit}
              isMinified={shouldRenderMinifiedPinPad}
            />
          </>
        );
      case SLIDES.passwordChanged:
        return (
          <>
            {isInsideModal ? (
              <ModalHeader
                title={lang('Password Changed!')}
                className={styles.modalHeader}
              />
            ) : (
              <div className={buildClassName(styles.header, styles.onlyTextHeader)}>
                <span className={styles.headerTitle}>{lang('Password Changed!')}</span>
              </div>
            )}
            <div className={styles.content}>
              <AnimatedIconWithPreview
                tgsUrl={ANIMATED_STICKERS_PATHS.yeee}
                previewUrl={ANIMATED_STICKERS_PATHS.yeeePreview}
                play={isActive}
                size={ANIMATED_STICKER_HUGE_SIZE_PX}
                nonInteractive
                noLoop={false}
                className={buildClassName(styles.sticker, styles.stickerHuge)}
              />

              <div className={modalStyles.buttons}>
                <Button isPrimary onClick={openSettingsSlide} className={modalStyles.customSubmitButton}>
                  {lang('Done')}
                </Button>
              </div>
            </div>
          </>
        );
      case SLIDES.backup:
        return (
          <Backup
            isActive={isActive && isSlideActive}
            isMultichainAccount={isMultichainAccount}
            openSettingsSlide={openSettingsSlide}
            isInsideModal={isInsideModal}
            onOpenPrivateKeySafetyRules={handleOpenPrivateKeySafetyRules}
            onOpenSecretWordsSafetyRules={handleOpenSecretWordsSafetyRules}
            onBackClick={handleBackToSettingsClick}
            hasMnemonicWallet={hasMnemonicWallet}
          />
        );
      case SLIDES.safetyRules:
        return (
          <BackupSafetyRules
            isActive={isActive && isSlideActive}
            isInsideModal={isInsideModal}
            backupType={backupType!}
            onBackClick={openBackupPage}
            onSubmit={
              backupType === 'key'
                ? handleOpenPrivateKey
                : handleOpenSecretWords
            }
          />
        );
      case SLIDES.secretWords:
        return (
          <BackupSecretWords
            isActive={isActive && isSlideActive}
            isBackupSlideActive={currentKey === SLIDES.secretWords || currentKey === SLIDES.safetyRules}
            isInsideModal={isInsideModal}
            enteredPassword={password}
            currentAccountId={currentAccountId}
            onBackClick={openBackupPage}
            onSubmit={onSettingsClose}
          />
        );
      case SLIDES.privateKey:
        return (
          <BackupPrivateKey
            isActive={isActive && isSlideActive}
            isBackupSlideActive={currentKey === SLIDES.privateKey || currentKey === SLIDES.safetyRules}
            isInsideModal={isInsideModal}
            enteredPassword={password}
            currentAccountId={currentAccountId}
            onBackClick={openBackupPage}
            onSubmit={onSettingsClose}
          />
        );
    }
  }

  return (
    <Transition
      direction={previousSlide === SLIDES.password && currentSlide === SLIDES.settings ? 1 : 'auto'}
      name={resolveSlideTransitionName()}
      className={buildClassName(modalStyles.transition, 'custom-scroll')}
      slideClassName={buildClassName(styles.slide, isInsideModal && modalStyles.transitionSlide)}
      activeKey={currentSlide}
      nextKey={nextKey}
      shouldCleanup
    >
      {renderContent}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isPasswordNumeric, autolockValue, isAppLockEnabled, isAutoConfirmEnabled,
  } = global.settings;

  const currentAccountId = selectCurrentAccountId(global)!;
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  const isNativeBiometricAuthEnabled = selectIsNativeBiometricAuthEnabled(global);
  const isAllowSuspiciousActions = selectIsAllowSuspiciousActions(global, currentAccountId);
  const isMultichainAccount = selectIsMultichainAccount(global, currentAccountId);
  const isMnemonicAccount = selectIsMnemonicAccount(global);

  return {
    isBiometricAuthEnabled,
    isNativeBiometricAuthEnabled,
    isMultichainAccount,
    isPasswordNumeric,
    isAppLockEnabled,
    autolockValue,
    isAutoConfirmEnabled,
    isAllowSuspiciousActions,
    shouldShowBackup: isMnemonicAccount,
    isLoading: global.auth.isLoading,
    currentAccountId,
  };
})(SettingsSecurity));
