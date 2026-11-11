import type {
  AgentNewsFeedDigestV2, AgentNewsFeedItemV2, AgentThreadNewsCardV2,
} from '../../api/agentV2/protocol/types';

import { getDayStartAt } from '../../util/dateFormat';
import { formatNumber } from '../../util/formatNumber';
import { toNativeDigits } from '../../util/nativeDigits';
import { formatAgentDayWithTime, formatAgentTime } from '../agent/helpers/agentDateFormat';
import { stripAgentNewsMarkdown } from '../agent/helpers/agentNews';

export type AgentNewsFeedEntry =
  | (AgentNewsFeedItemV2 & { kind: 'news' })
  | (AgentNewsFeedDigestV2 & { kind: 'digest' });

type AgentNewsFeedRow =
  | { kind: 'day'; key: string; timestamp: number }
  | { kind: 'unread'; key: string }
  | { kind: 'news'; key: string; item: AgentNewsFeedItemV2 };

// As much of the body as the server keeps in a thread's news card
const NEWS_EXCERPT_MAX_LENGTH = 200;

/**
 * The time a news post shows in its discussion: the time today, the day and the time this year, and the year too
 * before that, as on mobile. An abbreviated month loses its trailing dot ("20 июл, 15:38").
 */
export function formatAgentNewsPostTime(langCode: string, timestamp: string, now = Date.now()) {
  return getDayStartAt(new Date(timestamp)) === getDayStartAt(now)
    ? formatAgentTime(langCode, timestamp)
    : formatAgentDayWithTime(langCode, timestamp, now);
}

export function mergeAgentNewsFeedEntries(
  items: AgentNewsFeedItemV2[],
  digests: AgentNewsFeedDigestV2[] = [],
  current: AgentNewsFeedEntry[] = [],
): AgentNewsFeedEntry[] {
  const news = mergeAgentNewsItems([
    ...current.flatMap((entry) => (entry.kind === 'news' ? [entry] : [])), ...items,
  ]).map((item) => ({ ...item, kind: 'news' as const }));
  const byId = new Map<string, AgentNewsFeedDigestV2>();
  [...current.flatMap((entry) => (entry.kind === 'digest' ? [entry] : [])), ...digests].forEach((digest) => {
    const previous = byId.get(digest.id);
    if (previous && Date.parse(previous.deliveredAt) > Date.parse(digest.deliveredAt)) return;
    byId.set(digest.id, digest);
  });
  return [...news, ...[...byId.values()].map((digest) => ({ ...digest, kind: 'digest' as const }))]
    .sort((first, second) => Date.parse(first.deliveredAt) - Date.parse(second.deliveredAt));
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

// The News row counts unread news up to this many, and marks more with a dot alone
const NEWS_UNREAD_COUNT_MAX = 10;

/** The News row's count of unread news, or none for more than ten, which it marks with a dot */
export function formatAgentNewsUnreadCount(count: number) {
  return count > NEWS_UNREAD_COUNT_MAX ? undefined : toNativeDigits(formatNumber(count));
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
