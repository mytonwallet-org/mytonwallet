import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentNewsFeedItemV2, AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';

import AgentNewsRow from './AgentNewsRow';
import AgentThreadListItem from './AgentThreadListItem';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => Object.assign((key: string) => key, { code: 'en' }),
}));

const IMAGE_URL = 'https://pulse.mytonwallet.org/images/42.jpg';
const NEWS_ITEM: AgentNewsFeedItemV2 = {
  eventId: 42,
  deliveredAt: '2026-10-27T23:57:00.000Z',
  headline: 'TON rallies',
  body: 'TON is up 3%.',
  imageUrl: IMAGE_URL,
  sources: [],
};
const DISCUSSION: AgentThreadListItemV2 = {
  thread: {
    id: 'thread-1',
    revision: 1,
    createdAt: '2026-10-27T23:57:00.000Z',
    updatedAt: '2026-10-27T23:57:00.000Z',
    lastActivityAt: '2026-10-27T23:57:00.000Z',
    messageCount: 3,
    title: 'TON rallies',
    news: {
      eventId: 42, headline: 'TON rallies', imageUrl: IMAGE_URL, publishedAt: '2026-10-27T23:50:00.000Z',
    },
  },
  preview: 'Why did it go up?',
};

describe('a picture before the preview of a chat list row', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('leads the News row\'s preview with the newest news picture, loaded lazily at its size', async () => {
    TeactDOM.render(<AgentNewsRow latestItem={NEWS_ITEM} unreadCount={0} onClick={jest.fn()} />, root);
    await pause(20);

    const thumbnail = root.querySelector('img')!;
    expect(thumbnail.getAttribute('src')).toBe(IMAGE_URL);
    // Teact sets `loading` as a property, which jsdom does not reflect to the attribute
    expect(thumbnail.loading).toBe('lazy');
    expect([thumbnail.getAttribute('width'), thumbnail.getAttribute('height')]).toEqual(['20', '20']);
    expect(thumbnail.parentElement!.firstChild).toBe(thumbnail);
    expect(thumbnail.parentElement!.textContent).toBe('TON rallies');
  });

  it('leaves the News row without a picture when the newest news has none', async () => {
    TeactDOM.render(
      <AgentNewsRow latestItem={{ ...NEWS_ITEM, imageUrl: undefined }} unreadCount={0} onClick={jest.fn()} />,
      root,
    );
    await pause(20);

    expect(root.querySelector('img')).toBeNull();
  });

  it.each([
    ['leads a discussion\'s preview with its news picture', DISCUSSION, 'Why did it go up?'],
    ['shows no picture in a chat that names itself with its preview', {
      ...DISCUSSION, thread: { ...DISCUSSION.thread, title: undefined },
    }, undefined],
    ['shows no picture in a chat about no news', {
      ...DISCUSSION, thread: { ...DISCUSSION.thread, news: undefined },
    }, undefined],
  ])('%s', async (_name, item, previewWithPicture) => {
    TeactDOM.render(
      <AgentThreadListItem
        item={item}
        isUnread={false}
        onSelect={jest.fn()}
        onRename={jest.fn()}
        onTogglePin={jest.fn()}
        onDelete={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const thumbnail = root.querySelector('img') ?? undefined;
    const preview = thumbnail?.parentElement ?? undefined;
    expect(preview?.textContent).toBe(previewWithPicture);
    expect(preview?.firstChild).toBe(thumbnail);
  });
});
