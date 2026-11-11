import type { AgentMessage } from '../../../global/types';

import { getDayStartAt } from '../../../util/dateFormat';
import { getIsMarkerItemId } from './buildMessageIds';

const DAY_TURN_ID_PREFIX = 'day:';

/**
 * Maps every list item to the conversation turn it belongs to. A turn starts at an outgoing message and holds
 * the answers that follow it, so the whole exchange renders inside one element. An incoming message that no question
 * comes before is a turn of its own. The date line and the "New" line before a message that starts a turn join that
 * turn.
 *
 * A turn is named after its first message, so the name does not change when the rendered window moves or when older
 * history takes the date line that opened it.
 *
 * With `isGroupedByDay`, as in the news feed, a turn holds a day's messages with the day's date line, which stays over
 * them as they scroll under it. Such a turn is named after its day, which older messages of the day do not change.
 */
export default function buildMessageTurnIds(
  ids: string[],
  messagesById: Record<number, AgentMessage>,
  isGroupedByDay = false,
) {
  const turnIdByItemId: Record<string, string> = {};
  let turnId: string | undefined;
  let hasQuestion = false;
  let pendingMarkerIds: string[] = [];

  ids.forEach((id) => {
    if (getIsMarkerItemId(id)) {
      pendingMarkerIds.push(id);
      return;
    }

    const message = messagesById[Number(id)];
    const isQuestion = Boolean(message?.isOutgoing);
    if (isGroupedByDay) {
      turnId = message ? `${DAY_TURN_ID_PREFIX}${getDayStartAt(message.timestamp)}` : id;
    } else if (turnId === undefined || isQuestion || !hasQuestion) {
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
