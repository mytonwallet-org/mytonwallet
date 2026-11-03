import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { LangFn } from '../../hooks/useLang';

import {
  buildAgentThreadListSections,
  formatAgentThreadTime,
  mergeAgentThreadListRefresh,
} from './agentThreadListSections';

const lang = Object.assign((key: string) => key, { code: 'en' as const }) as LangFn;
// Wednesday, October 21, 2026, in the local time zone like the list itself
const NOW = new Date(2026, 9, 21, 15, 0).getTime();

describe('buildAgentThreadListSections', () => {
  it('puts pinned chats first and groups the rest by day, newest first', () => {
    const sections = buildAgentThreadListSections([
      item('older', new Date(2026, 9, 10, 9, 0)),
      item('yesterday', new Date(2026, 9, 20, 18, 0)),
      item('pinned', new Date(2026, 9, 1, 12, 0), true),
      item('today-early', new Date(2026, 9, 21, 9, 0)),
      item('monday', new Date(2026, 9, 19, 12, 0)),
      item('today-late', new Date(2026, 9, 21, 14, 0)),
    ], lang, NOW);

    expect(sections.map(({ title, items }) => [title, items.map(({ thread }) => thread.id)])).toEqual([
      ['Pinned', ['pinned']],
      ['Today', ['today-late', 'today-early']],
      ['Yesterday', ['yesterday']],
      ['Monday', ['monday']],
      [expect.stringMatching(/^October 10/), ['older']],
    ]);
  });
});

describe('mergeAgentThreadListRefresh', () => {
  it('updates the first page and keeps the chats later pages loaded', () => {
    const renamed = item('recent', new Date(2026, 9, 21, 14, 0));
    renamed.thread.title = 'Renamed';
    const merged = mergeAgentThreadListRefresh([
      item('recent', new Date(2026, 9, 21, 12, 0)),
      item('older', new Date(2026, 8, 1, 12, 0)),
    ], [renamed, item('new', new Date(2026, 9, 21, 13, 0))]);

    expect(merged.map(({ thread }) => [thread.id, thread.title])).toEqual([
      ['recent', 'Renamed'],
      ['new', undefined],
      ['older', undefined],
    ]);
  });
});

describe('formatAgentThreadTime', () => {
  it('shows the time today, the weekday within a week and the date before that', () => {
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 21, 10, 5).toISOString(), NOW)).toBe('10:05');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 19, 10, 5).toISOString(), NOW)).toBe('Mon');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 10, 10, 5).toISOString(), NOW)).toMatch(/^Oct 10/);
  });

  it('shows the time of yesterday\'s last 12 hours and "Yesterday" before them', () => {
    const lastNight = new Date(2026, 9, 20, 23, 57).toISOString();

    expect(formatAgentThreadTime(lang, lastNight, new Date(2026, 9, 21, 0, 57).getTime())).toBe('23:57');
    expect(formatAgentThreadTime(lang, lastNight, new Date(2026, 9, 21, 11, 56, 59).getTime())).toBe('23:57');
    expect(formatAgentThreadTime(lang, lastNight, new Date(2026, 9, 21, 11, 57).getTime())).toBe('Yesterday');
    expect(formatAgentThreadTime(lang, lastNight, new Date(2026, 9, 21, 11, 58).getTime())).toBe('Yesterday');
  });

  it('turns the day at midnight', () => {
    const midnight = new Date(2026, 9, 21, 0, 0).getTime();

    expect(formatAgentThreadTime(lang, new Date(midnight).toISOString(), midnight + 1)).toBe('00:00');
    expect(formatAgentThreadTime(lang, new Date(midnight - 1).toISOString(), midnight)).toBe('23:59');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 20, 12, 0, 1).toISOString(), midnight)).toBe('12:00');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 20, 12, 0).toISOString(), midnight)).toBe('Yesterday');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 19, 23, 59).toISOString(), midnight)).toBe('Mon');
  });

  it('names the weekday for six days back and the date from a week back', () => {
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 15, 23, 59).toISOString(), NOW)).toBe('Thu');
    expect(formatAgentThreadTime(lang, new Date(2026, 9, 14, 23, 59).toISOString(), NOW)).toMatch(/^Oct 14/);
  });
});

function item(id: string, lastActivityAt: Date, isPinned?: true): AgentThreadListItemV2 {
  const timestamp = lastActivityAt.toISOString();
  return {
    thread: {
      id,
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      lastActivityAt: timestamp,
      messageCount: 2,
      ...(isPinned && { isPinned }),
    },
  };
}
