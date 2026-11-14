import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type {
  AgentNewsFeedDigestV2, AgentNewsFeedItemV2, AgentNewsFeedLocaleV2,
} from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';
import { shareUrl } from '../../util/share';
import { copyAgentText } from '../agent/helpers/copyAgentText';

import AgentNewsCard from './AgentNewsCard';
import AgentNewsDigestCard from './AgentNewsDigestCard';
import AgentNewsPost from './AgentNewsPost';

let mockLangCode = 'en';
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: mockLangCode }),
}));
jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/share', () => ({ shareUrl: jest.fn() }));
jest.mock('../../hooks/useDeviceScreen', () => ({ useDeviceScreen: () => ({ isPortrait: true }) }));
// Every style module maps to the same stub, so its one mock names the classes of the bubble and of the digest
jest.mock('../agent/MessageBubble.module.scss', () => ({
  bubble: 'bubble',
  incoming: 'incoming',
  menu: 'bubble-menu',
  appearing: 'appearing',
  digestBullet: 'digest-bullet',
  digestThumbnailPlace: 'thumbnail-place',
  postIcon: 'news-mark',
}));
jest.mock('../agent/helpers/copyAgentText', () => ({ copyAgentText: jest.fn() }));
const mockOpenMediaViewer = jest.fn();
jest.mock('../../global', () => {
  const actual = jest.requireActual<typeof import('../../global')>('../../global');
  return { ...actual, getActions: () => ({ ...actual.getActions(), openMediaViewer: mockOpenMediaViewer }) };
});

