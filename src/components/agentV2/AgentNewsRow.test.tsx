import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentNewsRow from './AgentNewsRow';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
// Each class name is its own key here
jest.mock('./AgentThreadList.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

describe('AgentNewsRow', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it.each([
    [0, '', false],
    [1, '1', false],
    [10, '10', false],
    [11, '', true],
    [1234, '', true],
  ])('marks %i unread news with %j after the preview, or with a dot alone', async (unreadCount, countText, hasDot) => {
    TeactDOM.render(<AgentNewsRow unreadCount={unreadCount} onClick={jest.fn()} />, root);
    await pause(20);

    expect(root.textContent).toBe(`NewsCrypto Market News${countText}`);
    expect(Boolean(root.querySelector('.unreadDot'))).toBe(hasDot);
  });

  it('shows the latest digest\'s first headline and picture, and counts the new digests', async () => {
    const latestItem = {
      eventId: 1,
      deliveredAt: '2026-10-30T12:00:00.000Z',
      headline: 'Latest news',
      body: '',
      sources: [],
      imageUrl: 'https://x.test/news.png',
    };
    const latestDigest = {
      id: 'en:2026-10-30T06:00:00.000Z',
      deliveredAt: '2026-10-30T06:00:00.000Z',
      top: [
        { eventId: 2, headline: 'First headline', imageUrl: 'https://x.test/first.png' },
        { eventId: 3, headline: 'Second headline' },
      ],
      total: 5,
    };
    TeactDOM.render(
      <AgentNewsRow latestItem={latestItem} latestDigest={latestDigest} unreadCount={2} onClick={jest.fn()} />,
      root,
    );
    await pause(20);

    expect(root.querySelector('.itemPreview')?.textContent).toBe('First headline');
    expect(root.querySelector('img')?.getAttribute('src')).toBe('https://x.test/first.png');
    expect(root.querySelector('[data-agent-news-row]')?.getAttribute('aria-label'))
      .toContain('$agent_news_unread_digests_count');
  });
});
