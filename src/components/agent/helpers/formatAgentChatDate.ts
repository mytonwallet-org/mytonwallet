import type { LangFn } from '../../../util/langProvider';

import { formatFullDay, formatTime, getDayStartAt } from '../../../util/dateFormat';

/** The day and the time a chat's date line and message menus show: "Today" or the month and day, then the time */
export default function formatAgentChatDate(lang: LangFn, timestamp: number) {
  const isToday = getDayStartAt(timestamp) === getDayStartAt(Date.now());

  return {
    day: isToday ? lang('Today') : formatFullDay(lang.code!, timestamp),
    time: formatTime(timestamp),
  };
}