const ITEM: AgentNewsFeedItemV2 = {
  eventId: 7,
  deliveredAt: '2026-10-21T09:00:00.000Z',
  headline: 'News headline',
  body: 'Complete **news** body',
  sources: [{ name: 'Source', url: 'https://example.com/news' }],
  imageUrl: 'https://example.com/picture.png',
};
const DIGEST: AgentNewsFeedDigestV2 = {
  id: 'digest-1', deliveredAt: ITEM.deliveredAt, total: 1, top: [{ eventId: ITEM.eventId, headline: ITEM.headline }],
};
const DIGEST_WITH_PICTURES: AgentNewsFeedDigestV2 = {
  ...DIGEST,
  total: 3,
  top: [
    { eventId: 1, headline: 'First', imageUrl: 'https://example.com/1.png' },
    { eventId: 2, headline: 'Second' },
    { eventId: 3, headline: 'Third', imageUrl: 'https://example.com/3.png' },
  ],
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
    // The foot tells the time alone, as a message's does; the source opens from the menu
    const time = root.querySelector('time')!;
    expect(time.getAttribute('datetime')).toBe(ITEM.deliveredAt);
    // The time alone, whatever the day, in the 12 hours English writes it in
    expect(time.textContent).toMatch(/^\d{1,2}:\d{2}\s[AP]M$/);
    expect(time.parentElement!.lastElementChild).toBe(time);
    expect(root.querySelector('a')).toBeNull();
    expect(root.textContent).not.toContain('Source');

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

  it('offers the post\'s menu, copying the text of news without a source and sharing its link', async () => {
    renderCard({ ...ITEM, sources: [] });
    await pause(20);

    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);

    const buttons = Array.from(document.body.querySelectorAll<HTMLButtonElement>('[role="menuitem"], button'))
      .filter(({ textContent }) => ['Copy', 'Share', '$agent_news_sources'].includes(textContent!));
    expect(buttons.map(({ textContent }) => textContent)).toEqual(['Copy', 'Share']);
    buttons[0].click();
    expect(copyAgentText).toHaveBeenCalledWith('News headline\n\nComplete news body');
    expect(shareUrl).not.toHaveBeenCalled();
    // Without the feed's language at hand, the link names the one the feed is asked in for the app's
    buttons[1].click();
    expect(shareUrl).toHaveBeenCalledWith(
      'https://my.tt/agent?news=7&lang=en&utm_source=pulse_share', 'News headline', 'News headline',
    );

    renderCard({ ...ITEM, sources: [] }, undefined, undefined, undefined, 'ru');
    await pause(20);
    buttons[1].click();
    expect(shareUrl).toHaveBeenLastCalledWith(
      'https://my.tt/agent?news=7&lang=ru&utm_source=pulse_share', 'News headline', 'News headline',
    );

    // In Russian, the feed is asked in Russian, which the link names without the feed's language at hand
    mockLangCode = 'ru';
    try {
      renderCard({ ...ITEM, sources: [] });
      await pause(20);
      buttons[1].click();
    } finally {
      mockLangCode = 'en';
    }
    expect(shareUrl).toHaveBeenLastCalledWith(
      'https://my.tt/agent?news=7&lang=ru&utm_source=pulse_share', 'News headline', 'News headline',
    );
    expect(shareUrl).toHaveBeenCalledTimes(3);
  });

  it.each(['card', 'post'])('offers only Copy on a digest %s', async (kind) => {
    TeactDOM.render(kind === 'card' ? (
      <AgentNewsDigestCard
        digest={DIGEST}
        messageId={-1}
        onOpenNewsDiscussion={jest.fn()}
        onOpenDigestDiscussion={jest.fn()}
      />
    ) : (
      <AgentNewsPost
        digest={{ id: DIGEST.id, windowEnd: DIGEST.deliveredAt, total: DIGEST.total, top: DIGEST.top }}
        message={{ id: -1, text: '', isOutgoing: false, timestamp: Date.parse(DIGEST.deliveredAt) }}
        isDisabled={false}
        shouldShowFollowups={false}
      />
    ), root);
    await pause(20);

    root.querySelector('h3')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2 }));
    await pause(20);

    const buttons = Array.from(document.body.querySelectorAll<HTMLButtonElement>('[role="menuitem"], button'))
      .filter(({ textContent }) => textContent === 'Copy' || textContent === 'Share');
    expect(buttons.map(({ textContent }) => textContent)).toEqual(['Copy']);
  });

  it.each([
    ['card', 'feedDigest-digest-1'],
    ['post', 'postDigest-digest-1'],
  ])('leads a digest %s\'s headlines with their pictures, which open the viewer apart from the discussion', async (
    kind, surface,
  ) => {
    const onOpenNews = jest.fn();
    renderDigest(kind, DIGEST_WITH_PICTURES, onOpenNews);
    await pause(20);

    const rows = Array.from(root.querySelectorAll('[role="listitem"]'));
    const pictures = Array.from(root.querySelectorAll<HTMLImageElement>('[role="listitem"] img'));
    expect(pictures.map((picture) => picture.closest('[role="listitem"]'))).toEqual([rows[0], rows[2]]);
    // A headline without a picture keeps the texts in line with the News mark in its place, and no row has a bullet
    expect(rows.map((row) => row.querySelectorAll('.thumbnail-place').length)).toEqual([1, 1, 1]);
    expect(rows.map((row) => row.querySelectorAll('.news-mark').length)).toEqual([0, 1, 0]);
    expect(root.querySelector('.digest-bullet')).toBeNull();

    pictures[1].click();
    const ids = [`agent-news-${surface}-1`, `agent-news-${surface}-3`];
    expect(mockOpenMediaViewer).toHaveBeenCalledTimes(1);
    const { mediaId, pictures: viewerPictures } = mockOpenMediaViewer.mock.calls[0][0];
    expect(viewerPictures.ids).toEqual(ids);
    expect(viewerPictures.ids.indexOf(mediaId)).toBe(1);
    expect(pictures[1].dataset.mediaViewerPictureId).toBe(mediaId);
    // Captioned with the headline alone, and not shared, as its digest is not
    expect(viewerPictures.byId[mediaId].news).toStrictEqual({
      headline: 'Third', body: undefined, sources: undefined, timestamp: Date.parse(DIGEST.deliveredAt),
    });
    expect(onOpenNews).not.toHaveBeenCalled();

    // The first picture opens the viewer at itself, not at the last one
    pictures[0].click();
    const { mediaId: firstMediaId, pictures: firstViewerPictures } = mockOpenMediaViewer.mock.calls[1][0];
    expect(firstMediaId).toBe(ids[0]);
    expect(firstViewerPictures.ids.indexOf(firstMediaId)).toBe(0);

    // The rest of the row, the News mark's square included, opens the news item's discussion
    rows[1].querySelector<HTMLElement>('.thumbnail-place')!.click();
    expect(onOpenNews.mock.calls[0][0]).toBe(2);

    // A picture that fails leaves the News mark and is left out of the viewer
    pictures[0].dispatchEvent(new Event('error'));
    await pause(20);
    expect(rows[0].querySelector('img')).toBeNull();
    expect(rows[0].querySelector('.news-mark')).not.toBeNull();
    root.querySelector<HTMLImageElement>('[role="listitem"] img')!.click();
    expect(mockOpenMediaViewer.mock.calls[2][0].pictures.ids).toEqual([`agent-news-${surface}-3`]);
  });

  it.each(['Enter', ' '])('opens a digest\'s picture with %j, as a button named by its headline', async (key) => {
    const onOpenNews = jest.fn();
    renderDigest('card', DIGEST_WITH_PICTURES, onOpenNews);
    await pause(20);

    const picture = root.querySelectorAll<HTMLImageElement>('[role="listitem"] img')[0];
    expect(picture.getAttribute('role')).toBe('button');
    expect(picture.tabIndex).toBe(0);
    expect(picture.getAttribute('aria-label')).toBe('First');
    expect(picture.hasAttribute('aria-hidden')).toBe(false);
    // The News mark's square stays out of reach
    expect(root.querySelector('.thumbnail-place')!.getAttribute('aria-hidden')).toBe('true');

    picture.focus();
    const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
    picture.dispatchEvent(event);
    picture.dispatchEvent(new KeyboardEvent('keydown', { key: 'a', bubbles: true }));
    await pause(20);

    expect(event.defaultPrevented).toBe(true);
    expect(mockOpenMediaViewer).toHaveBeenCalledTimes(1);
    const { mediaId, pictures } = mockOpenMediaViewer.mock.calls[0][0];
    expect(mediaId).toBe('agent-news-feedDigest-digest-1-1');
    expect(pictures.ids.indexOf(mediaId)).toBe(0);
    expect(onOpenNews).not.toHaveBeenCalled();
  });

  it('tells apart the pictures of the same news in two digests of the feed', async () => {
    const digests = ['digest-a', 'digest-b'].map((id, index): AgentNewsFeedDigestV2 => ({
      ...DIGEST, id, top: [{ eventId: 42, headline: `Headline ${index}`, imageUrl: `https://example.com/${id}.png` }],
    }));
    TeactDOM.render(
      <div>
        {digests.map((digest) => (
          <AgentNewsDigestCard
            key={digest.id}
            digest={digest}
            messageId={-1}
            onOpenNewsDiscussion={jest.fn()}
            onOpenDigestDiscussion={jest.fn()}
          />
        ))}
      </div>,
      root,
    );
    await pause(20);

    const pictures = Array.from(root.querySelectorAll<HTMLImageElement>('[role="listitem"] img'));
    const ids = pictures.map((picture) => picture.dataset.mediaViewerPictureId);
    expect(ids).toEqual(['agent-news-feedDigest-digest-a-42', 'agent-news-feedDigest-digest-b-42']);

    pictures[1].click();
    const { mediaId, pictures: viewerPictures } = mockOpenMediaViewer.mock.calls[0][0];
    expect(mediaId).toBe(ids[1]);
    expect(viewerPictures.ids).toEqual([ids[1]]);
    expect(viewerPictures.byId[mediaId].url).toBe('https://example.com/digest-b.png');
  });

  it.each(['card', 'post'])('keeps the bullets of a digest %s without pictures', async (kind) => {
    renderDigest(kind, { ...DIGEST_WITH_PICTURES, top: DIGEST_WITH_PICTURES.top.map(({ imageUrl, ...rest }) => rest) });
    await pause(20);

    expect(root.querySelectorAll('.digest-bullet')).toHaveLength(3);
    expect(root.querySelector('[role="list"] :is(img, .thumbnail-place, .news-mark)')).toBeNull();
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

  function renderDigest(kind: string, digest: AgentNewsFeedDigestV2, onOpenNews = jest.fn()) {
    TeactDOM.render(kind === 'card' ? (
      <AgentNewsDigestCard
        digest={digest}
        messageId={-1}
        onOpenNewsDiscussion={onOpenNews}
        onOpenDigestDiscussion={jest.fn()}
      />
    ) : (
      <AgentNewsPost
        digest={{ id: digest.id, windowEnd: digest.deliveredAt, total: digest.total, top: digest.top }}
        message={{ id: -1, text: '', isOutgoing: false, timestamp: Date.parse(digest.deliveredAt) }}
        isDisabled={false}
        shouldShowFollowups={false}
        onOpenDigestNews={onOpenNews}
      />
    ), root);
  }

  function renderCard(
    item: AgentNewsFeedItemV2, onOpenDiscussion = jest.fn(), onOpenPicture = jest.fn(), isJustAdded = false,
    locale?: AgentNewsFeedLocaleV2,
  ) {
    TeactDOM.render(
      <AgentNewsCard
        item={item}
        locale={locale}
        isJustAdded={isJustAdded}
        isDiscussionContinued={false}
        onOpenDiscussion={onOpenDiscussion}
        onOpenPicture={onOpenPicture}
      />,
      root,
    );
  }
});
