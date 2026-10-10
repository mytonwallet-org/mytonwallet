import type { AgentMessage } from '../../../global/types';

import { DATE_ITEM_ID_PREFIX } from './buildMessageIds';

/**
 * Maps every list item to the conversation turn it belongs to. A turn starts at an outgoing message and holds
 * the answers that follow it, so the whole exchange renders inside one element. A date separator right before
 * an outgoing message joins that message's turn.
 *
 * A turn id is the id of its first item in the full list, so it does not change when the rendered window moves.
 */
export default function buildMessageTurnIds(ids: string[], messagesById: Record<number, AgentMessage>) {
  const turnIdByItemId: Record<string, string> = {};
  let turnId: string | undefined;

  ids.forEach((id, index) => {
    if (turnId === undefined || getIsTurnStart(ids, index, messagesById)) {
      turnId = id;
    }
    turnIdByItemId[id] = turnId;
  });

  return turnIdByItemId;
}

function getIsTurnStart(ids: string[], index: number, messagesById: Record<number, AgentMessage>) {
  const id = ids[index];
  if (getIsDateItem(id)) {
    const nextId = ids[index + 1];
    return nextId !== undefined && getIsOutgoingItem(nextId, messagesById);
  }

  const prevId = ids[index - 1];
  return getIsOutgoingItem(id, messagesById) && (prevId === undefined || !getIsDateItem(prevId));
}

function getIsDateItem(id: string) {
  return id.startsWith(DATE_ITEM_ID_PREFIX);
}

function getIsOutgoingItem(id: string, messagesById: Record<number, AgentMessage>) {
  return !getIsDateItem(id) && Boolean(messagesById[Number(id)]?.isOutgoing);
}
