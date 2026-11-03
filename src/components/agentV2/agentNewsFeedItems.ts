import type { AgentNewsFeedItemV2, AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';

import { formatTime, getDayStartAt } from '../../util/dateFormat';
import { formatNumber } from '../../util/formatNumber';
import { toNativeDigits } from '../../util/nativeDigits';
import { stripAgentNewsMarkdown } from '../agent/helpers/agentNews';

type AgentNewsFeedRow =
  | { kind: 'day'; key: string; timestamp: number }
  | { kind: 'unread'; key: string }
  | { kind: 'news'; key: string; item: AgentNewsFeedItemV2 };

// As much of the body as the server keeps in a thread's news card
const NEWS_EXCERPT_MAX_LENGTH = 200;
const TRAILING_DOT_PATTERN = /\.$/;
const POST_TIME_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
};

/**
 * The time a news post shows: the time today, the day and the time this year, and the year too before that, as on
 * mobile. An abbreviated month loses its trailing dot ("20 июл, 15:38").
 */
export function formatAgentNewsPostTime(langCode: string, timestamp: string, now = Date.now()) {
  const date = new Date(timestamp);
  if (getDayStartAt(date) === getDayStartAt(now)) return formatTime(timestamp);

  return new Intl.DateTimeFormat(langCode, {
    year: date.getFullYear() === new Date(now).getFullYear() ? undefined : 'numeric',
    ...POST_TIME_FORMAT_OPTIONS,
  }).formatToParts(date).map(({ type, value }) => (type === 'month' ? value.replace(TRAILING_DOT_PATTERN, '') : value))
    .join('');
}

/** One item per news, the latest delivery winning, oldest first as the feed shows them */
export function mergeAgentNewsItems(items: AgentNewsFeedItemV2[]) {
  const byId = new Map<number, AgentNewsFeedItemV2>();
  items.forEach((item) => {
    const previous = byId.get(item.eventId);
    if (previous && Date.parse(previous.deliveredAt) > Date.parse(item.deliveredAt)) return;
    byId.set(item.eventId, item);
  });

  return [...byId.values()].sort((first, second) => (
    Date.parse(first.deliveredAt) - Date.parse(second.deliveredAt) || first.eventId - second.eventId
  ));
}

/** The news delivered after the read mark, which the row counts and the feed marks as new */
export function getAgentNewsUnreadItems(items: AgentNewsFeedItemV2[], readThrough?: string) {
  if (!readThrough) return [];
  const readThroughAt = Date.parse(readThrough);
  return items.filter(({ deliveredAt }) => Date.parse(deliveredAt) > readThroughAt);
}

// As many news as a feed page holds: the row counts only the loaded page, so a count this high may have more behind it
const NEWS_UNREAD_COUNT_MAX = 30;

/** The News row's count of unread news, which reads as "30+" from a feed page's worth */
export function formatAgentNewsUnreadCount(count: number) {
  return count >= NEWS_UNREAD_COUNT_MAX
    ? `${toNativeDigits(String(NEWS_UNREAD_COUNT_MAX))}+`
    : toNativeDigits(formatNumber(count));
}

/** A header before each day's news and the "New" divider before the first news delivered after the read mark */
export function buildAgentNewsFeedRows(items: AgentNewsFeedItemV2[], unreadEventId?: number) {
  const rows: AgentNewsFeedRow[] = [];
  let previousDayStartAt: number | undefined;
  items.forEach((item) => {
    const dayStartAt = getDayStartAt(Date.parse(item.deliveredAt));
    if (dayStartAt !== previousDayStartAt) {
      rows.push({ kind: 'day', key: `day-${dayStartAt}`, timestamp: dayStartAt });
      previousDayStartAt = dayStartAt;
    }
    if (item.eventId === unreadEventId) rows.push({ kind: 'unread', key: 'unread' });
    rows.push({ kind: 'news', key: `news-${item.eventId}`, item });
  });

  return rows;
}

/** The news as a chat about it shows it until the server returns its own card */
export function buildAgentNewsPreviewCard(item: AgentNewsFeedItemV2): AgentThreadNewsCardV2 {
  const excerpt = stripAgentNewsMarkdown(item.body).slice(0, NEWS_EXCERPT_MAX_LENGTH);
  const source = item.sources[0]?.name;
  return {
    eventId: item.eventId,
    headline: item.headline,
    body: item.body,
    sources: item.sources,
    ...(excerpt && { excerpt }),
    ...(item.imageUrl && { imageUrl: item.imageUrl }),
    publishedAt: item.deliveredAt,
    ...(source && { source }),
  };
}
