import React, { requestAfterRender, type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type {
  AgentNewsFeedDigestV2, AgentNewsFeedItemV2, AgentNewsFeedLocaleV2, AgentNewsFeedPageV2,
} from '../../api/agentV2/protocol/types';
import type { AgentConversationMessageContext } from '../agent/AgentConversationShell';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';
import type { AgentNewsFeedView } from './agentNewsFeedView';

import { publishAgentV2Update } from '../../util/agentV2Updates';
import { formatTime } from '../../util/dateFormat';
import Deferred from '../../util/Deferred';
import { pause, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import { getAgentDigestTime, setAgentDigestTime, subscribeToAgentDigestTime } from './agentDigestTime';
import { mergeAgentNewsFeedEntries } from './agentNewsFeedItems';
import { getAgentNewsFeedView, setAgentNewsFeedView, subscribeToAgentNewsFeedView } from './agentNewsFeedView';
import {
  getAgentNewsDigestsReadThrough,
  getAgentNewsReadThrough,
  markAgentNewsDigestsReadThrough,
  markAgentNewsReadThrough,
} from './agentNewsReadState';
import useAgentNewsFeed from './useAgentNewsFeed';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentNewsFeed from './AgentNewsFeed';

const mockOpenMediaViewer = jest.fn();
jest.mock('../../global', () => {
  const actual = jest.requireActual<typeof import('../../global')>('../../global');
  return {
    ...actual,
    getActions: () => ({ ...actual.getActions(), openMediaViewer: mockOpenMediaViewer }),
    withGlobal: () => (Component: unknown) => Component,
  };
});
jest.mock('../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../util/windowEnvironment'),
  REM: 20,
}));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string, value?: Record<string, unknown>) => (
    value ? `${key} ${Object.values(value).join(' ')}` : key
  ), { code: 'en' }),
}));
jest.mock('../agent/AgentConversationShell', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));
// The sheet's content shows in place, without the modal's portal and gestures
jest.mock('../ui/Modal', () => {
  const { createElement } = jest.requireActual('../../lib/teact/teact');
  return {
    __esModule: true,
    default: ({ isOpen, title, children }: { isOpen?: boolean; title?: string; children: unknown }) => (
      isOpen ? createElement('div', { 'data-modal': true }, createElement('h2', undefined, title), children) : undefined
    ),
  };
});

const ITEMS: AgentNewsFeedItemV2[] = [2, 3].map((eventId) => ({
  eventId,
  deliveredAt: `2026-10-2${eventId}T09:00:00.000Z`,
  headline: `News ${eventId}`,
  body: 'Body',
  sources: [],
}));

const DIGEST: AgentNewsFeedDigestV2 = {
  id: 'digest', deliveredAt: '2026-10-22T21:00:00.000Z', total: 5,
  top: [{ eventId: 2, headline: 'News 2' }, { eventId: 3, headline: 'News 3' }],
};
const MESSAGE_CONTEXT: AgentConversationMessageContext = {
  shouldAnimateTextStreaming: false,
  isJustAdded: false,
  onEditMessage: jest.fn(),
  onReportMessage: jest.fn(),
  onTextRevealProgress: jest.fn(),
  onRequestLiveTail: jest.fn(),
};

const shellMock = jest.mocked(AgentConversationShell);

