import type {
  AgentNewsDigestHeadlineV2,
  AgentNewsFeedDigestV2,
  AgentNewsFeedItemV2,
  AgentNewsFeedPageV2,
  AgentThreadDigestCardV2,
  AgentThreadNewsCardV2,
} from '../types';

import {
  AgentV2ContractError,
  array,
  boundedInteger,
  boundedString,
  fail,
  integer,
  object,
  oneOf,
  string,
  timestamp,
} from '../wireReader';
import { followupText } from './messages';
import { protocol, uuid } from './readers';

const NEWS_FEED_LOCALES = new Set(['ru', 'en']);
const MAX_NEWS_EVENT_ID = 2_147_483_647;
const MAX_FEED_CURSOR_LENGTH = 2070;
const MAX_DIGEST_ID_LENGTH = 64;
const MAX_FEED_DIGEST_TOP_LENGTH = 5;

export function decodeAgentV2NewsFeed(value: unknown): AgentNewsFeedPageV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const locale = oneOf<AgentNewsFeedPageV2['locale']>(result.locale, NEWS_FEED_LOCALES, '$.locale');
  const items = array(result.items, '$.items', 30).map((item, index) => newsFeedItem(item, `$.items[${index}]`));
  const nextCursor = result.nextCursor === undefined
    ? undefined
    : boundedString(result.nextCursor, '$.nextCursor', 1, MAX_FEED_CURSOR_LENGTH);
  const digests = result.digests === undefined
    ? undefined
    : array(result.digests, '$.digests').map((digest, index) => newsFeedDigest(digest, `$.digests[${index}]`));
  return {
    protocolVersion: 3,
    locale,
    items,
    ...(nextCursor !== undefined && { nextCursor }),
    ...(digests !== undefined && { digests }),
  };
}

export function threadDigestCard(value: unknown, path: string): AgentThreadDigestCardV2 {
  const result = object(value, path);
  const id = digestId(result.id, `${path}.id`);
  const windowEnd = timestamp(result.windowEnd, `${path}.windowEnd`);
  const total = integer(result.total, `${path}.total`, 1);
  const top = digestTop(result.top, `${path}.top`);
  return { id, windowEnd, total, top };
}

export function threadNewsCard(value: unknown, path: string): AgentThreadNewsCardV2 {
  const result = object(value, path);
  const eventId = boundedInteger(result.eventId, `${path}.eventId`, 1, MAX_NEWS_EVENT_ID);
  const headline = string(result.headline, `${path}.headline`);
  const excerpt = result.excerpt === undefined ? undefined : boundedString(result.excerpt, `${path}.excerpt`, 0, 200);
  const body = result.body === undefined ? undefined : string(result.body, `${path}.body`, 0);
  const sources = result.sources === undefined ? undefined : array(result.sources, `${path}.sources`)
    .flatMap((item, index) => {
      try {
        return [newsSource(item, `${path}.sources[${index}]`)];
      } catch (error) {
        if (!(error instanceof AgentV2ContractError)) throw error;
        return [];
      }
    });
  const imageUrl = result.imageUrl === undefined ? undefined : string(result.imageUrl, `${path}.imageUrl`);
  const publishedAt = timestamp(result.publishedAt, `${path}.publishedAt`);
  const source = result.source === undefined ? undefined : string(result.source, `${path}.source`);
  return {
    eventId,
    headline,
    ...(excerpt !== undefined && { excerpt }),
    ...(body !== undefined && { body }),
    ...(sources !== undefined && { sources }),
    ...(imageUrl !== undefined && { imageUrl }),
    publishedAt,
    ...(source !== undefined && { source }),
  };
}

