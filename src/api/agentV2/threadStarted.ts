import type { AgentThreadSummaryV2 } from './protocol/types';

/**
 * Whether the user has written in the thread. A news or digest discussion starts with its post alone, one message,
 * until the user sends something there: the chat list leaves it out until then, and its Discuss button offers to
 * discuss rather than to continue.
 */
export function getIsAgentV2ThreadStarted({
  news, digest, messageCount,
}: Pick<AgentThreadSummaryV2, 'news' | 'digest' | 'messageCount'>) {
  return (!news && !digest) || messageCount > 1;
}
