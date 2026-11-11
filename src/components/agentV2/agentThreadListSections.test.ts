import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { LangFn } from '../../hooks/useLang';

import { buildAgentThreadListSections, mergeAgentThreadListRefresh } from './agentThreadListSections';

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
