import React, { memo } from '../../lib/teact/teact';

import type { AgentConversationComposerProps } from '../agent/AgentConversationShell';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentV2Dictation, { getIsAgentDictationSupported } from '../agent/hooks/useAgentV2Dictation';

import AgentInputBar from '../agent/AgentInputBar';
import { AgentDictationAnnouncement, AgentDictationNotice } from './AgentStatusNotice';

type OwnProps = AgentConversationComposerProps & {
  isActive: boolean;
  placeholder?: string;
  isDimmed?: boolean;
};

const IS_DICTATION_SUPPORTED = getIsAgentDictationSupported();

/** The agent's input bar with dictation: a transcript goes into the draft for the user to send */
function AgentV2Composer({ isActive, onInsertText, onInput, ...props }: OwnProps) {
  const lang = useLang();
  const dictation = useAgentV2Dictation({ isActive, langCode: lang.code, onTranscript: onInsertText });
  const {
    notice, failure, failureCount, dismissNotice,
  } = dictation;

  // Typing makes a dictation notice about an earlier phrase stale
  const handleInput = useLastCallback((value: string) => {
    if (notice) dismissNotice();
    onInput(value);
  });

  return (
    <AgentInputBar
      {...props}
      dictation={IS_DICTATION_SUPPORTED ? dictation : undefined}
      dictationNotice={notice ? <AgentDictationNotice notice={notice} /> : undefined}
      dictationAnnouncement={failure
        ? <AgentDictationAnnouncement key={failureCount} failure={failure} />
        : undefined}
      onInput={handleInput}
    />
  );
}

export default memo(AgentV2Composer);
