import { useEffect, useRef, useState } from '../../lib/teact/teact';

import type { AgentThreadListItemV2, AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2OperationError } from '../../api/agentV2/types';

import { getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import { subscribeToAgentV2Updates } from '../../util/agentV2Updates';
import { getIsInBackground } from '../../util/backgroundMode';
import { callApi } from '../../api';
import { compareAgentThreadListItems, mergeAgentThreadListRefresh } from './agentThreadListSections';
import {
  forgetAgentThreadReadState,
  markAgentThreadAnswerCompleted,
  observeAgentThreadCounts,
} from './agentThreadReadState';

import useBackgroundMode from '../../hooks/useBackgroundMode';
import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useInterval from '../../hooks/useInterval';
import useLastCallback from '../../hooks/useLastCallback';

import AgentThreadActivityTracker from './AgentThreadActivityTracker';

// The server's page limit
const THREAD_LIST_PAGE_SIZE = 50;
// Answers and renames arrive as thread updates without the preview, which the list reads again once they settle
const THREAD_LIST_REFRESH_DELAY_MS = 600;
// Nothing announces chats changed on other devices, so the list on screen reads them again this often, as on mobile
const THREAD_LIST_POLLING_INTERVAL_MS = 30_000;
// A completed answer keeps its status in the row at most this long while the list brings its preview
const ACTIVITY_HOLD_LIMIT_MS = 5000;
// A page that failed to load is requested again no sooner than this, unless the server asked for another delay
const THREAD_LIST_RETRY_DELAY_MS = 5000;

interface UseAgentV2ThreadListProps {
  isEnabled: boolean;
  /** The list is on screen: it reads the chats as it comes back and then every half a minute */
  isVisible: boolean;
}

/** The chats with what changed them last: the user, whose changes the list plays out, or new data from the server */
interface AgentV2ThreadListState {
  /** Absent until the first page loads */
  items?: AgentThreadListItemV2[];
  isUserChange?: boolean;
}

interface UseAgentV2ThreadListResult extends AgentV2ThreadListState {
  hasMore: boolean;
  /** What the Agent is doing in each chat that answers, as a localization key */
  activityLangKeys: Record<string, string>;
  loadMore: NoneToVoidFunction;
  removeThread: (threadId: string) => void;
  /** Moves the chat at once, as on mobile, before the server confirms it */
  setThreadPinned: (threadId: string, isPinned: boolean) => void;
  scheduleRefresh: NoneToVoidFunction;
  /** The open chat's own account of its answer; without `langKey` it is not answering */
  syncLoadedChat: (threadId: string, langKey: string | undefined) => void;
  /** The chat closed, and the status of its answer is left to its updates again */
  releaseLoadedChat: (threadId: string) => void;
}

export default function useAgentV2ThreadList({
  isEnabled,
  isVisible,
}: UseAgentV2ThreadListProps): UseAgentV2ThreadListResult {
  const [list, setList] = useState<AgentV2ThreadListState>({});
  const [nextCursor, setNextCursor] = useState<string | undefined>();
  const [activityLangKeys, setActivityLangKeys] = useState<Record<string, string>>({});
  // The latest first-page load, which a newer one supersedes
  const firstPageRequestIdRef = useRef(0);
  // The latest load of a further page, which a load that starts the list over supersedes, but a refresh does not
  const pageRequestIdRef = useRef(0);
  const isLoadingPageRef = useRef(false);
  const pageRetryTimeoutRef = useRef<number>();
  const refreshTimeoutRef = useRef<number>();
  const hasLoadedMorePagesRef = useRef(false);
  const trackerRef = useRef<AgentThreadActivityTracker>();
  trackerRef.current ??= new AgentThreadActivityTracker();
  const tracker = trackerRef.current;
  // List loads started so far, which tell a load that brings a completed answer's preview from one that does not
  const loadCountRef = useRef(0);
  const loadedChatRef = useRef<string | undefined>();

  const updateItems = useLastCallback((
    update: (items?: AgentThreadListItemV2[]) => AgentThreadListItemV2[] | undefined,
    isUserChange = false,
  ) => {
    setList((current) => {
      const updated = update(current.items);
      // Rows of unchanged chats keep their items, so a refresh that changes nothing renders nothing
      const items = current.items && updated ? reuseUnchangedItems(current.items, updated) : updated;
      return items === current.items ? current : { items, isUserChange };
    });
  });

  const applyActivityChange = useLastCallback((threadIds: Set<string>) => {
    if (!threadIds.size) return;

    setActivityLangKeys((current) => {
      const next = { ...current };
      threadIds.forEach((threadId) => {
        const langKey = tracker.getLangKey(threadId);
        if (langKey) {
          next[threadId] = langKey;
        } else {
          delete next[threadId];
        }
      });
      return next;
    });
  });

  /** `isRefresh` reads the first page again for a live update, keeping the pages loaded after it */
  const load = useLastCallback(async (isRefresh = false) => {
    // A retry scheduled before the list was disabled does not run
    if (!isEnabled) return;

    const localState = getAgentV2LocalState();
    // A first page replaces whatever first page is still loading; one that starts the list over drops the pages too
    const requestId = ++firstPageRequestIdRef.current;
    if (!isRefresh) {
      pageRequestIdRef.current += 1;
      isLoadingPageRef.current = false;
    }
    const loadCount = ++loadCountRef.current;
    const result = await callApi('listAgentV2Threads', { limit: THREAD_LIST_PAGE_SIZE });
    if (localState !== getAgentV2LocalState() || requestId !== firstPageRequestIdRef.current) return;
    if (!result?.ok) {
      handleFirstPageFailure(result?.error);
      return;
    }

    const { threads, nextCursor: pageCursor } = result.value;
    observeAgentThreadCounts(threads.map(({ thread }) => thread), tracker.getAnsweringThreadIds());
    // The rows get the previews of the answers that completed before this load started, and the statuses held for
    // them end in the same change
    applyActivityChange(tracker.releaseAnswered(
      loadCount, new Map(threads.map(({ thread }) => [thread.id, thread.revision] as const)),
    ));

    // The cursor of the last loaded page stays, so the next page continues where the list ends
    if (isRefresh && hasLoadedMorePagesRef.current) {
      updateItems((current) => (current ? mergeAgentThreadListRefresh(current, threads) : threads));
      return;
    }

    hasLoadedMorePagesRef.current = false;
    updateItems(() => threads);
    setNextCursor(pageCursor);
  });

  /**
   * A failed refresh keeps the chats already shown. A list that has not loaded yet keeps its placeholder and tries
   * again, after the delay the server asked for, rather than telling the user that there are no chats.
   *
   * A failure that retrying cannot fix, as an app that must be updated first, leaves the list empty. A list that is
   * disabled, off screen or in a hidden tab reads the chats again as it comes back.
   *
   * It runs as the request ends, so it sees the list as it is by then rather than as it was when the request started.
   */
  const handleFirstPageFailure = useLastCallback((error?: AgentV2OperationError) => {
    if (list.items) return;

    if (error && !error.retryable) {
      updateItems((current) => current ?? []);
      return;
    }
    if (!isEnabled || !isVisible || getIsInBackground()) return;

    window.clearTimeout(refreshTimeoutRef.current);
    refreshTimeoutRef.current = window.setTimeout(
      () => void load(true),
      error?.retryAfterMs ?? THREAD_LIST_RETRY_DELAY_MS,
    );
  });

  const loadPage = useLastCallback(async (cursor: string) => {
    const localState = getAgentV2LocalState();
    const requestId = ++pageRequestIdRef.current;
    isLoadingPageRef.current = true;
    const result = await callApi('listAgentV2Threads', { limit: THREAD_LIST_PAGE_SIZE, cursor });
    if (localState !== getAgentV2LocalState() || requestId !== pageRequestIdRef.current) return;
    if (!result?.ok) {
      // A failure that retrying cannot fix ends the paging, and the list keeps the chats it has loaded
      if (result && !result.error.retryable) {
        isLoadingPageRef.current = false;
        setNextCursor(undefined);
        return;
      }

      // The list keeps the failed page loading for a while, so that scrolling at its end does not ask for it again on
      // every scroll event
      window.clearTimeout(pageRetryTimeoutRef.current);
      pageRetryTimeoutRef.current = window.setTimeout(
        () => retryPage(requestId, cursor, localState),
        result?.error.retryAfterMs ?? THREAD_LIST_RETRY_DELAY_MS,
      );
      return;
    }
    isLoadingPageRef.current = false;

    const { threads, nextCursor: pageCursor } = result.value;
    observeAgentThreadCounts(threads.map(({ thread }) => thread), tracker.getAnsweringThreadIds());
    hasLoadedMorePagesRef.current = true;
    updateItems((current) => (current ? appendPage(current, threads) : threads));
    setNextCursor(pageCursor);
  });

  /**
   * The failed page is asked for again as its delay ends. A user who waits at the end of the list does not scroll any
   * more, and nothing else would ask for the page. A list that is disabled, off screen or in a hidden tab asks for it as
   * the user scrolls to its end again.
   */
  const retryPage = useLastCallback((
    requestId: number, cursor: string, localState: ReturnType<typeof getAgentV2LocalState>,
  ) => {
    if (requestId !== pageRequestIdRef.current || localState !== getAgentV2LocalState()) return;

    isLoadingPageRef.current = false;
    if (isEnabled && isVisible && !getIsInBackground() && cursor === nextCursor) void loadPage(cursor);
  });

  const refresh = useLastCallback(() => {
    window.clearTimeout(refreshTimeoutRef.current);
    // A hidden tab reads the chats again once it comes back
    if (getIsInBackground()) return;

    applyActivityChange(tracker.removeStale(Date.now(), loadedChatRef.current));
    void load(true);
  });

  const scheduleRefresh = useLastCallback(() => {
    window.clearTimeout(refreshTimeoutRef.current);
    refreshTimeoutRef.current = window.setTimeout(refresh, THREAD_LIST_REFRESH_DELAY_MS);
  });

  const applyThread = useLastCallback((thread: AgentThreadSummaryV2) => {
    updateItems((current) => {
      if (!current) return current;
      firstPageRequestIdRef.current += 1;
      const index = current.findIndex((item) => item.thread.id === thread.id);
      // The list leaves out empty chats, so a cleared chat goes and a new one comes once it has a message
      if (!thread.messageCount) {
        return index < 0 ? current : current.filter((item) => item.thread.id !== thread.id);
      }
      if (index < 0) return [...current, { thread }].sort(compareAgentThreadListItems);

      const next = [...current];
      next[index] = { ...current[index], thread };
      return next.sort(compareAgentThreadListItems);
    });
  });

  const removeThread = useLastCallback((threadId: string) => {
    firstPageRequestIdRef.current += 1;
    updateItems((current) => current?.filter((item) => item.thread.id !== threadId), true);
    applyActivityChange(tracker.removeThread(threadId));
    forgetAgentThreadReadState(threadId);
    scheduleRefresh();
  });

  const setThreadPinned = useLastCallback((threadId: string, isPinned: boolean) => {
    firstPageRequestIdRef.current += 1;
    updateItems((current) => current?.map((item) => (
      item.thread.id === threadId ? { ...item, thread: applyPinned(item.thread, isPinned) } : item
    )).sort(compareAgentThreadListItems), true);
  });

  const syncLoadedChat = useLastCallback((threadId: string, langKey: string | undefined) => {
    loadedChatRef.current = threadId;
    applyActivityChange(tracker.syncWithLoadedChat(threadId, langKey, Date.now()));
  });

  const releaseLoadedChat = useLastCallback((threadId: string) => {
    if (loadedChatRef.current === threadId) loadedChatRef.current = undefined;
  });

  const loadMore = useLastCallback(() => {
    if (nextCursor && !isLoadingPageRef.current) void loadPage(nextCursor);
  });

  useEffect(() => {
    if (!isEnabled) return;
    window.clearTimeout(refreshTimeoutRef.current);
    void load();
  }, [isEnabled, load]);

  useInterval(refresh, isEnabled && isVisible ? THREAD_LIST_POLLING_INTERVAL_MS : undefined, true);

  // The chats are read again as the list comes back on screen
  useEffectWithPrevDeps(([prevIsVisible]) => {
    if (isEnabled && isVisible && prevIsVisible === false) refresh();
  }, [isVisible, isEnabled, refresh]);

  useBackgroundMode(undefined, () => {
    if (isEnabled && isVisible) refresh();
  });

  useEffect(() => {
    if (!isEnabled) return undefined;

    const holdTimeouts = new Set<number>();
    const unsubscribe = subscribeToAgentV2Updates((update) => {
      applyActivityChange(tracker.handleUpdate(update, Date.now(), loadCountRef.current));

      if (update.kind === 'threadChanged') {
        applyThread(update.thread);
        scheduleRefresh();
      } else if (update.kind === 'messageCompleted') {
        markAgentThreadAnswerCompleted(update.threadId);
        scheduleRefresh();

        const { threadId } = update;
        const loadCount = loadCountRef.current;
        const timeout = window.setTimeout(() => {
          holdTimeouts.delete(timeout);
          applyActivityChange(tracker.releaseHeld([threadId], loadCount));
        }, ACTIVITY_HOLD_LIMIT_MS);
        holdTimeouts.add(timeout);
      }
    });

    return () => {
      unsubscribe();
      window.clearTimeout(refreshTimeoutRef.current);
      window.clearTimeout(pageRetryTimeoutRef.current);
      holdTimeouts.forEach((timeout) => window.clearTimeout(timeout));
    };
  }, [applyActivityChange, applyThread, isEnabled, scheduleRefresh, tracker]);

  return {
    ...list,
    hasMore: Boolean(nextCursor),
    activityLangKeys,
    loadMore,
    removeThread,
    setThreadPinned,
    scheduleRefresh,
    syncLoadedChat,
    releaseLoadedChat,
  };
}

function applyPinned(thread: AgentThreadSummaryV2, isPinned: boolean): AgentThreadSummaryV2 {
  const { isPinned: _wasPinned, ...unpinned } = thread;
  return isPinned ? { ...unpinned, isPinned: true } : unpinned;
}

function reuseUnchangedItems(current: AgentThreadListItemV2[], next: AgentThreadListItemV2[]) {
  const currentById = new Map(current.map((item) => [item.thread.id, item]));
  let isSame = next.length === current.length;
  const result = next.map((item, index) => {
    const currentItem = currentById.get(item.thread.id);
    const reused = currentItem && getIsSameItem(currentItem, item) ? currentItem : item;
    if (reused !== current[index]) isSame = false;
    return reused;
  });

  return isSame ? current : result;
}

function getIsSameItem(currentItem: AgentThreadListItemV2, nextItem: AgentThreadListItemV2) {
  const { thread: currentThread } = currentItem;
  const { thread: nextThread } = nextItem;
  return currentItem.preview === nextItem.preview
    && currentThread.revision === nextThread.revision
    && currentThread.lastActivityAt === nextThread.lastActivityAt
    && currentThread.messageCount === nextThread.messageCount
    && currentThread.title === nextThread.title
    && currentThread.icon === nextThread.icon
    && currentThread.isPinned === nextThread.isPinned;
}

function appendPage(current: AgentThreadListItemV2[], page: AgentThreadListItemV2[]) {
  const knownIds = new Set(current.map(({ thread }) => thread.id));
  return [...current, ...page.filter(({ thread }) => !knownIds.has(thread.id))];
}