describe('AgentNewsFeed', () => {
  let root: HTMLDivElement;
  let cardRoot: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    shellMock.mockClear();
    root = document.createElement('div');
    cardRoot = document.createElement('div');
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.append(root, cardRoot, portals);
  });

  afterEach(() => {
    TeactDOM.render(undefined, cardRoot);
    TeactDOM.render(undefined, root);
    root.remove();
    cardRoot.remove();
    portals.remove();
    setAgentDigestTime({ hour: 21, minute: 0 });
    localStorage.clear();
  });

  it('shows the news as the messages of a chat without a field, a date line for each day', () => {
    const onLoadMore = jest.fn();
    renderFeed({
      items: mergeAgentNewsFeedEntries(ITEMS), unreadEventId: 3, hasMore: true, onLoadMore,
    });

    const props = getShellProps();
    expect(props.composer).toBeUndefined();
    expect(props.conversation).toMatchObject({
      messages: [
        { id: 2, text: 'News 2', isOutgoing: false, timestamp: Date.parse(ITEMS[0].deliveredAt) },
        { id: 3, text: 'News 3', isOutgoing: false, timestamp: Date.parse(ITEMS[1].deliveredAt) },
      ],
      isInitialLoadComplete: true,
      hasDailyDateLines: true,
      unreadMessageId: 3,
    });
    expect(props.header).toMatchObject({ hasBackButton: true });
    expect(props.header!.titleContent).toBeTruthy();
    expect(props.history).toEqual({
      hasOlderMessages: true,
      isLoading: false,
      noLoadingIndicator: true,
      mode: 'continuous',
      loadOlderMessages: onLoadMore,
      thresholdRowCount: 5,
    });
    expect(props.conversation.loadFailure).toBeUndefined();
    expect(props.conversation.emptyText).toBeUndefined();
  });

  it('stands its placeholder in for news it has yet to read, and shows news it has at once', () => {
    renderFeed({ isLoading: true });
    expect(getShellProps().conversation).toMatchObject({ hasHistoryPlaceholder: true, isNewsPlaceholder: true });

    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS) });
    expect(getShellProps().conversation.hasHistoryPlaceholder).toBe(true);

    TeactDOM.render(undefined, root);
    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS) });
    expect(getShellProps().conversation.hasHistoryPlaceholder).toBe(false);
  });

  it('puts the "New" line above the first new digest in the Digests view alone', () => {
    const items = mergeAgentNewsFeedEntries(ITEMS, [DIGEST]);
    renderFeed({ view: 'digests', items, unreadDigestId: DIGEST.id });
    const { messages, unreadMessageId } = getShellProps().conversation;
    expect(unreadMessageId).toBe(messages[0].id);
    expect(unreadMessageId).toBeLessThan(0);

    renderFeed({ view: 'all', items, unreadEventId: 3, unreadDigestId: DIGEST.id });
    expect(getShellProps().conversation.unreadMessageId).toBe(3);
  });

  it('shares its news and their pictures in the language of its pages, apart from the app\'s', () => {
    const items = ITEMS.map((item) => ({
      ...item, imageUrl: `https://pulse.mytonwallet.org/images/${item.eventId}.jpg`,
    }));
    renderFeed({ items: mergeAgentNewsFeedEntries(items), locale: 'ru' });

    const { messages, renderMessage } = getShellProps().conversation;
    const card = renderMessage(messages[0], MESSAGE_CONTEXT) as unknown as VirtualElementComponent;
    expect(card.props.locale).toBe('ru');

    card.props.onOpenPicture(card.props.item.eventId);
    const { pictures } = mockOpenMediaViewer.mock.calls[0][0];
    expect(pictures.ids).toHaveLength(2);
    pictures.ids.forEach((id: string) => expect(pictures.byId[id].news.locale).toBe('ru'));
  });

  it.each(['all', 'digests'] as const)('opens digest and headline discussions in the %s view', async (view) => {
    const onOpenNewsDiscussion = jest.fn();
    const onOpenDigestDiscussion = jest.fn();
    const onDigestReached = jest.fn();
    renderFeed({
      view, items: mergeAgentNewsFeedEntries(ITEMS, [DIGEST]), unreadEventId: 3,
      onOpenNewsDiscussion, onOpenDigestDiscussion, onDigestReached,
    });

    const { messages, renderMessage, emptyText } = getShellProps().conversation;
    expect(emptyText).toBeUndefined();
    // The digest stands where it was delivered, under an ID no news has
    expect(messages).toMatchObject(view === 'all' ? [
      { id: 2 }, { isOutgoing: false, timestamp: Date.parse(DIGEST.deliveredAt) }, { id: 3 },
    ] : [{ isOutgoing: false, timestamp: Date.parse(DIGEST.deliveredAt) }]);
    expect(getShellProps().conversation.unreadMessageId).toBe(view === 'all' ? 3 : undefined);
    // The pinned digest stands under the header in the view of all news
    expect(getShellProps().slots?.headerAccessory?.height).toBe(view === 'all' ? 3.125 : undefined);
    const digestMessage = messages[view === 'all' ? 1 : 0];
    expect(digestMessage.id).toBeLessThan(0);
    if (view === 'all') getShellProps().actions.onMessageVisible!(messages[0].id);
    getShellProps().actions.onMessageVisible!(digestMessage.id);
    expect(onDigestReached.mock.calls).toEqual([[DIGEST.id]]);
    TeactDOM.render(<div>{renderMessage(digestMessage, MESSAGE_CONTEXT)}</div>, cardRoot);
    await pause(20);

    const card = cardRoot.querySelector(`[data-agent-v2-message-id="${digestMessage.id}"]`)!;
    expect(card.getAttribute('data-agent-v2-message-role')).toBe('assistant');
    expect(card.querySelector('h3')!.textContent).toBe('$agent_digest_title');
    expect(card.querySelector('h3')!.nextElementSibling!.textContent).toBe('$agent_digest_meta 5');
    // The time stands in the bubble's trailing corner, over "Discuss", as a news card's
    const time = card.querySelector('time')!;
    expect(time.textContent).toBe(formatTime(DIGEST.deliveredAt));
    expect(time.getAttribute('dateTime')).toBe(DIGEST.deliveredAt);
    const headlines = Array.from(card.querySelectorAll<HTMLButtonElement>('[data-agent-news-digest-headline]'));
    expect(headlines.map(({ textContent }) => textContent)).toEqual(['News 2', 'News 3']);
    // The news the digest leaves out are above in the feed, and the digests view lists no news to point at
    expect(card.textContent).toContain(view === 'all' ? '$agent_digest_more 3' : '$agent_digest_more_count 3');

    headlines[1].click();
    expect(onOpenNewsDiscussion).toHaveBeenCalledWith(3, 'digest');
    card.querySelector<HTMLButtonElement>('[aria-label="$agent_news_discuss, $agent_digest_title"]')!.click();
    // The card's bubble flies into the discussion
    expect(onOpenDigestDiscussion).toHaveBeenCalledWith('digest', card.querySelector('[data-agent-news-digest-id]'));

    // A digest of its headlines alone says nothing more, and a feed of digests alone is not empty
    renderFeed({ view, items: mergeAgentNewsFeedEntries([], [{ ...DIGEST, total: 2 }]) });
    const feed = getShellProps().conversation;
    expect(feed.emptyText).toBeUndefined();
    expect(feed.messages.map(({ id }) => id)).toEqual([digestMessage.id]);
    TeactDOM.render(<div>{feed.renderMessage(feed.messages[0], MESSAGE_CONTEXT)}</div>, cardRoot);
    await pause(20);
    expect(cardRoot.textContent).not.toContain('$agent_digest_more');
    renderFeed({ view, items: [] });
    expect(getShellProps().conversation.emptyText)
      .toBe(view === 'all' ? '$agent_news_empty' : '$agent_news_digests_empty');
  });

  it('pins the digests as Telegram pins messages, a tap going to the shown one and on to the one before', async () => {
    const older: AgentNewsFeedDigestV2 = {
      ...DIGEST, id: 'older', deliveredAt: '2026-10-21T21:00:00.000Z', top: [{ eventId: 2, headline: 'Older' }],
    };
    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS, [older, DIGEST]) });
    async function renderPanel() {
      TeactDOM.render(<div>{getShellProps().slots!.headerAccessory!.content}</div>, cardRoot);
      await pause(20);
      return cardRoot.querySelector<HTMLButtonElement>('[data-agent-news-pinned-digest]')!;
    }

    // Until the list scrolls, the newest digest shows, its bar lit the lower of two
    let panel = await renderPanel();
    expect(panel.getAttribute('aria-label')).toContain('News 2 · News 3');
    expect(panel.querySelector('[style*="height: 1.0625rem; transform: translateY(1.1875rem)"]')).not.toBeNull();
    const { messages } = getShellProps().conversation;
    const newestMessageId = messages.find(({ timestamp }) => timestamp === Date.parse(DIGEST.deliveredAt))!.id;

    panel.click();
    await pause(20);
    expect(getShellProps().conversation.scrollRequest).toMatchObject({ messageId: newestMessageId });
    panel = await renderPanel();
    expect(panel.getAttribute('aria-label')).toContain('Older');

    // From the oldest, a tap goes back to the newest
    panel.click();
    await pause(20);
    panel = await renderPanel();
    expect(panel.getAttribute('aria-label')).toContain('News 2 · News 3');

    // The scroll button shows the digest of the feed's end at once, the newest while the end is not rendered
    panel.click();
    await pause(20);
    expect((await renderPanel()).getAttribute('aria-label')).toContain('Older');
    getShellProps().actions.onScrollToBottom!(document.createElement('div'));
    await pause(20);
    expect((await renderPanel()).getAttribute('aria-label')).toContain('News 2 · News 3');

    // Without digests, nothing is pinned under the header
    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS) });
    expect(getShellProps().slots?.headerAccessory).toBeUndefined();
  });

  it('switches between all news and the digests in the header\'s title place, the current view marked', async () => {
    const onViewChange = jest.fn();
    async function renderSwitch(view: AgentNewsFeedView, items: AgentNewsFeedEntry[]) {
      renderFeed({ view, items, onViewChange });
      TeactDOM.render(<div>{getShellProps().header!.titleContent}</div>, cardRoot);
      await pause(20);
      const viewSwitch = cardRoot.querySelector('[data-agent-news-view-switch]')!;
      return {
        // The tabs to click, before the copies that draw the current one over them
        tabs: Array.from(viewSwitch.firstElementChild!.children as HTMLCollectionOf<HTMLElement>)
          .filter((element) => !element.hasAttribute('aria-hidden')),
        current: viewSwitch.querySelector('.current-tab')!.textContent,
      };
    }

    let { tabs, current } = await renderSwitch('all', mergeAgentNewsFeedEntries(ITEMS));
    expect(tabs.map(({ textContent }) => textContent)).toEqual(['$agent_news_view_all', '$agent_news_view_digests']);
    expect(current).toBe('$agent_news_view_all');
    tabs[0].click();
    expect(onViewChange).not.toHaveBeenCalled();
    tabs[1].click();
    expect(onViewChange.mock.calls).toEqual([['digests']]);

    // The view without digests to show keeps the switch, so the other view can be chosen
    ({ tabs, current } = await renderSwitch('digests', []));
    expect(getShellProps().conversation.emptyText).toBe('$agent_news_digests_empty');
    expect(current).toBe('$agent_news_view_digests');
    tabs[1].click();
    tabs[0].click();
    expect(onViewChange.mock.calls).toEqual([['digests'], ['all']]);
  });

  it('opens the digest\'s time from the settings button, whose wheel takes the time picked on it', async () => {
    renderFeed({ items: [] });
    expect(root.querySelector('[data-modal]')).toBeNull();

    getShellProps().actions.onOpenDigestSettings!();
    expect(await waitFor(() => Boolean(root.querySelector('[data-modal]')), 10, 300)).toBe(true);
    const sheet = root.querySelector('[data-modal]')!;
    expect(sheet.querySelector('h2')!.textContent).toBe('$agent_digest_sheet_title');
    expect(sheet.textContent).toContain('$agent_digest_settings_text');
    const timeRow = Array.from(sheet.querySelectorAll('button'))
      .find(({ textContent }) => textContent?.startsWith('$agent_digest_time'))!;
    expect(timeRow.textContent).toBe('$agent_digest_time21:00');

    // The row opens a wheel of the day's hours and the hour's quarters under it, which a tap on a row sets. The test
    // DOM has no scrolling.
    const scrollTo = jest.fn();
    Object.defineProperty(HTMLElement.prototype, 'scrollTo', { configurable: true, value: scrollTo });
    const [wheel, minuteWheel] = Array.from(sheet.querySelectorAll<HTMLElement>('[role="spinbutton"]'));
    // A screen reader tells the columns apart
    expect(wheel.getAttribute('aria-label')).toBe('$agent_digest_hours');
    expect(minuteWheel.getAttribute('aria-label')).toBe('$agent_digest_minutes');
    expect(wheel.getAttribute('tabindex')).toBe('-1');
    expect(minuteWheel.getAttribute('tabindex')).toBe('-1');
    // The empty band after both lists draws their focus ring, which a list's own mask would cut
    expect(minuteWheel.nextElementSibling!.textContent).toBe('');
    timeRow.click();
    expect(await waitFor(() => timeRow.getAttribute('aria-expanded') === 'true', 10, 300)).toBe(true);
    expect(wheel.getAttribute('tabindex')).toBe('0');
    expect(wheel.getAttribute('aria-valuetext')).toBe('21:00');
    const hours = Array.from(wheel.querySelectorAll<HTMLElement>('[data-index]'));
    expect(hours.map(({ textContent }) => textContent)).toHaveLength(24);
    expect(hours[0].textContent).toBe('00');
    hours[9].click();
    expect(getAgentDigestTime().hour).toBe(9);
    expect(await waitFor(() => timeRow.textContent === '$agent_digest_time09:00', 10, 300)).toBe(true);
    expect(wheel.getAttribute('aria-valuetext')).toBe('09:00');
    expect(await waitFor(() => scrollTo.mock.calls.some(([options]) => options.top === 9 * 2.25 * 20), 10, 300))
      .toBe(true);

    // The arrow keys move it an hour at a time
    wheel.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
    expect(getAgentDigestTime().hour).toBe(10);
    expect(await waitFor(() => wheel.getAttribute('aria-valuenow') === '10', 10, 300)).toBe(true);
    wheel.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    expect(getAgentDigestTime().hour).toBe(9);
    wheel.scrollTop = 6 * 2.25 * 20;
    wheel.dispatchEvent(new Event('scroll'));
    expect(await waitFor(() => getAgentDigestTime().hour === 6, 10, 300)).toBe(true);

    // The minutes turn a quarter of an hour at a time and keep the hour
    expect(minuteWheel.getAttribute('tabindex')).toBe('0');
    const minutes = Array.from(minuteWheel.querySelectorAll<HTMLElement>('[data-index]'));
    expect(minutes.map(({ textContent }) => textContent)).toEqual(['00', '15', '30', '45']);
    minutes[3].click();
    expect(getAgentDigestTime()).toEqual({ hour: 6, minute: 45 });
    expect(await waitFor(() => timeRow.textContent === '$agent_digest_time06:45', 10, 300)).toBe(true);
    expect(wheel.getAttribute('aria-valuetext')).toBe('06:45');
    expect(minuteWheel.getAttribute('aria-valuetext')).toBe('06:45');
    expect(minuteWheel.getAttribute('aria-valuenow')).toBe('45');
    minuteWheel.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
    expect(getAgentDigestTime()).toEqual({ hour: 6, minute: 45 });
    minuteWheel.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }));
    expect(getAgentDigestTime()).toEqual({ hour: 6, minute: 0 });

    // Both columns settling in one frame set both
    await pause(300);
    wheel.scrollTop = 7 * 2.25 * 20;
    minuteWheel.scrollTop = 2 * 2.25 * 20;
    wheel.dispatchEvent(new Event('scroll'));
    minuteWheel.dispatchEvent(new Event('scroll'));
    expect(await waitFor(() => getAgentDigestTime().minute === 30, 10, 300)).toBe(true);
    expect(getAgentDigestTime()).toEqual({ hour: 7, minute: 30 });
    delete (HTMLElement.prototype as Partial<HTMLElement>).scrollTo;

    Array.from(sheet.querySelectorAll('button')).find(({ textContent }) => textContent === 'Done')!.click();
    expect(await waitFor(() => !root.querySelector('[data-modal]'), 10, 300)).toBe(true);
  });

  it('waits for the first page before asking for older news', () => {
    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS), hasMore: true, isLoading: true });

    expect(getShellProps().history?.hasOlderMessages).toBe(false);
  });

  it('keeps the placeholder until the first page and says there is no news yet when it is empty', () => {
    renderFeed({ isLoading: true });
    expect(getShellProps().conversation.isInitialLoadComplete).toBe(false);
    expect(getShellProps().conversation.loadFailure).toBeUndefined();
    expect(getShellProps().conversation.emptyText).toBeUndefined();

    renderFeed({ items: [] });
    expect(getShellProps().conversation.emptyText).toBe('$agent_news_empty');
    expect(getShellProps().conversation.loadFailure).toBeUndefined();

    renderFeed({ items: [], isLoading: true });
    expect(getShellProps().conversation.emptyText).toBe('$agent_news_empty');
    expect(getShellProps().conversation.loadFailure).toBeUndefined();
  });

  it('says the news are unavailable, with Retry, when their reading fails', () => {
    const onRetry = jest.fn();
    renderFeed({ errorCode: 'news_unavailable', onRetry });

    const { loadFailure, emptyText } = getShellProps().conversation;
    expect(emptyText).toBeUndefined();
    expect(loadFailure).toMatchObject({ text: '$agent_news_unavailable', isRetrying: false });
    loadFailure!.onRetry();
    expect(onRetry).toHaveBeenCalledTimes(1);

    renderFeed({ items: [], errorCode: 'news_unavailable', isLoading: true });
    expect(getShellProps().conversation.loadFailure).toMatchObject({
      text: '$agent_news_unavailable', isRetrying: true,
    });
  });

  it('hands a failed reading of the news to the list, which tells it under the news already shown', () => {
    const onRetry = jest.fn();
    renderFeed({ items: mergeAgentNewsFeedEntries(ITEMS), errorCode: 'network_error', onRetry });

    const { loadFailure } = getShellProps().conversation;
    expect(loadFailure).toMatchObject({ text: '$agent_connection_lost', isRetrying: false });
    loadFailure!.onRetry();
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  function renderFeed({
    view = 'all',
    items,
    locale,
    unreadEventId,
    unreadDigestId,
    hasMore = false,
    isLoading = false,
    errorCode,
    onRetry = jest.fn(),
    onLoadMore = jest.fn(),
    onDigestReached = jest.fn(),
    onOpenNewsDiscussion = jest.fn(),
    onOpenDigestDiscussion = jest.fn(),
    onViewChange = setAgentNewsFeedView,
  }: Partial<{
    view: AgentNewsFeedView;
    items: AgentNewsFeedEntry[];
    locale: AgentNewsFeedLocaleV2;
    unreadEventId: number;
    unreadDigestId: string;
    hasMore: boolean;
    isLoading: boolean;
    errorCode: 'network_error' | 'news_unavailable';
    onRetry: NoneToVoidFunction;
    onLoadMore: NoneToVoidFunction;
    onDigestReached: (id: string) => void;
    onOpenNewsDiscussion: (eventId: number, digestId: string) => void;
    onOpenDigestDiscussion: (id: string, cardElement?: HTMLElement) => void;
    onViewChange: (view: AgentNewsFeedView) => void;
  }>) {
    TeactDOM.render(
      <AgentNewsFeed
        view={view}
        onViewChange={onViewChange}
        isActive
        items={items}
        locale={locale}
        unreadEventId={unreadEventId}
        unreadDigestId={unreadDigestId}
        hasMore={hasMore}
        isLoading={isLoading}
        isLoadingMore={false}
        errorCode={errorCode}
        onBack={jest.fn()}
        onRetry={onRetry}
        onLoadMore={onLoadMore}
        onDigestReached={onDigestReached}
        onOpenDiscussion={jest.fn()}
        onOpenNewsDiscussion={onOpenNewsDiscussion}
        onOpenDigestDiscussion={onOpenDigestDiscussion}
      />,
      root,
    );
  }
});

