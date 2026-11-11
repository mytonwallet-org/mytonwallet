import '../../global/actions/ui/initial';

import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import { addActionHandler, getActions } from '../../global';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { AgentHint } from '../../global/types';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';

import { getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import Deferred from '../../util/Deferred';
import { rafPromise, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import { getSnapEffectLayer } from '../agent/helpers/snapEffect';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';
import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';
import useAgentV2Dictation from '../agent/hooks/useAgentV2Dictation';

import AgentHints from '../agent/AgentHints';
import AgentInputBar from '../agent/AgentInputBar';
import AgentNewsFeed from './AgentNewsFeed';
import AgentNewsRow from './AgentNewsRow';
import AgentThreadList from './AgentThreadList';
import AgentThreadListItem from './AgentThreadListItem';
import AgentV2Chats from './AgentV2Chats';
import AgentV2Classic from './AgentV2Classic';
import { AgentV2ConsentSheet } from './AgentV2Conversation';
import DeleteAgentChatModal from './DeleteAgentChatModal';

const TIMESTAMP = '2026-10-21T12:00:00.000Z';
const SWAP_HINT: AgentHint = {
  id: 'learn.swap', langCode: 'en', title: 'Swaps', subtitle: '', prompt: 'How do swaps work?',
};

const mockScheduleRefresh = jest.fn();
const mockSetThreadPinned = jest.fn();
const mockRemoveThread = jest.fn();
const mockShowError = jest.fn();
let mockThreadListItems: AgentThreadListItemV2[] = [];
let mockIsCacheShown = false;
let mockFeedItems: AgentNewsFeedEntry[] = [];
let mockFeedLocale = 'en';

function runAtOnce(action: NoneToVoidFunction) {
  action();
}

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
jest.mock('../agent/hooks/useAgentV2Dictation', () => {
  const actual = jest.requireActual('../agent/hooks/useAgentV2Dictation');
  return { ...actual, __esModule: true, default: jest.fn(actual.default) };
});
jest.mock('./useAgentV2ThreadList', () => ({
  __esModule: true,
  default: () => ({
    items: mockThreadListItems,
    isCacheShown: mockIsCacheShown,
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
  default: () => ({
    items: mockFeedItems, locale: mockFeedLocale,
    startReading: jest.fn(), refresh: jest.fn(), removeDiscussion: jest.fn(), markDiscussion: jest.fn(),
    markDigestDiscussion: jest.fn(),
  }),
}));
jest.mock('./useAgentSuggestions', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('./useAgentThreadListMotion', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../agent/AgentInputBar', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('../agent/AgentHints', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentV2Classic', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentNewsFeed', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentNewsRow', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentThreadListItem', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./AgentV2Conversation', () => ({ AgentV2ConsentSheet: jest.fn(() => undefined) }));
jest.mock('./RenameAgentChatModal', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./DeleteAgentChatModal', () => ({ __esModule: true, default: jest.fn(() => undefined) }));

const InputBarMock = jest.mocked(AgentInputBar);
const ChatMock = jest.mocked(AgentV2Classic);
const ConsentSheetMock = jest.mocked(AgentV2ConsentSheet);
const FeedMock = jest.mocked(AgentNewsFeed);
const callApiMock = jest.mocked(callApi);
const INPUT_BAR_IMPLEMENTATION = InputBarMock.getMockImplementation()!;
const THREAD_LIST_ITEM_IMPLEMENTATION = jest.mocked(AgentThreadListItem).getMockImplementation()!;
const NEWS_ROW_IMPLEMENTATION = jest.mocked(AgentNewsRow).getMockImplementation()!;

addActionHandler('resetApiSettings', () => {});
addActionHandler('showError', (_global, _actions, payload) => {
  mockShowError(payload);
});

describe('Agent chat state across mounts', () => {
  let root: HTMLDivElement;
  let getBoundingClientRectMock: jest.SpyInstance | undefined;
  const originalCss = window.CSS;

  beforeAll(() => {
    Object.defineProperty(window, 'CSS', { value: { escape: (value: string) => value }, configurable: true });
  });

  afterAll(() => {
    Object.defineProperty(window, 'CSS', { value: originalCss, configurable: true });
  });

  beforeEach(() => {
    mockThreadListItems = [];
    mockIsCacheShown = false;
    mockFeedItems = [];
    mockFeedLocale = 'en';
    getActions().afterSignOut({ shouldReset: true });
    callApiMock.mockResolvedValue(true);
    ChatMock.mockImplementation(() => undefined);
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    await unmount();
    root.remove();
    getActions().afterSignOut({ shouldReset: true });
    getBoundingClientRectMock?.mockRestore();
    getBoundingClientRectMock = undefined;
    InputBarMock.mockImplementation(INPUT_BAR_IMPLEMENTATION);
    jest.mocked(AgentThreadListItem).mockImplementation(THREAD_LIST_ITEM_IMPLEMENTATION);
    jest.mocked(AgentNewsRow).mockImplementation(NEWS_ROW_IMPLEMENTATION);
    FeedMock.mockImplementation(() => undefined);
    jest.mocked(useAgentLayoutSwitch).mockReset();
    jest.clearAllMocks();
  });

  async function mountChats() {
    const inputRenderCount = InputBarMock.mock.calls.length;
    const chatRenderCount = ChatMock.mock.calls.length;
    const feedRenderCount = FeedMock.mock.calls.length;
    TeactDOM.render(<AgentV2Chats isActive />, root);
    expect(await waitFor(() => (
      InputBarMock.mock.calls.length > inputRenderCount
      || ChatMock.mock.calls.length > chatRenderCount
      || FeedMock.mock.calls.length > feedRenderCount
    ), 10, 300)).toBe(true);
  }

  async function unmount() {
    TeactDOM.render(undefined, root);
    await rafPromise();
  }

  async function remountChats() {
    await unmount();
    await mountChats();
  }

  it('shows starter suggestions with News in an empty list without focusing the input', async () => {
    const onOpenNews = jest.fn();
    const props = {
      isActive: true, hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews, onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => jest.mocked(AgentHints).mock.calls.at(-1)?.[0].isOpen === false, 10, 300)).toBe(true);
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(false);
    TeactDOM.render(<AgentThreadList {...props} items={[]} />, root);
    expect(await waitFor(() => jest.mocked(AgentHints).mock.calls.at(-1)?.[0].isOpen === true, 10, 300)).toBe(true);
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(true);
    expect(root.textContent).not.toContain('Ask a question to start a new chat.');
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(onOpenNews).toHaveBeenCalledTimes(1);
  });

  it('shows the failure with Retry under News in place of the suggestions when the chats failed to load', async () => {
    const onRetry = jest.fn();
    const props = {
      isActive: true, hasMore: false, activityLangKeys: {}, newsUnreadCount: 0, hasLoadFailed: true,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry,
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => Boolean(root.querySelector('[role="alert"]')), 10, 300)).toBe(true);

    expect(jest.mocked(AgentNewsRow)).toHaveBeenCalled();
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(false);
    const failure = root.querySelector('[role="alert"]')!;
    expect(failure.textContent).toContain('$agent_chats_unavailable');
    failure.querySelector('button')!.click();
    expect(onRetry).toHaveBeenCalledTimes(1);

    // An empty list that failed to refresh says so too, rather than offering suggestions
    TeactDOM.render(<AgentThreadList {...props} items={[]} />, root);
    expect(await waitFor(() => jest.mocked(AgentHints).mock.calls.at(-1)?.[0].isOpen === false, 10, 300)).toBe(true);
    expect(jest.mocked(AgentHints).mock.calls.at(-1)![0].isOpen).toBe(false);
    expect(root.querySelector('[role="alert"]')).not.toBeNull();

    // Chats that load replace the failure
    TeactDOM.render(<AgentThreadList {...props} hasLoadFailed={false} items={[buildListItem('loaded')]} />, root);
    expect(await waitFor(() => (
      jest.mocked(AgentThreadListItem).mock.calls.at(-1)?.[0].item.thread.id === 'loaded'
    ), 10, 300)).toBe(true);
    expect(root.querySelector('[role="alert"]')).toBeNull();
    expect(jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].item.thread.id).toBe('loaded');
  });

  it.each(['first', 'next'])('ends cached rows with Retry when the %s page fails', async (page) => {
    const onRetry = jest.fn();
    const props = {
      isActive: true, items: [buildListItem('shown')], hasMore: true, activityLangKeys: {},
      newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry,
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(
      <AgentThreadList {...props} hasLoadFailed={page === 'first'} hasPageLoadFailed={page === 'next'} />, root,
    );
    expect(await waitFor(() => Boolean(root.querySelector('[aria-label="Chats"] p')), 10, 300)).toBe(true);

    expect(root.querySelector('[role="alert"]')).toBeNull();
    const line = root.querySelector('[aria-label="Chats"] p')!;
    expect(line.textContent).toContain('$agent_chats_unavailable');
    line.querySelector('button')!.click();
    expect(onRetry).toHaveBeenCalledTimes(1);

    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => !root.querySelector('[aria-label="Chats"] p'), 10, 300)).toBe(true);
    expect(root.querySelector('[aria-label="Chats"] p')).toBeNull();
  });

  it.each(['stay', 'switch', 'unmount'] as const)('deletes an opening chat after it closes: %s', async (mode) => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('First question');
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'First question', 10, 300))
      .toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    const pendingThreadId = new Deferred<string | undefined>();
    const cancelPendingRequests = jest.fn(() => pendingThreadId.promise);
    chatProps.onDelete!(undefined, cancelPendingRequests);
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
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
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
    }
    expect(jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].isOpen).toBe(false);
    callApiMock.mockResolvedValue({ ok: true });
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    if (mode === 'switch') {
      InputBarMock.mock.calls.at(-1)![0].onInput('Second question');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Second question', 10, 300))
        .toBe(true);
      InputBarMock.mock.calls.at(-1)![0].onSend();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'Second question', 10, 300))
        .toBe(true);
    }
    chatProps.onThreadResolved!(chatProps.chatKey!, 'new-thread');
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    pendingThreadId.resolve('new-thread');
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'deleteAgentV2Thread'), 10, 300))
      .toBe(true);
    expect(callApiMock).toHaveBeenCalledWith('deleteAgentV2Thread', 'new-thread');
    if (mode === 'unmount') {
      await rafPromise();
      expect(ChatMock).not.toHaveBeenCalled();
      return;
    }
    expect(await waitFor(() => mockRemoveThread.mock.calls.length > 0, 10, 300)).toBe(true);
    await rafPromise();
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
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Question', 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onDelete!(undefined, () => Promise.resolve(undefined));
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);

    expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
    expect(jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].isOpen).toBe(false);
    expect(callApiMock).not.toHaveBeenCalledWith('deleteAgentV2Thread', expect.anything());
    expect(mockShowError).not.toHaveBeenCalled();
    await remountChats();
    expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
  });

  it.each(['success', 'failure', 'rejection'] as const)(
    'closes and cancels a resolved chat before its delete request settles: %s', async (outcome) => {
      const thread = {
        id: 'delete-thread', revision: 1, messageCount: 2,
        createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
      };
      mockThreadListItems = [{ thread }];
      await mountChats();
      jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
      const chatProps = ChatMock.mock.calls.at(-1)![0];
      const cancelPendingRequests = jest.fn(() => Promise.resolve(thread.id));
      chatProps.onDelete!(thread, cancelPendingRequests);
      expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
        .toBe(true);
      const deletion = new Deferred<{ ok: true } | undefined>();
      callApiMock.mockImplementationOnce(() => {
        expect(cancelPendingRequests).toHaveBeenCalledTimes(1);
        return deletion.promise as never;
      });

      jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(thread);
      expect(cancelPendingRequests).toHaveBeenCalledTimes(1);
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
      expect(mockRemoveThread).not.toHaveBeenCalled();
      expect(mockShowError).not.toHaveBeenCalled();

      if (outcome === 'rejection') deletion.reject(new Error('Offline'));
      else deletion.resolve(outcome === 'success' ? { ok: true } : undefined);
      await deletion.promise.catch(() => undefined);

      expect(callApiMock.mock.calls.filter(([method]) => method === 'deleteAgentV2Thread')).toHaveLength(1);
      if (outcome === 'success') {
        // The chat leaves the list once its dust has mostly drifted off
        expect(await waitFor(() => mockRemoveThread.mock.calls.length > 0, 10, 1000)).toBe(true);
        expect(mockRemoveThread).toHaveBeenCalledWith(thread.id);
        expect(mockShowError).not.toHaveBeenCalled();
      } else {
        expect(mockRemoveThread).not.toHaveBeenCalled();
        expect(mockShowError).toHaveBeenCalledWith({ error: 'An error occurred' });
      }
      await rafPromise();
      expect(ChatMock.mock.calls.at(-1)![0].isActive).toBe(false);
    },
  );

  it.each([false, true])('clears the open chat and its session only on full sign-out (%s)', async (shouldReset) => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('First question');
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'First question', 10, 300))
      .toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    expect(await waitFor(() => getAgentV2LocalState().openChatOnMount?.key === chatProps.chatKey, 10, 300)).toBe(true);
    const session = { draft: 'Private draft', scrollAnchor: { indexFromEnd: 1, offset: 25 } };
    chatProps.session!.save(session);

    // Both layouts know the consent while they hand the screen over
    jest.mocked(useAgentLayoutSwitch).mock.calls[0][0]();
    getActions().afterSignOut(shouldReset ? { shouldReset: true } : undefined);
    await unmount();
    chatProps.session!.save(session);
    ChatMock.mockClear();
    callApiMock.mockClear();
    // Without a reset the open chat comes back and replaces the input bar
    if (shouldReset) InputBarMock.mockClear();
    await mountChats();

    if (shouldReset) {
      expect(ChatMock).not.toHaveBeenCalled();
      expect(callApiMock).toHaveBeenCalledWith('getAgentV2Consent');
      InputBarMock.mock.calls.at(-1)![0].onInput('Next question');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Next question', 10, 300))
        .toBe(true);
      InputBarMock.mock.calls.at(-1)![0].onSend();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'Next question', 10, 300))
        .toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].session!.initial).toBeUndefined();
    } else {
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].session!.initial).toEqual(session);
    }
  });

  it.each([false, true])('clears the list draft only on full sign-out (%s)', async (shouldReset) => {
    const props = {
      isActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => InputBarMock.mock.calls.length > 0, 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onInput('Private list draft');
    expect(await waitFor(() => getAgentV2LocalState().draftOnMount === 'Private list draft', 10, 300)).toBe(true);
    await unmount();
    getActions().afterSignOut(shouldReset ? { shouldReset: true } : undefined);
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => (
      InputBarMock.mock.calls.at(-1)?.[0].inputValue === (shouldReset ? '' : 'Private list draft')
    ), 10, 300)).toBe(true);

    expect(InputBarMock.mock.calls.at(-1)![0].inputValue).toBe(shouldReset ? '' : 'Private list draft');
  });

  it('keeps the list draft typed as the layouts switch while the save of an earlier draft is still due', async () => {
    const props = {
      isActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    let switchLayout: NoneToVoidFunction | undefined;
    // The app mounts the other layout's list in the same pass that runs the effects of the last render
    function LayoutHost() {
      const [isPortrait, setIsPortrait] = useState(false);
      switchLayout = () => setIsPortrait(true);
      return (
        <div>
          {!isPortrait && <AgentThreadList {...props} />}
          {isPortrait && <AgentThreadList {...props} />}
        </div>
      );
    }
    let hasTypedAgain = false;
    InputBarMock.mockImplementation(({ inputValue, onInput }) => {
      if (inputValue !== 'First' || hasTypedAgain) return <div />;
      hasTypedAgain = true;
      // Right after the render of the first input, before its effects run
      void Promise.resolve().then(() => {
        onInput('First + latest');
        jest.mocked(useAgentLayoutSwitch).mock.calls.at(-1)![0]();
        switchLayout!();
      });
      return <div />;
    });
    TeactDOM.render(<LayoutHost />, root);
    expect(await waitFor(() => InputBarMock.mock.calls.length > 0, 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onInput('First');

    expect(await waitFor(() => hasTypedAgain, 10, 300)).toBe(true);
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'First + latest', 10, 300))
      .toBe(true);
    expect(InputBarMock.mock.calls.at(-1)![0].inputValue).toBe('First + latest');
  });

  it('keeps the whole transcript being written into the list draft as the layouts switch', async () => {
    jest.mocked(useAgentLayoutSwitch).mockImplementation(
      jest.requireActual('../agent/hooks/useAgentLayoutSwitch').default,
    );
    const props = {
      isActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      onSelect: jest.fn(), onOpenNews: jest.fn(), onStartChat: jest.fn(),
      onRequestConsent: runAtOnce, onLoadMore: jest.fn(), onRetry: jest.fn(),
      onRename: jest.fn(), onTogglePin: jest.fn(), onDelete: jest.fn(),
    };
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => InputBarMock.mock.calls.length > 0, 10, 300)).toBe(true);
    await rafPromise();

    jest.mocked(useAgentV2Dictation).mock.lastCall![0].onTranscript('one two three');
    switchLayout();
    expect(getAgentV2LocalState().draftOnMount).toBe('one two three');

    await unmount();
    TeactDOM.render(<AgentThreadList {...props} />, root);
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'one two three', 10, 300))
      .toBe(true);
  });

  it.each(['news', 'digest', 'thread'] as const)('keeps a %s chat on its thread across layouts', async (kind) => {
    const thread = {
      id: 'switched-thread', revision: 1, messageCount: 2,
      createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    };
    if (kind !== 'thread') {
      // Before consent a news discussion opens from the feed and resolves its thread there
      callApiMock.mockImplementation((...args) => Promise.resolve(args[0] !== 'getAgentV2Consent') as never);
      await mountChats();
      jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
      expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
      if (kind === 'news') {
        FeedMock.mock.calls.at(-1)![0].onOpenDiscussion({
          eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [],
        });
      } else {
        FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
      }
    } else {
      mockThreadListItems = [{ thread }];
      await mountChats();
      jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
    }
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onThreadResolved!(chatProps.chatKey!, thread.id);
    expect(await waitFor(() => getAgentV2LocalState().openChatOnMount?.threadId === thread.id, 10, 300)).toBe(true);

    jest.mocked(useAgentLayoutSwitch).mock.calls.at(-1)![0]();
    await unmount();
    ChatMock.mockClear();
    await mountChats();

    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const remountedProps = ChatMock.mock.calls.at(-1)![0];
    expect(remountedProps.chatKey).toBe(chatProps.chatKey);
    // A news discussion loads before consent, as it did before the switch
    expect(remountedProps.target).toEqual(
      kind !== 'thread'
        ? { kind: 'thread', threadId: thread.id, isNews: true } : { kind: 'thread', threadId: thread.id },
    );
    expect(remountedProps.hasConsent).toBe(kind === 'thread');
  });

  it('opens a digest headline by event id with the feed locale even when its news page is not loaded', async () => {
    mockFeedLocale = 'ru';
    callApiMock.mockResolvedValue(false);
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenNewsDiscussion(7);
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'news', news: { eventId: 7, locale: 'ru' } }, hasConsent: false,
    });
  });

  it.each([
    { threadId: undefined, isListed: false },
    { threadId: 'digest-thread', isListed: true },
    { threadId: 'digest-thread', isListed: false },
  ])('opens a digest by id or its existing discussion: %o', async ({ threadId, isListed }) => {
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1,
      top: [{ eventId: 7, headline: 'News' }], ...(threadId && { discussion: { threadId } }),
    }];
    if (threadId && isListed) {
      mockThreadListItems = [{ thread: {
        id: threadId, revision: 1, messageCount: 2,
        createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
      } }];
    }
    callApiMock.mockResolvedValue(isListed);
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: threadId && isListed
        ? { kind: 'thread', threadId, isNews: true } : { kind: 'digest', digest: { id: 'digest-1' } },
      hasConsent: isListed,
    });
  });

  it('opens one chat for repeated taps on a digest\'s Discuss and headlines while its chat opens', async () => {
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }],
    }];
    callApiMock.mockResolvedValue(false);
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const feedProps = FeedMock.mock.calls.at(-1)![0];

    feedProps.onOpenDigestDiscussion('digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const { chatKey } = ChatMock.mock.calls.at(-1)![0];
    feedProps.onOpenDigestDiscussion('digest-1');
    feedProps.onOpenNewsDiscussion(7);
    await rafPromise();
    await rafPromise();

    expect(new Set(ChatMock.mock.calls.map(([props]) => props.chatKey))).toEqual(new Set([chatKey]));
    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'digest', digest: { id: 'digest-1' } });
  });

  it('clears the open feed on full sign-out', async () => {
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
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
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);

    FeedMock.mock.calls.at(-1)![0].onOpenDiscussion({
      eventId: 7, deliveredAt: '2026-10-21T09:00:00.000Z', headline: 'News', body: 'Body', sources: [],
    });
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    (document.activeElement as HTMLElement | null)?.blur();
    ChatMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(() => Boolean(document.activeElement?.hasAttribute('data-agent-news-discuss')), 10, 300))
      .toBe(true);

    (document.activeElement as HTMLElement).blur();
    FeedMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(() => Boolean(document.activeElement?.hasAttribute('data-agent-news-row')), 10, 300))
      .toBe(true);
  });

  it('refreshes the list after a failed pin is rolled back', async () => {
    const thread = {
      id: 'pin-thread', revision: 1, messageCount: 2,
      createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
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

  it('turns a deleted chat\'s row to dust while it is deleted, and shows it again if the deletion fails', async () => {
    const thread = {
      id: 'delete-thread', revision: 1, messageCount: 2,
      createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    };
    mockThreadListItems = [{ thread }];
    const ItemMock = jest.mocked(AgentThreadListItem);
    ItemMock.mockImplementation(({ item }) => <div data-agent-row-key={item.thread.id} />);
    getBoundingClientRectMock = jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, left: 0, top: 0, right: 400, bottom: 600, width: 400, height: 600, toJSON: () => undefined,
    });
    await mountChats();
    ItemMock.mock.calls.at(-1)![0].onDelete(thread);
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
    const deletion = new Deferred<undefined>();
    callApiMock.mockReturnValueOnce(deletion.promise);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(thread);
    expect(await waitFor(() => ItemMock.mock.calls.at(-1)![0].isDissolved === true, 10, 300)).toBe(true);

    deletion.resolve(undefined);
    expect(await waitFor(() => ItemMock.mock.calls.at(-1)![0].isDissolved === false, 10, 300)).toBe(true);
    expect(mockRemoveThread).not.toHaveBeenCalled();
    expect(mockShowError).toHaveBeenCalled();
  });

  it('turns the title of a section a deleted chat leaves empty to dust with the chat', async () => {
    const threadBase = {
      revision: 1, messageCount: 2, createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    };
    const pinned = { ...threadBase, id: 'pinned-thread', isPinned: true as const };
    const first = { ...threadBase, id: 'first-thread' };
    const second = { ...threadBase, id: 'second-thread' };
    mockThreadListItems = [{ thread: pinned }, { thread: first }, { thread: second }];
    const ItemMock = jest.mocked(AgentThreadListItem);
    ItemMock.mockImplementation(({ item }) => <div data-agent-row-key={item.thread.id} />);
    getBoundingClientRectMock = jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, left: 0, top: 0, right: 400, bottom: 600, width: 400, height: 600, toJSON: () => undefined,
    });
    await mountChats();
    const [pinnedTitle, dayTitle] = Array.from(root.querySelectorAll('[data-agent-row-key^="section-"]'))
      .map(({ textContent }) => textContent!);
    const layer = getSnapEffectLayer();
    callApiMock.mockReturnValue(new Deferred<undefined>().promise);

    // The day keeps its other chat, so its title stays
    ItemMock.mock.calls.at(-1)![0].onDelete(first);
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(first);
    expect(await waitFor(() => layer.childElementCount === 1, 10, 300)).toBe(true);
    expect(layer.textContent).not.toContain(dayTitle);

    ItemMock.mock.calls.at(-1)![0].onDelete(pinned);
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(pinned);
    expect(await waitFor(() => layer.textContent!.includes(pinnedTitle), 10, 300)).toBe(true);
    expect(layer.textContent).not.toContain(dayTitle);
  });

  it('opens a chat the list marks as unread where its unseen messages start, there again after a remount', async () => {
    const thread = {
      id: 'unread-thread', revision: 1, messageCount: 6,
      createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    };
    localStorage.setItem('mytonwallet-agent-thread-read-state', JSON.stringify({
      records: { [thread.id]: { seenMessageCount: 4, isBaselineNeeded: false, isMarkedUnread: false } },
      order: [thread.id],
    }));
    mockThreadListItems = [{ thread }];
    await mountChats();
    jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].unreadStart === 4, 10, 300)).toBe(true);

    const chatProps = ChatMock.mock.calls.at(-1)![0];
    expect(chatProps.unreadStart).toBe(4);
    chatProps.onUnreadStartResolved!(chatProps.chatKey!, 3);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].unreadStart === 3, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].unreadStart).toBe(3);
    expect(await waitFor(() => getAgentV2LocalState().openChatOnMount?.unreadStart === 3, 10, 300)).toBe(true);

    await remountChats();
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'thread', threadId: thread.id }, unreadStart: 3,
    });
  });

  it.each(['answer', 'operator'])('resolves a cached row unread position after fresh history: %s', async (kind) => {
    const thread = {
      id: 'cached-unread', revision: 1, messageCount: 4,
      createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    };
    localStorage.setItem('mytonwallet-agent-thread-read-state', JSON.stringify({
      records: { [thread.id]: { seenMessageCount: 4, isBaselineNeeded: false, isMarkedUnread: false } },
      order: [thread.id],
    }));
    mockThreadListItems = [{ thread }];
    mockIsCacheShown = true;
    await mountChats();
    jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isUnreadStateUnknown === true, 10, 300)).toBe(true);
    await rafPromise();
    await rafPromise();
    expect(ChatMock.mock.calls.at(-1)![0].unreadStart).toBeUndefined();
    expect(getAgentV2LocalState().shownThreadCounts.has(thread.id)).toBe(false);
    expect(getAgentV2LocalState().threadReadState?.records[thread.id].isBaselineNeeded).toBe(false);

    await remountChats();
    expect(ChatMock.mock.calls.at(-1)![0].isUnreadStateUnknown).toBe(true);
    const fresh = {
      ...thread, revision: 2, messageCount: kind === 'answer' ? 6 : 4,
      ...(kind === 'operator' && { support: { state: 'operator' as const, lastOperatorMessageAt: TIMESTAMP } }),
    };
    ChatMock.mock.calls.at(-1)![0].onThreadLoaded!(fresh);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isUnreadStateUnknown === false, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].unreadStart).toBe(kind === 'answer' ? 4 : 'latestAnswer');
    expect(await waitFor(() => getAgentV2LocalState().shownThreadCounts.has(thread.id), 10, 300)).toBe(true);
  });

  it('keeps the chat memoized when only its parent state changes', async () => {
    const renderChat = jest.fn(() => undefined);
    ChatMock.mockImplementation(memo(renderChat));
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('Question');
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Question', 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => renderChat.mock.calls.length > 0, 10, 100)).toBe(true);
    expect(await waitFor(() => (
      getAgentV2LocalState().openChatOnMount?.key === ChatMock.mock.calls.at(-1)?.[0].chatKey
    ), 10, 300)).toBe(true);
    const renderCount = renderChat.mock.calls.length;
    const parentRenderCount = ChatMock.mock.calls.length;

    ChatMock.mock.calls.at(-1)![0].onAnswerChange!('new-thread', '$agent_activity_writing');
    expect(await waitFor(() => ChatMock.mock.calls.length > parentRenderCount, 10, 100)).toBe(true);
    expect(renderChat).toHaveBeenCalledTimes(renderCount);
  });

  it('keeps a thread resolved by another chat out of the chat on screen', async () => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('Question');
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Question', 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    const { chatKey, onThreadResolved } = ChatMock.mock.calls.at(-1)![0];
    onThreadResolved!(chatKey! - 1, 'other-thread');
    await rafPromise();
    await rafPromise();
    await remountChats();

    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'new' });
  });

  it('keeps the opening question across remounts until the chat accepts it once', async () => {
    await mountChats();
    InputBarMock.mock.calls.at(-1)![0].onInput('What is TON?');
    expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'What is TON?', 10, 300)).toBe(true);
    InputBarMock.mock.calls.at(-1)![0].onSend();
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onThreadResolved!(chatProps.chatKey!, 'new-thread');
    expect(await waitFor(() => getAgentV2LocalState().openChatOnMount?.threadId === 'new-thread', 10, 300)).toBe(true);
    ChatMock.mockClear();
    await remountChats();

    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'thread', 10, 300)).toBe(true);
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
    ChatMock.mockClear();
    await remountChats();
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === undefined, 10, 300)).toBe(true);
    await rafPromise();
    expect(ChatMock.mock.calls.at(-1)![0].initialMessage).toBeUndefined();
    expect(sendMessage).toHaveBeenCalledTimes(1);
  });

  describe('before the Agent is allowed', () => {
    beforeEach(() => {
      // Every call succeeds, and the consent reads as not given
      callApiMock.mockImplementation(((method: string) => Promise.resolve(method !== 'getAgentV2Consent')) as never);
    });

    function getSheet() {
      return ConsentSheetMock.mock.calls.at(-1)![0];
    }

    function getInputBar() {
      return InputBarMock.mock.calls.at(-1)![0];
    }

    function getOpenedQuestions() {
      const questions = new Map<number, string | undefined>();
      ChatMock.mock.calls.forEach(([props]) => questions.set(props.chatKey!, props.initialMessage));
      return [...questions.values()];
    }

    it('asks in a sheet at the first question, keeps the draft when closed and sends it once on Allow', async () => {
      await mountChats();
      // The list shows at once, with News, nothing sent and no sheet
      expect(getSheet().isOpen).toBe(false);
      expect(getInputBar().isDictationHeld).toBe(true);
      expect(jest.mocked(AgentNewsRow)).toHaveBeenCalled();

      getInputBar().onInput('What is TON?');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'What is TON?', 10, 300))
        .toBe(true);
      getInputBar().onSend();
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(true);
      expect(ChatMock).not.toHaveBeenCalled();

      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(false);
      expect(getInputBar().inputValue).toBe('What is TON?');
      expect(ChatMock).not.toHaveBeenCalled();
      expect(callApiMock).not.toHaveBeenCalledWith('acceptAgentV2Consent');

      // The next send asks again
      getInputBar().onSend();
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(true);

      // A consent that fails to be stored keeps the sheet, the draft and the question, and Allow can be tried again
      const answerApi = callApiMock.getMockImplementation() as (...args: unknown[]) => unknown;
      callApiMock.mockImplementation(((method: string, ...args: unknown[]) => (
        method === 'acceptAgentV2Consent' ? Promise.resolve(undefined) : answerApi(method, ...args)
      )) as never);
      getSheet().onAllow();
      expect(await waitFor(() => mockShowError.mock.calls.length > 0, 10, 300)).toBe(true);
      await rafPromise();
      expect(getSheet().isOpen).toBe(true);
      expect(getInputBar().inputValue).toBe('What is TON?');
      expect(getInputBar().isDictationHeld).toBe(true);
      expect(ChatMock).not.toHaveBeenCalled();
      callApiMock.mockImplementation(answerApi as never);

      getSheet().onAllow();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'What is TON?', 10, 300))
        .toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('acceptAgentV2Consent');
      expect(getSheet().isOpen).toBe(false);
      expect(getOpenedQuestions()).toEqual(['What is TON?']);

      // The consent stays: a later question opens its chat without the sheet
      ChatMock.mock.calls.at(-1)![0].onBack!();
      expect(await waitFor(() => (
        getInputBar().inputValue === '' && getInputBar().isDictationHeld === false
      ), 10, 300)).toBe(true);
      expect(getInputBar().inputValue).toBe('');
      expect(getInputBar().isDictationHeld).toBe(false);
      getInputBar().onInput('And staking?');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'And staking?', 10, 300))
        .toBe(true);
      getInputBar().onSend();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'And staking?', 10, 300))
        .toBe(true);
      expect(getSheet().isOpen).toBe(false);
      expect(getOpenedQuestions()).toEqual(['What is TON?', 'And staking?']);
    });

    it('asks before a hint and before a recording, and drops either when the sheet closes', async () => {
      await mountChats();
      jest.mocked(AgentHints).mock.calls.at(-1)![0].onHintClick(SWAP_HINT, document.createElement('button'));
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(true);
      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);
      expect(ChatMock).not.toHaveBeenCalled();

      getInputBar().onHeldDictation!();
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(true);
      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);

      jest.mocked(AgentHints).mock.calls.at(-1)![0].onHintClick(SWAP_HINT, document.createElement('button'));
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      getSheet().onAllow();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'How do swaps work?', 10, 300))
        .toBe(true);
      expect(getOpenedQuestions()).toEqual(['How do swaps work?']);
    });

    it('opens News and a discussion, which asks before it sends, goes on once allowed and hears a close', async () => {
      await mountChats();
      jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
      expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(FeedMock).toHaveBeenCalled();

      FeedMock.mock.calls.at(-1)![0].onOpenDiscussion({
        eventId: 7, deliveredAt: '2026-10-21T09:00:00.000Z', headline: 'News', body: 'Body', sources: [],
      });
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'news', 10, 300)).toBe(true);
      const discussion = ChatMock.mock.calls.at(-1)![0];
      expect(discussion.target).toMatchObject({ kind: 'news', news: { eventId: 7 } });
      expect(discussion.hasConsent).toBe(false);
      expect(getSheet().isOpen).toBe(false);

      const send = jest.fn();
      const decline = jest.fn();
      discussion.onRequestConsent!(send, undefined, decline);
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(getSheet().isOpen).toBe(true);
      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);
      expect(send).not.toHaveBeenCalled();
      expect(decline).toHaveBeenCalledTimes(1);

      discussion.onRequestConsent!(send, undefined, decline);
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      getSheet().onAllow();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].hasConsent === true, 10, 300)).toBe(true);
      expect(callApiMock).toHaveBeenCalledWith('acceptAgentV2Consent');
      expect(send).toHaveBeenCalledTimes(1);
      expect(decline).toHaveBeenCalledTimes(1);
      expect(ChatMock.mock.calls.at(-1)![0].hasConsent).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].chatKey).toBe(discussion.chatKey);
    });

    it('hides the keyboard for the sheet and gives the field its focus back only after a send from it', async () => {
      await mountChats();
      jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
      expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
      FeedMock.mock.calls.at(-1)![0].onOpenDiscussion({
        eventId: 7, deliveredAt: '2026-10-21T09:00:00.000Z', headline: 'News', body: 'Body', sources: [],
      });
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      const discussion = ChatMock.mock.calls.at(-1)![0];
      const field = document.createElement('textarea');
      document.body.appendChild(field);

      // A send from the field: the field gives up the focus, and gets it back as the sheet closes
      field.focus();
      discussion.onRequestConsent!(jest.fn(), field);
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(document.activeElement).not.toBe(field);
      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);
      expect(document.activeElement).toBe(field);

      // A suggestion or the microphone: the keyboard goes too, but does not come back
      discussion.onRequestConsent!(jest.fn());
      expect(await waitFor(() => getSheet().isOpen, 10, 300)).toBe(true);
      expect(document.activeElement).not.toBe(field);
      getSheet().onClose();
      expect(await waitFor(() => !getSheet().isOpen, 10, 300)).toBe(true);
      expect(document.activeElement).not.toBe(field);
      field.remove();
    });
  });
});

// Calls the listeners of the layouts' media query, as the app switches between them
function switchLayout() {
  jest.mocked(window.matchMedia).mock.results.forEach(({ type, value }) => {
    if (type !== 'return' || value.media !== PORTRAIT_SCREEN_QUERY) return;

    const removedListeners = jest.mocked(value.removeEventListener).mock.calls.map(([, listener]) => listener);
    jest.mocked(value.addEventListener).mock.calls.forEach(([eventType, listener]) => {
      if (eventType === 'change' && !removedListeners.includes(listener)) {
        (listener as EventListener)(new Event('change'));
      }
    });
  });
}

function buildListItem(id: string): AgentThreadListItemV2 {
  return {
    thread: {
      id, revision: 1, messageCount: 2, createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP,
    },
  };
}
