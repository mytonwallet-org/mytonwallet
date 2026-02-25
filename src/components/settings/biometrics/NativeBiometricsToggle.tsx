import { Dialog } from '@capacitor/dialog';
import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { IS_CAPACITOR } from '../../../config';
import renderText from '../../../global/helpers/renderText';
import { selectIsNativeBiometricAuthEnabled } from '../../../global/selectors';
import {
  getIsFaceIdAvailable,
  getIsNativeBiometricAuthSupported,
  getIsTouchIdAvailable,
} from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { getIsTelegramBiometricsRestricted, getTelegramApp } from '../../../util/telegram';
import { IS_IOS } from '../../../util/windowEnvironment';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import Switcher from '../../ui/Switcher';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

import biometricsImg from '../../../assets/settings/settings_biometrics.svg';
import faceIdImg from '../../../assets/settings/settings_face-id.svg';

interface OwnProps {
  onEnable: NoneToVoidFunction;
}

interface StateProps {
  isBiometricAuthEnabled: boolean;
}

function NativeBiometricsToggle({ isBiometricAuthEnabled, onEnable }: OwnProps & StateProps) {
  const { disableNativeBiometrics } = getActions();
  const isFaceId = getIsFaceIdAvailable() || (!getIsNativeBiometricAuthSupported() && IS_IOS);
  const isTouchId = getIsTouchIdAvailable();

  const lang = useLang();
  const [isWarningModalOpen, openWarningModal, closeWarningModal] = useFlag();
  const switcherTitle = isFaceId ? 'Face ID' : (isTouchId ? 'Touch ID' : lang('Biometric Authentication'));
  const warningTitle = isFaceId
    ? 'Turn Off Face ID'
    : (isTouchId ? 'Turn Off Touch ID' : 'Turn Off Biometrics');
  const warningDescription = isFaceId
    ? 'Are you sure you want to disable Face ID?'
    : (isTouchId ? 'Are you sure you want to disable Touch ID?' : 'Are you sure you want to disable biometrics?');

  const icon = isFaceId ? faceIdImg : biometricsImg;

  const handleConfirmDisableBiometrics = useLastCallback(() => {
    closeWarningModal();
    disableNativeBiometrics();
  });

  useSyncEffect(() => {
    if (!IS_CAPACITOR) return;

    if (isWarningModalOpen) {
      void Dialog.confirm({
        title: lang(warningTitle),
        message: lang(warningDescription),
        okButtonTitle: lang('Yes'),
        cancelButtonTitle: lang('Cancel'),
      })
        .then(({ value }) => {
          if (value) {
            handleConfirmDisableBiometrics();
          }
        })
        .finally(closeWarningModal);
    }
  }, [handleConfirmDisableBiometrics, isWarningModalOpen, lang, warningDescription, warningTitle]);

  const handleBiometricAuthToggle = useLastCallback(() => {
    if (getIsTelegramBiometricsRestricted()) {
      getTelegramApp()?.BiometricManager.openSettings();
      return;
    }

    if (isBiometricAuthEnabled) {
      openWarningModal();
    } else {
      onEnable();
    }
  });

  function renderDisableNativeBiometricsWarning() {
    if (IS_CAPACITOR) return undefined;

    return (
      <Modal
        isCompact
        isOpen={isWarningModalOpen}
        title={lang(warningTitle)}
        onClose={closeWarningModal}
        dialogClassName={styles.stakingSafeDialog}
      >
        <p className={modalStyles.text}>
          {renderText(lang(warningDescription))}
        </p>

        <div className={modalStyles.buttons}>
          <Button onClick={closeWarningModal}>{lang('Cancel')}</Button>
          <Button onClick={handleConfirmDisableBiometrics}>{lang('Yes')}</Button>
        </div>
      </Modal>
    );
  }

  return (
    <>
      <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
        <div className={styles.item} onClick={handleBiometricAuthToggle}>
          <img className={styles.menuIcon} src={icon} alt="" />
          {switcherTitle}

          <Switcher
            className={styles.menuSwitcher}
            label={switcherTitle}
            checked={isBiometricAuthEnabled}
          />
        </div>
        {renderDisableNativeBiometricsWarning()}
      </div>
      <p className={styles.blockDescription}>{
        lang('To avoid entering the passcode every time, you can use biometrics.')
      }
      </p>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    isBiometricAuthEnabled: selectIsNativeBiometricAuthEnabled(global),
  };
})(NativeBiometricsToggle));
