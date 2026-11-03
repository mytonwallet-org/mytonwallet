import type { AgentNewsFeedItemV2, AgentNewsFeedPageV2, AgentThreadNewsCardV2 } from '../types';

import {
  AgentV2ContractError,
  array,
  boundedInteger,
  boundedString,
  object,
  oneOf,
  string,
  timestamp,
} from '../wireReader';
import { protocol, uuid } from './readers';

const NEWS_FEED_LOCALES = new Set(['ru', 'en']);
const MAX_NEWS_EVENT_ID = 2_147_483_647;

export function decodeAgentV2NewsFeed(value: unknown): AgentNewsFeedPageV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const locale = oneOf<AgentNewsFeedPageV2['locale']>(result.locale, NEWS_FEED_LOCALES, '$.locale');
  const items = array(result.items, '$.items', 30).map((item, index) => newsFeedItem(item, `$.items[${index}]`));
  const nextCursor = result.nextCursor === undefined
    ? undefined
    : boundedString(result.nextCursor, '$.nextCursor', 1, 2048);
  return { protocolVersion: 3, locale, items, ...(nextCursor !== undefined && { nextCursor }) };
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
  return {
    eventId,
    deliveredAt,
    headline,
    body,
    ...(imageUrl !== undefined && { imageUrl }),
    sources,
    ...(discussion !== undefined && { discussion }),
  };
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
