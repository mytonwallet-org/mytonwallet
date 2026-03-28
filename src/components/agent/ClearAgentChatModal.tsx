import React, { memo } from '../../lib/teact/teact';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Modal from '../ui/Modal';

import styles from './ClearAgentChatModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
  onConfirm: NoneToVoidFunction;
}

function ClearAgentChatModal({ isOpen, onClose, onConfirm }: OwnProps) {
  const lang = useLang();

  const handleConfirm = useLastCallback(() => {
    onClose();
    onConfirm();
  });

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={lang('Clear Chat')}
      onClose={onClose}
    >
      <div className={styles.description}>
        {lang('$agent_clear_chat_confirm')}
      </div>
      <div className={styles.buttons}>
        <Button onClick={onClose} className={styles.button}>{lang('Cancel')}</Button>
        <Button isPrimary isDestructive onClick={handleConfirm} className={styles.button}>
          {lang('Clear Chat')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(ClearAgentChatModal);
