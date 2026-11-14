import { useEffect, useMemo, useState } from '../../lib/teact/teact';

import type { AgentMessage } from '../../global/types';

import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';

/**
 * Keeps the messages a regeneration removes in the list for one more render, so the list can turn them to dust where
 * they stand, and hands over the next messages once it lets them go
 */
export default function useRegenerationDissolve(messages: AgentMessage[], isRunActive: boolean) {
  const [targetMessageId, setTargetMessageId] = useState<number>();
  const previousMessages = usePrevious2(messages);
  const dissolvingMessageIds = useMemo(() => (
    targetMessageId !== undefined && previousMessages
      ? getRegenerationRemovedIds(previousMessages, messages, targetMessageId)
      : undefined
  ), [messages, previousMessages, targetMessageId]);

  // A regeneration that ends without the server taking it leaves the messages in place
  useEffect(() => {
    if (!isRunActive) setTargetMessageId(undefined);
  }, [isRunActive]);

  const releaseMessages = useLastCallback(() => {
    setTargetMessageId(undefined);
  });

  return {
    messages: dissolvingMessageIds ? previousMessages! : messages,
    /** The answer being answered again, until it turns to dust or stays */
    regeneratingMessageId: targetMessageId,
    dissolvingMessageIds,
    markRegenerating: setTargetMessageId,
    releaseMessages,
  };
}

/**
 * The messages a regeneration removed: the regenerated answer and everything after it, once the messages no longer
 * have it and every message before it is still there. The list turns everything from the answer on to dust, so a
 * message after it that stays, as a question queued meanwhile, leaves them to go without it.
 */
export function getRegenerationRemovedIds(
  previousMessages: readonly AgentMessage[],
  messages: readonly AgentMessage[],
  targetMessageId: number,
) {
  const targetIndex = previousMessages.findIndex(({ id }) => id === targetMessageId);
  if (targetIndex < 1 || messages.some(({ id }) => id === targetMessageId)) return undefined;

  for (let index = 0; index < targetIndex; index++) {
    if (messages[index]?.id !== previousMessages[index].id) return undefined;
  }

  const removedIds = previousMessages.slice(targetIndex).map(({ id }) => id);
  const keptIds = new Set(messages.map(({ id }) => id));
  return removedIds.some((id) => keptIds.has(id)) ? undefined : removedIds;
}