function newsFeedItem(value: unknown, path: string): AgentNewsFeedItemV2 {
  const result = object(value, path);
  const eventId = boundedInteger(result.eventId, `${path}.eventId`, 1, MAX_NEWS_EVENT_ID);
  const deliveredAt = timestamp(result.deliveredAt, `${path}.deliveredAt`);
  const headline = string(result.headline, `${path}.headline`);
  const body = string(result.body, `${path}.body`, 0);
  const imageUrl = result.imageUrl === undefined ? undefined : string(result.imageUrl, `${path}.imageUrl`);
  const sources = array(result.sources, `${path}.sources`)
    .map((item, index) => newsSource(item, `${path}.sources[${index}]`));
  const discussion = result.discussion === undefined
    ? undefined
    : newsDiscussion(result.discussion, `${path}.discussion`);
  const discussionNaming = result.discussionNaming === undefined
    ? undefined
    : decodeDiscussionNaming(result.discussionNaming, `${path}.discussionNaming`);
  return {
    eventId,
    deliveredAt,
    headline,
    body,
    ...(imageUrl !== undefined && { imageUrl }),
    sources,
    ...(discussion !== undefined && { discussion }),
    ...(discussionNaming !== undefined && { discussionNaming }),
  };
}

function newsFeedDigest(value: unknown, path: string): AgentNewsFeedDigestV2 {
  const result = object(value, path);
  const id = digestId(result.id, `${path}.id`);
  const deliveredAt = timestamp(result.deliveredAt, `${path}.deliveredAt`);
  const top = digestTop(result.top, `${path}.top`, MAX_FEED_DIGEST_TOP_LENGTH);
  const total = integer(result.total, `${path}.total`, 1);
  const discussion = result.discussion === undefined
    ? undefined
    : newsDiscussion(result.discussion, `${path}.discussion`);
  const discussionNaming = result.discussionNaming === undefined
    ? undefined
    : decodeDiscussionNaming(result.discussionNaming, `${path}.discussionNaming`);
  return {
    id,
    deliveredAt,
    top,
    total,
    ...(discussion !== undefined && { discussion }),
    ...(discussionNaming !== undefined && { discussionNaming }),
  };
}

function digestId(value: unknown, path: string) {
  return boundedString(value, path, 1, MAX_DIGEST_ID_LENGTH);
}

function digestTop(value: unknown, path: string, maxLength?: number): AgentNewsDigestHeadlineV2[] {
  const top = array(value, path, maxLength);
  if (!top.length) fail(path);
  return top.map((headline, index) => digestHeadline(headline, `${path}[${index}]`));
}

function digestHeadline(value: unknown, path: string): AgentNewsDigestHeadlineV2 {
  const result = object(value, path);
  const eventId = boundedInteger(result.eventId, `${path}.eventId`, 1, MAX_NEWS_EVENT_ID);
  const headline = string(result.headline, `${path}.headline`);
  const imageUrl = result.imageUrl === undefined ? undefined : string(result.imageUrl, `${path}.imageUrl`);
  return { eventId, headline, ...(imageUrl !== undefined && { imageUrl }) };
}

function newsSource(value: unknown, path: string): AgentNewsFeedItemV2['sources'][number] {
  const source = object(value, path);
  const name = source.name === undefined ? undefined : string(source.name, `${path}.name`);
  const url = string(source.url, `${path}.url`);
  return { ...(name !== undefined && { name }), url };
}

function newsDiscussion(value: unknown, path: string): NonNullable<AgentNewsFeedItemV2['discussion']> {
  const result = object(value, path);
  const threadId = uuid(result.threadId, `${path}.threadId`);
  const icon = result.icon === undefined ? undefined : boundedString(result.icon, `${path}.icon`, 1, 16);
  return { threadId, ...(icon !== undefined && { icon }) };
}

function decodeDiscussionNaming(value: unknown, path: string): AgentNewsFeedItemV2['discussionNaming'] {
  try {
    const result = object(value, path);
    const title = boundedString(result.title, `${path}.title`, 1, 80);
    if (!title.trim() || title.includes('\u0000')) fail(`${path}.title`);
    const icon = result.icon === undefined ? undefined : boundedString(result.icon, `${path}.icon`, 1, 16);
    const followups = array(result.followups, `${path}.followups`, 3)
      .map((value, index) => followupText(value, `${path}.followups[${index}]`, 80));
    return { title, ...(icon !== undefined && { icon }), followups };
  } catch (error) {
    if (!(error instanceof AgentV2ContractError)) throw error;
    return undefined;
  }
}
