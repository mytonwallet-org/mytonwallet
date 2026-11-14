import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import { getDayStartAt } from '../../util/dateFormat';
import { getAgentNewsCopyText, getAgentNewsMenuSources } from '../agent/helpers/agentNews';
import {
  buildAgentNewsFeedRows,
  buildAgentNewsPreviewCard,
  formatAgentNewsPostTime,
  getAgentNewsUnreadItems,
  mergeAgentNewsFeedEntries,
  mergeAgentNewsItems,
} from './agentNewsFeedItems';

describe('agentNewsFeedItems', () => {
  it('shows a post\'s time today, its day and time this year, and its year before that', () => {
    const now = new Date(2026, 9, 21, 18, 0).getTime();

    expect(formatAgentNewsPostTime('ru', new Date(2026, 9, 21, 9, 5).toISOString(), now)).toBe('09:05');
    expect(formatAgentNewsPostTime('ru', new Date(2026, 6, 20, 15, 38).toISOString(), now)).toBe('20 июл, 15:38');
    expect(formatAgentNewsPostTime('ru', new Date(2025, 6, 20, 15, 38).toISOString(), now))
      .toBe('20 июл 2025, 15:38');
    // English writes the time in 12 hours, with a space before AM or PM that is narrow in newer locale data
    expect(formatAgentNewsPostTime('en', new Date(2026, 9, 21, 9, 5).toISOString(), now)).toMatch(/^9:05\sAM$/);
    expect(formatAgentNewsPostTime('en', new Date(2025, 6, 20, 15, 38).toISOString(), now))
      .toMatch(/^Jul 20, 2025, 3:38\sPM$/);
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

  it('merges digest entries between news by delivery time and keeps each digest once across page refreshes', () => {
    const digest = {
      id: 'digest-1', deliveredAt: '2026-10-21T08:00:00.000Z', total: 2,
      top: [{ eventId: 1, headline: 'News 1' }],
    };
    const entries = mergeAgentNewsFeedEntries([
      newsItem(1, '2026-10-21T07:00:00.000Z'), newsItem(2, '2026-10-21T09:00:00.000Z'),
    ], [digest]);

    expect(entries).toMatchObject([
      { kind: 'news', eventId: 1 }, { kind: 'digest', ...digest }, { kind: 'news', eventId: 2 },
    ]);
    expect(mergeAgentNewsFeedEntries([], [{ ...digest, discussion: { threadId: 'discussion' } }], entries))
      .toMatchObject([
        { kind: 'news', eventId: 1 },
        { kind: 'digest', id: digest.id, discussion: { threadId: 'discussion' } },
        { kind: 'news', eventId: 2 },
      ]);
  });

  it('opens only web and Telegram sources without credentials', () => {
    function getUrls(url: string) {
      return getAgentNewsMenuSources(newsItem(1, '2026-10-21T09:00:00.000Z', 'News', url)).map((source) => source.url);
    }

    expect(getUrls('https://example.com/a')).toEqual(['https://example.com/a']);
    expect(getUrls('tg://resolve?domain=mypulse')).toEqual(['tg://resolve?domain=mypulse']);
    expect(getUrls('javascript:alert(1)')).toEqual([]);
    expect(getUrls('https://user:pass@example.com')).toEqual([]);
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

  it('finds feed and post sources with the same URL checks', () => {
    const item = newsItem(5, '2026-10-21T09:00:00.000Z', 'News', 'tg://resolve?domain=mypulse');

    const urls = [{ name: 'Source', url: 'tg://resolve?domain=mypulse' }];
    expect(getAgentNewsMenuSources(item)).toEqual(urls);
    expect(getAgentNewsMenuSources(buildAgentNewsPreviewCard(item))).toEqual(urls);
    expect(getAgentNewsMenuSources({ sources: [{ url: 'javascript:alert(1)' }] })).toEqual([]);
  });

  it('copies the complete post with plain body text and without its source', () => {
    const item = { ...newsItem(5, '2026-10-21T09:00:00.000Z'), body: `**Bitcoin** ${'a'.repeat(300)}` };

    expect(getAgentNewsCopyText(buildAgentNewsPreviewCard(item)))
      .toBe(`News 5\n\nBitcoin ${'a'.repeat(300)}`);
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