describe('useAgentNewsFeed digest hour', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    localStorage.clear();
    root = document.createElement('div');
    document.body.appendChild(root);
    jest.mocked(callApi).mockReset();
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
    setAgentDigestTime({ hour: 0, minute: 0 });
    setAgentDigestTime({ hour: 21, minute: 0 });
    localStorage.clear();
  });

  it('defaults to 21:00, persists valid times and notifies subscribers only of changes', () => {
    expect(getAgentDigestTime()).toEqual({ hour: 21, minute: 0 });
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentDigestTime(onChange);
    setAgentDigestTime({ hour: 0, minute: 0 });
    expect(getAgentDigestTime().hour).toBe(0);
    expect(localStorage.getItem('mytonwallet-agent-mypulse-digest-time')).toBe('{"hour":0,"minute":0}');
    setAgentDigestTime({ hour: 0, minute: 0 });
    expect(onChange.mock.calls).toEqual([[{ hour: 0, minute: 0 }]]);
    // A change is one write, so another tab never sees the new hour with the old minute
    const setItem = jest.spyOn(Storage.prototype, 'setItem');
    setAgentDigestTime({ hour: 0, minute: 15 });
    expect(setItem.mock.calls).toEqual([['mytonwallet-agent-mypulse-digest-time', '{"hour":0,"minute":15}']]);
    setItem.mockRestore();
    // The same time is the same object, which state can keep
    expect(getAgentDigestTime()).toBe(getAgentDigestTime());
    expect(onChange.mock.calls).toEqual([[{ hour: 0, minute: 0 }], [{ hour: 0, minute: 15 }]]);
    expect(() => setAgentDigestTime({ hour: 24, minute: 0 })).toThrow(RangeError);
    expect(() => setAgentDigestTime({ hour: 9.5, minute: 0 })).toThrow(RangeError);
    expect(() => setAgentDigestTime({ hour: 9, minute: 10 as never })).toThrow(RangeError);
    expect(() => setAgentDigestTime({ hour: 9, minute: 60 as never })).toThrow(RangeError);
    unsubscribe();
    setAgentDigestTime({ hour: 23, minute: 0 });
    expect(onChange).toHaveBeenCalledTimes(2);
    expect(getAgentDigestTime().hour).toBe(23);
    localStorage.clear();
    expect(getAgentDigestTime().hour).toBe(23);
  });

  it('writes a time again after a failed write and takes another tab\'s time after one', () => {
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentDigestTime(onChange);
    const setItem = jest.spyOn(Storage.prototype, 'setItem').mockImplementationOnce(() => {
      throw new Error('Storage unavailable');
    });
    setAgentDigestTime({ hour: 7, minute: 15 });
    expect(localStorage.getItem('mytonwallet-agent-mypulse-digest-time')).toBeNull();
    // Picked again once storage works, the time is written without a second notice
    setAgentDigestTime({ hour: 7, minute: 15 });
    expect(localStorage.getItem('mytonwallet-agent-mypulse-digest-time')).toBe('{"hour":7,"minute":15}');
    expect(onChange.mock.calls).toEqual([[{ hour: 7, minute: 15 }]]);

    setItem.mockImplementationOnce(() => {
      throw new Error('Storage unavailable');
    });
    setAgentDigestTime({ hour: 8, minute: 30 });
    localStorage.setItem('mytonwallet-agent-mypulse-digest-time', '{"hour":10,"minute":45}');
    window.dispatchEvent(new StorageEvent('storage', {
      key: 'mytonwallet-agent-mypulse-digest-time', storageArea: localStorage,
    }));
    expect(getAgentDigestTime()).toEqual({ hour: 10, minute: 45 });
    expect(onChange.mock.calls.at(-1)).toEqual([{ hour: 10, minute: 45 }]);
    setItem.mockRestore();
    unsubscribe();
  });

  it('reads an hour stored without a time on the hour and rejects bad stored times', () => {
    setAgentDigestTime({ hour: 6, minute: 45 });
    localStorage.clear();
    localStorage.setItem('mytonwallet-agent-mypulse-digest-hour', '8');
    expect(getAgentDigestTime()).toEqual({ hour: 8, minute: 0 });
    // Another tab's time arrives whole
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentDigestTime(onChange);
    localStorage.setItem('mytonwallet-agent-mypulse-digest-time', '{"hour":9,"minute":30}');
    window.dispatchEvent(new StorageEvent('storage', {
      key: 'mytonwallet-agent-mypulse-digest-time', storageArea: localStorage,
    }));
    expect(onChange.mock.calls).toEqual([[{ hour: 9, minute: 30 }]]);
    unsubscribe();
    localStorage.setItem('mytonwallet-agent-mypulse-digest-time', '{"hour":9,"minute":10}');
    expect(getAgentDigestTime()).toEqual({ hour: 21, minute: 0 });
    localStorage.setItem('mytonwallet-agent-mypulse-digest-time', '9');
    expect(getAgentDigestTime()).toEqual({ hour: 21, minute: 0 });
  });

  it('persists the news view across reloads, rejects bad stored values and synchronizes tabs', () => {
    expect(getAgentNewsFeedView()).toBe('all');
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentNewsFeedView(onChange);
    setAgentNewsFeedView('digests');
    setAgentNewsFeedView('digests');
    expect(onChange.mock.calls).toEqual([['digests']]);
    jest.isolateModules(() => {
      const reloaded = jest.requireActual<typeof import('./agentNewsFeedView')>('./agentNewsFeedView');
      expect(reloaded.getAgentNewsFeedView()).toBe('digests');
    });
    localStorage.setItem('mytonwallet-agent-mypulse-news-view', 'invalid');
    window.dispatchEvent(new StorageEvent('storage', {
      key: 'mytonwallet-agent-mypulse-news-view', storageArea: localStorage,
    }));
    expect(getAgentNewsFeedView()).toBe('all');
    expect(onChange.mock.calls).toEqual([['digests'], ['all']]);
    unsubscribe();
  });

  it('keeps the selected news view in memory when storage is unavailable', () => {
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentNewsFeedView(onChange);
    const write = jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('Storage unavailable');
    });
    setAgentNewsFeedView('digests');
    expect(getAgentNewsFeedView()).toBe('digests');
    const read = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('Storage unavailable');
    });
    expect(getAgentNewsFeedView()).toBe('digests');
    read.mockRestore();
    write.mockRestore();
    setAgentNewsFeedView('all');
    expect(onChange.mock.calls).toEqual([['digests'], ['all']]);
    unsubscribe();
  });

  it('sends the hour and current time zone on each page and reloads after an hour change', async () => {
    let result: ReturnType<typeof useAgentNewsFeed>;
    let timeZone = 'America/New_York';
    const options = Intl.DateTimeFormat().resolvedOptions();
    jest.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
      .mockImplementation(() => ({ ...options, timeZone }));
    const oldPage = new Deferred<void>();
    const digest = {
      id: 'digest', deliveredAt: '2026-10-22T21:00:00.000Z', total: 2,
      top: [{ eventId: 2, headline: 'News 2' }],
    };
    jest.mocked(callApi).mockImplementation(async (...args) => {
      if (args[0] !== 'getAgentV2NewsFeed') return undefined;
      const params = args[1];
      if (typeof params === 'object' && 'cursor' in params && params.cursor) {
        const isStale = 'digestHour' in params && params.digestHour === 21;
        if (isStale) await oldPage.promise;
        return { ok: true, value: {
          protocolVersion: 3, locale: 'en', items: [],
          digests: [{ ...digest, id: isStale ? 'stale-digest' : 'older-digest', deliveredAt: ITEMS[0].deliveredAt }],
        } } as never;
      }
      const isEarlyDigest = typeof params === 'object' && 'digestHour' in params && params.digestHour === 9;
      return { ok: true, value: {
        protocolVersion: 3, locale: 'en', items: isEarlyDigest ? ITEMS.slice(1) : ITEMS,
        digests: [{ ...digest, id: isEarlyDigest ? 'digest-9' : digest.id }], nextCursor: 'older',
      } } as never;
    });
    function Harness() {
      result = useAgentNewsFeed({ isEnabled: true, isActive: true, langCode: 'en', isFeedVisible: false });
      return undefined;
    }
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.items !== undefined && !result.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 21, digestMinute: 0, timeZone: 'America/New_York',
    });
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2 }, { kind: 'digest', id: 'digest' }, { kind: 'news', eventId: 3 },
    ]);

    result!.loadMore();
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', cursor: 'older', digestHour: 21, digestMinute: 0, timeZone: 'America/New_York',
    });
    setAgentDigestTime({ hour: 9, minute: 0 });
    expect(await waitFor(() => result!.items?.some((item) => item.kind === 'digest' && item.id === 'digest-9') === true
      && !result!.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 9, digestMinute: 0, timeZone: 'America/New_York',
    });
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2 }, { kind: 'digest', id: 'digest-9' }, { kind: 'news', eventId: 3 },
    ]);
    oldPage.resolve();
    await oldPage.promise;
    await pause(50);
    expect(result!.items?.filter(({ kind }) => kind === 'digest')).toHaveLength(1);

    timeZone = 'Europe/Moscow';
    result!.loadMore();
    expect(await waitFor(() => (
      result!.items?.some((item) => item.kind === 'digest' && item.id === 'older-digest') === true
      && !result!.isLoadingMore
    ), 10, 300)).toBe(true);
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2 }, { kind: 'digest', id: 'older-digest' },
      { kind: 'news', eventId: 3 },
    ]);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', cursor: 'older', digestHour: 9, digestMinute: 0, timeZone: 'Europe/Moscow',
    });

    TeactDOM.render(undefined, root);
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 5 && !result!.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 9, digestMinute: 0, timeZone: 'Europe/Moscow',
    });

    // A new minute is another schedule too
    setAgentDigestTime({ hour: 9, minute: 45 });
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 6 && !result!.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 9, digestMinute: 45, timeZone: 'Europe/Moscow',
    });
  });

  it.each(['hour', 'minute', 'timeZone'] as const)('drops cached digests on a new %s, keeping news discussions', async (
    setting,
  ) => {
    let result: ReturnType<typeof useAgentNewsFeed> | undefined;
    let timeZone = 'America/New_York';
    const options = Intl.DateTimeFormat().resolvedOptions();
    jest.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
      .mockImplementation(() => ({ ...options, timeZone }));
    jest.mocked(callApi).mockResolvedValue({ ok: true, value: {
      protocolVersion: 3, locale: 'en', items: ITEMS,
      digests: [{ id: 'cached-digest', deliveredAt: ITEMS[0].deliveredAt, total: 1, top: [] }],
    } } as never);
    function Harness({ isEnabled = false }: { isEnabled?: boolean }) {
      result = useAgentNewsFeed({ isEnabled, isActive: isEnabled, langCode: 'en', isFeedVisible: false });
      return undefined;
    }
    TeactDOM.render(<Harness isEnabled />, root);
    expect(await waitFor(() => (
      jest.mocked(callApi).mock.calls.length === 1 && !result?.isLoading
      && result?.items?.some((item) => item.kind === 'digest' && item.id === 'cached-digest') === true
    ), 10, 300)).toBe(true);
    result!.markDiscussion(2, { threadId: 'news-thread' });
    result!.markDigestDiscussion('cached-digest', { threadId: 'stale-digest-thread' });
    expect(await waitFor(() => (
      result?.items?.some((item) => item.discussion?.threadId === 'stale-digest-thread') === true
    ), 10, 300)).toBe(true);
    await pause(50);
    TeactDOM.render(undefined, root);

    if (setting === 'hour') setAgentDigestTime({ hour: 9, minute: 0 });
    else if (setting === 'minute') setAgentDigestTime({ hour: 21, minute: 15 });
    else timeZone = 'Europe/Moscow';
    result = undefined;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.items !== undefined, 10, 300)).toBe(true);
    await pause(50);
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2, discussion: { threadId: 'news-thread' } }, { kind: 'news', eventId: 3 },
    ]);
    expect(jest.mocked(callApi)).toHaveBeenCalledTimes(1);

    if (setting !== 'timeZone') setAgentDigestTime({ hour: 21, minute: 0 });
    else timeZone = 'America/New_York';
    TeactDOM.render(<Harness isEnabled />, root);
    expect(await waitFor(() => (
      jest.mocked(callApi).mock.calls.length === 2 && !result?.isLoading
      && result?.items?.some((item) => item.kind === 'digest' && item.id === 'cached-digest') === true
    ), 10, 300)).toBe(true);
    expect(result!.items?.find((item) => item.kind === 'digest')?.discussion).toBeUndefined();
    expect(result!.items?.find((item) => item.kind === 'news' && item.eventId === 2)?.discussion)
      .toEqual({ threadId: 'news-thread' });
  });

  it.each([false, true])('keeps the hour across remounts when writes fail, with failing reads: %s', async (
    shouldFailReads,
  ) => {
    expect(getAgentDigestTime().hour).toBe(21);
    localStorage.setItem('mytonwallet-agent-mypulse-digest-hour', '21');
    if (shouldFailReads) {
      jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
        throw new Error('Storage unavailable');
      });
    }
    jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('Storage unavailable');
    });
    jest.mocked(callApi).mockResolvedValue({ ok: true, value: {
      protocolVersion: 3, locale: 'en', items: [],
    } } as never);
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentDigestTime(onChange);
    setAgentDigestTime({ hour: 9, minute: 0 });
    expect(getAgentDigestTime().hour).toBe(9);
    let result: ReturnType<typeof useAgentNewsFeed> | undefined;
    function Harness() {
      result = useAgentNewsFeed({ isEnabled: true, isActive: true, langCode: 'en', isFeedVisible: false });
      return undefined;
    }
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 1 && !result?.isLoading, 10, 300)).toBe(true);
    TeactDOM.render(undefined, root);
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 2 && !result?.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed',
      expect.objectContaining({ digestHour: 9 }));
    setAgentDigestTime({ hour: 21, minute: 0 });
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 3 && !result?.isLoading, 10, 300)).toBe(true);
    expect(getAgentDigestTime().hour).toBe(21);
    expect(onChange.mock.calls).toEqual([[{ hour: 9, minute: 0 }], [{ hour: 21, minute: 0 }]]);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed',
      expect.objectContaining({ digestHour: 21 }));
    unsubscribe();
  });
});

