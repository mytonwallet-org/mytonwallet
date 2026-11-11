import type { LangFn } from '../../../util/langProvider';

import { formatAgentDay, formatAgentTime } from './agentDateFormat';

/**
 * The day and the time a chat's date line and message menus show: "Today", "Yesterday" or the month and day, with the
 * year for another year, then the time
 */
export default function formatAgentChatDate(lang: LangFn, timestamp: number) {
  return {
    day: formatAgentDay(lang, timestamp),
    time: formatAgentTime(lang.code ?? 'en', timestamp),
  };
}
