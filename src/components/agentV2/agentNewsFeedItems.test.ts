import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import { getDayStartAt } from '../../util/dateFormat';
import { openUrl } from '../../util/openUrl';
import { getAgentNewsCopyText, getAgentNewsSourceUrl, openAgentNewsSource } from '../agent/helpers/agentNews';
import {
  buildAgentNewsFeedRows,
  buildAgentNewsPreviewCard,
  formatAgentNewsPostTime,
  getAgentNewsUnreadItems,
  mergeAgentNewsItems,
} from './agentNewsFeedItems';

jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));

describe('agentNewsFeedItems', () => {
  it('shows a post\'s time today, its day and time this year, and its year before that', () => {
    const now = new Date(2026, 9, 21, 18, 0).getTime();

    expect(formatAgentNewsPostTime('en', new Date(2026, 9, 21, 9, 5).toISOString(), now)).toBe('09:05');
    expect(formatAgentNewsPostTime('en', new Date(2026, 6, 20, 15, 38).toISOString(), now)).toBe('Jul 20, 15:38');
    expect(formatAgentNewsPostTime('ru', new Date(2026, 6, 20, 15, 38).toISOString(), now)).toBe('20 июл, 15:38');
    expect(formatAgentNewsPostTime('en', new Date(2025, 6, 20, 15, 38).toISOString(), now))
      .toBe('Jul 20, 2025, 15:38');
  });

  it('merges pages into one item per news, oldest first, the latest delivery winning', () => {
    const merged = mergeAgentNewsItems([
      newsItem(3, '2026-10-21T09:00:00.000Z'),
      newsItem(1, '2026-10-20T08:00:00.000Z'),
      newsItem(2, '2026-10-21T07:00:00.000Z', 'Old copy'),
      newsItem(2, '2026-10-21T08:00:00.000Z', 'New copy'),
    ]);

    expect(merged.map(({ eventId, headline }) => [eventId, headline])).toEqual([
      [1, 'News 1'], [2, 'New copy'], [3, 'News 3'],
    ]);
  });

  it('heads each day and marks the first news delivered after the read mark as new', () => {
    const items = mergeAgentNewsItems([
      newsItem(1, '2026-10-20T08:00:00.000Z'),
      newsItem(2, '2026-10-21T07:00:00.000Z'),
      newsItem(3, '2026-10-21T09:00:00.000Z'),
    ]);
    const unread = getAgentNewsUnreadItems(items, '2026-10-21T07:00:00.000Z');

    expect(unread.map(({ eventId }) => eventId)).toEqual([3]);
    expect(getAgentNewsUnreadItems(items, undefined)).toEqual([]);
    expect(buildAgentNewsFeedRows(items, unread[0].eventId).map(({ key }) => key)).toEqual([
      `day-${getDayStartAt(Date.parse('2026-10-20T08:00:00.000Z'))}`,
      'news-1',
      `day-${getDayStartAt(Date.parse('2026-10-21T07:00:00.000Z'))}`,
      'news-2',
      'unread',
      'news-3',
    ]);
  });

  it('opens only web and Telegram sources without credentials', () => {
    expect(getAgentNewsSourceUrl(newsItem(1, '2026-10-21T09:00:00.000Z', 'News', 'https://example.com/a')))
      .toBe('https://example.com/a');
    expect(getAgentNewsSourceUrl(newsItem(1, '2026-10-21T09:00:00.000Z', 'News', 'tg://resolve?domain=mypulse')))
      .toBe('tg://resolve?domain=mypulse');
    expect(getAgentNewsSourceUrl(newsItem(1, '2026-10-21T09:00:00.000Z', 'News', 'javascript:alert(1)')))
      .toBeUndefined();
    expect(getAgentNewsSourceUrl(newsItem(1, '2026-10-21T09:00:00.000Z', 'News', 'https://user:pass@example.com')))
      .toBeUndefined();
  });

  it('previews a news chat with its full body, sources, plain excerpt and delivery time', () => {
    const item = { ...newsItem(5, '2026-10-21T09:00:00.000Z'), body: `**Bitcoin** ${'a'.repeat(300)}` };

    expect(buildAgentNewsPreviewCard(item)).toEqual({
      eventId: 5,
      headline: 'News 5',
      body: item.body,
      sources: item.sources,
      excerpt: `Bitcoin ${'a'.repeat(192)}`,
      publishedAt: '2026-10-21T09:00:00.000Z',
      source: 'Source',
    });
  });

  it('opens feed and post sources with the same URL checks', () => {
    const item = newsItem(5, '2026-10-21T09:00:00.000Z', 'News', 'tg://resolve?domain=mypulse');

    void openAgentNewsSource(item);
    void openAgentNewsSource(buildAgentNewsPreviewCard(item));
    void openAgentNewsSource({ sources: [{ url: 'javascript:alert(1)' }] });

    expect(openUrl).toHaveBeenCalledTimes(2);
    expect(openUrl).toHaveBeenNthCalledWith(1, 'tg://resolve?domain=mypulse');
    expect(openUrl).toHaveBeenNthCalledWith(2, 'tg://resolve?domain=mypulse');
  });

  it('copies the complete post with plain body text and its source', () => {
    const item = { ...newsItem(5, '2026-10-21T09:00:00.000Z'), body: `**Bitcoin** ${'a'.repeat(300)}` };

    expect(getAgentNewsCopyText(buildAgentNewsPreviewCard(item)))
      .toBe(`News 5\n\nBitcoin ${'a'.repeat(300)}\n\nhttps://example.com`);
  });
});

function newsItem(
  eventId: number,
  deliveredAt: string,
  headline = `News ${eventId}`,
  url = 'https://example.com',
): AgentNewsFeedItemV2 {
  return {
    eventId,
    deliveredAt,
    headline,
    body: 'Body',
    sources: [{ name: 'Source', url }],
  };
}
