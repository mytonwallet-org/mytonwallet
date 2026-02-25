import React, {
  memo, useEffect, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { IS_CAPACITOR, MNEMONIC_COUNT } from '../../../config';
import { selectMnemonicForCheck } from '../../../global/actions/api/auth';
import { selectCurrentAccountId, selectCurrentAccountState } from '../../../global/selectors';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { vibrateOnError, vibrateOnSuccess } from '../../../util/haptics';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { callApi } from '../../../api';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import MnemonicCheck from '../../auth/MnemonicCheck';
import MnemonicList from '../../auth/MnemonicList';
import MnemonicPrivateKey from '../../auth/MnemonicPrivateKey';
import SafetyRules from '../../auth/SafetyRules';
import Modal from '../../ui/Modal';
import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';
import Transition from '../../ui/Transition';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './BackupModal.module.scss';

type OwnProps = {
  isOpen?: boolean;
  onClose: () => void;
};

type StateProps = {
  currentAccountId?: string;
  isBackupRequired?: boolean;
};

enum SLIDES {
  confirm,
  password,
  mnemonic,
  check,
}

function BackupModal({
  isOpen, currentAccountId, onClose, isBackupRequired,
}: OwnProps & StateProps) {
  const { setIsBackupRequired, setIsPinAccepted, clearIsPinAccepted } = getActions();

  const lang = useLang();
  const [currentSlide, setCurrentSlide] = useState<SLIDES>(SLIDES.confirm);
  const [nextKey, setNextKey] = useState<SLIDES | undefined>(SLIDES.password);
  const [checkIndexes, setCheckIndexes] = useState<number[]>([]);

  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | undefined>();

  const mnemonicRef = useRef<string[] | undefined>(undefined);
  useEffect(() => {
    mnemonicRef.current = undefined;
  }, [isOpen]);

  const handleSafetyConfirm = useLastCallback(() => {
    setCurrentSlide(SLIDES.password);
    setNextKey(SLIDES.mnemonic);
  });

  const handlePasswordSubmit = useLastCallback(async (password: string) => {
    setIsLoading(true);
    mnemonicRef.current = await callApi('fetchMnemonic', currentAccountId!, password);

    if (!mnemonicRef.current) {
      const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
      setError(error);
      setIsLoading(false);
      void vibrateOnError();
      return;
    }
    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
      clearIsPinAccepted();
    }

    setIsLoading(false);
    setNextKey(SLIDES.check);
    setCurrentSlide(SLIDES.mnemonic);
  });

  const handleBackupErrorUpdate = useLastCallback(() => {
    setError(undefined);
  });

  const handleCheckMnemonic = useLastCallback(() => {
    setCheckIndexes(selectMnemonicForCheck(mnemonicRef.current?.length || MNEMONIC_COUNT));
    setCurrentSlide(SLIDES.check);
    setNextKey(undefined);
  });

  const handleRestartCheckMnemonic = useLastCallback(() => {
    setCurrentSlide(SLIDES.mnemonic);
    setNextKey(SLIDES.check);
  });

  const handleModalClose = useLastCallback(() => {
    setIsLoading(false);
    setError(undefined);
    setCurrentSlide(SLIDES.confirm);
    setNextKey(SLIDES.password);
  });

  const handleCheckMnemonicSubmit = useLastCallback(() => {
    setIsBackupRequired({ isMnemonicChecked: true });
    onClose();
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    const mnemonic = mnemonicRef.current;

    switch (currentKey) {
      case SLIDES.confirm:
        return (
          <SafetyRules
            isActive={isActive}
            onSubmit={handleSafetyConfirm}
            onClose={onClose}
          />
        );

      case SLIDES.password:
        return (
          <>
            {!getDoesUsePinPad() && (
              <ModalHeader title={lang('Enter Password')} onClose={onClose} />
            )}
            <PasswordForm
              isActive={isActive}
              isLoading={isLoading}
              error={error}
              withCloseButton={IS_CAPACITOR}
              submitLabel={lang('$back_up_auth')}
              cancelLabel={lang('Cancel')}
              noAutoConfirm
              onSubmit={handlePasswordSubmit}
              onCancel={onClose}
              onUpdate={handleBackupErrorUpdate}
            />
          </>
        );

      case SLIDES.mnemonic:
        return mnemonic && isMnemonicPrivateKey(mnemonic) ? (
          <MnemonicPrivateKey
            privateKeyHex={mnemonic[0]}
            onClose={onClose}
          />
        ) : (
          <MnemonicList
            isActive={isActive}
            mnemonic={mnemonic}
            onNext={isBackupRequired ? handleCheckMnemonic : undefined}
            onClose={onClose}
          />
        );

      case SLIDES.check:
        return (
          <MnemonicCheck
            isActive={isActive}
            mnemonic={mnemonicRef.current as string[]}
            checkIndexes={checkIndexes}
            buttonLabel={lang('Done')}
            onSubmit={handleCheckMnemonicSubmit}
            onCancel={handleRestartCheckMnemonic}
            onClose={onClose}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      hasCloseButton
      dialogClassName={styles.modalDialog}
      onClose={onClose}
      onCloseAnimationEnd={handleModalClose}
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

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { isBackupRequired } = selectCurrentAccountState(global) || {};
  return { currentAccountId: selectCurrentAccountId(global), isBackupRequired };
})(BackupModal));
