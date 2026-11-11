import React, { memo } from '../../lib/teact/teact';

import type { AgentConversationComposerProps } from '../agent/AgentConversationShell';

import { getReturnKeyAction } from '../agent/helpers/composerReturnKey';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentTranscriptReveal from '../agent/hooks/useAgentTranscriptReveal';
import useAgentV2Dictation, { getIsAgentDictationSupported } from '../agent/hooks/useAgentV2Dictation';

import AgentInputBar from '../agent/AgentInputBar';
import { AgentDictationAnnouncement, AgentDictationNotice } from './AgentStatusNotice';

type OwnProps = AgentConversationComposerProps & {
  isActive: boolean;
  placeholder?: string;
  isDimmed?: boolean;
  onFocus?: NoneToVoidFunction;
};

const IS_DICTATION_SUPPORTED = getIsAgentDictationSupported();

/**
 * The agent's input bar with dictation: a transcript goes into the draft for the user to send. The recording's level
 * and time change many times a second, so they render this bar alone rather than the screen around it.
 */
function AgentV2Composer({
  isActive, inputValue, onInput, onKeyDown, onSend, onRequestConsent, ...props
}: OwnProps) {
  const lang = useLang();
  const { reveal, revealTranscript, finishReveal } = useAgentTranscriptReveal({ inputValue, onInput });
  const dictation = useAgentV2Dictation({ isActive, langCode: lang.code, onTranscript: revealTranscript });
  const {
    notice, failure, failureCount, dismissNotice,
  } = dictation;

  // Typing makes a dictation notice about an earlier phrase stale. A transcript still being written comes whole
  // first, and the keystroke goes.
  const handleInput = useLastCallback((value: string) => {
    if (notice) dismissNotice();
    if (finishReveal()) return;
    onInput(value);
  });

  // Enter and Send while a transcript is being written write the rest of it, for the user to send
  const handleKeyDown = useLastCallback((event: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const isSending = getReturnKeyAction(event) === 'send';
    if (isSending && finishReveal()) {
      event.preventDefault();
      return;
    }
    if (isSending && onRequestConsent) {
      event.preventDefault();
      handleSend();
      return;
    }
    onKeyDown(event);
  });

  // The draft stays while the consent sheet asks, and goes once the user allows the Agent
  const handleSend = useLastCallback(() => {
    if (finishReveal()) return;
    if (onRequestConsent) {
      if (inputValue.trim()) onRequestConsent(onSend, props.inputRef.current);
      return;
    }
    onSend();
  });

  const handleHeldDictation = useLastCallback(() => {
    onRequestConsent!(dictation.start);
  });

  return (
    <AgentInputBar
      {...props}
      inputValue={inputValue}
      dictation={IS_DICTATION_SUPPORTED ? dictation : undefined}
      dictationNotice={notice ? <AgentDictationNotice notice={notice} /> : undefined}
      dictationAnnouncement={failure
        ? <AgentDictationAnnouncement key={failureCount} failure={failure} />
        : undefined}
      transcriptReveal={reveal}
      isDictationHeld={Boolean(onRequestConsent)}
      onHeldDictation={handleHeldDictation}
      onInput={handleInput}
      onKeyDown={handleKeyDown}
      onSend={handleSend}
    />
  );
}

export default memo(AgentV2Composer);
