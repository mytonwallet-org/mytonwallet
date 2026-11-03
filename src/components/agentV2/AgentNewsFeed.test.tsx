import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentNewsFeed from './AgentNewsFeed';

jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  withGlobal: () => (Component: unknown) => Component,
}));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../agent/AgentConversationShell', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));

const ITEMS: AgentNewsFeedItemV2[] = [2, 3].map((eventId) => ({
  eventId,
  deliveredAt: `2026-10-2${eventId}T09:00:00.000Z`,
  headline: `News ${eventId}`,
  body: 'Body',
  sources: [],
}));

const shellMock = jest.mocked(AgentConversationShell);

describe('AgentNewsFeed', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    shellMock.mockClear();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows the news as the messages of a chat without a field, a date line for each day', () => {
    const onLoadMore = jest.fn();
    renderFeed({
      items: ITEMS, unreadEventId: 3, initialEventId: 2, hasMore: true, onLoadMore,
    });

    const props = getShellProps();
    expect(props.composer).toBeUndefined();
    expect(props.conversation).toMatchObject({
      messages: [
        { id: 2, text: 'News 2', isOutgoing: false, timestamp: Date.parse(ITEMS[0].deliveredAt) },
        { id: 3, text: 'News 3', isOutgoing: false, timestamp: Date.parse(ITEMS[1].deliveredAt) },
      ],
      isInitialLoadComplete: true,
      hasHistoryPlaceholder: true,
      isNewsPlaceholder: true,
      hasDailyDateLines: true,
      unreadMessageId: 3,
      initialMessageId: 2,
    });
    expect(props.header).toEqual({ title: 'News', hasBackButton: true });
    expect(props.history).toEqual({
      hasOlderMessages: true, isLoading: false, mode: 'continuous', loadOlderMessages: onLoadMore,
    });
    expect(props.conversation.loadFailure).toBeUndefined();
  });

  it('waits for the first page before asking for older news', () => {
    renderFeed({ items: ITEMS, hasMore: true, isLoading: true });

    expect(getShellProps().history?.hasOlderMessages).toBe(false);
  });

  it('keeps the placeholder until the first page and says the news are unavailable without any', () => {
    renderFeed({ isLoading: true });
    expect(getShellProps().conversation.isInitialLoadComplete).toBe(false);
    expect(getShellProps().conversation.loadFailure).toBeUndefined();

    renderFeed({ items: [] });
    expect(getShellProps().conversation.loadFailure).toMatchObject({ text: '$agent_news_unavailable' });

    renderFeed({ items: [], isLoading: true });
    expect(getShellProps().conversation.loadFailure).toMatchObject({ isRetrying: true });
  });

  it('hands a failed reading of the news to the list, which tells it under the news already shown', () => {
    const onRetry = jest.fn();
    renderFeed({ items: ITEMS, errorCode: 'network_error', onRetry });

    const { loadFailure } = getShellProps().conversation;
    expect(loadFailure).toMatchObject({ text: '$agent_connection_lost', isRetrying: false });
    loadFailure!.onRetry();
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  function renderFeed({
    items,
    unreadEventId,
    initialEventId,
    hasMore = false,
    isLoading = false,
    errorCode,
    onRetry = jest.fn(),
    onLoadMore = jest.fn(),
  }: Partial<{
    items: AgentNewsFeedItemV2[];
    unreadEventId: number;
    initialEventId: number;
    hasMore: boolean;
    isLoading: boolean;
    errorCode: 'network_error';
    onRetry: NoneToVoidFunction;
    onLoadMore: NoneToVoidFunction;
  }>) {
    TeactDOM.render(
      <AgentNewsFeed
        isActive
        items={items}
        unreadEventId={unreadEventId}
        initialEventId={initialEventId}
        hasMore={hasMore}
        isLoading={isLoading}
        isLoadingMore={false}
        errorCode={errorCode}
        onBack={jest.fn()}
        onRetry={onRetry}
        onLoadMore={onLoadMore}
        onOpenDiscussion={jest.fn()}
      />,
      root,
    );
  }
});

function getShellProps() {
  return shellMock.mock.calls.at(-1)![0];
}
