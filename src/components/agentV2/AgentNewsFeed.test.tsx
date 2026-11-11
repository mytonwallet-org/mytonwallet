import React, { requestAfterRender } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type {
  AgentNewsFeedDigestV2, AgentNewsFeedItemV2, AgentNewsFeedPageV2,
} from '../../api/agentV2/protocol/types';
import type { AgentConversationMessageContext } from '../agent/AgentConversationShell';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';

import { formatTime } from '../../util/dateFormat';
import Deferred from '../../util/Deferred';
import { pause, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import { getAgentDigestHour, setAgentDigestHour, subscribeToAgentDigestHour } from './agentDigestHour';
import { mergeAgentNewsFeedEntries } from './agentNewsFeedItems';
import useAgentNewsFeed from './useAgentNewsFeed';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentNewsFeed from './AgentNewsFeed';

jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  withGlobal: () => (Component: unknown) => Component,
}));
jest.mock('../../api', () => ({ callApi: jest.fn() }));
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
    setAgentDigestHour(21);
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
    expect(props.header).toEqual({ title: 'News', hasBackButton: true });
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

  it('shows a digest as a card among the news, which opens its headlines\' discussions and its own', async () => {
    const onOpenNewsDiscussion = jest.fn();
    const onOpenDigestDiscussion = jest.fn();
    const onDigestReached = jest.fn();
    renderFeed({
      items: mergeAgentNewsFeedEntries(ITEMS, [DIGEST]), onOpenNewsDiscussion, onOpenDigestDiscussion, onDigestReached,
    });

    const { messages, renderMessage, emptyText } = getShellProps().conversation;
    expect(emptyText).toBeUndefined();
    // The digest stands where it was delivered, under an ID no news has
    expect(messages).toMatchObject([
      { id: 2 }, { isOutgoing: false, timestamp: Date.parse(DIGEST.deliveredAt) }, { id: 3 },
    ]);
    const digestMessage = messages[1];
    expect(digestMessage.id).toBeLessThan(0);
    getShellProps().actions.onMessageVisible!(messages[0].id);
    getShellProps().actions.onMessageVisible!(digestMessage.id);
    expect(onDigestReached.mock.calls).toEqual([[DIGEST.id]]);
    TeactDOM.render(<div>{renderMessage(digestMessage, MESSAGE_CONTEXT)}</div>, cardRoot);
    await pause(20);

    const card = cardRoot.querySelector(`[data-agent-v2-message-id="${digestMessage.id}"]`)!;
    expect(card.getAttribute('data-agent-v2-message-role')).toBe('assistant');
    expect(card.querySelector('h3')!.textContent).toBe('$agent_digest_title');
    expect(card.textContent).toContain(`$agent_digest_meta 5 ${formatTime(DIGEST.deliveredAt)}`);
    const headlines = Array.from(card.querySelectorAll<HTMLButtonElement>('[data-agent-news-digest-headline]'));
    expect(headlines.map(({ textContent }) => textContent)).toEqual(['News 2', 'News 3']);
    // The news the digest leaves out are above in the feed
    expect(card.textContent).toContain('$agent_digest_more 3');

    headlines[1].click();
    expect(onOpenNewsDiscussion).toHaveBeenCalledWith(3);
    card.querySelector<HTMLButtonElement>('[aria-label="$agent_news_discuss, $agent_digest_title"]')!.click();
    expect(onOpenDigestDiscussion).toHaveBeenCalledWith('digest');

    // A digest of its headlines alone says nothing more, and a feed of digests alone is not empty
    renderFeed({ items: mergeAgentNewsFeedEntries([], [{ ...DIGEST, total: 2 }]) });
    const feed = getShellProps().conversation;
    expect(feed.emptyText).toBeUndefined();
    expect(feed.messages.map(({ id }) => id)).toEqual([digestMessage.id]);
    TeactDOM.render(<div>{feed.renderMessage(feed.messages[0], MESSAGE_CONTEXT)}</div>, cardRoot);
    await pause(20);
    expect(cardRoot.textContent).not.toContain('$agent_digest_more');
  });

  it('opens the digest\'s hour from the bell, which takes the hour picked in its menu', async () => {
    renderFeed({ items: [] });
    expect(root.querySelector('[data-modal]')).toBeNull();

    getShellProps().actions.onOpenDigestSettings!();
    expect(await waitFor(() => Boolean(root.querySelector('[data-modal]')), 10, 300)).toBe(true);
    const sheet = root.querySelector('[data-modal]')!;
    expect(sheet.querySelector('h2')!.textContent).toBe('$agent_digest_sheet_title');
    expect(sheet.textContent).toContain('$agent_digest_settings_text');
    expect(sheet.textContent).toContain('$agent_digest_device_time_zone');
    const timeRow = Array.from(sheet.querySelectorAll('button'))
      .find(({ textContent }) => textContent?.startsWith('$agent_digest_time'))!;
    expect(timeRow.textContent).toBe('$agent_digest_time21:00');

    timeRow.click();
    expect(await waitFor(() => portals.querySelectorAll('button').length === 24, 10, 300)).toBe(true);
    const hours = Array.from(portals.querySelectorAll('button'));
    expect(hours[0].textContent).toBe('00:00');
    hours.find(({ textContent }) => textContent === '09:00')!.click();
    expect(getAgentDigestHour()).toBe(9);
    expect(await waitFor(() => timeRow.textContent === '$agent_digest_time09:00', 10, 300)).toBe(true);

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
    items,
    unreadEventId,
    hasMore = false,
    isLoading = false,
    errorCode,
    onRetry = jest.fn(),
    onLoadMore = jest.fn(),
    onDigestReached = jest.fn(),
    onOpenNewsDiscussion = jest.fn(),
    onOpenDigestDiscussion = jest.fn(),
  }: Partial<{
    items: AgentNewsFeedEntry[];
    unreadEventId: number;
    hasMore: boolean;
    isLoading: boolean;
    errorCode: 'network_error' | 'news_unavailable';
    onRetry: NoneToVoidFunction;
    onLoadMore: NoneToVoidFunction;
    onDigestReached: (id: string) => void;
    onOpenNewsDiscussion: (eventId: number) => void;
    onOpenDigestDiscussion: (id: string) => void;
  }>) {
    TeactDOM.render(
      <AgentNewsFeed
        isActive
        items={items}
        unreadEventId={unreadEventId}
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
    setAgentDigestHour(0);
    setAgentDigestHour(21);
    localStorage.clear();
  });

  it('defaults to 21, persists valid hours and notifies subscribers only of changes', () => {
    expect(getAgentDigestHour()).toBe(21);
    const onChange = jest.fn();
    const unsubscribe = subscribeToAgentDigestHour(onChange);
    setAgentDigestHour(0);
    expect(getAgentDigestHour()).toBe(0);
    expect(localStorage.getItem('mytonwallet-agent-mypulse-digest-hour')).toBe('0');
    setAgentDigestHour(0);
    expect(onChange.mock.calls).toEqual([[0]]);
    expect(() => setAgentDigestHour(24)).toThrow(RangeError);
    expect(() => setAgentDigestHour(9.5)).toThrow(RangeError);
    unsubscribe();
    setAgentDigestHour(23);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(getAgentDigestHour()).toBe(23);
    localStorage.clear();
    expect(getAgentDigestHour()).toBe(23);
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
      lang: 'en', digestHour: 21, timeZone: 'America/New_York',
    });
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2 }, { kind: 'digest', id: 'digest' }, { kind: 'news', eventId: 3 },
    ]);

    result!.loadMore();
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', cursor: 'older', digestHour: 21, timeZone: 'America/New_York',
    });
    setAgentDigestHour(9);
    expect(await waitFor(() => result!.items?.some((item) => item.kind === 'digest' && item.id === 'digest-9') === true
      && !result!.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 9, timeZone: 'America/New_York',
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
      lang: 'en', cursor: 'older', digestHour: 9, timeZone: 'Europe/Moscow',
    });

    TeactDOM.render(undefined, root);
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 5 && !result!.isLoading, 10, 300)).toBe(true);
    expect(jest.mocked(callApi)).toHaveBeenLastCalledWith('getAgentV2NewsFeed', {
      lang: 'en', digestHour: 9, timeZone: 'Europe/Moscow',
    });
  });

  it.each(['hour', 'timeZone'] as const)('drops cached digests after a %s change and keeps news discussions', async (
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

    if (setting === 'hour') setAgentDigestHour(9);
    else timeZone = 'Europe/Moscow';
    result = undefined;
    TeactDOM.render(<Harness />, root);
    expect(await waitFor(() => result?.items !== undefined, 10, 300)).toBe(true);
    await pause(50);
    expect(result!.items).toMatchObject([
      { kind: 'news', eventId: 2, discussion: { threadId: 'news-thread' } }, { kind: 'news', eventId: 3 },
    ]);
    expect(jest.mocked(callApi)).toHaveBeenCalledTimes(1);

    if (setting === 'hour') setAgentDigestHour(21);
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
    expect(getAgentDigestHour()).toBe(21);
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
    const unsubscribe = subscribeToAgentDigestHour(onChange);
    setAgentDigestHour(9);
    expect(getAgentDigestHour()).toBe(9);
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
    setAgentDigestHour(21);
    expect(await waitFor(() => jest.mocked(callApi).mock.calls.length === 3 && !result?.isLoading, 10, 300)).toBe(true);
    expect(getAgentDigestHour()).toBe(21);
    expect(onChange.mock.calls).toEqual([[9], [21]]);
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
    setAgentDigestHour(21);
    await flushFeed();
    root.remove();
    localStorage.clear();
    jest.restoreAllMocks();
    jest.useRealTimers();
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

    setAgentDigestHour(9);
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

      if (setting === 'hour') setAgentDigestHour(9);
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

  function Harness({ isDisabled = false, isInactive = false, langCode = 'en' }: {
    isDisabled?: boolean;
    isInactive?: boolean;
    langCode?: string;
  }) {
    const isActive = !isInactive;
    result = useAgentNewsFeed({ isEnabled: !isDisabled, isActive, langCode, isFeedVisible: isActive });
    return undefined;
  }

  function getRequestedCursors() {
    return apiMock.mock.calls.map(([, params]) => (
      params && typeof params === 'object' && 'cursor' in params ? params.cursor : undefined
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
