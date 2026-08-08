import React, { memo, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  ANIMATED_STICKER_HUGE_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  PIN_LENGTH,
} from '../../../config';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { vibrateOnSuccess } from '../../../util/haptics';
import { pause } from '../../../util/schedulers';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import CreatePasswordForm from '../../ui/CreatePasswordForm';
import ModalHeader from '../../ui/ModalHeader';
import PinPad from '../../ui/PinPad';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

export const enum ChangePasscodeSlide {
  NewPassword,
  CreateNewPin,
  ConfirmNewPin,
  PasswordChanged,
}

const SWITCH_CONFIRM_PASSCODE_PAUSE_MS = 500;
const CHANGE_PASSWORD_PAUSE_MS = 1500;

interface OwnProps {
  isActive: boolean;
  isSlideActive: boolean;
  currentSlide: ChangePasscodeSlide;
  isInsideModal?: boolean;
  isLoading?: boolean;
  onSlideChange: (slide: ChangePasscodeSlide) => void;
  onComplete: NoneToVoidFunction;
  onCancel: NoneToVoidFunction;
}

function ChangePasscodeFlow({
  isActive,
  isSlideActive,
  currentSlide,
  isInsideModal,
  isLoading,
  onSlideChange,
  onComplete,
  onCancel,
}: OwnProps) {
  const { changePasscode, setIsPinAccepted, clearIsPinAccepted } = getActions();
  const lang = useLang();

  const [pinValue, setPinValue] = useState<string>('');
  const [confirmPinValue, setConfirmPinValue] = useState<string>('');
  const [passwordError, setPasswordError] = useState<string>();
  const [pinPadTitle, setPinPadTitle] = useState<string>();

  const shouldRenderMinifiedPinPad = isInsideModal && getDoesUsePinPad();

  const cleanup = useLastCallback(() => {
    setPinValue('');
    setConfirmPinValue('');
    setPasswordError(undefined);
    setPinPadTitle(undefined);
    clearIsPinAccepted();
  });

  const handleNewPasscodeSubmit = useLastCallback((passcode: string) => {
    changePasscode({
      passcode,
      onSuccess: () => {
        if (getDoesUsePinPad()) {
          cleanup();
          onComplete();
        } else {
          onSlideChange(ChangePasscodeSlide.PasswordChanged);
        }
      },
    });
  });

  const handlePinSubmit = useLastCallback(async (pin: string) => {
    setPinValue(pin);
    await vibrateOnSuccess(true);
    await pause(SWITCH_CONFIRM_PASSCODE_PAUSE_MS);
    onSlideChange(ChangePasscodeSlide.ConfirmNewPin);
  });

  const handleConfirmPinSubmit = useLastCallback(async (pin: string) => {
    if (pin === pinValue) {
      setPasswordError(undefined);
      setPinPadTitle('New code set successfully');
      setIsPinAccepted();
      await vibrateOnSuccess(true);
      await pause(CHANGE_PASSWORD_PAUSE_MS);
      handleNewPasscodeSubmit(pin);
    } else {
      setPasswordError(lang('Codes don\u2019t match'));
      setPinPadTitle(undefined);
      await pause(CHANGE_PASSWORD_PAUSE_MS);
      cleanup();
      onSlideChange(ChangePasscodeSlide.CreateNewPin);
    }
  });

  const handleCancel = useLastCallback(() => {
    cleanup();
    onCancel();
  });

  const handleComplete = useLastCallback(() => {
    cleanup();
    onComplete();
  });

  function renderHeader(title: string) {
    if (isInsideModal) {
      return (
        <ModalHeader
          onBackButtonClick={handleCancel}
          className={styles.modalHeader}
          title={title}
        />
      );
    }

    return (
      <div className={styles.header}>
        <Button isSimple isText onClick={handleCancel} className={styles.headerBack}>
          <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
        <span className={styles.headerTitle}>{title}</span>
      </div>
    );
  }

  switch (currentSlide) {
    case ChangePasscodeSlide.NewPassword:
      return (
        <>
          {renderHeader(lang('Change Password'))}
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
              onSubmit={handleNewPasscodeSubmit}
              onCancel={handleCancel}
              formId="auth-create-password"
            />
          </div>
        </>
      );

    case ChangePasscodeSlide.CreateNewPin:
      return (
        <>
          {isInsideModal ? (
            <ModalHeader
              onBackButtonClick={handleCancel}
              className={styles.modalHeader}
              title={shouldRenderMinifiedPinPad && lang('Change Passcode')}
            />
          ) : (
            <div className={styles.header}>
              <Button isSimple isText onClick={handleCancel} className={styles.headerBack}>
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

    case ChangePasscodeSlide.ConfirmNewPin:
      return (
        <>
          {isInsideModal ? (
            <ModalHeader
              onBackButtonClick={handleCancel}
              className={styles.modalHeader}
              title={shouldRenderMinifiedPinPad && (
                passwordError && pinValue === confirmPinValue
                  ? lang('Passcode Changed!')
                  : lang('Change Passcode')
              )}
            />
          ) : (
            <div className={styles.header}>
              <Button isSimple isText onClick={handleCancel} className={styles.headerBack}>
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
            title={pinPadTitle ? lang(pinPadTitle) : (!passwordError ? lang('Re-enter your new code') : passwordError)}
            type={passwordError ? (pinValue === confirmPinValue ? 'success' : 'error') : undefined}
            length={PIN_LENGTH}
            value={confirmPinValue}
            onChange={setConfirmPinValue}
            onSubmit={handleConfirmPinSubmit}
            isMinified={shouldRenderMinifiedPinPad}
          />
        </>
      );

    case ChangePasscodeSlide.PasswordChanged:
      return (
        <>
          {renderHeader(lang('Password Changed!'))}
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
              <Button isPrimary onClick={handleComplete} className={modalStyles.customSubmitButton}>
                {lang('Done')}
              </Button>
            </div>
          </div>
        </>
      );

    default:
      return undefined;
  }
}

export default memo(ChangePasscodeFlow);
