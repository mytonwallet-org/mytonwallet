import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { removeExtraClass, toggleExtraClass } from '../../lib/teact/teact-dom';
import { getActions } from '../../global';

import type {
  AgentNewsFeedItemV2,
  AgentThreadListItemV2,
  AgentThreadSummaryV2,
} from '../../api/agentV2/protocol/types';
import type { ChatSelection, FeedSelection } from '../../util/agent/agentV2LocalState';
import type { AgentConversationSessionStore } from '../agent/AgentConversationShell';
import type { AgentV2ChatTarget } from '../agent/hooks/useAgentV2Messages';

import { IS_EXTENSION } from '../../config';
import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import { forgetRecentAgentChat, getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { subscribeToAgentV2RuntimeReady } from '../../util/agentV2Updates';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { pause } from '../../util/schedulers';
import { captureControlledSwipe } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import { IS_ANDROID, IS_TOUCH_ENV } from '../../util/windowEnvironment';
import windowSize from '../../util/windowSize';
import { callApi } from '../../api';
import { getIsAgentV2ThreadStarted } from '../../api/agentV2/threadStarted';
import getCanAnimate from '../agent/helpers/getCanAnimate';
import { getSnapEffectKind, getSnapGapCloseDelay } from '../agent/helpers/snapEffect';
import { startAgentNewsCardFlight } from './agentNewsCardFlight';
import { buildAgentNewsPreviewCard } from './agentNewsFeedItems';
import { getAgentThreadUnreadStart, markAgentThreadHidden, markAgentThreadShown } from './agentThreadReadState';
import useAgentNewsFeed from './useAgentNewsFeed';
import useAgentV2ThreadList from './useAgentV2ThreadList';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';

import Transition from '../ui/Transition';
import AgentNewsFeed from './AgentNewsFeed';
import AgentThreadList from './AgentThreadList';
import AgentV2Classic from './AgentV2Classic';
import { AgentV2ConsentSheet } from './AgentV2Conversation';
import DeleteAgentChatModal from './DeleteAgentChatModal';
import RenameAgentChatModal from './RenameAgentChatModal';

import styles from './AgentV2Chats.module.scss';

interface OwnProps {
  isActive: boolean;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
}

/**
 * The screens of the stack, bottom to top: the chat list; a chat or the news feed pushed over it; the discussion of a
 * news item pushed over the feed
 */
enum StackLevel {
  List,
  Pushed,
  OverFeed,
}

const STACK_LEVEL_COUNT = 3;
// A swipe that starts on a table or a code block of an answer scrolls it
const SWIPE_EXCLUDED_SELECTOR = '[data-agent-v2-message-role] pre, [data-agent-v2-message-role] table';
// The platform's own push on Android, as on its other screens; the iOS-like layers elsewhere, as on iPad
const STACK_TRANSITION_NAME = IS_ANDROID ? 'slideFadeAndroid' : 'slideLayers';
// Before consent the list has no chats to load, and shows what an allowed user without chats sees
const NO_THREADS: AgentThreadListItemV2[] = [];
const NO_THREAD_IDS: ReadonlySet<string> = new Set();
// How many frames the focus waits for a screen to show what takes it
const RETURN_FOCUS_FRAMES = 10;
// The longest the consent sheet waits for the keyboard to go, past the window's size updates, which come 250 ms apart
const KEYBOARD_HIDE_TIMEOUT_MS = 600;

function AgentV2Chats({ isActive, onScroll }: OwnProps) {
  const localState = useRef(getAgentV2LocalState()).current;
  const { showError, switchToWallet } = getActions();
  const lang = useLang();
  const stackRef = useRef<HTMLDivElement>();
  // Continues from the chat kept across a remount, so that the next chat gets a key of its own
  const chatKeyRef = useRef(localState.openChatOnMount?.key ?? 0);
  const feedKeyRef = useRef(localState.openFeedOnMount?.key ?? 0);
  const [isConsentAccepted, setIsConsentAccepted] = useState(takeSwitchedLayoutConsent);
  const [chat, setChat] = useState<ChatSelection | undefined>(() => localState.openChatOnMount);
  const [feed, setFeed] = useState<FeedSelection | undefined>(() => localState.openFeedOnMount);
  const [renamingThread, setRenamingThread] = useState<AgentThreadSummaryV2 | undefined>();
  const [deletingThread, setDeletingThread] = useState<AgentThreadSummaryV2 | undefined>();
  const [deletingOpeningChatKey, setDeletingOpeningChatKey] = useState<number>();
  const pendingDeletionKeys = useRef(new Set<number>()).current;
  const deletingChatRef = useRef<{ key: number; cancelPendingRequests: () => Promise<string | undefined> }>();
  // Requests of the chats being deleted, so that a chat is deleted once however often it is asked
  const deletingThreadIds = useRef(new Set<string>()).current;
  // The chats whose rows turn to dust in the list while their deletion runs
  const [dissolvingThreadIds, setDissolvingThreadIds] = useState<ReadonlySet<string>>(NO_THREAD_IDS);
  // The screens a swipe back left, which come back if the swipe is cancelled
  const swipedScreensRef = useRef<{ chat?: ChatSelection; feed?: FeedSelection }>();
  // After going back, the focus moves to the element that opened the closed screen: a chat's row or the News row in
  // the list, or the news card in the feed whose discussion was closed
  const returnFocusRef = useRef<{ level: StackLevel; selector: string }>();
  // A chat started while composing one under the list comes in place of the list instead of sliding over it
  const [isInPlacePush, setIsInPlacePush] = useState(false);
  // The chats the Agent answered in while open here, as news discussions the user has written in
  const [answeredThreadIds, setAnsweredThreadIds] = useState<Set<string>>(() => new Set());
  // Before consent the feed and its discussions open as they do after it, and chats wait for it
  const activeLevel = feed
    ? (chat ? StackLevel.OverFeed : StackLevel.Pushed)
    : (chat ? StackLevel.Pushed : StackLevel.List);
  const canGoBack = activeLevel !== StackLevel.List;
  // Telegram's own swipe would close the Mini App in place of the swipe back
  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose(isActive && canGoBack);

  const {
    items, isUserChange, isCacheShown, hasMore, hasLoadFailed, hasPageLoadFailed, isRetrying, activityLangKeys,
    loadMore, retry, removeThread, setThreadPinned, syncLoadedChat, releaseLoadedChat, scheduleRefresh,
  } = useAgentV2ThreadList({
    isEnabled: isConsentAccepted === true,
    isVisible: isActive && activeLevel === StackLevel.List,
  });
  // The feed needs no consent, only the SDK, which answers once the list knows the consent
  const newsFeed = useAgentNewsFeed({
    isEnabled: isConsentAccepted !== undefined,
    isActive,
    langCode: lang.code ?? 'en',
    isFeedVisible: isActive && Boolean(feed) && !chat,
  });

  useEffect(() => {
    localState.openChatOnMount = chat && rememberChat(chat);
    // A chat the user has left keeps nothing for later
    if (!chat) localState.chatSessionOnMount = undefined;
  }, [chat, localState]);

  useEffect(() => {
    localState.openFeedOnMount = feed;
    if (!feed) localState.feedSessionOnMount = undefined;
  }, [feed, localState]);

  useAgentLayoutSwitch(() => {
    localState.isConsentAcceptedOnSwitch = isConsentAccepted;
  }, isActive);

  const chatKey = chat?.key;
  const chatSession = useMemo<AgentConversationSessionStore | undefined>(() => (chatKey === undefined ? undefined : {
    initial: localState.chatSessionOnMount?.chatKey === chatKey ? localState.chatSessionOnMount.session : undefined,
    save: (session) => {
      if (localState.openChatOnMount?.key === chatKey) localState.chatSessionOnMount = { chatKey, session };
    },
  }), [chatKey, localState]);
  // The feed opens again where it was, as a chat does, as the app switches layouts, and as the user comes back to it from
  // a discussion, as on mobile
  const feedKey = feed?.key;
  const feedSession = useMemo<AgentConversationSessionStore | undefined>(() => (feedKey === undefined ? undefined : {
    // Read as the feed mounts, which it does again under a discussion that goes away
    get initial() {
      return localState.feedSessionOnMount?.feedKey === feedKey ? localState.feedSessionOnMount.session : undefined;
    },
    save: (session) => {
      if (localState.openFeedOnMount?.key === feedKey) localState.feedSessionOnMount = { feedKey, session };
    },
    shouldKeepPlaceOffScreen: true,
  }), [feedKey, localState]);

  // The app takes the agent's background while the section is on screen
  useLayoutEffect(() => {
    toggleExtraClass(document.documentElement, 'is-agent-active', isActive);

    return () => {
      removeExtraClass(document.documentElement, 'is-agent-active');
    };
  }, [isActive]);

  // The chat on screen is read, and its answers do not mark it
  const shownThreadId = isActive && !chat?.isUnreadStateUnknown ? chat?.threadId : undefined;
  useEffect(() => {
    if (!shownThreadId) return undefined;

    markAgentThreadShown(shownThreadId);
    return () => markAgentThreadHidden(shownThreadId);
  }, [shownThreadId]);

  const openThreadId = chat?.threadId;
  useEffect(() => {
    if (!openThreadId) return undefined;

    return () => releaseLoadedChat(openThreadId);
  }, [openThreadId, releaseLoadedChat]);

  function createChat(
    target: AgentV2ChatTarget,
    options: Pick<ChatSelection, 'initialMessage' | 'newsEventId'> = {},
  ): ChatSelection {
    chatKeyRef.current += 1;
    const threadId = target.kind === 'thread' ? target.threadId : undefined;
    const thread = threadId ? findListThread(threadId) : undefined;
    // A chat the list marks as unread opens at the first message the user has not seen
    const isUnreadStateUnknown = isCacheShown && Boolean(thread);
    const unreadStart = !isUnreadStateUnknown && thread ? getAgentThreadUnreadStart(thread) : undefined;
    return {
      key: chatKeyRef.current, target, threadId, thread, isUnreadStateUnknown,
      ...(unreadStart !== undefined && { unreadStart }), ...options,
    };
  }

  const openChat = useLastCallback((
    target: AgentV2ChatTarget,
    options: Pick<ChatSelection, 'initialMessage' | 'newsEventId'> = {},
  ) => {
    setChat(createChat(target, options));
  });

  const openFeed = useLastCallback(() => {
    feedKeyRef.current += 1;
    setFeed({ key: feedKeyRef.current });
  });

  const goBack = useLastCallback(() => {
    if (!chat) {
      setFeed(undefined);
      returnFocusRef.current = { level: StackLevel.List, selector: '[data-agent-news-row]' };
      return;
    }

    setChat(undefined);
    // The feed under a discussion comes back where it was left, with the focus on the news the discussion is about
    if (feed && chat.newsEventId !== undefined) {
      returnFocusRef.current = {
        level: StackLevel.Pushed,
        selector: `[data-agent-news-event-id="${chat.newsEventId}"] [data-agent-news-discuss]`,
      };
    } else if (!feed && chat.threadId) {
      returnFocusRef.current = {
        level: StackLevel.List, selector: `[data-agent-v2-thread-id="${CSS.escape(chat.threadId)}"]`,
      };
    }
  });

  useEffect(() => {
    const returnFocus = returnFocusRef.current;
    if (!isActive || !returnFocus || activeLevel !== returnFocus.level) return;

    returnFocusRef.current = undefined;
    focusOnReturn(stackRef, returnFocus.selector);
  }, [activeLevel, isActive]);

  useEffect(() => {
    if (!isActive || isConsentAccepted !== undefined) return undefined;

    let isCurrent = true;
    // Asked again once the SDK is ready: before that the question has no answer
    const checkConsent = () => {
      void callApi('getAgentV2Consent').then((isAccepted) => {
        if (!isCurrent || typeof isAccepted !== 'boolean') return;
        setIsConsentAccepted(isAccepted);
      });
    };
    const unsubscribe = subscribeToAgentV2RuntimeReady(checkConsent);
    checkConsent();
    return () => {
      isCurrent = false;
      unsubscribe();
    };
  }, [isActive, isConsentAccepted]);

  // Back from the list leaves the agent; a chat or the feed opened over the list handles back itself
  useHistoryBack({
    isActive: isActive && activeLevel === StackLevel.List && isConsentAccepted !== undefined,
    onBack: switchToWallet,
  });

  useEffect(() => {
    if (!isActive || !canGoBack) return undefined;

    return captureKeyboardListeners({
      onEsc: { handler: goBack, shouldPreventDefault: IS_EXTENSION },
    });
  }, [canGoBack, goBack, isActive]);

  const handleSwipeBack = useLastCallback(() => {
    if (!canGoBack) return;

    swipedScreensRef.current = { chat, feed };
    disableSwipeToClose();
    goBack();
  });

  const handleSwipeCancel = useLastCallback(() => {
    const swipedScreens = swipedScreensRef.current;
    swipedScreensRef.current = undefined;
    if (swipedScreens) {
      setChat(swipedScreens.chat);
      setFeed(swipedScreens.feed);
    }
    enableSwipeToClose();
  });

  // The capture outlives the screens a swipe changes, so that the gesture it follows goes on. The list itself has
  // nothing to go back to, and its rows have swipe actions of their own.
  useEffect(() => {
    if (!IS_TOUCH_ENV || !isActive) return undefined;

    // A pushed screen comes in from the inline end, so going back follows the finger toward it
    return captureControlledSwipe(stackRef.current!, {
      ...(lang.isRtl ? { onSwipeLeftStart: handleSwipeBack } : { onSwipeRightStart: handleSwipeBack }),
      onCancel: handleSwipeCancel,
      excludedSelector: SWIPE_EXCLUDED_SELECTOR,
    });
  }, [handleSwipeBack, handleSwipeCancel, isActive, lang.isRtl]);

  const handleSelect = useLastCallback((threadId: string) => {
    openChat({ kind: 'thread', threadId });
  });

  const handleStartChat = useLastCallback((text: string, isInPlace: boolean) => {
    openChat({ kind: 'new' }, { initialMessage: text });
    setIsInPlacePush(isInPlace);
  });

  // The stack takes the cross-fade for this one push; going back slides as usual
  useEffect(() => {
    if (isInPlacePush) setIsInPlacePush(false);
  }, [isInPlacePush]);

  const handleAnswerChange = useLastCallback((threadId: string, activityLangKey: string | undefined) => {
    syncLoadedChat(threadId, activityLangKey);
    if (activityLangKey && !answeredThreadIds.has(threadId)) {
      setAnsweredThreadIds(new Set(answeredThreadIds).add(threadId));
    }
  });

  // A news card offers to continue its discussion once the user has written in it
  const continuedThreadIds = useMemo(() => {
    const threadIds = new Set(answeredThreadIds);
    items?.forEach(({ thread }) => {
      if (getIsAgentV2ThreadStarted(thread)) threadIds.add(thread.id);
    });
    return threadIds;
  }, [answeredThreadIds, items]);

  const handleOpenNews = useLastCallback(() => {
    if (feed) return;
    newsFeed.startReading();
    newsFeed.refresh();
    openFeed();
  });

  const handleOpenNewsDiscussion = useLastCallback((
    eventId: number, item?: AgentNewsFeedItemV2, cardElement?: HTMLElement,
  ) => {
    // Taps on the feed while a discussion slides in over it are ignored
    if (chat || !newsFeed.locale) return;

    const discussion = item?.discussion;
    const threadId = discussion?.threadId;
    const isContinued = Boolean(threadId && continuedThreadIds.has(threadId));
    // The card flies into a discussion the user has not written in, which starts with the news post alone. The
    // feed's copy of the news shows that post, under its name and date, from the first frame, as it lands.
    if (cardElement && !isContinued && getCanAnimate()) {
      startAgentNewsCardFlight(cardElement, eventId);
    }
    const preview = item && !isContinued ? buildAgentNewsPreviewCard(item) : undefined;
    // A listed discussion opens by its thread; other discussions resolve through their news identity
    if (threadId && findListThread(threadId)) {
      openChat({ kind: 'thread', threadId, preview, isNews: true }, { newsEventId: eventId });
      return;
    }
    openChat({
      kind: 'news',
      news: { eventId, locale: newsFeed.locale },
      preview,
    }, { newsEventId: eventId });
  });

  const handleOpenDiscussion = useLastCallback((item: AgentNewsFeedItemV2, cardElement?: HTMLElement) => {
    handleOpenNewsDiscussion(item.eventId, item, cardElement);
  });

  const handleOpenDigestNews = useLastCallback((eventId: number) => {
    const item = newsFeed.items?.find((entry) => entry.kind === 'news' && entry.eventId === eventId);
    handleOpenNewsDiscussion(eventId, item?.kind === 'news' ? item : undefined);
  });

  const handleOpenDigestDiscussion = useLastCallback((id: string) => {
    if (chat) return;
    const digest = newsFeed.items?.find((entry) => entry.kind === 'digest' && entry.id === id);
    const threadId = digest?.discussion?.threadId;
    if (threadId && findListThread(threadId)) {
      openChat({ kind: 'thread', threadId, isNews: true });
      return;
    }
    openChat({ kind: 'digest', digest: { id } });
  });

  // A chat reports its thread by its key, so a chat sliding away cannot rename the one that replaced it. A chat that a
  // swipe back is taking away keeps the thread in case the swipe is cancelled and the chat comes back.
  const handleThreadResolved = useLastCallback((key: number, threadId: string) => {
    if (pendingDeletionKeys.has(key)) return;

    const swipedScreens = swipedScreensRef.current;
    const swipedChat = swipedScreens?.chat?.key === key ? swipedScreens.chat : undefined;
    const selection = chat?.key === key ? chat : swipedChat;
    if (!selection) return;

    if (swipedChat) swipedScreensRef.current = { ...swipedScreens, chat: { ...swipedChat, threadId } };
    setChat((current) => (current?.key === key ? { ...current, threadId } : current));
    if (selection.target.kind === 'news') newsFeed.markDiscussion(selection.target.news.eventId, { threadId });
    if (selection.target.kind === 'digest') newsFeed.markDigestDiscussion(selection.target.digest.id, { threadId });
  });

  const handleInitialMessageSent = useLastCallback((key: number) => {
    if (localState.openChatOnMount?.key === key) {
      localState.openChatOnMount = { ...localState.openChatOnMount, initialMessage: undefined };
    }
    setChat((current) => (current?.key === key ? { ...current, initialMessage: undefined } : current));
  });

  // The "New" line stays at the same message when the chat mounts again, as after the app switches layouts
  const handleUnreadStartResolved = useLastCallback((key: number, unreadStart: number) => {
    setChat((current) => (current?.key === key ? { ...current, unreadStart } : current));
  });

  // The chat keeps its thread as last loaded, so that it opens again with its name, as after the app switches layouts
  const handleThreadLoaded = useLastCallback((thread: AgentThreadSummaryV2) => {
    setChat((current) => (
      current?.threadId === thread.id && (current.isUnreadStateUnknown || current.thread !== thread) ? {
        ...current,
        thread,
        unreadStart: current.isUnreadStateUnknown ? getAgentThreadUnreadStart(thread) : current.unreadStart,
        isUnreadStateUnknown: false,
      } : current
    ));
  });

  const handleThreadNotFound = useLastCallback(() => {
    const threadId = chat?.threadId;
    if (threadId) {
      forgetRecentAgentChat(threadId);
      removeThread(threadId);
      newsFeed.removeDiscussion(threadId);
    }
    goBack();
  });

  // The consent is asked in a sheet at the first thing the user does that sends something to the Agent, which waits
  // for Allow; closing the sheet drops it, and the next one asks again
  const [isConsentSheetOpen, setIsConsentSheetOpen] = useState(false);
  const [isAllowingConsent, setIsAllowingConsent] = useState(false);
  const consentActionRef = useRef<NoneToVoidFunction>();
  const consentDeclineRef = useRef<NoneToVoidFunction>();
  // The field a question was sent from, which gets its focus and keyboard back if the sheet closes without consent
  const consentFieldRef = useRef<HTMLElement>();

  const requestConsent = useLastCallback((
    action: NoneToVoidFunction, field?: HTMLElement, onDecline?: NoneToVoidFunction,
  ) => {
    if (isConsentAccepted) {
      action();
      return;
    }

    consentActionRef.current = action;
    consentFieldRef.current = field;
    consentDeclineRef.current = onDecline;
    // The keyboard goes before the sheet comes, so the whole sheet shows without moving under it
    const { activeElement } = document;
    if (!(activeElement instanceof HTMLElement) || !activeElement.matches('input, textarea')) {
      setIsConsentSheetOpen(true);
      return;
    }
    activeElement.blur();
    openAfterKeyboard(() => {
      if (consentActionRef.current === action) setIsConsentSheetOpen(true);
    });
  });

  const handleConsentClose = useLastCallback(() => {
    const onDecline = consentDeclineRef.current;
    consentActionRef.current = undefined;
    consentDeclineRef.current = undefined;
    setIsConsentSheetOpen(false);
    consentFieldRef.current?.focus();
    consentFieldRef.current = undefined;
    onDecline?.();
  });

  const handleConsentAllow = useLastCallback(async () => {
    if (isAllowingConsent) return;

    setIsAllowingConsent(true);
    const isAccepted = await callApi('acceptAgentV2Consent');
    setIsAllowingConsent(false);
    if (isAccepted !== true) {
      showError({ error: 'An error occurred' });
      return;
    }

    const action = consentActionRef.current;
    consentActionRef.current = undefined;
    consentDeclineRef.current = undefined;
    consentFieldRef.current = undefined;
    setIsConsentAccepted(true);
    setIsConsentSheetOpen(false);
    action?.();
  });

  // The row moves at once, and back if the server refuses
  const handleTogglePin = useLastCallback(async (thread: AgentThreadSummaryV2) => {
    const isPinned = !thread.isPinned;
    setThreadPinned(thread.id, isPinned);
    const result = await callApi('updateAgentV2Thread', thread.id, { isPinned });
    if (!result?.ok) {
      setThreadPinned(thread.id, Boolean(thread.isPinned));
      showError({ error: 'An error occurred' });
    }
    scheduleRefresh();
  });

  const handleRenameClose = useLastCallback(() => {
    setRenamingThread(undefined);
  });

  const handleRenameSave = useLastCallback(async (thread: AgentThreadSummaryV2, title: string) => {
    const result = await callApi('updateAgentV2Thread', thread.id, { title });
    if (!result?.ok) showError({ error: 'An error occurred' });
  });

  const handleDeleteClose = useLastCallback(() => {
    deletingChatRef.current = undefined;
    setDeletingThread(undefined);
    setDeletingOpeningChatKey(undefined);
  });

  const handleChatDelete = useLastCallback((
    thread: AgentThreadSummaryV2 | undefined,
    cancelPendingRequests: () => Promise<string | undefined>,
  ) => {
    if (!chat) return;
    deletingChatRef.current = { key: chat.key, cancelPendingRequests };
    setDeletingThread(thread);
    setDeletingOpeningChatKey(thread ? undefined : chat?.key);
  });

  const handleDeleteConfirm = useLastCallback((thread?: AgentThreadSummaryV2) => {
    const deletingChat = deletingChatRef.current;
    const deletingChatKey = deletingChat?.key;
    if (deletingChatKey !== undefined) pendingDeletionKeys.add(deletingChatKey);
    const pendingThreadId = deletingChat?.cancelPendingRequests();
    const id = thread?.id ?? (chat?.key === deletingOpeningChatKey ? chat?.threadId : undefined);
    handleDeleteClose();
    if (chat && (chat.key === deletingChatKey || (id && chat.threadId === id))) {
      localState.openChatOnMount = undefined;
      localState.chatSessionOnMount = undefined;
      goBack();
    }
    if (id) void deleteThread(id);
    void pendingThreadId?.then((resolvedId) => {
      pendingDeletionKeys.delete(deletingChatKey!);
      if (!id && resolvedId) void deleteThread(resolvedId);
    });
  });

  async function deleteThread(id: string) {
    if (deletingThreadIds.has(id)) return;

    deletingThreadIds.add(id);
    setDissolvingThreadIds((current) => new Set([...current, id]));
    // The chat's place holds while most of its dust drifts off, so the chats that stay don't run into it
    const closesGapAt = Date.now() + getSnapGapCloseDelay(getSnapEffectKind(getCanAnimate()));
    const result = await callApi('deleteAgentV2Thread', id).catch(() => undefined);
    if (result?.ok) await pause(Math.max(0, closesGapAt - Date.now()));
    deletingThreadIds.delete(id);
    if (result?.ok) handleThreadDeleted(id);
    setDissolvingThreadIds((current) => new Set([...current].filter((threadId) => threadId !== id)));
    if (!result?.ok) showError({ error: 'An error occurred' });
  }

  // Runs after the request, against the chat shown by then
  const handleThreadDeleted = useLastCallback((threadId: string) => {
    forgetRecentAgentChat(threadId);
    removeThread(threadId);
    newsFeed.removeDiscussion(threadId);
    if (chat?.threadId === threadId) goBack();
  });

  function findListThread(threadId: string) {
    return items?.find((item) => item.thread.id === threadId)?.thread;
  }

  function renderChat(selection: ChatSelection, isScreenActive: boolean) {
    return (
      <div key={`chat-${selection.key}`} className={styles.chat} inert={!isScreenActive}>
        <AgentV2Classic
          isActive={isActive && isScreenActive}
          chatKey={selection.key}
          target={selection.target}
          initialMessage={selection.initialMessage}
          initialThread={selection.thread}
          unreadStart={selection.unreadStart}
          isUnreadStateUnknown={selection.isUnreadStateUnknown}
          session={selection.key === chatKey ? chatSession : undefined}
          onInitialMessageSent={handleInitialMessageSent}
          onUnreadStartResolved={handleUnreadStartResolved}
          onScroll={onScroll}
          onBack={canGoBack ? goBack : undefined}
          onThreadResolved={handleThreadResolved}
          // Only the chat on screen reports what it loads. A chat that slides away stays mounted until its animation
          // ends, and the handlers would apply its thread to the chat that replaced it.
          onThreadLoaded={selection.key === chatKey ? handleThreadLoaded : undefined}
          onThreadNotFound={selection.key === chatKey ? handleThreadNotFound : undefined}
          onAnswerChange={handleAnswerChange}
          onDelete={handleChatDelete}
          hasConsent={Boolean(isConsentAccepted)}
          onRequestConsent={requestConsent}
        />
      </div>
    );
  }

  // The feed sits in a screen of its own, as a chat does, so the stack can lay it over the list while it slides in
  function renderFeed(selection: FeedSelection, isScreenActive: boolean) {
    return (
      <div key={`feed-${selection.key}`} className={styles.chat} inert={!isScreenActive}>
        <AgentNewsFeed
          isActive={isActive && isScreenActive}
          items={newsFeed.items}
          unreadEventId={newsFeed.unreadEventId}
          hasMore={newsFeed.hasMore}
          isLoading={newsFeed.isLoading}
          isLoadingMore={newsFeed.isLoadingMore}
          errorCode={newsFeed.errorCode}
          continuedThreadIds={continuedThreadIds}
          session={selection.key === feedKey ? feedSession : undefined}
          onBack={goBack}
          onRetry={newsFeed.refresh}
          onLoadMore={newsFeed.loadMore}
          onDigestReached={newsFeed.markDigestReached}
          onOpenDiscussion={handleOpenDiscussion}
          onOpenNewsDiscussion={handleOpenDigestNews}
          onOpenDigestDiscussion={handleOpenDigestDiscussion}
        />
      </div>
    );
  }

  function renderList(isScreenActive: boolean) {
    return (
      <AgentThreadList
        isActive={isActive && isScreenActive}
        items={isConsentAccepted ? items : NO_THREADS}
        isUserChange={isUserChange}
        dissolvingThreadIds={dissolvingThreadIds}
        hasMore={hasMore}
        hasLoadFailed={hasLoadFailed}
        hasPageLoadFailed={hasPageLoadFailed}
        isRetrying={isRetrying}
        activityLangKeys={activityLangKeys}
        latestNewsItem={newsFeed.latestItem}
        newsUnreadCount={newsFeed.unreadCount}
        isDictationHeld={!isConsentAccepted}
        onSelect={handleSelect}
        onOpenNews={handleOpenNews}
        onStartChat={handleStartChat}
        onRequestConsent={requestConsent}
        onLoadMore={loadMore}
        onRetry={retry}
        onRename={setRenamingThread}
        onTogglePin={handleTogglePin}
        onDelete={setDeletingThread}
      />
    );
  }

  // The screen of each level; a level that is not shown keeps the one it showed last, which an outgoing screen
  // needs for its animation
  function renderScreen(isScreenActive: boolean, _isFrom: boolean, level: StackLevel) {
    switch (level) {
      case StackLevel.List:
        return (
          <div className={styles.listLevel}>
            {renderList(isScreenActive)}
          </div>
        );
      case StackLevel.Pushed:
        if (feed) return renderFeed(feed, isScreenActive);
        return chat && renderChat(chat, isScreenActive);
      case StackLevel.OverFeed:
        return chat && renderChat(chat, isScreenActive);
    }
  }

  return (
    <div ref={stackRef} className={styles.root}>
      {isConsentAccepted !== undefined && (
        <Transition
          name={isInPlacePush ? 'fade' : STACK_TRANSITION_NAME}
          activeKey={activeLevel}
          renderCount={STACK_LEVEL_COUNT}
          shouldCleanup
          cleanupExceptionKey={StackLevel.List}
          withSwipeControl
          className={styles.stack}
        >
          {renderScreen}
        </Transition>
      )}
      <AgentV2ConsentSheet
        isOpen={isConsentSheetOpen}
        isAllowing={isAllowingConsent}
        onAllow={handleConsentAllow}
        onClose={handleConsentClose}
      />
      <RenameAgentChatModal
        thread={renamingThread}
        onClose={handleRenameClose}
        onSave={handleRenameSave}
      />
      <DeleteAgentChatModal
        thread={deletingThread}
        isOpen={Boolean(deletingThread) || deletingOpeningChatKey !== undefined}
        onClose={handleDeleteClose}
        onConfirm={handleDeleteConfirm}
      />
    </div>
  );
}

export default memo(AgentV2Chats);

/** Calls `callback` once the on-screen keyboard has gone, or at once without one, waiting no longer than it takes */
function openAfterKeyboard(callback: NoneToVoidFunction) {
  const startedAt = performance.now();
  requestAnimationFrame(function check() {
    if (windowSize.getIsKeyboardVisible() && performance.now() - startedAt < KEYBOARD_HIDE_TIMEOUT_MS) {
      requestAnimationFrame(check);
      return;
    }
    callback();
  });
}

/**
 * Focuses what `selector` finds once the screen shows it, as the feed shows its news once it has placed them. Focus that
 * moved on, as to the list's field, stays where it is.
 */
function focusOnReturn(stackRef: { current?: HTMLDivElement }, selector: string, frameCount = RETURN_FOCUS_FRAMES) {
  requestMeasure(() => {
    const { activeElement } = document;
    if (activeElement && activeElement !== document.body && activeElement.isConnected) return;

    const element = stackRef.current?.querySelector<HTMLElement>(selector);
    element?.focus({ preventScroll: true });
    if (document.activeElement !== element && frameCount > 1) focusOnReturn(stackRef, selector, frameCount - 1);
  });
}

function takeSwitchedLayoutConsent() {
  const localState = getAgentV2LocalState();
  const isAccepted = localState.isConsentAcceptedOnSwitch;
  localState.isConsentAcceptedOnSwitch = undefined;
  return isAccepted;
}

/** A chat reopens by its thread once known, keeping a question until it is sent */
function rememberChat({
  key, target, threadId, thread, initialMessage, newsEventId, unreadStart, isUnreadStateUnknown,
}: ChatSelection): ChatSelection {
  // A news discussion stays one on the thread it resolved, so that it loads before consent again
  const isNews = target.kind === 'news' || target.kind === 'digest' || (target.kind === 'thread' && target.isNews)
    || Boolean(thread?.news || thread?.digest);
  return {
    key,
    target: threadId ? { kind: 'thread', threadId, ...(isNews && { isNews }) } : target,
    threadId,
    thread,
    initialMessage,
    newsEventId,
    unreadStart,
    isUnreadStateUnknown,
  };
}
