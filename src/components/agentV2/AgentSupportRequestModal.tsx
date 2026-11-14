import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';

interface OwnProps {
  isOpen: boolean;
  /** The operator gets the wallet's addresses with the chat, which the user has allowed the Agent and has a wallet */
  hasWalletAddresses: boolean;
  /** Call sends nothing while the chat cannot call support, as when that changes with the sheet open */
  canConfirm: boolean;
  onClose: NoneToVoidFunction;
  onConfirm: NoneToVoidFunction;
}

/** Asks before a chat is handed to a support operator */
function AgentSupportRequestModal({
  isOpen, hasWalletAddresses, canConfirm, onClose, onConfirm,
}: OwnProps) {
  const lang = useLang();

  const handleConfirm = useLastCallback(() => {
    if (!canConfirm) return;
    onConfirm();
    onClose();
  });

  return (
    <Modal isOpen={isOpen} isCompact title={lang('$agent_support_confirm_title')} onClose={onClose}>
      <p className={buildClassName(modalStyles.text, modalStyles.text_centered)}>
        {lang(hasWalletAddresses ? '$agent_support_confirm_text' : '$agent_support_confirm_text_no_wallet')}
      </p>
      <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsNoExtraSpace)}>
        <Button className={modalStyles.button} onClick={onClose}>{lang('Cancel')}</Button>
        <Button isPrimary isDisabled={!canConfirm} className={modalStyles.button} onClick={handleConfirm}>
          {lang('$agent_support_confirm_action')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(AgentSupportRequestModal);
