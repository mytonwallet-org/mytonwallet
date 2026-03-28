import type { AgentMessage } from '../../../global/types';

import { getDayStartAt } from '../../../util/dateFormat';

export const DATE_ITEM_ID_PREFIX = 'date:';

export default function buildMessageIds(msgs: AgentMessage[]): string[] {
  const ids: string[] = [];
  let prevDay: number | undefined;

  for (const msg of msgs) {
    const day = getDayStartAt(msg.timestamp);
    if (day !== prevDay) {
      ids.push(`${DATE_ITEM_ID_PREFIX}${day}`);
      prevDay = day;
    }
    ids.push(String(msg.id));
  }

  return ids;
}
