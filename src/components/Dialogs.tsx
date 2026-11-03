import React, { type FC, memo, useEffect, useRef } from '../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../global';

import type { DialogAction, DialogType } from '../global/types';

import { collectLogs, EXPORT_LOGS_TITLE, exportLogs } from '../global/helpers/logsExport';
import renderText from '../global/helpers/renderText';
import { selectCurrentAccountId } from '../global/selectors';
import { pick } from '../util/iteratees';
import { getTranslation } from '../util/langProvider';
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
  const logsRef = useRef<Promise<string>>();

  const dialog = dialogs[dialogs.length - 1];
  const title = lang(dialog?.title ?? 'Something went wrong');

  const buttons = dialog?.buttons ?? { confirm: {} };
  const hasCancel = Boolean(dialog?.buttons?.cancel);
  const defaultConfirmTitle = buttons.confirm.action === 'exportLogs' ? EXPORT_LOGS_TITLE : 'OK';
  const confirmTitle = lang(buttons.confirm.title ?? defaultConfirmTitle);
  const cancelTitle = hasCancel ? lang(buttons.cancel?.title ?? 'Cancel') : undefined;

  const handleAction = useLastCallback(() => {
    const { action } = buttons.confirm;
    if (action) {
      executeDialogAction(action, dialog, logsRef.current);
    }

    // The saved logs go to the support contact this dialog names, so it stays in front of the user
    if (action !== 'exportLogs') {
      closeModal();
    }
  });

  useEffect(() => {
    if (!dialog) {
      closeModal();
      return;
    }

    // Collected while the dialog is being read, so a slow worker does not outlast the click's user activation
    logsRef.current = dialog.buttons?.confirm.action === 'exportLogs' ? collectLogs(getLogsContext()) : undefined;
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

function getLogsContext() {
  const global = getGlobal();

  return { currentAccountId: selectCurrentAccountId(global), accountsById: global.accounts?.byId };
}

function executeDialogAction(action: DialogAction, dialog: DialogType, logs?: Promise<string>) {
  switch (action) {
    case 'openReturnUrl': {
      getActions().closeLoadingOverlay();
      // Close the wake placeholder skeleton (if any) when returning to the dapp.
      getActions().closeDappTransfer();
      void openUrl(dialog.entities!.url, { isExternal: true });
      break;
    }

    case 'exportLogs': {
      void exportLogs(getLogsContext(), logs)
        .then((isCopied) => {
          if (isCopied) {
            getActions().showToast({ message: getTranslation('Logs Copied'), icon: 'icon-copy' });
          }
        });
      break;
    }
  }
}
