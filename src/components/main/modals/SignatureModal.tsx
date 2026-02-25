import React, {
  memo, useEffect, useLayoutEffect, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import renderText from '../../../global/helpers/renderText';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import captureKeyboardListeners from '../../../util/captureKeyboardListeners';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';
import Transition from '../../ui/Transition';

import transferStyles from '../../transfer/Transfer.module.scss';
import modalStyles from '../../ui/Modal.module.scss';
import styles from './SignatureModal.module.scss';

type StateProps = {
  dataHex?: string;
  error?: string;
  isSigned?: boolean;
};

const enum SLIDES {
  confirm,
  password,
  complete,
}

function SignatureModal({
  dataHex, error, isSigned,
}: StateProps) {
  const { submitSignature, clearSignatureError, cancelSignature } = getActions();

  const lang = useLang();
  const [isModalOpen, openModal, closeModal] = useFlag(false);
  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.confirm);
  const [nextKey, setNextKey] = useState<SLIDES | undefined>(SLIDES.password);

  useLayoutEffect(() => {
    if (dataHex) {
      setCurrentSlide(SLIDES.confirm);
      setNextKey(SLIDES.password);
      openModal();
    }
  }, [dataHex, openModal]);

  useLayoutEffect(() => {
    if (isSigned) {
      setCurrentSlide(SLIDES.complete);
      setNextKey(undefined);
    }
  }, [isSigned]);

  useEffect(() => (
    currentSlide === SLIDES.complete
      ? captureKeyboardListeners({ onEnter: closeModal })
      : undefined
  ), [closeModal, currentSlide]);

  const handleConfirm = useLastCallback(() => {
    setCurrentSlide(SLIDES.password);
    setNextKey(SLIDES.complete);
  });

  const handlePasswordSubmit = useLastCallback((password: string) => {
    submitSignature({ password });
  });

  function renderConfirm() {
    return (
      <>
        <ModalHeader title={lang('Confirmation')} onClose={closeModal} />
        <div className={modalStyles.transitionContent}>
          <div className={transferStyles.label}>{lang('Signing Data')}</div>
          <div className={transferStyles.inputReadOnly}>
            {dataHex}
          </div>

          <div className={styles.error}>
            {renderText(lang('$signature_warning'))}
          </div>
          <div className={modalStyles.buttons}>
            <Button className={modalStyles.button} onClick={closeModal}>{lang('Cancel')}</Button>
            <Button isPrimary className={modalStyles.button} onClick={handleConfirm}>{lang('Sign')}</Button>
          </div>
        </div>
      </>
    );
  }

  function renderPasswordForm(isActive: boolean) {
    return (
      <>
        <ModalHeader title={lang(getDoesUsePinPad() ? 'Enter Passcode' : 'Enter Password')} onClose={closeModal} />
        <PasswordForm
          isActive={isActive}
          error={error}
          submitLabel={lang('Sign')}
          cancelLabel={lang('Cancel')}
          noAutoConfirm
          onSubmit={handlePasswordSubmit}
          onCancel={closeModal}
          onUpdate={clearSignatureError}
        />
      </>
    );
  }

  function renderComplete(isActive: boolean) {
    return (
      <>
        <ModalHeader title={lang('Done!')} onClose={closeModal} />

        <div className={buildClassName(modalStyles.transitionContent, modalStyles.transitionContent_simple)}>
          <AnimatedIconWithPreview
            play={isActive}
            noLoop={false}
            nonInteractive
            className={styles.sticker}
            tgsUrl={ANIMATED_STICKERS_PATHS.thumbUp}
            previewUrl={ANIMATED_STICKERS_PATHS.thumbUpPreview}
          />
          <div className={styles.description}>
            {lang('Signing was confirmed!')}
          </div>

          <div className={modalStyles.buttons}>
            <Button isPrimary onClick={closeModal}>{lang('Close')}</Button>
          </div>
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.confirm:
        return renderConfirm();

      case SLIDES.password:
        return renderPasswordForm(isActive);

      case SLIDES.complete:
        return renderComplete(isActive);
    }
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isModalOpen}
      dialogClassName={styles.modalDialog}
      onClose={closeModal}
      onCloseAnimationEnd={cancelSignature}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={currentSlide}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal(
  (global): StateProps => {
    const {
      dataHex, error, isSigned,
    } = global.currentSignature || {};

    return {
      dataHex, error, isSigned,
    };
  },
)(SignatureModal));
