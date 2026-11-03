import React, { memo } from '../../lib/teact/teact';

import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Modal from '../ui/Modal';

import styles from './DeleteAgentChatModal.module.scss';

interface OwnProps {
  /** The chat to delete, or nothing for a chat whose thread is still being created */
  thread?: AgentThreadSummaryV2;
  isOpen: boolean;
  onClose: NoneToVoidFunction;
  onConfirm: (thread?: AgentThreadSummaryV2) => void;
}

function DeleteAgentChatModal({ thread, isOpen, onClose, onConfirm }: OwnProps) {
  const lang = useLang();

  const handleConfirm = useLastCallback(() => {
    onConfirm(thread);
    onClose();
  });

  return (
    <Modal isOpen={isOpen} isCompact title={lang('Delete Chat?')} onClose={onClose}>
      <div className={styles.description}>
        {lang('$agent_delete_chat_confirmation')}
      </div>
      <div className={styles.buttons}>
        <Button className={styles.button} onClick={onClose}>{lang('Cancel')}</Button>
        <Button isPrimary isDestructive className={styles.button} onClick={handleConfirm}>
          {lang('Delete')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(DeleteAgentChatModal);
