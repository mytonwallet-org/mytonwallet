import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { LangCode } from '../../global/types';
import type { LangFn } from '../../hooks/useLang';

import {
  DAY, formatFullDay, formatShortDay, formatTime, getDayStartAt, HOUR,
} from '../../util/dateFormat';

export interface AgentThreadListSection {
  key: string;
  title: string;
  items: AgentThreadListItemV2[];
}

const WEEK_DAYS = 7;
// Yesterday's activity this recent still reads as a time, as today's does
const YESTERDAY_TIME_MAX_AGE = 12 * HOUR;

/** Pinned chats first, then the rest grouped by the day of their last activity, newest first, as on mobile */
export function buildAgentThreadListSections(
  items: AgentThreadListItemV2[],
  lang: LangFn,
  now = Date.now(),
): AgentThreadListSection[] {
  const sections: AgentThreadListSection[] = [];
  [...items].sort(compareAgentThreadListItems).forEach((item) => {
    const { isPinned, lastActivityAt } = item.thread;
    const key = isPinned ? 'pinned' : `day-${getDayStartAt(Date.parse(lastActivityAt))}`;
    let section = sections[sections.length - 1];
    if (section?.key !== key) {
      section = {
        key,
        title: isPinned ? lang('Pinned') : formatAgentThreadDay(lang, lastActivityAt, now),
        items: [],
      };
      sections.push(section);
    }
    section.items.push(item);
  });

  return sections;
}

/**
 * A live refresh reads only the first page. Chats that later pages brought in stay after it, so the list
 * neither shrinks under the reader nor loses its place.
 */
export function mergeAgentThreadListRefresh(current: AgentThreadListItemV2[], firstPage: AgentThreadListItemV2[]) {
  const firstPageIds = new Set(firstPage.map(({ thread }) => thread.id));
  return [...firstPage, ...current.filter(({ thread }) => !firstPageIds.has(thread.id))]
    .sort(compareAgentThreadListItems);
}

export function compareAgentThreadListItems(first: AgentThreadListItemV2, second: AgentThreadListItemV2) {
  if (Boolean(first.thread.isPinned) !== Boolean(second.thread.isPinned)) {
    return first.thread.isPinned ? -1 : 1;
  }

  return Date.parse(second.thread.lastActivityAt) - Date.parse(first.thread.lastActivityAt);
}

/** Today and yesterday by name, the rest of the week by weekday, older days by date */
export function formatAgentThreadDay(lang: LangFn, timestamp: string, now = Date.now()) {
  const daysAgo = getDaysAgo(timestamp, now);
  if (daysAgo <= 0) return lang('Today');
  if (daysAgo === 1) return lang('Yesterday');

  const langCode = lang.code ?? 'en';
  if (daysAgo < WEEK_DAYS) {
    const weekday = new Date(timestamp).toLocaleDateString(langCode, { weekday: 'long' });
    return weekday.charAt(0).toLocaleUpperCase(langCode) + weekday.slice(1);
  }

  return formatFullDay(langCode, timestamp);
}

/**
 * The time of a row outside the day sections: the time today and in the last 12 hours of yesterday, "Yesterday"
 * earlier, a short weekday within the week and a short date before that, as on mobile
 */
export function formatAgentThreadTime(lang: LangFn, timestamp: string, now = Date.now()) {
  const daysAgo = getDaysAgo(timestamp, now);
  if (daysAgo <= 0) return formatTime(timestamp);
  if (daysAgo === 1) {
    return now - Date.parse(timestamp) < YESTERDAY_TIME_MAX_AGE ? formatTime(timestamp) : lang('Yesterday');
  }

  const langCode: LangCode = lang.code ?? 'en';
  if (daysAgo < WEEK_DAYS) return new Date(timestamp).toLocaleDateString(langCode, { weekday: 'short' });

  return formatShortDay(langCode, timestamp);
}

function getDaysAgo(timestamp: string, now: number) {
  return getDayOrdinal(now) - getDayOrdinal(Date.parse(timestamp));
}

// Counts days on the local calendar, which a daylight saving change cannot shift
function getDayOrdinal(time: number) {
  const date = new Date(time);
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / DAY;
}
