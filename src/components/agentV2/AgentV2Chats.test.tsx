import '../../global/actions/ui/initial';

import React, { memo, useEffect } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import { addActionHandler, getActions } from '../../global';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';

import Deferred from '../../util/Deferred';
import { pause, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';

import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';

import AgentHints from '../agent/AgentHints';
import AgentInputBar from '../agent/AgentInputBar';
import AgentNewsFeed from './AgentNewsFeed';
import AgentNewsRow from './AgentNewsRow';
import AgentThreadList from './AgentThreadList';
import AgentThreadListItem from './AgentThreadListItem';
import AgentV2Chats from './AgentV2Chats';
import AgentV2Classic from './AgentV2Classic';
import DeleteAgentChatModal from './DeleteAgentChatModal';

const mockScheduleRefresh = jest.fn();
const mockSetThreadPinned = jest.fn();
const mockRemoveThread = jest.fn();
const mockShowError = jest.fn();
let mockThreadListItems: AgentThreadListItemV2[] = [];

jest.mock('../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../enclave', () => ({ enclave: { reset: jest.fn() } }));
jest.mock('../../util/agent/clearLegacyAgentStorage', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../util/notificationSound', () => ({ initializeSounds: jest.fn() }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../../hooks/useHistoryBack', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../agent/hooks/useAgentLayoutSwitch', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('./useAgentV2ThreadList', () => ({
  __esModule: true,
  default: () => ({
    items: mockThreadListItems,
    activityLangKeys: {},
    hasMore: false,
    releaseLoadedChat: jest.fn(),
    syncLoadedChat: jest.fn(),
    setThreadPinned: mockSetThreadPinned,
    removeThread: mockRemoveThread,
    scheduleRefresh: mockScheduleRefresh,
  }),
}));
jest.mock('./useAgentNewsFeed', () => ({
  __esModule: true,
  default: () => ({ startReading: jest.fn(), refresh: jest.fn(), removeDiscussion: jest.fn() }),
}));
jest.mock('./useAgentSuggestions', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('./useAgentThreadListMotion', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../agent/AgentInputBar', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('../agent/AgentHints', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentV2Classic', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentNewsFeed', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentNewsRow', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentThreadListItem', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentV2Conversation', () => ({ AgentV2ConsentPage: jest.fn(() => undefined) }));
jest.mock('./RenameAgentChatModal', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./DeleteAgentChatModal', () => ({ __esModule: true, default: jest.fn(() => undefined) }));

const InputBarMock = jest.mocked(AgentInputBar);
const ChatMock = jest.mocked(AgentV2Classic);
const FeedMock = jest.mocked(AgentNewsFeed);
const callApiMock = jest.mocked(callApi);

addActionHandler('resetApiSettings', () => {});
addActionHandler('showError', (_global, _actions, payload) => {
  mockShowError(payload);
});

describe('Agent chat state across mounts', () => {
  let root: HTMLDivElement;
  const originalCss = window.CSS;

  beforeAll(() => {
    Object.defineProperty(window, 'CSS', { value: { escape: (value: string) => value }, configurable: true });
  });

  afterAll(() => {
    Object.defineProperty(window, 'CSS', { value: originalCss, configurable: true });
  });

  beforeEach(() => {
    mockThreadListItems = [];
    getActions().afterSignOut({ shouldReset: true });
    callApiMock.mockResolvedValue(true);
    ChatMock.mockImplementation(() => undefined);
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await pause(20);
    root.remove();
    getActions().afterSignOut({ shouldReset: true });
    jest.clearAllMocks();
  });

  async function mountChats() {
    TeactDOM.render(<AgentV2Chats isActive />, root);
    await pause(50);
  }

  async function unmount() {
    TeactDOM.render(undefined, root);
    await pause(20);
  }

  async function remountChats() {
    await unmount();
    await mountChats();
  }

  it('shows starter suggestions with News in an empty list without focusing the input', async () => {
    const onOpenNews = jest.fn();
    const props = {
      isActive: true, hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews, onStartChat: jest.fn(), onLoadMore: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    await pause(30);
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(false);
    TeactDOM.render(<AgentThreadList {...props} items={[]} />, root);
    await pause(30);
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(true);
    expect(root.textContent).not.toContain('Ask a question to start a new chat.');
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(onOpenNews).toHaveBeenCalledTimes(1);
  });

  it.each(['stay', 'switch', 'unmount'] as const)('deletes an opening chat after it closes: %s', async (mode) => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('First question');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    await pause(50);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    const pendingThreadId = new Deferred<string | undefined>();
    const cancelPendingRequests = jest.fn(() => pendingThreadId.promise);
    chatProps.onDelete!(undefined, cancelPendingRequests);
    await pause(20);
    const confirmation = jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0];
    expect(confirmation.isOpen).toBe(true);
    confirmation.onConfirm();
    confirmation.onClose();
    expect(cancelPendingRequests).toHaveBeenCalledTimes(1);
    if (mode === 'unmount') {
      await unmount();
      ChatMock.mockClear();
      await mountChats();
      expect(ChatMock).not.toHaveBeenCalled();
      await unmount();
    } else {
      await pause(50);
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
    }
    expect(jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].isOpen).toBe(false);
    callApiMock.mockResolvedValue({ ok: true });
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    if (mode === 'switch') {
      InputBarMock.mock.calls.at(-1)![0].onInput('Second question');
      await pause(20);
      InputBarMock.mock.calls.at(-1)![0].onSend();
      await pause(50);
    }
    chatProps.onThreadResolved!(chatProps.chatKey!, 'new-thread');
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    pendingThreadId.resolve('new-thread');
    await pause(50);
    expect(callApiMock).toHaveBeenCalledWith('deleteAgentV2Thread', 'new-thread');
    if (mode === 'unmount') {
      expect(ChatMock).not.toHaveBeenCalled();
      return;
    }
    const currentChat = ChatMock.mock.calls.at(-1)![0];
    expect(currentChat.isActive).toBe(mode === 'switch');
    if (mode === 'switch') {
      expect(currentChat.chatKey).not.toBe(chatProps.chatKey);
      expect(currentChat.target).toEqual({ kind: 'new' });
      expect(currentChat.initialMessage).toBe('Second question');
    }
  });

  it('closes an opening chat whose creation failed or never started without a delete request or error', async () => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('Question');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    await pause(50);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onDelete!(undefined, () => Promise.resolve(undefined));
    await pause(20);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm();
    await pause(50);

    expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
    expect(jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].isOpen).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    expect(mockShowError).not.toHaveBeenCalled();
    await remountChats();
    expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
  });

  it.each(['success', 'failure', 'rejection'] as const)(
    'closes and cancels a resolved chat before its delete request settles: %s', async (outcome) => {
      const timestamp = '2026-10-21T12:00:00.000Z';
      const thread = {
        id: 'delete-thread', revision: 1, messageCount: 2,
        createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
      };
      mockThreadListItems = [{ thread }];
      await mountChats();
      jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
      await pause(50);
      const chatProps = ChatMock.mock.calls.at(-1)![0];
      const cancelPendingRequests = jest.fn(() => Promise.resolve(thread.id));
      chatProps.onDelete!(thread, cancelPendingRequests);
      await pause(20);
      const deletion = new Deferred<{ ok: true } | undefined>();
      callApiMock.mockImplementationOnce(() => {
        expect(cancelPendingRequests).toHaveBeenCalledTimes(1);
        return deletion.promise as never;
      });

      jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(thread);
      expect(cancelPendingRequests).toHaveBeenCalledTimes(1);
      await pause(50);
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
      expect(mockRemoveThread).not.toHaveBeenCalled();
      expect(mockShowError).not.toHaveBeenCalled();

      if (outcome === 'rejection') deletion.reject(new Error('Offline'));
      else deletion.resolve(outcome === 'success' ? { ok: true } : undefined);
      await pause(50);

      expect(callApiMock.mock.calls.filter(([method]) => method === 'deleteAgentV2Thread')).toHaveLength(1);
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
      if (outcome === 'success') {
        expect(mockRemoveThread).toHaveBeenCalledWith(thread.id);
        expect(mockShowError).not.toHaveBeenCalled();
      } else {
        expect(mockRemoveThread).not.toHaveBeenCalled();
        expect(mockShowError).toHaveBeenCalledWith({ error: 'An error occurred' });
      }
    },
  );

  it.each([false, true])('clears the open chat and its session only on full sign-out (%s)', async (shouldReset) => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('First question');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    await pause(50);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    const session = { draft: 'Private draft', scrollAnchor: { indexFromEnd: 1, offset: 25 } };
    chatProps.session!.save(session);

    // Both layouts know the consent while they hand the screen over
    jest.mocked(useAgentLayoutSwitch).mock.calls[0][0]();
    getActions().afterSignOut(shouldReset ? { shouldReset: true } : undefined);
    await unmount();
    chatProps.session!.save(session);
    ChatMock.mockClear();
    callApiMock.mockClear();
    await mountChats();

    if (shouldReset) {
      expect(ChatMock).not.toHaveBeenCalled();
      expect(callApiMock).toHaveBeenCalledWith('getAgentV2Consent');
      InputBarMock.mock.calls.at(-1)![0].onInput('Next question');
      await pause(20);
      InputBarMock.mock.calls.at(-1)![0].onSend();
      await pause(50);
      expect(ChatMock.mock.calls.at(-1)![0].session!.initial).toBeUndefined();
    } else {
      expect(ChatMock.mock.calls.at(-1)![0].session!.initial).toEqual(session);
    }
  });

  it.each([false, true])('clears the list draft only on full sign-out (%s)', async (shouldReset) => {
    const props = {
      isActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(), onLoadMore: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onInput('Private list draft');
    await pause(100);
    await unmount();
    getActions().afterSignOut(shouldReset ? { shouldReset: true } : undefined);
    TeactDOM.render(<AgentThreadList {...props} />, root);
    await pause(20);

    expect(InputBarMock.mock.calls.at(-1)![0].inputValue).toBe(shouldReset ? '' : 'Private list draft');
  });

  it('clears the open feed on full sign-out', async () => {
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    await pause(50);
    expect(FeedMock).toHaveBeenCalled();
    getActions().afterSignOut({ shouldReset: true });
    FeedMock.mockClear();
    await remountChats();
    expect(FeedMock).not.toHaveBeenCalled();
  });

  it('gives the focus back to the News row and to the card of the news whose discussion the user leaves', async () => {
    jest.mocked(AgentNewsRow).mockImplementation(({ onClick }) => (
      <div role="button" tabIndex={0} data-agent-news-row onClick={onClick} />
    ));
    FeedMock.mockImplementation(() => (
      <div data-agent-news-event-id="7"><button type="button" data-agent-news-discuss /></div>
    ));
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    await pause(50);

    FeedMock.mock.calls.at(-1)![0].onOpenDiscussion({
      eventId: 7, deliveredAt: '2026-10-21T09:00:00.000Z', headline: 'News', body: 'Body', sources: [],
    });
    await pause(50);
    (document.activeElement as HTMLElement | null)?.blur();
    ChatMock.mock.calls.at(-1)![0].onBack!();
    await pause(100);
    expect(document.activeElement?.hasAttribute('data-agent-news-discuss')).toBe(true);

    (document.activeElement as HTMLElement).blur();
    FeedMock.mock.calls.at(-1)![0].onBack!();
    await pause(100);
    expect(document.activeElement?.hasAttribute('data-agent-news-row')).toBe(true);
  });

  it('refreshes the list after a failed pin is rolled back', async () => {
    const timestamp = '2026-10-21T12:00:00.000Z';
    const thread = {
      id: 'pin-thread', revision: 1, messageCount: 2,
      createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
    };
    mockThreadListItems = [{ thread }];
    await mountChats();
    const pendingUpdate = new Deferred<undefined>();
    callApiMock.mockReturnValueOnce(pendingUpdate.promise);
    jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onTogglePin(thread);
    expect(mockSetThreadPinned).toHaveBeenCalledWith(thread.id, true);
    expect(mockScheduleRefresh).not.toHaveBeenCalled();

    pendingUpdate.resolve(undefined);
    expect(await waitFor(() => mockScheduleRefresh.mock.calls.length === 1, 10, 100)).toBe(true);
    expect(mockSetThreadPinned).toHaveBeenLastCalledWith(thread.id, false);
    expect(mockSetThreadPinned.mock.invocationCallOrder.at(-1)!)
      .toBeLessThan(mockScheduleRefresh.mock.invocationCallOrder[0]);
  });

  it('opens a chat the list marks as unread where its unseen messages start, there again after a remount', async () => {
    const timestamp = '2026-10-21T12:00:00.000Z';
    const thread = {
      id: 'unread-thread', revision: 1, messageCount: 6,
      createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp,
    };
    localStorage.setItem('mytonwallet-agent-thread-read-state', JSON.stringify({
      records: { [thread.id]: { seenMessageCount: 4, isBaselineNeeded: false, isMarkedUnread: false } },
      order: [thread.id],
    }));
    mockThreadListItems = [{ thread }];
    await mountChats();
    jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
    await pause(50);

    const chatProps = ChatMock.mock.calls.at(-1)![0];
    expect(chatProps.unreadStart).toBe(4);
    chatProps.onUnreadStartResolved!(chatProps.chatKey!, 3);
    await pause(50);
    expect(ChatMock.mock.calls.at(-1)![0].unreadStart).toBe(3);

    await remountChats();
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'thread', threadId: thread.id }, unreadStart: 3,
    });
  });

  it('keeps the chat memoized when only its parent state changes', async () => {
    const renderChat = jest.fn(() => undefined);
    ChatMock.mockImplementation(memo(renderChat));
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('Question');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => renderChat.mock.calls.length > 0, 10, 100)).toBe(true);
    await pause(50);
    const renderCount = renderChat.mock.calls.length;
    const parentRenderCount = ChatMock.mock.calls.length;

    ChatMock.mock.calls.at(-1)![0].onAnswerChange!('new-thread', '$agent_activity_writing');
    expect(await waitFor(() => ChatMock.mock.calls.length > parentRenderCount, 10, 100)).toBe(true);
    expect(renderChat).toHaveBeenCalledTimes(renderCount);
  });

  it('keeps a thread resolved by another chat out of the chat on screen', async () => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('Question');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    await pause(50);
    const { chatKey, onThreadResolved } = ChatMock.mock.calls.at(-1)![0];
    onThreadResolved!(chatKey! - 1, 'other-thread');
    await pause(50);
    await remountChats();

    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'new' });
  });

  it('keeps the opening question across remounts until the chat accepts it once', async () => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('What is TON?');
    await pause(20);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    await pause(50);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onThreadResolved!(chatProps.chatKey!, 'new-thread');
    await pause(50);
    await remountChats();

    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'thread', threadId: 'new-thread' }, initialMessage: 'What is TON?',
    });

    const sendMessage = jest.fn();
    ChatMock.mockImplementation(function Chat({ initialMessage, onInitialMessageSent, chatKey }) {
      useEffect(() => {
        if (!initialMessage) return;
        sendMessage(initialMessage);
        onInitialMessageSent?.(chatKey!);
      }, [chatKey, initialMessage, onInitialMessageSent]);
      return undefined;
    });
    await remountChats();
    expect(await waitFor(() => sendMessage.mock.calls.length === 1, 10, 100)).toBe(true);
    expect(sendMessage).toHaveBeenCalledWith('What is TON?');
    expect(sendMessage).toHaveBeenCalledTimes(1);
    await remountChats();
    await pause(100);
    expect(ChatMock.mock.calls.at(-1)![0].initialMessage).toBeUndefined();
    expect(sendMessage).toHaveBeenCalledTimes(1);
  });
});
