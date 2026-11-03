import type { AgentMessage } from '../../../global/types';

import { getDayStartAt } from '../../../util/dateFormat';

export const DATE_ITEM_ID_PREFIX = 'date:';
export const UNREAD_ITEM_ID_PREFIX = 'unread:';

// A date line opens the chat and comes back before a message sent this long after the previous one, as on mobile
const DATE_LINE_GAP_MS = 10 * 60 * 1000;

interface BuildMessageIdsOptions {
  /** The first message the user has not seen, which the "New" line comes before */
  unreadMessageId?: number;
  /** A date line comes before the first message of each day rather than after a pause */
  hasDailyDateLines?: boolean;
}

/**
 * The list's items in order: each message's id, and before the messages that open a date line, an item named after
 * that message (`date:<message id>`), so that the line keeps its key while the message changes. The "New" line comes
 * after the date line, as `unread:<message id>`.
 */
export default function buildMessageIds(
  messages: AgentMessage[],
  { unreadMessageId, hasDailyDateLines = false }: BuildMessageIdsOptions = {},
): string[] {
  const ids: string[] = [];
  let previousTimestamp: number | undefined;

  for (const message of messages) {
    if (previousTimestamp === undefined || getIsDateLineDue(previousTimestamp, message.timestamp, hasDailyDateLines)) {
      ids.push(`${DATE_ITEM_ID_PREFIX}${message.id}`);
    }
    if (message.id === unreadMessageId) ids.push(`${UNREAD_ITEM_ID_PREFIX}${message.id}`);
    previousTimestamp = message.timestamp;
    ids.push(String(message.id));
  }

  return ids;
}

/** A date line or the "New" line, which belong to the message after them */
export function getIsMarkerItemId(id: string) {
  return id.startsWith(DATE_ITEM_ID_PREFIX) || id.startsWith(UNREAD_ITEM_ID_PREFIX);
}

function getIsDateLineDue(previousTimestamp: number, timestamp: number, hasDailyDateLines: boolean) {
  return hasDailyDateLines
    ? getDayStartAt(timestamp) !== getDayStartAt(previousTimestamp)
    : timestamp - previousTimestamp > DATE_LINE_GAP_MS;
}
