import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';
import { SignDataState } from '../../global/types';

import { IS_CAPACITOR } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { pick } from '../../util/iteratees';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import DappSignDataInitial from './DappSignDataInitial';
import DappTransferComplete from './DappTransferComplete';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

type StateProps = Pick<GlobalState['currentDappSignData'], 'isLoading' | 'state' | 'error'>;

function DappSignDataModal({
  isLoading,
  state,
  error,
}: StateProps) {
  const {
    setDappSignDataScreen,
    submitDappSignData,
    clearDappSignDataError,
    closeDappSignData,
    cancelDappSignData,
  } = getActions();

  const lang = useLang();

  const isOpen = state !== SignDataState.None;

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const handleBackClick = useLastCallback(() => {
    if (state === SignDataState.Password) {
      setDappSignDataScreen({ state: SignDataState.Initial });
    }
  });

  const handlePasswordSubmit = useLastCallback((password: string) => {
    submitDappSignData({ password });
  });

  const handleResetSignData = useLastCallback(() => {
    cancelDappSignData();
    updateNextKey();
  });

  function renderPassword(isActive: boolean) {
    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader title={lang('Sign Data')} onClose={closeDappSignData} />
        )}
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          error={error}
          withCloseButton={IS_CAPACITOR}
          submitLabel={lang('Sign')}
          cancelLabel={lang('Back')}
          noAutoConfirm
          onSubmit={handlePasswordSubmit}
          onCancel={handleBackClick}
          onUpdate={clearDappSignDataError}
        />
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SignDataState) {
    switch (currentKey) {
      case SignDataState.Initial:
        return <DappSignDataInitial />;

      case SignDataState.Password:
        return renderPassword(isActive);

      case SignDataState.Complete:
        return (
          <DappTransferComplete
            isActive={isActive}
            onClose={closeDappSignData}
            type="signData"
          />
        );
    }
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      noBackdropClose
      onClose={closeDappSignData}
      onCloseAnimationEnd={handleResetSignData}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => pick(
  global.currentDappSignData,
  ['isLoading', 'state', 'error'],
))(DappSignDataModal));
