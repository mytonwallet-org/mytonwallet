import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';
import { shareUrl } from '../../util/share';

import AgentNewsCard from './AgentNewsCard';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../hooks/useDeviceScreen', () => ({ useDeviceScreen: () => ({ isPortrait: true }) }));
jest.mock('../agent/MessageBubble.module.scss', () => ({
  bubble: 'bubble', incoming: 'incoming', menu: 'bubble-menu', appearing: 'appearing',
}));
jest.mock('../../util/share', () => ({ shareUrl: jest.fn() }));

const ITEM: AgentNewsFeedItemV2 = {
  eventId: 7,
  deliveredAt: '2026-10-21T09:00:00.000Z',
  headline: 'News headline',
  body: 'Complete **news** body',
  sources: [{ name: 'Source', url: 'https://example.com/news' }],
  imageUrl: 'https://example.com/picture.png',
};

describe('AgentNewsCard', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(root);
    document.body.appendChild(portals);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    jest.clearAllMocks();
  });

  it('is a message of the list that opens its picture and its discussion from the card', async () => {
    const onOpenDiscussion = jest.fn();
    const onOpenPicture = jest.fn();
    renderCard(ITEM, onOpenDiscussion, onOpenPicture);
    await pause(20);

    expect(root.querySelector('[data-agent-v2-message-id="7"]')?.getAttribute('data-agent-v2-message-role'))
      .toBe('assistant');
    expect(root.querySelector('time')?.getAttribute('datetime')).toBe(ITEM.deliveredAt);
    expect(root.querySelector('a')?.textContent).toBe('Source');

    const picture = root.querySelector<HTMLImageElement>('img')!;
    // The picture's button is named by its news, which a screen reader tells among the feed's pictures
    expect(picture.getAttribute('aria-label')).toBe('News headline');
    picture.click();
    expect(onOpenPicture).toHaveBeenCalledWith(7);
    // A picture is a button for the keyboard too
    picture.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    picture.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
    picture.dispatchEvent(new KeyboardEvent('keydown', { key: 'a', bubbles: true }));
    expect(onOpenPicture).toHaveBeenCalledTimes(3);

    root.querySelector<HTMLButtonElement>('[aria-label="$agent_news_discuss, News headline"]')!.click();
    expect(onOpenDiscussion).toHaveBeenCalledWith(ITEM, root.querySelector('[data-agent-news-event-id="7"]'));
  });

  it('offers the post\'s menu, sharing the text of news without a source to pass on', async () => {
    renderCard({ ...ITEM, sources: [] });
    await pause(20);

    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);

    const buttons = Array.from(document.body.querySelectorAll<HTMLButtonElement>('[role="menuitem"], button'))
      .filter(({ textContent }) => textContent === 'Copy' || textContent === 'Share');
    expect(buttons.map(({ textContent }) => textContent)).toEqual(['Copy', 'Share']);
    buttons[1].click();
    expect(shareUrl).toHaveBeenCalledWith(undefined, ITEM.headline, 'News headline\n\nComplete news body');
  });

  it('keeps its look while its menu tints the rest of the screen on a phone, as a message does', async () => {
    renderCard(ITEM);
    await pause(20);

    const bubble = root.querySelector<HTMLElement>('.bubble')!;
    bubble.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(50);

    expect(document.body.querySelector('.bubble-menu')).not.toBeNull();
    expect(bubble.classList.contains('bubble-menu')).toBe(false);
  });

  it('fades in as a chat\'s new message does when it comes while the feed is open', async () => {
    renderCard(ITEM, jest.fn(), jest.fn(), true);
    await pause(20);
    expect(root.querySelector('.bubble')!.classList.contains('appearing')).toBe(true);

    TeactDOM.render(undefined, root);
    renderCard(ITEM);
    await pause(20);
    expect(root.querySelector('.bubble')!.classList.contains('appearing')).toBe(false);
  });

  function renderCard(
    item: AgentNewsFeedItemV2, onOpenDiscussion = jest.fn(), onOpenPicture = jest.fn(), isJustAdded = false,
  ) {
    TeactDOM.render(
      <AgentNewsCard
        item={item}
        isJustAdded={isJustAdded}
        isDiscussionContinued={false}
        onOpenDiscussion={onOpenDiscussion}
        onOpenPicture={onOpenPicture}
      />,
      root,
    );
  }
});
