import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import { BiometricsState } from '../../../global/types';

import { ANIMATED_STICKER_HUGE_SIZE_PX } from '../../../config';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useModalTransitionKeys from '../../../hooks/useModalTransitionKeys';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import CreatePasswordForm from '../../ui/CreatePasswordForm';
import Modal from '../../ui/Modal';
import ModalHeader from '../../ui/ModalHeader';
import Transition from '../../ui/Transition';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './Biometrics.module.scss';

interface OwnProps {
  isOpen: boolean;
  state: BiometricsState;
  error?: string;
  onClose: NoneToVoidFunction;
  isLoading?: boolean;
  isInsideModal?: boolean;
}

const STICKER_SIZE = 180;

function TurnOff({
  isOpen, isLoading, isInsideModal, state, error, onClose,
}: OwnProps) {
  const { disableBiometrics } = getActions();

  const lang = useLang();
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const handleSubmit = useLastCallback((password: string, isPasswordNumeric?: boolean) => {
    disableBiometrics({ password, isPasswordNumeric });
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: BiometricsState) {
    switch (currentKey) {
      case BiometricsState.TurnOffBiometricConfirmation:
        return (
          <>
            <ModalHeader title={lang('Biometric Confirmation')} onClose={onClose} />
            <div className={modalStyles.transitionContent}>
              <AnimatedIconWithPreview
                tgsUrl={ANIMATED_STICKERS_PATHS.holdTon}
                previewUrl={ANIMATED_STICKERS_PATHS.holdTonPreview}
                play={isActive}
                size={STICKER_SIZE}
                nonInteractive
                noLoop={false}
                className={styles.sticker}
              />

              {error ? (
                <div className={styles.error}>{lang(error)}</div>
              ) : (
                <div className={styles.step}>{lang('Please verify the action.')}</div>
              )}

              <div className={modalStyles.buttons}>
                <Button onClick={onClose} className={modalStyles.customSubmitButton}>
                  {lang('Cancel')}
                </Button>
              </div>
            </div>
          </>
        );

      case BiometricsState.TurnOffCreatePassword:
        return (
          <>
            <ModalHeader title={lang(getDoesUsePinPad() ? 'Create Passcode' : 'Create Password')} onClose={onClose} />
            <div className={modalStyles.transitionContent}>
              <AnimatedIconWithPreview
                tgsUrl={ANIMATED_STICKERS_PATHS.guard}
                previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
                play={isActive}
                size={STICKER_SIZE}
                nonInteractive
                noLoop={false}
                className={styles.sticker}
              />
              <CreatePasswordForm
                isActive={isActive}
                isLoading={isLoading}
                formId="biometrics-create-password"
                onSubmit={handleSubmit}
                onCancel={onClose}
              />
            </div>
          </>
        );

      case BiometricsState.TurnOffComplete:
        return (
          <>
            <ModalHeader title={lang('Biometrics Disabled')} onClose={onClose} />
            <div className={modalStyles.transitionContent}>
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
                <Button isPrimary onClick={onClose} className={modalStyles.customSubmitButton}>
                  {lang('Done')}
                </Button>
              </div>
            </div>
          </>
        );
    }
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      onClose={onClose}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={buildClassName(isInsideModal && modalStyles.transitionSlide)}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(TurnOff);
