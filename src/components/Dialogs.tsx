import React, { type FC, memo, useEffect } from '../lib/teact/teact';
import { getActions, withGlobal } from '../global';

import type { DialogAction, DialogType } from '../global/types';

import renderText from '../global/helpers/renderText';
import { pick } from '../util/iteratees';
import { openUrl } from '../util/openUrl';

import useFlag from '../hooks/useFlag';
import useLang from '../hooks/useLang';
import useLastCallback from '../hooks/useLastCallback';

import Button from './ui/Button';
import Modal from './ui/Modal';

import modalStyles from './ui/Modal.module.scss';

type StateProps = {
  dialogs: DialogType[];
};

const Dialogs: FC<StateProps> = ({ dialogs }) => {
  const { dismissDialog } = getActions();

  const lang = useLang();
  const [isModalOpen, openModal, closeModal] = useFlag();

  const dialog = dialogs[dialogs.length - 1];
  const title = lang(dialog?.title ?? 'Something went wrong');

  const buttons = dialog?.buttons ?? { confirm: {} };
  const hasCancel = Boolean(dialog?.buttons?.cancel);
  const confirmTitle = lang(buttons.confirm.title ?? 'OK');
  const cancelTitle = hasCancel ? lang(buttons.cancel?.title ?? 'Cancel') : undefined;

  const handleAction = useLastCallback(() => {
    if (buttons.confirm.action) {
      executeDialogAction(buttons.confirm.action, dialog);
    }

    closeModal();
  });

  useEffect(() => {
    if (!dialog) {
      closeModal();
      return;
    }

    openModal();
  }, [dialog]);

  if (!dialog) {
    return undefined;
  }

  return (
    <Modal
      isOpen={isModalOpen}
      isCompact
      title={title}
      noBackdropClose={dialog.noBackdropClose}
      isInAppLock={dialog.isInAppLock}
      onClose={closeModal}
      onCloseAnimationEnd={dismissDialog}
    >
      <div>
        {
          typeof dialog.message === 'string'
            ? renderText(lang(dialog.message, dialog.entities))
            : dialog.message
        }
      </div>
      <div className={modalStyles.footerButtons}>
        {hasCancel && <Button onClick={closeModal}>{cancelTitle}</Button>}
        <Button
          isPrimary
          isDestructive={buttons.confirm.isDestructive}
          onClick={handleAction}
        >
          {confirmTitle}
        </Button>
      </div>
    </Modal>
  );
};

export default memo(withGlobal(
  (global): StateProps => pick(global, ['dialogs']),
)(Dialogs));

function executeDialogAction(action: DialogAction, dialog: DialogType) {
  switch (action) {
    case 'signOutAll': {
      const { signOut } = getActions();

      signOut({ level: 'all' });
      break;
    }

    case 'openReturnUrl': {
      getActions().closeLoadingOverlay();
      // Close the wake placeholder skeleton (if any) when returning to the dapp.
      getActions().closeDappTransfer();
      void openUrl(dialog.entities!.url, { isExternal: true });
      break;
    }
  }
}
