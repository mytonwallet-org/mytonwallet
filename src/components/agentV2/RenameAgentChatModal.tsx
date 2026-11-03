import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';

import { stopEvent } from '../../util/domEvents';

import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Input from '../ui/Input';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';

interface OwnProps {
  /** The chat being renamed; the modal is open while it is set */
  thread?: AgentThreadSummaryV2;
  onClose: NoneToVoidFunction;
  onSave: (thread: AgentThreadSummaryV2, title: string) => void;
}

// The server's limit for a chat title
const CHAT_TITLE_MAX_LENGTH = 80;

function RenameAgentChatModal({ thread, onClose, onSave }: OwnProps) {
  const lang = useLang();
  const isOpen = Boolean(thread);
  const title = thread?.title;
  const inputRef = useRef<HTMLInputElement>();
  const [value, setValue] = useState(title ?? '');

  useEffect(() => {
    if (isOpen) setValue(title ?? '');
  }, [isOpen, title]);

  useFocusAfterAnimation(inputRef, !isOpen);

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);
    const trimmed = value.trim();
    if (!thread || !trimmed) return;

    onClose();
    if (trimmed !== title) onSave(thread, trimmed);
  });

  return (
    <Modal isCompact isOpen={isOpen} title={lang('Rename Chat')} onClose={onClose}>
      <form action="#" onSubmit={handleSubmit}>
        <Input
          ref={inputRef}
          placeholder={lang('Name')}
          value={value}
          maxLength={CHAT_TITLE_MAX_LENGTH}
          enterKeyHint="done"
          onInput={setValue}
        />
        <div className={modalStyles.buttons}>
          <Button className={modalStyles.button} onClick={onClose}>{lang('Cancel')}</Button>
          <Button isPrimary isSubmit isDisabled={!value.trim()} className={modalStyles.button}>
            {lang('Save')}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

export default memo(RenameAgentChatModal);
