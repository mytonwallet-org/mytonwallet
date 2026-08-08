import React, { memo } from '../../../lib/teact/teact';

import type { AutolockValueType } from '../../../global/types';

import {
  APP_NAME,
  AUTO_CONFIRM_DURATION_MINUTES,
  AUTOLOCK_OPTIONS_LIST,
  DEFAULT_AUTOLOCK_OPTION,
} from '../../../config';
import {
  getDoesUsePinPad,
  getIsBiometricAuthSupported,
  getIsFaceIdAvailable,
  getIsTouchIdAvailable,
} from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { getIsTelegramBiometricsRestricted } from '../../../util/telegram';
import { CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY, IS_ELECTRON, IS_IOS } from '../../../util/windowEnvironment';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Button from '../../ui/Button';
import Collapsible from '../../ui/Collapsible';
import Dropdown, { type DropdownItem } from '../../ui/Dropdown';
import ModalHeader from '../../ui/ModalHeader';
import Switcher from '../../ui/Switcher';

import styles from '../Settings.module.scss';

import mfaImg from '../../../assets/settings/settings_2fa.svg';
import backupImg from '../../../assets/settings/settings_backup.svg';
import biometricsImg from '../../../assets/settings/settings_biometrics.svg';
import faceIdImg from '../../../assets/settings/settings_face-id.svg';

interface OwnProps {
  isInsideModal?: boolean;
  isBiometricAuthEnabled: boolean;
  isAppLockEnabled?: boolean;
  autolockValue: AutolockValueType;
  isAutoConfirmEnabled?: boolean;
  isAllowSuspiciousActions?: boolean;
  isAutoUpdateEnabled: boolean;
  shouldShowBackup: boolean;
  isMfaVisible?: boolean;
  onBackClick: NoneToVoidFunction;
  onChangePasswordClick: NoneToVoidFunction;
  onOpenBackupWallet: NoneToVoidFunction;
  onOpenMfa?: NoneToVoidFunction;
  onBiometricAuthToggle: NoneToVoidFunction;
  onAppLockToggle: NoneToVoidFunction;
  onAutolockChange: (value: AutolockValueType) => void;
  onAutoConfirmToggle: NoneToVoidFunction;
  onAllowSuspiciousActionsToggle: NoneToVoidFunction;
  onAutoUpdateToggle: NoneToVoidFunction;
}

function SecurityMain({
  isInsideModal,
  isBiometricAuthEnabled,
  isAppLockEnabled,
  autolockValue = DEFAULT_AUTOLOCK_OPTION,
  isAutoConfirmEnabled,
  isAllowSuspiciousActions,
  isAutoUpdateEnabled,
  shouldShowBackup,
  isMfaVisible,
  onBackClick,
  onChangePasswordClick,
  onOpenBackupWallet,
  onOpenMfa,
  onBiometricAuthToggle,
  onAppLockToggle,
  onAutolockChange,
  onAutoConfirmToggle,
  onAllowSuspiciousActionsToggle,
  onAutoUpdateToggle,
}: OwnProps) {
  const lang = useLang();

  const {
    isScrolled,
    handleScroll: handleContentScroll,
  } = useScrolledState();

  const isBiometricsAvailable = getIsBiometricAuthSupported();

  // Platform-specific biometric label and icon
  const isFaceId = getIsFaceIdAvailable() || IS_IOS;
  const isTouchId = getIsTouchIdAvailable();
  const biometricLabel = isFaceId ? 'Face ID' : (isTouchId ? 'Touch ID' : lang('Biometric Authentication'));
  const biometricIcon = isFaceId ? faceIdImg : biometricsImg;

  const isAutoConfirmAvailable = !isBiometricAuthEnabled;

  const biometricDescription = lang(getDoesUsePinPad()
    ? 'To avoid entering the passcode every time, you can use biometrics.'
    : 'To avoid entering the password every time, you can use biometrics.');

  const handleBiometricToggle = useLastCallback(async () => {
    if (getIsTelegramBiometricsRestricted()) {
      const { getTelegramApp } = await import('../../../util/telegram');
      getTelegramApp()?.BiometricManager.openSettings();
      return;
    }

    onBiometricAuthToggle();
  });

  return (
    <div className={styles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('Security')}
          withNotch={isScrolled}
          onBackButtonClick={onBackClick}
          className={styles.modalHeader}
        />
      ) : (
        <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={onBackClick} className={styles.headerBack}>
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
            <div className={buildClassName(styles.item)} onClick={onOpenBackupWallet}>
              <img className={styles.menuIcon} src={backupImg} alt={lang('$back_up_security')} />
              <span className={styles.itemTitle}>{lang('$back_up_security')}</span>

              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
          </div>
        )}

        {(isBiometricsAvailable || IS_IOS || getIsTelegramBiometricsRestricted()) && (
          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={styles.item} onClick={handleBiometricToggle}>
                <img className={styles.menuIcon} src={biometricIcon} alt={biometricLabel} />
                <span className={styles.itemTitle}>{biometricLabel}</span>

                <Switcher
                  className={styles.menuSwitcher}
                  label={biometricLabel}
                  checked={isBiometricAuthEnabled}
                />
              </div>
            </div>
            <p className={styles.blockDescription}>{biometricDescription}</p>
          </>
        )}

        {!(isBiometricAuthEnabled && CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY) && (
          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <Button
                className={styles.changePasswordButton}
                isSimple
                onClick={onChangePasswordClick}
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

        {isMfaVisible && (
          <>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={buildClassName(styles.item)} onClick={onOpenMfa}>
                <img className={styles.menuIcon} src={mfaImg} alt={lang('2FA with Telegram')} />

                <span className={styles.textWithBadge}>
                  {lang('2FA with Telegram')}
                  <span className={styles.badge}>TON</span>
                </span>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
            <p className={styles.blockDescription}>{lang('Confirm operations in Telegram as a second step.')}</p>
          </>
        )}

        <>
          <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
            <div className={buildClassName(styles.item, styles.itemSmall)} onClick={onAppLockToggle}>
              <span className={styles.itemTitle}>{lang('App Lock')}</span>

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
                labelClassName={styles.itemAutoLockLabel}
                onChange={onAutolockChange}
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
              onClick={isAutoConfirmAvailable ? onAutoConfirmToggle : undefined}
            >
              <span className={styles.itemTitle}>
                {getDoesUsePinPad() ? lang('Remember Passcode') : lang('Remember Password')}
              </span>

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
              <div className={buildClassName(styles.item, styles.item_small)} onClick={onAutoUpdateToggle}>
                <span className={styles.itemTitle}>{lang('Auto-Updates')}</span>

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
              onClick={onAllowSuspiciousActionsToggle}
            >
              <span className={styles.itemTitle}>{lang('Allow Suspicious Actions')}</span>

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

export default memo(SecurityMain);