describe('useAgentNewsFeed prefetch', () => {
  let root: HTMLDivElement;
  let result: ReturnType<typeof useAgentNewsFeed>;
  const apiMock = jest.mocked(callApi);

  beforeEach(async () => {
    // Teact can have a real frame queued by the previous test
    jest.useFakeTimers({ doNotFake: ['requestAnimationFrame', 'cancelAnimationFrame'] });
    apiMock.mockReset();
    root = document.createElement('div');
    document.body.appendChild(root);
    // A distinct mount language excludes the cached feed from this hook instance
    TeactDOM.render(<Harness isDisabled langCode="prefetch-initialization" />, root);
    await flushFeed();
    expect(result.items).toBeUndefined();
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    setAgentDigestTime({ hour: 21, minute: 0 });
    await flushFeed();
    root.remove();
    localStorage.clear();
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  it('sets the first-launch read-through only after the all view is shown', async () => {
    const allPage = buildFeedPage([0]);
    apiMock.mockImplementation((...args) => {
      const params = args[1];
      return Promise.resolve(
        params && typeof params === 'object' && 'view' in params && params.view === 'digests'
          ? buildFeedPage([], [0]) : allPage,
      ) as never;
    });
    expect(getAgentNewsReadThrough()).toBeUndefined();
    TeactDOM.render(<Harness view="digests" langCode="first-launch" isFeedHidden />, root);
    await flushFeed();
    expect(result.items).toMatchObject([{ kind: 'digest', id: 'digest-0' }]);
    expect(result.allItems).toMatchObject([{ kind: 'news', eventId: 1000 }]);
    expect(result.unreadCount).toBe(0);
    expect(getAgentNewsReadThrough()).toBeUndefined();

    TeactDOM.render(<Harness view="all" langCode="first-launch" isFeedHidden />, root);
    await flushFeed();
    expect(getRequestedCursors()).toHaveLength(3);
    expect(getAgentNewsReadThrough()).toBe(allPage.value.items[0].deliveredAt);
    expect(result.unreadCount).toBe(0);
  });

  it('pages digests to the history end, keeps a failed refresh and reloads the digest schedule', async () => {
    let timeZone = 'UTC';
    const createFormatter = Intl.DateTimeFormat;
    jest.spyOn(Intl, 'DateTimeFormat').mockImplementation((...args) => {
      const formatter = createFormatter(...args);
      const options = formatter.resolvedOptions();
      formatter.resolvedOptions = () => ({ ...options, timeZone });
      return formatter;
    });
    const firstPage = buildFeedPage([], [0], 'ndv1:older');
    const olderPage = buildFeedPage([], [-24]);
    const refreshedPage = buildFeedPage([], [-1], 'ndv1:fresh');
    const responses = [firstPage, olderPage, undefined, refreshedPage, refreshedPage];
    apiMock.mockImplementation((...args) => {
      const params = args[1];
      return Promise.resolve(
        params && typeof params === 'object' && 'view' in params && params.view === 'digests'
          ? responses.shift() : { ok: true, value: { protocolVersion: 3, locale: 'en', items: ITEMS } },
      ) as never;
    });
    TeactDOM.render(undefined, root);
    await flushFeed();
    const readThrough = markAgentNewsReadThrough('2026-10-21T00:00:00.000Z');

    TeactDOM.render(<Harness view="digests" langCode="digests-lifecycle" />, root);
    await flushFeed();
    expect(result.items).toMatchObject([{ kind: 'digest', id: 'digest-0' }]);
    expect(result.hasMore).toBe(true);
    expect(result.unreadEventId).toBeUndefined();
    // In the Digests view the News row counts the new digests and shows the latest; the digests on screen are read
    expect(result.unreadCount).toBe(0);
    expect(result.latestDigest).toMatchObject({ id: 'digest-0' });
    expect(result.latestItem).toEqual({ ...ITEMS[1], kind: 'news' });
    expect(getAgentNewsReadThrough()).toBe(readThrough);
    expect(getDigestRequests()).toEqual([{
      lang: 'digests-lifecycle', view: 'digests', digestHour: 21, digestMinute: 0, timeZone: 'UTC',
    }]);

    result.loadMore();
    await flushFeed();
    expect(result.items).toMatchObject([{ id: 'digest--24' }, { id: 'digest-0' }]);
    expect(result.hasMore).toBe(false);
    result.loadMore();
    await flushFeed();
    expect(getDigestRequests().map((params) => params.cursor)).toEqual([undefined, 'ndv1:older']);

    result.markDigestDiscussion('digest-0', { threadId: 'digest-thread' });
    await flushFeed();
    result.refresh();
    await flushFeed();
    expect(result.errorCode).toBe('network_error');
    expect(result.items).toMatchObject([
      { id: 'digest--24' }, { id: 'digest-0', discussion: { threadId: 'digest-thread' } },
    ]);
    publishAgentV2Update({
      kind: 'threadChanged', threadId: 'digest-thread', thread: {
        id: 'digest-thread', revision: 1, messageCount: 2, icon: '🗞️',
        createdAt: DIGEST.deliveredAt, updatedAt: DIGEST.deliveredAt, lastActivityAt: DIGEST.deliveredAt,
        digest: { id: 'digest-0', windowEnd: DIGEST.deliveredAt, top: DIGEST.top, total: DIGEST.total },
      },
    });
    await flushFeed();
    expect(result.items?.at(-1)?.discussion).toEqual({ threadId: 'digest-thread', icon: '🗞️' });
    result.removeDiscussion('digest-thread');
    await flushFeed();
    expect(result.items?.at(-1)?.discussion).toBeUndefined();

    setAgentDigestTime({ hour: 9, minute: 0 });
    await flushFeed();
    expect(getDigestRequests().at(-1)).toEqual({
      lang: 'digests-lifecycle', view: 'digests', digestHour: 9, digestMinute: 0, timeZone: 'UTC',
    });
    expect(result.errorCode).toBeUndefined();
    expect(result.items).toMatchObject([{ id: 'digest--1' }]);
    timeZone = 'Europe/Moscow';
    window.dispatchEvent(new Event('focus'));
    await flushFeed();
    expect(getDigestRequests().at(-1)).toEqual({
      lang: 'digests-lifecycle', view: 'digests', digestHour: 9, digestMinute: 0, timeZone: 'Europe/Moscow',
    });
    expect(result.unreadCount).toBe(0);
    expect(getAgentNewsReadThrough()).toBe(readThrough);
  });

  it('counts the new digests in the Digests view and keeps the first one new while the feed is open', async () => {
    apiMock.mockImplementation((...args) => {
      const params = args[1];
      return Promise.resolve(
        params && typeof params === 'object' && 'view' in params && params.view === 'digests'
          ? buildFeedPage([], [0, -24, -48]) : buildFeedPage([0]),
      ) as never;
    });
    const digestTime = (hour: number) => new Date(Date.UTC(2026, 9, 30, 12) + hour * 3_600_000).toISOString();
    TeactDOM.render(undefined, root);
    await flushFeed();
    markAgentNewsDigestsReadThrough(digestTime(-48));
    TeactDOM.render(<Harness view="digests" langCode="digests-unread" isFeedHidden />, root);
    await flushFeed();
    expect(result.unreadCount).toBe(2);
    expect(result.latestDigest).toMatchObject({ id: 'digest-0' });
    expect(result.unreadDigestId).toBeUndefined();

    // The feed opened from the chat list reads the digests on screen and keeps the line above the first new one, from
    // the first render, which positions the list
    const renderedUnreadDigestIds: (string | undefined)[] = [];
    function OpenedDigests() {
      result = useAgentNewsFeed({
        isEnabled: true, isActive: true, langCode: 'digests-unread', view: 'digests', isFeedVisible: true,
      });
      renderedUnreadDigestIds.push(result.unreadDigestId);
      return undefined;
    }
    result.startReading();
    TeactDOM.render(<OpenedDigests />, root);
    await flushFeed();
    expect(renderedUnreadDigestIds[0]).toBe('digest--24');
    expect(result.unreadDigestId).toBe('digest--24');
    expect(result.unreadCount).toBe(0);
    expect(getAgentNewsDigestsReadThrough()).toBe(digestTime(0));
    TeactDOM.render(<Harness langCode="digests-unread" />, root);
    await flushFeed();
    expect(result.unreadDigestId).toBeUndefined();
    expect(result.latestDigest).toBeUndefined();
  });

  it('takes no digest that All News showed as new when the Digests view is shown later', async () => {
    apiMock.mockImplementation(() => Promise.resolve(buildFeedPage([0], [0, -24, -48])) as never);
    const digestTime = (hour: number) => new Date(Date.UTC(2026, 9, 30, 12) + hour * 3_600_000).toISOString();
    TeactDOM.render(undefined, root);
    await flushFeed();
    markAgentNewsDigestsReadThrough(digestTime(-48));
    TeactDOM.render(<Harness langCode="digests-seen-in-all" isFeedHidden />, root);
    await flushFeed();

    result.startReading();
    TeactDOM.render(<Harness langCode="digests-seen-in-all" />, root);
    await flushFeed();
    expect(getAgentNewsDigestsReadThrough()).toBe(digestTime(0));

    TeactDOM.render(<Harness view="digests" langCode="digests-seen-in-all" />, root);
    await flushFeed();
    expect(result.unreadDigestId).toBeUndefined();
    expect(result.unreadCount).toBe(0);
  });

  it('shows each cached view immediately and rereads digests on activation and remount', async () => {
    const pendingPage = new Deferred<ReturnType<typeof buildFeedPage>>();
    let digestReads = 0;
    let allReads = 0;
    apiMock.mockImplementation((...args) => {
      const params = args[1];
      if (params && typeof params === 'object' && 'view' in params && params.view === 'digests') {
        digestReads++;
        return (digestReads === 1 ? Promise.resolve(buildFeedPage([], [0, -24])) : pendingPage.promise) as never;
      }
      allReads++;
      return Promise.resolve(buildFeedPage([0], [-1])) as never;
    });
    TeactDOM.render(<Harness view="digests" langCode="digests-cache" />, root);
    await flushFeed();
    expect(result.items).toMatchObject([{ id: 'digest--24' }, { id: 'digest-0' }]);
    TeactDOM.render(<Harness langCode="digests-cache" />, root);
    await flushFeed();
    expect(result.items).toMatchObject([{ kind: 'digest', id: 'digest--1' }, { kind: 'news' }]);
    expect(allReads).toBe(2);
    TeactDOM.render(<Harness view="digests" langCode="digests-cache" />, root);
    await flushFeed();
    expect(result.isLoading).toBe(true);
    expect(result.items).toMatchObject([{ id: 'digest--24' }, { id: 'digest-0' }]);
    expect(digestReads).toBe(2);
    TeactDOM.render(undefined, root);
    await flushFeed();
    TeactDOM.render(<Harness view="digests" langCode="digests-cache" />, root);
    await flushFeed();
    expect(result.items).toMatchObject([{ id: 'digest--24' }, { id: 'digest-0' }]);
    expect(digestReads).toBe(3);
    pendingPage.resolve(buildFeedPage([], [0, -24]));
    await flushFeed();
  });

  it('loads one page at a time until two digests are available after the first page', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0], [], 'one') as never)
      .mockResolvedValueOnce(buildFeedPage([-12], [-11], 'two') as never)
      .mockResolvedValueOnce(buildFeedPage([-36], [-35], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-72]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();

    expect(getRequestedCursors()).toEqual([undefined, 'one', 'two']);
    expect(result.items?.filter(({ kind }) => kind === 'digest')).toHaveLength(2);
    expect(result.hasMore).toBe(true);
    expect(result.isLoadingMore).toBe(false);
  });

  it('stops at exactly 48 hours from the newest news when there are no digests', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0], [], 'one') as never)
      .mockResolvedValueOnce(buildFeedPage([-24], [], 'two') as never)
      .mockResolvedValueOnce(buildFeedPage([-48], [], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-72]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();

    expect(getRequestedCursors()).toEqual([undefined, 'one', 'two']);
    expect(result.items).toHaveLength(3);
    expect(result.hasMore).toBe(true);
  });

  it('keeps the end of history across refreshes and remounts without blocking scroll loading', async () => {
    apiMock.mockImplementation((method, ...args) => {
      if (method !== 'getAgentV2NewsFeed') return Promise.resolve(undefined);
      const params = args[0];
      return Promise.resolve(
        params && typeof params === 'object' && 'cursor' in params && params.cursor
          ? buildFeedPage([-12]) : buildFeedPage([0], [-1], 'p2'),
      ) as never;
    });
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'p2']);

    result.refresh();
    result.markDigestReached('digest--1');
    await flushFeed();
    result.refresh();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'p2', undefined, undefined]);
    expect(getRequestedCursors().filter((cursor) => cursor === 'p2')).toHaveLength(1);
    expect(result.hasMore).toBe(true);

    TeactDOM.render(undefined, root);
    await flushFeed();
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    expect(getRequestedCursors().filter((cursor) => cursor === 'p2')).toHaveLength(1);

    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors().filter((cursor) => cursor === 'p2')).toHaveLength(2);

    TeactDOM.render(<Harness langCode="ru" />, root);
    await flushFeed();
    expect(getRequestedCursors().filter((cursor) => cursor === 'p2')).toHaveLength(3);

    setAgentDigestTime({ hour: 9, minute: 0 });
    await flushFeed();
    expect(getRequestedCursors().filter((cursor) => cursor === 'p2')).toHaveLength(4);
  });

  it('fills a refreshed feed gap without counting disconnected cached entries', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0, -26], [-1, -25], 'old') as never)
      .mockResolvedValueOnce(buildFeedPage([-30], [-29]) as never)
      .mockResolvedValueOnce(buildFeedPage([60, 50], [59, 51], 'gap') as never)
      .mockResolvedValueOnce(buildFeedPage([36], [35], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-100]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    result.loadMore();
    await flushFeed();
    const oldEntries = result.items!;
    expect(result.hasMore).toBe(false);

    result.refresh();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'old', undefined]);
    expect(result.items).toEqual(expect.arrayContaining(oldEntries));

    result.markDigestReached('digest-59');
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'old', undefined, 'gap']);
    expect(result.items?.some((item) => item.kind === 'digest' && item.id === 'digest-35')).toBe(true);
    expect(result.items).toEqual(expect.arrayContaining(oldEntries));
  });

  it('prefetches two digests older than the oldest reached digest and keeps that reference', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0, -26], [-1, -25], 'older') as never)
      .mockResolvedValueOnce(buildFeedPage([-50], [-49, -50], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-100]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined]);

    result.markDigestReached('digest--25');
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'older']);
    expect(result.items?.filter(({ kind }) => kind === 'digest')).toHaveLength(4);

    result.markDigestReached('digest--1');
    result.markDigestReached('digest--25');
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'older']);
  });

  it('pauses on a page error without losing news and retries that cursor on a scroll to the top', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0], [], 'older') as never)
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce(buildFeedPage([-26], [-1, -25], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-100]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    await jest.advanceTimersByTimeAsync(60_000);

    expect(getRequestedCursors()).toEqual([undefined, 'older']);
    expect(result.items).toMatchObject([{ kind: 'news', eventId: 1000 }]);
    expect(result.errorCode).toBeUndefined();
    expect(result.isLoadingMore).toBe(false);
    expect(result.hasMore).toBe(true);

    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'older', 'older']);
    expect(result.items?.filter(({ kind }) => kind === 'digest')).toHaveLength(2);
  });

  it('prefetches after reaching an older digest when a first-page refresh fails', async () => {
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0, -26], [-1, -25], 'older') as never)
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce(buildFeedPage([-50], [-49, -50], 'beyond') as never)
      .mockResolvedValue(buildFeedPage([-100]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    const initialItems = result.items;
    expect(getRequestedCursors()).toEqual([undefined]);

    result.refresh();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, undefined]);
    expect(result.items).toBe(initialItems);
    expect(result.errorCode).toBe('network_error');

    result.markDigestReached('digest--25');
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, undefined, 'older']);
    expect(result.items?.filter(({ kind }) => kind === 'digest')).toHaveLength(4);
  });

  it.each(['hour', 'language', 'timeZone'] as const)(
    'discards an older page and resets the reached digest after a %s change', async (setting) => {
      const oldPage = new Deferred<ReturnType<typeof buildFeedPage>>();
      let timeZone = 'UTC';
      const createFormatter = Intl.DateTimeFormat;
      // Fake timers bind `resolvedOptions` on each formatter, bypassing the native prototype
      jest.spyOn(Intl, 'DateTimeFormat').mockImplementation((...args) => {
        const formatter = createFormatter(...args);
        const options = formatter.resolvedOptions();
        formatter.resolvedOptions = () => ({ ...options, timeZone });
        return formatter;
      });
      apiMock
        .mockResolvedValueOnce(buildFeedPage([0], [-1], 'old') as never)
        .mockImplementationOnce(() => oldPage.promise as never)
        .mockResolvedValueOnce(buildFeedPage([0], [-0.5, -1.5], 'fresh') as never)
        .mockResolvedValue(buildFeedPage([-100]) as never);
      TeactDOM.render(<Harness />, root);
      await flushFeed();
      result.markDigestReached('digest--1');
      await flushFeed();
      expect(getRequestedCursors()).toEqual([undefined, 'old']);
      expect(apiMock).toHaveBeenNthCalledWith(1, 'getAgentV2NewsFeed', expect.objectContaining({ timeZone: 'UTC' }));

      if (setting === 'hour') setAgentDigestTime({ hour: 9, minute: 0 });
      else if (setting === 'language') TeactDOM.render(<Harness langCode="ru" />, root);
      else {
        timeZone = 'Europe/Moscow';
        result.refresh();
      }
      await flushFeed();
      expect(getRequestedCursors()).toEqual([undefined, 'old', undefined]);
      expect(apiMock).toHaveBeenNthCalledWith(3, 'getAgentV2NewsFeed', expect.objectContaining({
        timeZone: setting === 'timeZone' ? 'Europe/Moscow' : 'UTC',
      }));

      oldPage.resolve(buildFeedPage([-3], [-3], 'stale'));
      await flushFeed();
      expect(getRequestedCursors()).toEqual([undefined, 'old', undefined]);
      expect(result.items?.some((item) => item.kind === 'digest' && item.id === 'digest--3')).toBe(false);
      expect(result.items?.some((item) => item.kind === 'news' && item.eventId === 997)).toBe(false);
      expect(result.isLoadingMore).toBe(false);
    },
  );

  it('serializes background and scroll loads even across a first-page refresh', async () => {
    const firstPage = new Deferred<ReturnType<typeof buildFeedPage>>();
    const secondPage = new Deferred<ReturnType<typeof buildFeedPage>>();
    let activePages = 0;
    let maximumActivePages = 0;
    let firstPageReads = 0;
    apiMock.mockImplementation(async (method, ...args) => {
      if (method !== 'getAgentV2NewsFeed') return undefined;
      const params = args[0];
      if (!params || typeof params !== 'object' || !('cursor' in params) || !params.cursor) {
        return buildFeedPage([0], [], ++firstPageReads === 1 ? 'one' : 'two') as never;
      }
      activePages++;
      maximumActivePages = Math.max(maximumActivePages, activePages);
      const page = await (params.cursor === 'one' ? firstPage.promise : secondPage.promise);
      activePages--;
      return page as never;
    });
    TeactDOM.render(<Harness />, root);
    await flushFeed();
    result.loadMore();
    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one']);

    result.refresh();
    await flushFeed();
    result.loadMore();
    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one', undefined]);

    firstPage.resolve(buildFeedPage([-12], [], 'ignored'));
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one', undefined, 'two']);
    secondPage.resolve(buildFeedPage([-26], [-1, -25], 'two'));
    await flushFeed();
    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one', undefined, 'two']);
    expect(maximumActivePages).toBe(1);
    expect(result.hasMore).toBe(false);
  });

  it('blocks cursor loading while reopening the feed refreshes its first page', async () => {
    const olderPage = new Deferred<ReturnType<typeof buildFeedPage>>();
    const refreshedPage = new Deferred<ReturnType<typeof buildFeedPage>>();
    apiMock
      .mockResolvedValueOnce(buildFeedPage([0], [], 'one') as never)
      .mockImplementationOnce(() => olderPage.promise as never)
      .mockImplementationOnce(() => refreshedPage.promise as never)
      .mockResolvedValue(buildFeedPage([-100]) as never);
    TeactDOM.render(<Harness />, root);
    await flushFeed();

    TeactDOM.render(<Harness isInactive />, root);
    await flushFeed();
    olderPage.resolve(buildFeedPage([-12], [-11], 'stale-cursor'));
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one']);

    TeactDOM.render(<Harness />, root);
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one', undefined]);

    refreshedPage.resolve(buildFeedPage([0], [-1, -2], 'fresh'));
    await flushFeed();
    result.loadMore();
    await flushFeed();
    expect(getRequestedCursors()).toEqual([undefined, 'one', undefined, 'fresh']);
  });

  function Harness({ isDisabled = false, isInactive = false, isFeedHidden = false, langCode = 'en', view = 'all' }: {
    isDisabled?: boolean;
    isInactive?: boolean;
    isFeedHidden?: boolean;
    langCode?: string;
    view?: AgentNewsFeedView;
  }) {
    const isActive = !isInactive;
    result = useAgentNewsFeed({
      isEnabled: !isDisabled, isActive, langCode, view, isFeedVisible: isActive && !isFeedHidden,
    });
    return undefined;
  }

  function getRequestedCursors() {
    return apiMock.mock.calls.map(([, params]) => (
      params && typeof params === 'object' && 'cursor' in params ? params.cursor : undefined
    ));
  }

  function getDigestRequests() {
    return apiMock.mock.calls.flatMap(([, params]) => (
      params && typeof params === 'object' && 'view' in params && params.view === 'digests'
        ? [params] : []
    ));
  }

  async function flushFeed() {
    let previousResult: typeof result | undefined;
    let previousCallCount = -1;
    for (let frame = 0; frame < 20; frame++) {
      await new Promise<void>(requestAfterRender);
      await jest.advanceTimersByTimeAsync(0);
      if (result === previousResult && apiMock.mock.calls.length === previousCallCount) return;
      previousResult = result;
      previousCallCount = apiMock.mock.calls.length;
    }
    throw new Error('News feed did not settle across render and request boundaries');
  }
});

function buildFeedPage(newsHours: number[], digestHours: number[] = [], nextCursor?: string) {
  return { ok: true, value: {
    protocolVersion: 3,
    locale: 'en',
    items: newsHours.map((hour) => ({
      ...ITEMS[0], eventId: 1000 + hour, deliveredAt: new Date(Date.UTC(2026, 9, 30, 12 + hour)).toISOString(),
    })),
    digests: digestHours.map((hour) => ({
      ...DIGEST,
      id: `digest-${hour}`,
      deliveredAt: new Date(Date.UTC(2026, 9, 30, 12) + hour * 3_600_000).toISOString(),
    })),
    nextCursor,
  } satisfies AgentNewsFeedPageV2 };
}

function getShellProps() {
  return shellMock.mock.calls.at(-1)![0];
}
