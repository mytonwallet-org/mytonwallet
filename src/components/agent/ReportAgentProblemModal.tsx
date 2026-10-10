import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AgentProblemReportOutcome } from './AgentConversationShell';

import { stopEvent } from '../../util/domEvents';

import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Input from '../ui/Input';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';
import styles from './ReportAgentProblemModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
  onSubmit: (comment: string) => Promise<AgentProblemReportOutcome>;
}

const COMMENT_MAX_LENGTH = 1000;
const OUTCOME_MESSAGE_KEYS: Record<AgentProblemReportOutcome, string> = {
  sent: '$agent_report_problem_sent',
  rateLimited: '$agent_report_problem_rate_limited',
  failed: '$agent_report_problem_failed',
};

function ReportAgentProblemModal({ isOpen, onClose, onSubmit }: OwnProps) {
  const { showToast } = getActions();
  const lang = useLang();
  const inputRef = useRef<HTMLInputElement>();
  const [comment, setComment] = useState('');
  const [isSending, setIsSending] = useState(false);
  const openingRef = useRef(0);

  useEffect(() => {
    if (!isOpen) return;
    // A report still being sent from an earlier opening neither holds nor closes this one
    openingRef.current += 1;
    setComment('');
    setIsSending(false);
  }, [isOpen]);

  useFocusAfterAnimation(inputRef, !isOpen);

  const handleSubmit = useLastCallback(async (e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);
    if (isSending) return;

    const opening = openingRef.current;
    setIsSending(true);
    const outcome = await onSubmit(comment.trim());
    showToast({
      message: lang(OUTCOME_MESSAGE_KEYS[outcome]),
      ...(outcome === 'sent' ? { icon: 'icon-check' } : {}),
    });
    if (opening !== openingRef.current) return;

    setIsSending(false);
    if (outcome === 'sent') onClose();
  });

  return (
    <Modal
      isCompact
      isOpen={isOpen}
      title={lang('Report a Problem')}
      onClose={onClose}
    >
      <form action="#" onSubmit={handleSubmit}>
        <p className={styles.description}>{lang('$agent_report_problem_description')}</p>
        <Input
          ref={inputRef}
          id="agent-report-problem-comment"
          isMultiline
          placeholder={lang('Optional')}
          value={comment}
          maxLength={COMMENT_MAX_LENGTH}
          isDisabled={isSending}
          onInput={setComment}
        />

        <div className={modalStyles.buttons}>
          <Button className={modalStyles.button} onClick={onClose}>{lang('Cancel')}</Button>
          <Button
            id="agent-report-problem-send"
            isPrimary
            isSubmit
            isLoading={isSending}
            className={modalStyles.button}
          >
            {lang('Send')}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

export default memo(ReportAgentProblemModal);
