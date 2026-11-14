import '../../global/actions/ui/initial';
import '../../global/actions/ui/misc';

import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../global';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2RunResult, AgentV2StarterHints } from '../../api/agentV2/types';
import type { AgentHint } from '../../global/types';
import type { AgentV2ChatTarget, UseAgentV2MessagesResult } from '../agent/hooks/useAgentV2Messages';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';
import type { AgentNewsFeedView } from './agentNewsFeedView';

import { DEFAULT_STAKING_STATE } from '../../config';
import { getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import Deferred from '../../util/Deferred';
import { pause, rafPromise, waitFor } from '../../util/schedulers';
import { callApi } from '../../api';
import { getSnapEffectLayer } from '../agent/helpers/snapEffect';
import { setAgentNewsFeedView } from './agentNewsFeedView';
import useAgentSuggestions from './useAgentSuggestions';

import { PORTRAIT_SCREEN_QUERY } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';
import useAgentV2Dictation from '../agent/hooks/useAgentV2Dictation';
import useAgentV2Messages from '../agent/hooks/useAgentV2Messages';

import * as AgentConversationShellModule from '../agent/AgentConversationShell';
import AgentHints from '../agent/AgentHints';
import AgentInputBar from '../agent/AgentInputBar';
import AgentNewsFeed from './AgentNewsFeed';
import AgentNewsRow from './AgentNewsRow';
import AgentSupportRequestModal from './AgentSupportRequestModal';
import AgentThreadList from './AgentThreadList';
import AgentThreadListItem from './AgentThreadListItem';
import AgentV2Chats from './AgentV2Chats';
import AgentV2Classic from './AgentV2Classic';
import { AgentV2ConsentSheet } from './AgentV2Conversation';
import DeleteAgentChatModal from './DeleteAgentChatModal';

const TIMESTAMP = '2026-10-21T12:00:00.000Z';
const SWAP_HINT: AgentHint = {
  id: 'action.swap', langCode: 'en', title: 'Swap tokens', subtitle: '', prompt: 'Swap tokens',
};
const SWAP_STARTER_HINTS: AgentV2StarterHints = {
  catalogVersion: 'agent-starter-hints-v2', items: [{ id: 'action.swap', group: 'action' }],
};
const SWAP_HINT_ENTRY_POINT = {
  kind: 'emptyState', surface: 'agentTab', hintId: 'action.swap', catalogVersion: 'agent-starter-hints-v2',
} as const;

const mockScheduleRefresh = jest.fn();
const mockSetThreadPinned = jest.fn();
const mockRemoveThread = jest.fn();
const mockShowError = jest.fn();
const mockMarkDiscussion = jest.fn();
const mockMarkDigestDiscussion = jest.fn();
let mockThreadListItems: AgentThreadListItemV2[] = [];
const mockThreadListUpdates = new Set<NoneToVoidFunction>();
let mockIsCacheShown = false;
let mockFeedItems: AgentNewsFeedEntry[] = [];
let mockFeedLocale: string | undefined = 'en';

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
jest.mock('./useAgentV2ThreadList', () => {
  const { useEffect, useState } = jest.requireActual<typeof import('../../lib/teact/teact')>('../../lib/teact/teact');
  return {
    ...jest.requireActual('./useAgentV2ThreadList'),
    __esModule: true,
    default: () => {
      // The chats render again as a load ends
      const [, setRevision] = useState(0);
      useEffect(() => {
        const update = () => setRevision((revision) => revision + 1);
        mockThreadListUpdates.add(update);
        return () => {
          mockThreadListUpdates.delete(update);
        };
      }, []);
      return {
        items: mockThreadListItems,
        isCacheShown: mockIsCacheShown,
        activityLangKeys: {},
        hasMore: false,
        releaseLoadedChat: jest.fn(),
        syncLoadedChat: jest.fn(),
        setThreadPinned: mockSetThreadPinned,
        removeThread: mockRemoveThread,
        scheduleRefresh: mockScheduleRefresh,
      };
    },
  };
});
jest.mock('./useAgentNewsFeed', () => ({
  __esModule: true,
  default: ({ view }: { view: AgentNewsFeedView }) => ({
    items: view === 'digests' ? mockFeedItems.filter((entry) => entry.kind === 'digest') : mockFeedItems,
    allItems: mockFeedItems, locale: mockFeedLocale,
    unreadCount: 2,
    startReading: jest.fn(), refresh: jest.fn(), removeDiscussion: jest.fn(), markDiscussion: mockMarkDiscussion,
    markDigestDiscussion: mockMarkDigestDiscussion,
  }),
}));
jest.mock('./useAgentSuggestions', () => ({
  ...jest.requireActual('./useAgentSuggestions'), __esModule: true, default: jest.fn(),
}));
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
jest.mock('./AgentSupportRequestModal', () => ({
  __esModule: true,
  default: jest.fn(jest.requireActual('./AgentSupportRequestModal').default),
}));

const InputBarMock = jest.mocked(AgentInputBar);
const ChatMock = jest.mocked(AgentV2Classic);
const ConsentSheetMock = jest.mocked(AgentV2ConsentSheet);
const SupportSheetMock = jest.mocked(AgentSupportRequestModal);
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
    setAgentNewsFeedView('all');
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
    setAgentNewsFeedView('all');
    root.remove();
    getActions().afterSignOut({ shouldReset: true });
    getBoundingClientRectMock?.mockRestore();
    getBoundingClientRectMock = undefined;
    InputBarMock.mockImplementation(INPUT_BAR_IMPLEMENTATION);
    jest.mocked(AgentThreadListItem).mockImplementation(THREAD_LIST_ITEM_IMPLEMENTATION);
    jest.mocked(AgentNewsRow).mockImplementation(NEWS_ROW_IMPLEMENTATION);
    FeedMock.mockImplementation(() => undefined);
    jest.mocked(useAgentLayoutSwitch).mockReset();
    mockMarkDiscussion.mockReset();
    mockMarkDigestDiscussion.mockReset();
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

  it('keeps the News row count and each view\'s place in the feed while it is open', async () => {
    await mountChats();
    expect(jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].unreadCount).toBe(2);
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const allSession = { draft: '', scrollAnchor: { indexFromEnd: 1, offset: 25 }, isPlaced: true };
    expect(await waitFor(() => Boolean(getAgentV2LocalState().openFeedOnMount), 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].session!.save(allSession);
    await remountChats();
    expect(FeedMock.mock.calls.at(-1)![0].session!.initial).toEqual(allSession);

    // A view not shown yet opens as the feed does
    const allProps = FeedMock.mock.calls.at(-1)![0];
    const onLeave = jest.fn();
    const unsubscribe = allProps.session!.subscribeToLeave!(onLeave);
    allProps.onViewChange('digests');
    expect(onLeave).toHaveBeenCalledTimes(1);
    unsubscribe();
    expect(await waitFor(() => FeedMock.mock.calls.at(-1)?.[0].view === 'digests', 10, 300)).toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].session!.initial).toBeUndefined();
    expect(jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].unreadCount).toBe(2);
    const digestsSession = { draft: '', isPlaced: true };
    FeedMock.mock.calls.at(-1)![0].session!.save(digestsSession);
    await remountChats();
    expect(FeedMock.mock.calls.at(-1)![0].view).toBe('digests');
    expect(FeedMock.mock.calls.at(-1)![0].session!.initial).toEqual(digestsSession);

    // A view switched back to returns where it was
    FeedMock.mock.calls.at(-1)![0].onViewChange('all');
    expect(await waitFor(() => FeedMock.mock.calls.at(-1)?.[0].view === 'all', 10, 300)).toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].session!.initial).toEqual(allSession);
    FeedMock.mock.calls.at(-1)![0].onViewChange('digests');
    expect(await waitFor(() => FeedMock.mock.calls.at(-1)?.[0].view === 'digests', 10, 300)).toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].session!.initial).toEqual(digestsSession);
  });

  describe('suggestions under the list', () => {
    const marketStarterHints: AgentV2StarterHints = {
      catalogVersion: 'agent-starter-hints-v2', items: [{ id: 'market.today', group: 'market' }],
    };

    afterEach(() => {
      jest.mocked(useAgentSuggestions).mockReset();
    });

    function getStarterHintsCalls() {
      return callApiMock.mock.calls.filter(([method]) => method === 'getAgentV2StarterHints');
    }

    function getShownHintIds() {
      return jest.mocked(AgentHints).mock.calls.at(-1)![0].hints?.map(({ id }) => id);
    }

    it('picks them each time they show, keeps the pick while they stay and sends a tapped one', async () => {
      jest.mocked(useAgentSuggestions).mockImplementation(
        jest.requireActual<{ default: typeof useAgentSuggestions }>('./useAgentSuggestions').default,
      );
      const picks = [SWAP_STARTER_HINTS, marketStarterHints];
      callApiMock.mockImplementation(((method: string) => Promise.resolve(method === 'getAgentV2StarterHints'
        ? picks[getStarterHintsCalls().length - 1]
        : true)) as never);
      await mountChats();
      expect(await waitFor(() => getShownHintIds()?.[0] === 'action.swap', 10, 300)).toBe(true);
      expect(getStarterHintsCalls()).toEqual([['getAgentV2StarterHints']]);

      // Typing and a reload of the chats render the list again with the same pick
      InputBarMock.mock.calls.at(-1)![0].onInput('Wh');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'Wh', 10, 300)).toBe(true);
      mockThreadListUpdates.forEach((update) => update());
      await pause(20);
      expect(getShownHintIds()).toEqual(['action.swap']);
      expect(getStarterHintsCalls()).toHaveLength(1);

      jest.mocked(AgentHints).mock.calls.at(-1)![0].onHintClick(SWAP_HINT, document.createElement('button'));
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
        initialMessage: 'Swap tokens', initialHintEntryPoint: SWAP_HINT_ENTRY_POINT,
      });

      // Back at the list they show again with a pick of their own
      ChatMock.mock.calls.at(-1)![0].onBack!();
      expect(await waitFor(() => getShownHintIds()?.[0] === 'market.today', 10, 300)).toBe(true);
      expect(getStarterHintsCalls()).toHaveLength(2);
    });

    it('mounts a chat opened again afresh, for it to pick its hints anew', async () => {
      const mountedChatKeys: number[] = [];
      ChatMock.mockImplementation(function Chat({ chatKey }) {
        // Runs once for each mount
        useState(() => mountedChatKeys.push(chatKey!));
        return undefined;
      });
      jest.mocked(useAgentSuggestions).mockReturnValue({ starterHints: SWAP_STARTER_HINTS, hints: [SWAP_HINT] });
      await mountChats();
      jest.mocked(AgentHints).mock.calls.at(-1)![0].onHintClick(SWAP_HINT, document.createElement('button'));
      expect(await waitFor(() => mountedChatKeys.length === 1, 10, 300)).toBe(true);

      ChatMock.mock.calls.at(-1)![0].onBack!();
      jest.mocked(AgentHints).mock.calls.at(-1)![0].onHintClick(SWAP_HINT, document.createElement('button'));
      expect(await waitFor(() => mountedChatKeys.length === 2, 10, 300)).toBe(true);
      expect(mountedChatKeys[1]).not.toBe(mountedChatKeys[0]);
      expect(ChatMock.mock.calls.at(-1)![0].chatKey).toBe(mountedChatKeys[1]);
    });

    it('shows none when the pick fails to load, and keeps Contact Support', async () => {
      jest.mocked(useAgentSuggestions).mockImplementation(
        jest.requireActual<{ default: typeof useAgentSuggestions }>('./useAgentSuggestions').default,
      );
      callApiMock.mockImplementation(((method: string) => Promise.resolve(
        method === 'getAgentV2StarterHints' ? undefined : true,
      )) as never);
      await mountChats();
      expect(await waitFor(() => getStarterHintsCalls().length > 0, 10, 300)).toBe(true);
      await pause(20);
      const hints = jest.mocked(AgentHints).mock.calls.at(-1)![0];
      expect(hints.isOpen).toBe(true);
      expect(hints.hints).toBeUndefined();
      expect(hints.onSupportClick).toBeDefined();
    });

    it.each([
      ['empty', 0n, 0n, 'empty'],
      ['funded', 1_000_000_000n, 0n, 'funded'],
      ['staked only', 0n, 1_000_000_000n, 'funded'],
      ['not loaded', undefined, 0n, undefined],
    ] as const)('picks them under the list for a wallet whose balance is %s', async (
      _, amount, stakedAmount, walletState,
    ) => {
      const global = getGlobal();
      setGlobal({
        ...global,
        currentAccountId: 'account-1',
        byAccountId: {
          ...global.byAccountId,
          'account-1': amount === undefined ? {} : {
            balances: { bySlug: { toncoin: amount } },
            staking: { stateById: { liquid: { ...DEFAULT_STAKING_STATE, balance: stakedAmount } } },
          },
        },
      });
      jest.mocked(useAgentSuggestions).mockImplementation(
        jest.requireActual<{ default: typeof useAgentSuggestions }>('./useAgentSuggestions').default,
      );
      callApiMock.mockImplementation(((method: string) => Promise.resolve(
        method === 'getAgentV2StarterHints' ? SWAP_STARTER_HINTS : true,
      )) as never);
      await mountChats();
      expect(await waitFor(() => getShownHintIds()?.[0] === 'action.swap', 10, 300)).toBe(true);
      expect(getStarterHintsCalls()).toEqual([
        walletState ? ['getAgentV2StarterHints', walletState] : ['getAgentV2StarterHints'],
      ]);
    });
  });

  describe('Contact Support under the list', () => {
    let portals: HTMLDivElement;

    beforeEach(() => {
      portals = document.createElement('div');
      portals.id = 'portals';
      document.body.appendChild(portals);
    });

    afterEach(() => {
      portals.remove();
      setGlobal({ ...getGlobal(), currentAccountId: undefined });
    });

    function setWallet() {
      setGlobal({ ...getGlobal(), currentAccountId: 'account-1' });
    }

    function getHints() {
      return jest.mocked(AgentHints).mock.calls.at(-1)![0];
    }

    function findSheetButton(text: string) {
      return [...portals.querySelectorAll('button')].find(({ textContent }) => textContent === text);
    }

    async function openSheet() {
      getHints().onSupportClick!();
      expect(await waitFor(() => Boolean(findSheetButton('Cancel')), 10, 300)).toBe(true);
      return portals.querySelector('p')!.textContent;
    }

    it('ends the suggestions, last and after however many there are', async () => {
      const { default: RealAgentHints } = jest.requireActual<{ default: typeof AgentHints }>('../agent/AgentHints');
      const hints = Array.from({ length: 4 }, (_, index) => ({ ...SWAP_HINT, id: `hint-${index}` }));
      const onSupportClick = jest.fn();
      TeactDOM.render(
        <RealAgentHints
          isOpen
          hints={hints}
          isSupportDisabled
          onHintClick={jest.fn()}
          onSupportClick={onSupportClick}
        />,
        root,
      );
      await pause(20);

      const buttons = [...root.querySelectorAll('button')];
      expect(buttons).toHaveLength(5);
      expect(buttons.at(-1)!.textContent).toBe('$agent_support_contact');
      expect(buttons.at(-1)!.querySelector('svg')).not.toBeNull();
      expect(buttons.at(-1)!.disabled).toBe(true);
    });

    it('is disabled until the chats load, asks, and opens a new chat that calls support on Call', async () => {
      setWallet();
      mockThreadListItems = undefined as unknown as AgentThreadListItemV2[];
      await mountChats();
      expect(getHints().onSupportClick).toBeDefined();
      expect(getHints().isSupportDisabled).toBe(true);

      mockThreadListItems = [buildListItem('plain')];
      await remountChats();
      expect(getHints().isSupportDisabled).toBe(false);

      expect(await openSheet()).toBe('$agent_support_confirm_text');
      findSheetButton('Cancel')!.click();
      expect(await waitFor(() => !findSheetButton('Cancel'), 10, 500)).toBe(true);
      expect(ChatMock).not.toHaveBeenCalled();

      await openSheet();
      findSheetButton('$agent_support_confirm_action')!.click();
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({ target: { kind: 'new' }, shouldRequestSupport: true });
    });

    it('opens the chat support already has', async () => {
      setWallet();
      const supportItem = buildListItem('support');
      supportItem.thread.support = { state: 'waiting' };
      mockThreadListItems = [buildListItem('plain'), supportItem];
      await mountChats();

      await openSheet();
      findSheetButton('$agent_support_confirm_action')!.click();
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'thread', threadId: 'support' });
      expect(ChatMock.mock.calls.at(-1)![0].shouldRequestSupport).toBeUndefined();
    });

    it('waits for the fresh chats behind cached ones and opens the one an operator has', async () => {
      setWallet();
      mockIsCacheShown = true;
      mockThreadListItems = [buildListItem('plain')];
      await mountChats();

      await openSheet();
      findSheetButton('$agent_support_confirm_action')!.click();
      await pause(50);
      expect(ChatMock).not.toHaveBeenCalled();

      const operatorItem = buildListItem('operator');
      operatorItem.thread.support = { state: 'operator' };
      mockIsCacheShown = false;
      mockThreadListItems = [buildListItem('plain'), operatorItem];
      mockThreadListUpdates.forEach((update) => update());
      expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'thread', threadId: 'operator' });
      expect(ChatMock.mock.calls.at(-1)![0].shouldRequestSupport).toBeUndefined();
    });

    it('tells that the operator gets no addresses without a wallet', async () => {
      mockThreadListItems = [buildListItem('plain')];
      await mountChats();

      expect(await openSheet()).toBe('$agent_support_confirm_text_no_wallet');
    });

    it('offers nothing to send while the consent is being read', async () => {
      setWallet();
      callApiMock.mockImplementation(((method: string) => (
        method === 'getAgentV2Consent' ? new Promise(() => undefined) : Promise.resolve(true)
      )) as never);
      TeactDOM.render(<AgentV2Chats isActive />, root);
      expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'getAgentV2Consent'), 10, 300))
        .toBe(true);
      await pause(50);

      expect(jest.mocked(AgentHints).mock.calls.every(([props]) => props.isSupportDisabled !== false)).toBe(true);
      const sheet = SupportSheetMock.mock.calls.at(-1)![0];
      expect(sheet.canConfirm).toBe(false);
      sheet.onConfirm();
      await pause(50);
      expect(ConsentSheetMock.mock.calls.every(([props]) => !props.isOpen)).toBe(true);
      expect(ChatMock).not.toHaveBeenCalled();
    });

    describe('before consent', () => {
      beforeEach(() => {
        callApiMock.mockImplementation(((method: string) => Promise.resolve(method !== 'getAgentV2Consent')) as never);
      });

      async function callAndAllow() {
        expect(getHints().isSupportDisabled).toBe(false);
        expect(await openSheet()).toBe('$agent_support_confirm_text_no_wallet');
        findSheetButton('$agent_support_confirm_action')!.click();
        expect(await waitFor(() => ConsentSheetMock.mock.calls.at(-1)![0].isOpen, 10, 300)).toBe(true);
        expect(ChatMock).not.toHaveBeenCalled();
        ConsentSheetMock.mock.calls.at(-1)![0].onAllow();
      }

      it('tells that the operator gets no addresses, and asks for consent on Call', async () => {
        setWallet();
        await mountChats();

        await callAndAllow();
        expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
        expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({ target: { kind: 'new' }, shouldRequestSupport: true });
      });

      it('waits for the chats after consent and opens the one an operator has', async () => {
        setWallet();
        mockThreadListItems = undefined as unknown as AgentThreadListItemV2[];
        await mountChats();

        await callAndAllow();
        expect(await waitFor(() => !ConsentSheetMock.mock.calls.at(-1)![0].isOpen, 10, 300)).toBe(true);
        await pause(50);
        expect(ChatMock).not.toHaveBeenCalled();

        const operatorItem = buildListItem('operator');
        operatorItem.thread.support = { state: 'operator' };
        mockThreadListItems = [buildListItem('plain'), operatorItem];
        mockThreadListUpdates.forEach((update) => update());
        expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
        expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({ kind: 'thread', threadId: 'operator' });
        expect(ChatMock.mock.calls.at(-1)![0].shouldRequestSupport).toBeUndefined();
      });
    });
  });

  it('shows starter suggestions with News in an empty list without focusing the input', async () => {
    const onOpenNews = jest.fn();
    const props = {
      isActive: true, isAgentActive: true, hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
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
      isActive: true, isAgentActive: true, hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
      hasLoadFailed: true,
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
      isActive: true, isAgentActive: true, items: [buildListItem('shown')], hasMore: true, activityLangKeys: {},
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
      isActive: true, isAgentActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
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
      isActive: true, isAgentActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
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
      isActive: true, isAgentActive: true, items: [], hasMore: false, activityLangKeys: {}, newsUnreadCount: 0,
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
    // A news discussion loads before consent, as it did before the switch, and shares in the language it opened in
    expect(remountedProps.target).toEqual(
      kind !== 'thread'
        ? { kind: 'thread', threadId: thread.id, isNews: true, ...(kind === 'news' && { newsLocale: 'en' }) }
        : { kind: 'thread', threadId: thread.id },
    );
    expect(remountedProps.hasConsent).toBe(kind === 'thread');
  });

  it('opens a digest headline by event id in the feed locale before its page loads, then focuses it', async () => {
    mockFeedLocale = 'ru';
    callApiMock.mockResolvedValue(false);
    FeedMock.mockImplementation(() => (
      <div data-agent-news-digest-id="digest-1"><button type="button" data-agent-news-digest-headline="7" /></div>
    ));
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenNewsDiscussion(7, 'digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'news', news: { eventId: 7, locale: 'ru' } }, hasConsent: false,
    });
    expect(ChatMock.mock.calls.at(-1)![0].target).not.toHaveProperty('shouldDeferCreation');

    (document.activeElement as HTMLElement | null)?.blur();
    ChatMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(
      () => document.activeElement?.getAttribute('data-agent-news-digest-headline') === '7', 10, 300,
    )).toBe(true);
  });

  it.each(['all', 'digests'] as const)('opens headline threads with previews in the %s view', async (view) => {
    setAgentNewsFeedView(view);
    // The thread keeps the feed's language, apart from the app's, which its shared links name
    mockFeedLocale = 'ru';
    const newsItem = {
      eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [],
      discussion: { threadId: 'news-thread' },
    };
    mockFeedItems = [
      { ...newsItem, kind: 'news' },
      { kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }] },
    ];
    mockThreadListItems = [{ thread: {
      ...buildListItem('news-thread').thread, messageCount: 1,
      news: { eventId: newsItem.eventId, headline: newsItem.headline, publishedAt: newsItem.deliveredAt },
    } }];
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].items?.map((entry) => entry.kind))
      .toEqual(view === 'digests' ? ['digest'] : ['news', 'digest']);
    FeedMock.mock.calls.at(-1)![0].onOpenNewsDiscussion(7, 'digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    const expectedTarget = {
      kind: 'thread', threadId: 'news-thread', isNews: true, newsLocale: 'ru',
      preview: {
        eventId: 7, headline: 'News', body: 'Body', sources: [], excerpt: 'Body', publishedAt: TIMESTAMP,
      },
    };
    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual(expectedTarget);

    ChatMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(() => FeedMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'digest', 10, 300)).toBe(true);
    ChatMock.mock.calls.at(-1)![0].onOpenDigestNews!(7, 'digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'thread', 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual(expectedTarget);
  });

  it.each(['news', 'digest'].flatMap((kind) => [
    { kind, threadId: undefined, isListed: false },
    { kind, threadId: 'news-thread', isListed: true },
    { kind, threadId: 'news-thread', isListed: false },
  ]))('defers only a feed item without a discussion: %o', async ({ kind, threadId, isListed }) => {
    const discussionNaming = { title: 'Discuss TON news', icon: '💎', followups: ['What does this mean?'] };
    const discussion = threadId ? { discussion: { threadId } } : undefined;
    const item = {
      eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [], discussionNaming, ...discussion,
    };
    if (kind === 'digest') {
      mockFeedItems = [{
        kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1,
        top: [{ eventId: 7, headline: 'News' }], discussionNaming, ...discussion,
      }];
    }
    if (threadId && isListed) mockThreadListItems = [buildListItem(threadId)];
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    if (kind === 'digest') FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
    else FeedMock.mock.calls.at(-1)![0].onOpenDiscussion(item);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === true, 10, 300)).toBe(true);
    await rafPromise();

    const chatProps = ChatMock.mock.calls.at(-1)![0];
    expect(chatProps.target).toMatchObject(threadId && isListed
      ? { kind: 'thread', threadId, isNews: true }
      : kind === 'digest'
        ? { kind: 'digest', digest: { id: 'digest-1' } }
        : { kind: 'news', news: { eventId: 7, locale: 'en' } });
    if (threadId) {
      expect(chatProps.target).not.toHaveProperty('shouldDeferCreation');
      return;
    }
    expect(chatProps.target).toMatchObject({ shouldDeferCreation: true, discussionNaming });
    chatProps.onBack!();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);
    await rafPromise();
    chatProps.onThreadResolved!(chatProps.chatKey!, 'created-news-thread', chatProps.target);
    const markMock = kind === 'digest' ? mockMarkDigestDiscussion : mockMarkDiscussion;
    expect(await waitFor(() => markMock.mock.calls.length === 1, 10, 300)).toBe(true);
    expect(markMock).toHaveBeenCalledWith(kind === 'digest' ? 'digest-1' : 7, { threadId: 'created-news-thread' });
    chatProps.onAnswerChange!('created-news-thread', '$agent_activity_analyzing');
    expect(await waitFor(() => (
      FeedMock.mock.calls.at(-1)![0].continuedThreadIds!.has('created-news-thread')
    ), 10, 300)).toBe(true);
  });

  it.each(['news', 'digest'] as const)('shows the first question of a %s discussion reopened before its thread', async (
    kind,
  ) => {
    const item = { eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [] };
    mockFeedItems = kind === 'digest'
      ? [{ kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }] }]
      : [{ kind: 'news', ...item }];
    const thread = {
      ...buildListItem('created-thread').thread,
      ...(kind === 'digest'
        ? { digest: { id: 'digest-1', windowEnd: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }] } }
        : { news: { eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [] } }),
    };
    const creation = new Deferred<void>();
    const run = new Deferred<AgentV2RunResult>();
    callApiMock.mockImplementation(((method: string) => {
      switch (method) {
        case 'getAgentV2Consent': return Promise.resolve(true);
        case 'createAgentV2Thread':
          return creation.promise.then(() => ({ ok: true, value: { protocolVersion: 3, thread, created: true } }));
        case 'getAgentV2Messages': return Promise.resolve({ ok: true, value: { thread, messages: [] } });
        case 'updateAgentV2HostContext':
          return Promise.resolve({ ok: true, value: { authorityChanged: false, generation: 1 } });
        case 'startAgentV2Run': return run.promise;
        default: return Promise.resolve(undefined);
      }
    }) as never);
    let messages: UseAgentV2MessagesResult | undefined;
    ChatMock.mockImplementation(({ isActive, target }) => (isActive ? <ChatHarness target={target} /> : undefined));
    function ChatHarness({ target }: { target?: AgentV2ChatTarget }) {
      messages = useAgentV2Messages({ isActive: true, target, lang: useLang() });
      return undefined;
    }
    function openDiscussion() {
      if (kind === 'digest') FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
      else FeedMock.mock.calls.at(-1)![0].onOpenDiscussion(item);
    }
    function getCreationCount() {
      return callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread').length;
    }

    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    openDiscussion();
    expect(await waitFor(() => messages?.isSendDisabled === false, 10, 300)).toBe(true);
    const firstTarget = ChatMock.mock.calls.at(-1)![0].target;
    expect(firstTarget).toMatchObject({ shouldDeferCreation: true });
    messages!.sendMessage('Question before the thread');
    expect(await waitFor(() => messages?.hasPendingQuestion === true && getCreationCount() === 1, 10, 300))
      .toBe(true);

    ChatMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);
    await rafPromise();
    messages = undefined;
    openDiscussion();
    expect(await waitFor(() => messages?.isConsentAccepted === true, 10, 300)).toBe(true);
    await pause(50);
    expect(ChatMock.mock.calls.at(-1)![0].target).not.toBe(firstTarget);
    expect(messages!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'Question before the thread' }),
    ]);
    expect(messages!.isSendDisabled).toBe(true);
    expect(getCreationCount()).toBe(1);

    creation.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 300))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({
      threadId: 'created-thread', input: { kind: 'append', text: 'Question before the thread' },
    });
    expect(getCreationCount()).toBe(1);
    run.resolve({ clientRunId: 'opening-run', state: 'completed' });
  });

  it.each(['news', 'digest'] as const)('sends the question of a %s discussion reopened as its thread comes', async (
    kind,
  ) => {
    const item = { eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [] };
    mockFeedItems = kind === 'digest'
      ? [{ kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }] }]
      : [{ kind: 'news', ...item }];
    // The feed marks the discussion as its thread is created
    function markDiscussion(threadId: string) {
      mockFeedItems = mockFeedItems.map((entry) => ({ ...entry, discussion: { threadId } }));
      mockThreadListUpdates.forEach((update) => update());
    }
    mockMarkDiscussion.mockImplementation((_, { threadId }) => markDiscussion(threadId));
    mockMarkDigestDiscussion.mockImplementation((_, { threadId }) => markDiscussion(threadId));
    const thread = {
      ...buildListItem('created-thread').thread,
      ...(kind === 'digest'
        ? { digest: { id: 'digest-1', windowEnd: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }] } }
        : { news: { eventId: 7, deliveredAt: TIMESTAMP, headline: 'News', body: 'Body', sources: [] } }),
    };
    const creation = new Deferred<void>();
    const senderHistory = new Deferred<void>();
    const run = new Deferred<AgentV2RunResult>();
    let historyReads = 0;
    callApiMock.mockImplementation(((method: string) => {
      switch (method) {
        case 'getAgentV2Consent': return Promise.resolve(true);
        case 'createAgentV2Thread':
          return creation.promise.then(() => ({ ok: true, value: { protocolVersion: 3, thread, created: true } }));
        case 'getAgentV2Messages': {
          const history = { ok: true, value: { thread, messages: [] } };
          return ++historyReads === 1 ? senderHistory.promise.then(() => history) : Promise.resolve(history);
        }
        case 'updateAgentV2HostContext':
          return Promise.resolve({ ok: true, value: { authorityChanged: false, generation: 1 } });
        case 'startAgentV2Run': return run.promise;
        default: return Promise.resolve(undefined);
      }
    }) as never);
    let messages: UseAgentV2MessagesResult | undefined;
    ChatMock.mockImplementation(({ isActive, target, chatKey, onThreadResolved }) => (isActive ? (
      <ChatHarness target={target} onThreadResolved={(threadId) => onThreadResolved?.(chatKey!, threadId, target)} />
    ) : undefined));
    function ChatHarness({ target, onThreadResolved }: {
      target?: AgentV2ChatTarget; onThreadResolved: (threadId: string) => void;
    }) {
      messages = useAgentV2Messages({ isActive: true, target, lang: useLang(), onThreadResolved });
      return undefined;
    }
    function openDiscussion() {
      const entry = mockFeedItems[0];
      if (entry.kind === 'digest') FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion(entry.id);
      else FeedMock.mock.calls.at(-1)![0].onOpenDiscussion(entry);
    }
    function getCreationCount() {
      return callApiMock.mock.calls.filter(([method]) => method === 'createAgentV2Thread').length;
    }

    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    openDiscussion();
    expect(await waitFor(() => messages?.isSendDisabled === false, 10, 300)).toBe(true);
    messages!.sendMessage('Question before the history');
    expect(await waitFor(() => messages?.hasPendingQuestion === true && getCreationCount() === 1, 10, 300))
      .toBe(true);
    ChatMock.mock.calls.at(-1)![0].onBack!();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].isActive === false, 10, 300)).toBe(true);
    await rafPromise();

    messages = undefined;
    creation.resolve();
    expect(await waitFor(() => historyReads === 1 && Boolean(mockFeedItems[0].discussion), 10, 300)).toBe(true);
    await rafPromise();
    openDiscussion();
    expect(await waitFor(() => messages?.isConsentAccepted === true, 10, 300)).toBe(true);
    await pause(50);
    expect(ChatMock.mock.calls.at(-1)![0].target).not.toHaveProperty('shouldDeferCreation');
    expect(messages!.messages.filter(({ isOutgoing }) => isOutgoing)).toEqual([
      expect.objectContaining({ text: 'Question before the history' }),
    ]);
    expect(getCreationCount()).toBe(1);
    expect(callApiMock).not.toHaveBeenCalledWith('startAgentV2Run', expect.anything());

    senderHistory.resolve();
    expect(await waitFor(() => callApiMock.mock.calls.some(([method]) => method === 'startAgentV2Run'), 10, 300))
      .toBe(true);
    await pause(50);
    const sends = callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run');
    expect(sends).toHaveLength(1);
    expect(sends[0][1]).toMatchObject({
      threadId: 'created-thread', input: { kind: 'append', text: 'Question before the history' },
    });
    expect(getCreationCount()).toBe(1);
    run.resolve({ clientRunId: 'opening-run', state: 'completed' });
  });

  it.each([
    { threadId: undefined, isListed: false, isContinued: false },
    { threadId: 'digest-thread', isListed: true, isContinued: false },
    { threadId: 'digest-thread', isListed: false, isContinued: false },
    { threadId: 'digest-thread', isListed: true, isContinued: true },
  ])('opens a digest by id or its existing discussion: %o', async ({ threadId, isListed, isContinued }) => {
    const digestPreview = {
      id: 'digest-1', windowEnd: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }],
    };
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1,
      top: [{ eventId: 7, headline: 'News' }], ...(threadId && { discussion: { threadId } }),
    }];
    if (threadId && isListed) {
      mockThreadListItems = [{ thread: {
        id: threadId, revision: 1, messageCount: isContinued ? 3 : 1, digest: digestPreview,
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
    expect(ChatMock.mock.calls.at(-1)![0].target).toHaveProperty(
      'digestPreview', isContinued ? undefined : digestPreview,
    );
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
    feedProps.onOpenNewsDiscussion(7, 'digest-1');
    await rafPromise();
    await rafPromise();

    expect(new Set(ChatMock.mock.calls.map(([props]) => props.chatKey))).toEqual(new Set([chatKey]));
    // The chat shows the digest's post from the feed's copy of it until its thread comes
    expect(ChatMock.mock.calls.at(-1)![0].target).toEqual({
      kind: 'digest',
      digest: { id: 'digest-1' },
      digestPreview: {
        id: 'digest-1', windowEnd: '2026-10-21T12:00:00.000Z', total: 1, top: [{ eventId: 7, headline: 'News' }],
      },
      shouldDeferCreation: true,
    });
  });

  it('opens a headline from the digest preview before its thread resolves', async () => {
    const creation = new Deferred<undefined>();
    const { AgentV2Classic: Classic } = jest.requireActual<typeof import('./AgentV2Classic')>('./AgentV2Classic');
    const shellSpy = jest.spyOn(AgentConversationShellModule, 'default').mockImplementation(({ conversation }) => (
      <div>
        {conversation.messages.map((message) => conversation.renderMessage(message, {
          shouldAnimateTextStreaming: false,
          isJustAdded: false,
          onEditMessage: jest.fn(),
          onTextRevealProgress: jest.fn(),
          onRequestLiveTail: jest.fn(),
        }))}
      </div>
    ));
    ChatMock.mockImplementation((props) => props.isActive ? <Classic {...props} animationLevel={0} /> : undefined);
    callApiMock.mockImplementation(((method: string) => {
      if (method === 'createAgentV2Thread') return creation.promise;
      return Promise.resolve(method === 'getAgentV2Consent' ? true : undefined);
    }) as never);
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }],
    }];
    try {
      await mountChats();
      jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
      expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
      FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
      expect(await waitFor(() => Boolean(root.querySelector('[data-agent-news-digest-headline="7"]')), 10, 300))
        .toBe(true);
      await pause(50);
      expect(callApiMock).not.toHaveBeenCalledWith('createAgentV2Thread', expect.anything());
      expect(getAgentV2LocalState().openChatOnMount?.threadId).toBeUndefined();

      root.querySelector<HTMLButtonElement>('[data-agent-news-digest-headline="7"]')!.click();
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)![0].target?.kind === 'news', 10, 300)).toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].target).toMatchObject({
        kind: 'news', news: { eventId: 7, locale: 'en' },
      });
    } finally {
      await unmount();
      shellSpy.mockRestore();
    }
  });

  it.each([false, true])('returns from a digest headline to its discussion, remount: %s', async (shouldRemount) => {
    mockFeedLocale = 'ru';
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }],
    }];
    callApiMock.mockResolvedValue(false);
    ChatMock.mockImplementation(({ target }) => (
      target?.kind === 'digest' ? <button type="button" data-agent-news-digest-headline="7" /> : undefined
    ));
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const digestChat = ChatMock.mock.calls.at(-1)![0];

    digestChat.onOpenDigestNews!(7, 'digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)![0].target?.kind === 'news', 10, 300)).toBe(true);
    const newsChat = ChatMock.mock.calls.at(-1)![0];
    expect(newsChat.target).toMatchObject({ kind: 'news', news: { eventId: 7, locale: 'ru' } });
    // The digest's discussion stays under it
    expect(ChatMock.mock.calls.slice(-2).some(([props]) => props.chatKey === digestChat.chatKey)).toBe(true);

    if (shouldRemount) {
      expect(await waitFor(() => (
        getAgentV2LocalState().openChatOnMount?.key === newsChat.chatKey
        && getAgentV2LocalState().openParentChatOnMount?.key === digestChat.chatKey
      ), 10, 300)).toBe(true);
      await unmount();
      ChatMock.mockClear();
      await mountChats();
      expect(await waitFor(() => (
        ChatMock.mock.calls.some(([props]) => props.isActive && props.chatKey === newsChat.chatKey)
      ), 10, 300)).toBe(true);
      expect(getAgentV2LocalState().openParentChatOnMount?.key).toBe(digestChat.chatKey);
    }
    (document.activeElement as HTMLElement | null)?.blur();
    const activeNewsChat = ChatMock.mock.calls.filter(([props]) => props.isActive).at(-1)![0];
    activeNewsChat.onBack!();
    expect(await waitFor(
      () => document.activeElement?.getAttribute('data-agent-news-digest-headline') === '7', 10, 300,
    )).toBe(true);
    const lastChats = ChatMock.mock.calls.slice(-2).map(([props]) => props);
    expect(lastChats.find(({ chatKey }) => chatKey === digestChat.chatKey)!.isActive).toBe(true);
    expect(lastChats.find(({ chatKey }) => chatKey === newsChat.chatKey)?.isActive).not.toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].isActive).toBe(false);
    lastChats.find(({ chatKey }) => chatKey === digestChat.chatKey)!.onOpenDigestNews!(7, 'digest-1');
    expect(await waitFor(() => (
      ChatMock.mock.calls.some(([props]) => props.isActive && props.chatKey! > newsChat.chatKey!)
    ), 10, 300)).toBe(true);
  });

  it('opens a headline of the digest\'s post in the app\'s language before the feed has loaded', async () => {
    mockFeedLocale = undefined;
    mockFeedItems = [{
      kind: 'digest', id: 'digest-1', deliveredAt: TIMESTAMP, total: 1, top: [{ eventId: 7, headline: 'News' }],
    }];
    callApiMock.mockResolvedValue(false);
    await mountChats();
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    FeedMock.mock.calls.at(-1)![0].onOpenDigestDiscussion('digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);

    ChatMock.mock.calls.at(-1)![0].onOpenDigestNews!(7, 'digest-1');
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)![0].target?.kind === 'news', 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].target).toMatchObject({ kind: 'news', news: { eventId: 7, locale: 'en' } });
  });

  it('opens the discussion a news link asks for as it shows, in place of a discussion, and over the feed', async () => {
    mockFeedLocale = undefined;
    setGlobal({ ...getGlobal(), agentNewsDiscussionRequest: { eventId: 7 } });
    await mountChats();
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'news', 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].target).toMatchObject({ kind: 'news', news: { eventId: 7, locale: 'en' } });
    expect(getGlobal().agentNewsDiscussionRequest).toBeUndefined();

    setGlobal({ ...getGlobal(), agentNewsDiscussionRequest: { eventId: 8 } });
    expect(await waitFor(() => {
      const target = ChatMock.mock.calls.at(-1)![0].target;
      return target?.kind === 'news' && target.news.eventId === 8;
    }, 10, 300)).toBe(true);
    expect(getGlobal().agentNewsDiscussionRequest).toBeUndefined();

    // The feed shows its news in its own language, apart from the app's, and a link opens a discussion over it in that
    // language
    ChatMock.mock.calls.at(-1)![0].onBack!();
    mockFeedLocale = 'ru';
    expect(await waitFor(() => jest.mocked(AgentNewsRow).mock.calls.length > 0, 10, 300)).toBe(true);
    jest.mocked(AgentNewsRow).mock.calls.at(-1)![0].onClick();
    expect(await waitFor(() => FeedMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(FeedMock.mock.calls.at(-1)![0].locale).toBe('ru');
    const feedRenderCount = FeedMock.mock.calls.length;
    setGlobal({ ...getGlobal(), agentNewsDiscussionRequest: { eventId: 9 } });
    expect(await waitFor(() => {
      const target = ChatMock.mock.calls.at(-1)![0].target;
      return target?.kind === 'news' && target.news.eventId === 9;
    }, 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0].target).toMatchObject({ news: { eventId: 9, locale: 'ru' } });
    // The feed stays under the discussion
    expect(FeedMock.mock.calls.slice(feedRenderCount).some(([props]) => !props.isActive)).toBe(true);
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

  it.each([
    ['list', false], ['list', true], ['open chat', false], ['open chat', true],
  ] as const)('holds a queued chat deleted from %s until server responds: success=%s', async (source, isSuccess) => {
    const thread = buildListItem('delete-thread').thread;
    mockThreadListItems = [{ thread }];
    const deletion = new Deferred<{ ok: true } | undefined>();
    const firstRun = new Deferred<AgentV2RunResult>();
    const secondRun = new Deferred<AgentV2RunResult>();
    const thirdRun = new Deferred<AgentV2RunResult>();
    const runs = [firstRun.promise, secondRun.promise, thirdRun.promise];
    callApiMock.mockImplementation(((method: string) => {
      switch (method) {
        case 'deleteAgentV2Thread': return deletion.promise;
        case 'getAgentV2Consent': return Promise.resolve(true);
        case 'getAgentV2Messages': return Promise.resolve({ ok: true, value: { thread, messages: [] } });
        case 'updateAgentV2HostContext':
          return Promise.resolve({ ok: true, value: { authorityChanged: false, generation: 1 } });
        case 'startAgentV2Run': return runs.shift();
        default: return Promise.resolve(undefined);
      }
    }) as never);
    let messages: UseAgentV2MessagesResult | undefined;
    ChatMock.mockImplementation(({ isActive, target }) => isActive ? <ChatHarness target={target} /> : undefined);
    function ChatHarness({ target }: { target?: AgentV2ChatTarget }) {
      messages = useAgentV2Messages({ isActive: true, target, lang: useLang() });
      return undefined;
    }
    function getStartedTexts() {
      return callApiMock.mock.calls.filter(([method]) => method === 'startAgentV2Run')
        .map(([, command]) => (command as { input: { text: string } }).input.text);
    }

    await mountChats();
    jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onSelect(thread.id);
    expect(await waitFor(() => messages?.isInitialLoadComplete === true, 10, 300)).toBe(true);
    messages!.sendMessage('Question');
    messages!.sendMessage('Next question');
    messages!.sendMessage('Last question');
    expect(await waitFor(() => messages?.queuedMessageCount === 2 && getStartedTexts().length === 1, 10, 300))
      .toBe(true);
    if (source === 'list') {
      ChatMock.mock.calls.at(-1)![0].onBack!();
      expect(await waitFor(() => getAgentV2LocalState().backgroundQueues.has(thread.id), 10, 100)).toBe(true);
      jest.mocked(AgentThreadListItem).mock.calls.at(-1)![0].onDelete(thread);
    } else {
      ChatMock.mock.calls.at(-1)![0].onDelete!(thread, messages!.cancelPendingRequests);
    }
    expect(await waitFor(() => jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)?.[0].isOpen === true, 10, 300))
      .toBe(true);
    jest.mocked(DeleteAgentChatModal).mock.calls.at(-1)![0].onConfirm(thread);
    expect(await waitFor(() => getAgentV2LocalState().backgroundQueues.has(thread.id), 10, 100)).toBe(true);

    firstRun.resolve({ clientRunId: 'first-run', state: 'completed' });
    await pause(60);
    expect(getStartedTexts()).toEqual(['Question']);
    expect(getAgentV2LocalState().backgroundQueues.has(thread.id)).toBe(true);

    deletion.resolve(isSuccess ? { ok: true } : undefined);
    if (isSuccess) {
      expect(await waitFor(() => mockRemoveThread.mock.calls.length === 1, 10, 1000)).toBe(true);
      await pause(60);
      expect(getStartedTexts()).toEqual(['Question']);
      expect(getAgentV2LocalState().backgroundQueues.has(thread.id)).toBe(false);
    } else {
      expect(await waitFor(() => mockShowError.mock.calls.length === 1 && getStartedTexts().length === 2, 10, 300))
        .toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question']);
      secondRun.resolve({ clientRunId: 'second-run', state: 'completed' });
      expect(await waitFor(() => getStartedTexts().length === 3, 10, 300)).toBe(true);
      expect(getStartedTexts()).toEqual(['Question', 'Next question', 'Last question']);
      thirdRun.resolve({ clientRunId: 'third-run', state: 'completed' });
    }
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

  it.each([false, true])('keeps the opening question across remounts until accepted: support=%s', async (
    shouldRequestSupport,
  ) => {
    if (shouldRequestSupport) {
      getAgentV2LocalState().openChatOnMount = { key: 1, target: { kind: 'new' }, shouldRequestSupport: true };
    }
    await mountChats();
    if (!shouldRequestSupport) {
      InputBarMock.mock.calls.at(-1)![0].onInput('What is TON?');
      expect(await waitFor(() => InputBarMock.mock.calls.at(-1)?.[0].inputValue === 'What is TON?', 10, 300))
        .toBe(true);
      InputBarMock.mock.calls.at(-1)![0].onSend();
    }
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    const chatProps = ChatMock.mock.calls.at(-1)![0];
    chatProps.onThreadResolved!(chatProps.chatKey!, 'new-thread');
    expect(await waitFor(() => getAgentV2LocalState().openChatOnMount?.threadId === 'new-thread', 10, 300)).toBe(true);
    ChatMock.mockClear();
    await remountChats();

    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].target?.kind === 'thread', 10, 300)).toBe(true);
    expect(ChatMock.mock.calls.at(-1)![0]).toMatchObject({
      target: { kind: 'thread', threadId: 'new-thread' },
      ...(shouldRequestSupport ? { shouldRequestSupport: true } : { initialMessage: 'What is TON?' }),
    });

    const sendMessage = jest.fn();
    ChatMock.mockImplementation(function Chat({ initialMessage, shouldRequestSupport, onInitialMessageSent, chatKey }) {
      useEffect(() => {
        if (!initialMessage && !shouldRequestSupport) return;
        sendMessage(shouldRequestSupport ? '$agent_support_request_message' : initialMessage);
        onInitialMessageSent?.(chatKey!);
      }, [chatKey, initialMessage, onInitialMessageSent, shouldRequestSupport]);
      return undefined;
    });
    await remountChats();
    expect(await waitFor(() => sendMessage.mock.calls.length === 1, 10, 100)).toBe(true);
    expect(sendMessage).toHaveBeenCalledWith(shouldRequestSupport ? '$agent_support_request_message' : 'What is TON?');
    expect(sendMessage).toHaveBeenCalledTimes(1);
    expect(getAgentV2LocalState().openChatOnMount?.shouldRequestSupport).toBeUndefined();
    ChatMock.mockClear();
    await remountChats();
    expect(await waitFor(() => ChatMock.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === undefined, 10, 300)).toBe(true);
    await rafPromise();
    expect(ChatMock.mock.calls.at(-1)![0].initialMessage).toBeUndefined();
    expect(ChatMock.mock.calls.at(-1)![0].shouldRequestSupport).toBeUndefined();
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
      jest.mocked(useAgentSuggestions).mockReturnValue({ starterHints: SWAP_STARTER_HINTS, hints: [SWAP_HINT] });
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
      expect(await waitFor(() => ChatMock.mock.calls.at(-1)?.[0].initialMessage === 'Swap tokens', 10, 300))
        .toBe(true);
      expect(ChatMock.mock.calls.at(-1)![0].initialHintEntryPoint).toEqual(SWAP_HINT_ENTRY_POINT);
      expect(getOpenedQuestions()).toEqual(['Swap tokens']);
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
