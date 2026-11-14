import '../../global/actions/ui/misc';

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import * as globalState from '../../global';

import type { ApiNft } from '../../api/types';
import type { MediaViewerPictureNews } from '../../global/types';
import { MediaType } from '../../global/types';

import { openUrl } from '../../util/openUrl';
import { pause } from '../../util/schedulers';
import { shareUrl } from '../../util/share';
import { copyAgentText } from '../agent/helpers/copyAgentText';
import { buildAgentNewsPictures, getAgentDigestPictureSurface } from '../agentV2/agentNewsPictures';

import useControlsSignal from './hooks/useControlsSignal';

import MediaViewer from './MediaViewer';
import PictureActions from './PictureActions';
import PictureCaption from './PictureCaption';
import PictureInfo from './PictureInfo';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign(
    (key: string, values?: Record<string, unknown>) => (values ? `${key} ${Object.values(values).join('/')}` : key),
    { code: 'en' },
  ),
}));
jest.mock('./MediaViewer.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));
jest.mock('../../util/openUrl', () => ({ openUrl: jest.fn() }));
jest.mock('../../util/share', () => ({ shareUrl: jest.fn() }));
jest.mock('../agent/helpers/copyAgentText', () => ({ copyAgentText: jest.fn() }));

// The caption measures itself in a frame, which runs on its timeout fallback here
const FRAME_FALLBACK_DELAY = 50;
const WAIT_ATTEMPTS = 40;
const NEWS_LINK = 'https://my.tt/agent?news=7&lang=ru&utm_source=pulse_share';

const NEWS: MediaViewerPictureNews = {
  eventId: 7,
  locale: 'ru',
  headline: 'News headline',
  body: 'The **news** body',
  sources: [{ name: 'Source', url: 'https://example.com/news' }],
  timestamp: Date.UTC(2026, 9, 21, 9),
};

describe('the News picture viewer', () => {
  let root: HTMLDivElement;
  let initialGlobal: ReturnType<typeof globalState.getGlobal>;
  let hasFakeTimers: boolean;
  const { setAreControlsVisible, setIsZoomed } = useControlsSignal();

  beforeEach(() => {
    initialGlobal = globalState.getGlobal();
    hasFakeTimers = false;
    root = document.createElement('div');
    document.body.appendChild(root);
    setAreControlsVisible(true);
    setIsZoomed(false);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    root.remove();
    globalState.setGlobal(initialGlobal);
    if (hasFakeTimers) await jest.runAllTimersAsync();
    jest.clearAllMocks();
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  it('does not reopen after closing before a pending picture selection', async () => {
    jest.useFakeTimers();
    hasFakeTimers = true;
    const openMediaViewer = jest.spyOn(globalState.getActions(), 'openMediaViewer');
    const global = globalState.getGlobal();
    const pictures = {
      ids: ['first', 'second'],
      byId: {
        first: { url: 'https://example.com/first.jpg', title: NEWS.headline, news: NEWS },
        second: { url: 'https://example.com/second.jpg', title: NEWS.headline, news: NEWS },
      },
    };
    globalState.setGlobal({
      ...global,
      settings: { ...global.settings, animationLevel: 0 },
      mediaViewer: { mediaId: 'first', mediaType: MediaType.AgentNews, pictures },
    });
    TeactDOM.render(<MediaViewer />, root);
    await jest.advanceTimersByTimeAsync(50);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    expect(openMediaViewer).not.toHaveBeenCalled();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    await jest.advanceTimersByTimeAsync(50);
    expect(globalState.getGlobal().mediaViewer).toEqual({
      mediaId: undefined, mediaType: MediaType.AgentNews, pictures,
    });

    await jest.advanceTimersByTimeAsync(350);
    expect(openMediaViewer).not.toHaveBeenCalled();
  });

  it('keeps NFT paging through visible items', async () => {
    jest.useFakeTimers();
    hasFakeTimers = true;
    const openMediaViewer = jest.spyOn(globalState.getActions(), 'openMediaViewer');
    const global = globalState.getGlobal();
    const nft: ApiNft = {
      chain: 'ton', index: 1, address: 'first', isOnSale: false, metadata: {}, interface: 'default',
      image: 'https://example.com/nft.jpg',
    };
    globalState.setGlobal({
      ...global,
      currentAccountId: '0-mainnet',
      settings: { ...global.settings, animationLevel: 0 },
      byAccountId: {
        '0-mainnet': {
          nfts: {
            orderedAddresses: ['first', 'hidden', 'second'],
            byAddress: {
              first: nft,
              hidden: { ...nft, address: 'hidden', isHidden: true },
              second: { ...nft, address: 'second' },
            },
          },
        },
      },
      mediaViewer: { mediaId: 'first', mediaType: MediaType.Nft },
    });
    TeactDOM.render(<MediaViewer />, root);
    await jest.advanceTimersByTimeAsync(50);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    expect(openMediaViewer).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(350);

    expect(openMediaViewer).toHaveBeenCalledTimes(1);
    expect(openMediaViewer).toHaveBeenCalledWith({ mediaType: MediaType.Nft, mediaId: 'second' });
    expect(globalState.getGlobal().mediaViewer.mediaId).toBe('second');
  });

  it('heads a picture with its place among several over its date, and a single picture with its date', async () => {
    const onClick = jest.fn();
    TeactDOM.render(<PictureInfo news={NEWS} position={2} count={3} onClick={onClick} />, root);
    await pause(20);

    function getLines() {
      return Array.from(root.querySelectorAll<HTMLElement>('[dir="auto"]')).map((line) => line.textContent);
    }

    const date = getLines()[1];
    expect(getLines()).toEqual(['$agent_wallet_page_indicator 2/3', date]);
    expect(date).toMatch(/, /u);
    expect(root.textContent).not.toContain('Source');
    expect(root.querySelector('.pictureInfoAvatar')).toBeNull();
    root.querySelector<HTMLElement>('[dir="auto"]')!.click();
    expect(onClick).toHaveBeenCalledTimes(1);

    // A discussion's post has its picture alone, which needs no count
    TeactDOM.render(<PictureInfo news={NEWS} position={1} count={1} onClick={onClick} />, root);
    await pause(20);
    expect(getLines()).toEqual([date]);
  });

  it('offers the post\'s own actions as buttons on a desktop, without saving the picture', async () => {
    const onClose = jest.fn();
    TeactDOM.render(<PictureActions news={NEWS} isMobile={false} onClose={onClose} />, root);
    await pause(20);

    // The buttons, without the closed sources menu's own
    const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('button[aria-label]'));
    expect(buttons.map((button) => button.getAttribute('aria-label')))
      .toEqual(['$agent_news_sources', 'Copy', 'Share', 'Close']);

    // Sources lists the post's sources in a menu under it, each opening its link
    expect(buttons[0].getAttribute('aria-expanded')).toBe('false');
    buttons[0].click();
    await pause(50);
    expect(buttons[0].getAttribute('aria-expanded')).toBe('true');
    const source = Array.from(root.querySelectorAll<HTMLElement>('[role="menuitem"], button'))
      .find(({ textContent }) => textContent === 'Source')!;
    source.click();
    expect(openUrl).toHaveBeenCalledWith('https://example.com/news');
    buttons[1].click();
    expect(copyAgentText).toHaveBeenCalledWith('News headline\n\nThe news body');
    expect(shareUrl).not.toHaveBeenCalled();
    buttons[2].click();
    expect(shareUrl).toHaveBeenCalledWith(NEWS_LINK, 'News headline', 'News headline');
    buttons[3].click();
    expect(onClose).toHaveBeenCalledTimes(1);

    // Without a source to open, the buttons have no Sources
    TeactDOM.render(<PictureActions news={{ ...NEWS, sources: [] }} isMobile={false} onClose={onClose} />, root);
    await pause(20);
    expect(Array.from(root.querySelectorAll('button')).map((button) => button.getAttribute('aria-label')))
      .toEqual(['Copy', 'Share', 'Close']);
  });

  it('offers no Share on the picture of a digest\'s headline, as on its digest', async () => {
    const pictures = buildAgentNewsPictures([{
      eventId: 7, headline: NEWS.headline, time: '2026-10-21T09:00:00.000Z', imageUrl: 'https://example.com/7.jpg',
    }], getAgentDigestPictureSurface('digest-1', false), 'ru');
    TeactDOM.render(
      <PictureActions news={pictures.byId[pictures.ids[0]].news} isMobile={false} onClose={jest.fn()} />, root,
    );
    await pause(20);

    expect(Array.from(root.querySelectorAll('button')).map((button) => button.getAttribute('aria-label')))
      .toEqual(['Copy', 'Close']);
  });

  it('gathers the actions into a menu on a phone', async () => {
    TeactDOM.render(<PictureActions news={NEWS} isMobile onClose={jest.fn()} />, root);
    await pause(20);

    const menuButton = root.querySelector<HTMLButtonElement>('[aria-label="More actions"]')!;
    expect(menuButton.getAttribute('aria-expanded')).toBe('false');
    menuButton.click();
    await pause(50);

    expect(menuButton.getAttribute('aria-expanded')).toBe('true');
    const items = Array.from(root.querySelectorAll<HTMLElement>('[role="menuitem"], button'))
      .filter(({ textContent }) => ['$agent_news_sources', 'Copy', 'Share'].includes(textContent!));
    expect(items.map(({ textContent }) => textContent)).toEqual(['$agent_news_sources', 'Copy', 'Share']);
    // Share is in the Tab order as Copy is, and a native button, which Enter and Space press
    const [, copyItem, shareItem] = items as HTMLButtonElement[];
    expect(shareItem).toBeInstanceOf(HTMLButtonElement);
    expect(shareItem.disabled).toBe(false);
    expect(shareItem.tabIndex).toBeGreaterThanOrEqual(0);
    expect(shareItem.tabIndex).toBe(copyItem.tabIndex);
    shareItem.focus();
    expect(document.activeElement).toBe(shareItem);
    shareItem.click();
    expect(shareUrl).toHaveBeenCalledWith(NEWS_LINK, 'News headline', 'News headline');
    items[1].click();
    expect(copyAgentText).toHaveBeenCalledTimes(1);
  });

  it('cuts a long caption to Telegram\'s lines and shows all of it on a click or a key, as its post', async () => {
    mockCutOff();
    TeactDOM.render(<PictureCaption news={NEWS} isActive />, root);
    await waitFor(() => Boolean(root.querySelector('[role="button"]')));

    const text = root.querySelector<HTMLElement>('[role="button"]')!;
    expect(text.textContent).toBe('News headline\nThe news body');
    expect(text.querySelector('strong:not(.captionHeadline)')!.textContent).toBe('news');
    expect(text.getAttribute('aria-expanded')).toBe('false');
    expect(text.tabIndex).toBe(0);

    text.click();
    expect(await waitFor(() => text.getAttribute('aria-expanded') === 'true')).toBe(true);
    expect(text.classList.contains('captionText_expanded')).toBe(true);

    text.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(await waitFor(() => text.getAttribute('aria-expanded') === 'false')).toBe(true);
  });

  it('leaves a caption that fits as plain text', async () => {
    TeactDOM.render(<PictureCaption news={NEWS} isActive />, root);
    await pause(FRAME_FALLBACK_DELAY);

    expect(root.querySelector('[role="button"]')).toBeNull();
    expect(root.textContent).toContain('News headline');
  });

  it('hides the caption with the header, and while the picture is zoomed in', async () => {
    mockCutOff();
    TeactDOM.render(<PictureCaption news={NEWS} isActive />, root);
    await waitFor(() => Boolean(root.querySelector('[role="button"]')));
    const caption = root.querySelector<HTMLElement>('.caption')!;
    const text = root.querySelector<HTMLElement>('[role="button"]')!;
    const isHidden = () => caption.classList.contains('caption_hidden');

    setAreControlsVisible(false);
    expect(await waitFor(isHidden)).toBe(true);
    expect(text.tabIndex).toBe(-1);

    setAreControlsVisible(true);
    setIsZoomed(true);
    await pause(FRAME_FALLBACK_DELAY);
    expect(isHidden()).toBe(true);

    setIsZoomed(false);
    expect(await waitFor(() => !isHidden())).toBe(true);
    expect(text.tabIndex).toBe(0);
  });

  it('keeps the caption of a neighbour picture out of the Tab order and away from screen readers', async () => {
    mockCutOff();
    TeactDOM.render(<PictureCaption news={NEWS} />, root);
    await waitFor(() => Boolean(root.querySelector('[role="button"]')));

    expect(root.querySelector('.caption')!.getAttribute('aria-hidden')).toBe('true');
    expect(root.querySelector<HTMLElement>('[role="button"]')!.tabIndex).toBe(-1);
  });
});

// Nothing is laid out here, so elements are made to report more height than they show, as a cut caption does
function mockCutOff() {
  jest.spyOn(Element.prototype, 'scrollHeight', 'get').mockReturnValue(200);
  jest.spyOn(Element.prototype, 'clientHeight', 'get').mockReturnValue(66);
}

async function waitFor(check: () => boolean) {
  for (let attempt = 0; attempt < WAIT_ATTEMPTS && !check(); attempt++) {
    await pause(FRAME_FALLBACK_DELAY);
  }

  return check();
}
