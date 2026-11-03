import type { AgentMessage } from '../../../global/types';

import { getIsMarkerItemId } from './buildMessageIds';

/**
 * Maps every list item to the conversation turn it belongs to. A turn starts at an outgoing message and holds
 * the answers that follow it, so the whole exchange renders inside one element. An incoming message that no question
 * comes before, as a news item, is a turn of its own. The date line and the "New" line before a message that starts a
 * turn join that turn.
 *
 * A turn is named after its first message, so the name does not change when the rendered window moves or when older
 * history takes the date line that opened it.
 */
export default function buildMessageTurnIds(ids: string[], messagesById: Record<number, AgentMessage>) {
  const turnIdByItemId: Record<string, string> = {};
  let turnId: string | undefined;
  let hasQuestion = false;
  let pendingMarkerIds: string[] = [];

  ids.forEach((id) => {
    if (getIsMarkerItemId(id)) {
      pendingMarkerIds.push(id);
      return;
    }

    const isQuestion = Boolean(messagesById[Number(id)]?.isOutgoing);
    if (turnId === undefined || isQuestion || !hasQuestion) {
      turnId = id;
      hasQuestion = isQuestion;
    }
    pendingMarkerIds.forEach((markerId) => {
      turnIdByItemId[markerId] = turnId!;
    });
    pendingMarkerIds = [];
    turnIdByItemId[id] = turnId;
  });

  return turnIdByItemId;
}
