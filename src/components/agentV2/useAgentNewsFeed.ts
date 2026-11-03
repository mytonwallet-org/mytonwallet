import {
  useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentNewsFeedItemV2,
  AgentNewsFeedLocaleV2,
  AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';

import { subscribeToAgentV2Updates } from '../../util/agentV2Updates';
import { callApi } from '../../api';
import { getAgentNewsUnreadItems, mergeAgentNewsItems } from './agentNewsFeedItems';
import { getAgentNewsReadThrough, markAgentNewsReadThrough } from './agentNewsReadState';

import useLastCallback from '../../hooks/useLastCallback';

type AgentNewsDiscussion = NonNullable<AgentNewsFeedItemV2['discussion']>;

interface LoadedAgentNewsFeed {
  langCode: string;
  pageItems: AgentNewsFeedItemV2[];
  locale?: AgentNewsFeedLocaleV2;
  nextCursor?: string;
  discussions: Record<number, AgentNewsDiscussion>;
  unreadCutoff?: string;
}

interface UseAgentNewsFeedProps {
  /** The feed needs the agent consent, as the chats do */
  isEnabled: boolean;
  /** The first page is read again each time the section opens, since nothing announces new news */
  isActive: boolean;
  langCode: string;
  /** The news on screen count as read */
  isFeedVisible: boolean;
}

interface UseAgentNewsFeedResult {
  /** Oldest first; absent until the first page loads */
  items?: AgentNewsFeedItemV2[];
  locale?: AgentNewsFeedLocaleV2;
  latestItem?: AgentNewsFeedItemV2;
  unreadCount: number;
  /** The first news that was new when the feed was opened from the chat list */
  unreadEventId?: number;
  hasMore: boolean;
  isLoading: boolean;
  isLoadingMore: boolean;
  /** Why the latest reading of the first page failed */
  errorCode?: AgentV2ErrorCode;
  refresh: NoneToVoidFunction;
  loadMore: NoneToVoidFunction;
  /** Keeps the news that are new now marked as new while the user stays in the feed and its chats */
  startReading: NoneToVoidFunction;
  /** Shows a news item's discussion before the server lists it, as right after the user starts one */
  markDiscussion: (eventId: number, discussion: AgentNewsDiscussion) => void;
  removeDiscussion: (threadId: string) => void;
}

// The feed as it was last loaded. A later mount, as when the app switches layouts, shows it at once and reads the
// first page again behind it.
let loadedFeed: LoadedAgentNewsFeed | undefined;

export default function useAgentNewsFeed({
  isEnabled,
  isActive,
  langCode,
  isFeedVisible,
}: UseAgentNewsFeedProps): UseAgentNewsFeedResult {
  const [initialFeed] = useState(() => (loadedFeed?.langCode === langCode ? loadedFeed : undefined));
  const [pageItems, setPageItems] = useState<AgentNewsFeedItemV2[] | undefined>(initialFeed?.pageItems);
  const [locale, setLocale] = useState<AgentNewsFeedLocaleV2 | undefined>(initialFeed?.locale);
  const [nextCursor, setNextCursor] = useState<string | undefined>(initialFeed?.nextCursor);
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [errorCode, setErrorCode] = useState<AgentV2ErrorCode | undefined>();
  const [readThrough, setReadThrough] = useState(getAgentNewsReadThrough);
  const [unreadCutoff, setUnreadCutoff] = useState<string | undefined>(initialFeed?.unreadCutoff);
  const [discussions, setDiscussions] = useState<Record<number, AgentNewsDiscussion>>(
    initialFeed?.discussions ?? {},
  );
  const requestIdRef = useRef(0);
  const requestedCursorsRef = useRef(new Set<string>());

  const items = useMemo(() => pageItems?.map((item) => {
    const discussion = discussions[item.eventId];
    return discussion ? { ...item, discussion } : item;
  }), [discussions, pageItems]);
  const latestItem = items?.[items.length - 1];
  const unreadCount = useMemo(
    () => (items ? getAgentNewsUnreadItems(items, readThrough).length : 0),
    [items, readThrough],
  );
  const unreadEventId = useMemo(
    () => (items && unreadCutoff ? getAgentNewsUnreadItems(items, unreadCutoff)[0]?.eventId : undefined),
    [items, unreadCutoff],
  );

  const refresh = useLastCallback(async () => {
    const requestId = ++requestIdRef.current;
    setIsLoading(true);
    setIsLoadingMore(false);
    const result = await callApi('getAgentV2NewsFeed', { lang: langCode });
    if (requestId !== requestIdRef.current) return;
    setIsLoading(false);
    // A failed refresh keeps the news already shown
    if (!result?.ok) {
      setErrorCode(result?.error.code ?? 'network_error');
      return;
    }

    const page = result.value;
    const isSameLocale = page.locale === locale;
    setErrorCode(undefined);
    setLocale(page.locale);
    setPageItems((current) => mergeAgentNewsItems(isSameLocale && current ? [...current, ...page.items] : page.items));
    if (!isSameLocale) setDiscussions({});
    setNextCursor(page.nextCursor);
    requestedCursorsRef.current.clear();
    // On the first launch the news already published are not new
    const newestItem = mergeAgentNewsItems(page.items).pop();
    if (!readThrough && newestItem) setReadThrough(markAgentNewsReadThrough(newestItem.deliveredAt));
  });

  const loadMore = useLastCallback(async () => {
    const cursor = nextCursor;
    if (!cursor || isLoading || isLoadingMore || requestedCursorsRef.current.has(cursor)) return;

    const requestId = requestIdRef.current;
    requestedCursorsRef.current.add(cursor);
    setIsLoadingMore(true);
    const result = await callApi('getAgentV2NewsFeed', { lang: langCode, cursor });
    if (requestId !== requestIdRef.current) return;
    setIsLoadingMore(false);
    // The next scroll to the top asks for the page again; a page in another language is dropped, as the refresh that
    // the language change starts replaces the feed
    if (!result?.ok || result.value.locale !== locale) {
      requestedCursorsRef.current.delete(cursor);
      return;
    }

    setPageItems((current) => mergeAgentNewsItems([...(current ?? []), ...result.value.items]));
    const pageCursor = result.value.nextCursor;
    setNextCursor(pageCursor && !requestedCursorsRef.current.has(pageCursor) ? pageCursor : undefined);
  });

  const startReading = useLastCallback(() => {
    setUnreadCutoff(readThrough);
  });

  const markDiscussion = useLastCallback((eventId: number, discussion: AgentNewsDiscussion) => {
    setDiscussions((current) => ({ ...current, [eventId]: discussion }));
  });

  const removeDiscussion = useLastCallback((threadId: string) => {
    setDiscussions((current) => Object.fromEntries(
      Object.entries(current).filter(([, discussion]) => discussion.threadId !== threadId),
    ));
    setPageItems((current) => current?.map((item) => (
      item.discussion?.threadId === threadId ? { ...item, discussion: undefined } : item
    )));
  });

  useEffect(() => {
    if (isEnabled && isActive) void refresh();
  }, [isActive, isEnabled, langCode, refresh]);

  useEffect(() => {
    if (!pageItems) return;
    loadedFeed = {
      langCode, pageItems, locale, nextCursor, discussions, unreadCutoff,
    };
  }, [discussions, langCode, locale, nextCursor, pageItems, unreadCutoff]);

  useEffect(() => {
    if (!isFeedVisible || !latestItem) return;
    setReadThrough(markAgentNewsReadThrough(latestItem.deliveredAt));
  }, [isFeedVisible, latestItem]);

  // The agent names a discussion after its first answer, and the feed shows that emoji on the news card
  useEffect(() => {
    if (!isEnabled) return undefined;

    return subscribeToAgentV2Updates((update) => {
      if (update.kind !== 'threadChanged' || !update.thread.news || !update.thread.messageCount) return;
      const { id: threadId, icon, news } = update.thread;
      markDiscussion(news.eventId, { threadId, ...(icon && { icon }) });
    });
  }, [isEnabled, markDiscussion]);

  return {
    items,
    locale,
    latestItem,
    unreadCount,
    unreadEventId,
    hasMore: Boolean(nextCursor),
    isLoading,
    isLoadingMore,
    errorCode,
    refresh,
    loadMore,
    startReading,
    markDiscussion,
    removeDiscussion,
  };
}
