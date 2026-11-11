import {
  useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentNewsFeedItemV2,
  AgentNewsFeedLocaleV2,
  AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';

import { subscribeToAgentV2Updates } from '../../util/agentV2Updates';
import { callApi } from '../../api';
import { getAgentDigestHour, subscribeToAgentDigestHour } from './agentDigestHour';
import { getAgentNewsUnreadItems, mergeAgentNewsFeedEntries, mergeAgentNewsItems } from './agentNewsFeedItems';
import { getAgentNewsReadThrough, markAgentNewsReadThrough } from './agentNewsReadState';

import useLastCallback from '../../hooks/useLastCallback';

type AgentNewsDiscussion = NonNullable<AgentNewsFeedItemV2['discussion']>;

interface LoadedAgentNewsFeed {
  langCode: string;
  digestHour: number;
  timeZone: string;
  pageItems: AgentNewsFeedEntry[];
  locale?: AgentNewsFeedLocaleV2;
  nextCursor?: string;
  /** The entries connected to the latest first page through cursor pages */
  continuousItems?: AgentNewsFeedEntry[];
  hasReachedHistoryEnd: boolean;
  discussions: Record<string, AgentNewsDiscussion>;
  unreadCutoff?: string;
}

interface UseAgentNewsFeedProps {
  /** The feed loads once the SDK can answer; it needs no consent */
  isEnabled: boolean;
  /** The first page is read again each time the section opens, since nothing announces new news */
  isActive: boolean;
  langCode: string;
  /** The news on screen count as read */
  isFeedVisible: boolean;
}

interface UseAgentNewsFeedResult {
  /** Oldest first; absent until the first page loads */
  items?: AgentNewsFeedEntry[];
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
  markDigestReached: (id: string) => void;
  /** Keeps the news that are new now marked as new while the user stays in the feed and its chats */
  startReading: NoneToVoidFunction;
  /** Shows a news item's discussion before the server lists it, as right after the user starts one */
  markDiscussion: (eventId: number, discussion: AgentNewsDiscussion) => void;
  markDigestDiscussion: (id: string, discussion: AgentNewsDiscussion) => void;
  removeDiscussion: (threadId: string) => void;
}

// The feed as it was last loaded. A later mount, as when the app switches layouts, shows it at once and reads the
// first page again behind it.
let loadedFeed: LoadedAgentNewsFeed | undefined;

const PREFETCH_WINDOW_MS = 48 * 60 * 60 * 1000;

export default function useAgentNewsFeed({
  isEnabled,
  isActive,
  langCode,
  isFeedVisible,
}: UseAgentNewsFeedProps): UseAgentNewsFeedResult {
  const [digestHour, setDigestHour] = useState(getAgentDigestHour);
  const [initialFeed] = useState(() => {
    if (loadedFeed?.langCode !== langCode) return undefined;
    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (loadedFeed.digestHour === digestHour && loadedFeed.timeZone === timeZone) return loadedFeed;
    return {
      ...loadedFeed,
      digestHour,
      timeZone,
      continuousItems: loadedFeed.continuousItems?.filter((entry) => entry.kind === 'news'),
      hasReachedHistoryEnd: false,
      pageItems: loadedFeed.pageItems.filter((entry) => entry.kind === 'news'),
      discussions: keepNewsDiscussions(loadedFeed.discussions),
    };
  });
  const [pageItems, setPageItems] = useState<AgentNewsFeedEntry[] | undefined>(initialFeed?.pageItems);
  const [loadedDigestSettings, setLoadedDigestSettings] = useState(() => ({
    digestHour: initialFeed?.digestHour ?? digestHour,
    timeZone: initialFeed?.timeZone ?? Intl.DateTimeFormat().resolvedOptions().timeZone,
  }));
  const [locale, setLocale] = useState<AgentNewsFeedLocaleV2 | undefined>(initialFeed?.locale);
  const [nextCursor, setNextCursor] = useState<string | undefined>(initialFeed?.nextCursor);
  const [continuousItems, setContinuousItems] = useState<AgentNewsFeedEntry[] | undefined>(
    initialFeed?.continuousItems,
  );
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [canPrefetch, setCanPrefetch] = useState(Boolean(initialFeed));
  const [hasReachedHistoryEnd, setHasReachedHistoryEnd] = useState(initialFeed?.hasReachedHistoryEnd ?? false);
  const [hasPrefetchFailed, setHasPrefetchFailed] = useState(false);
  const [reachedDigestAt, setReachedDigestAt] = useState<number>();
  const [errorCode, setErrorCode] = useState<AgentV2ErrorCode | undefined>();
  const [readThrough, setReadThrough] = useState(getAgentNewsReadThrough);
  const [unreadCutoff, setUnreadCutoff] = useState<string | undefined>(initialFeed?.unreadCutoff);
  const [discussions, setDiscussions] = useState<Record<string, AgentNewsDiscussion>>(
    initialFeed?.discussions ?? {},
  );
  const requestIdRef = useRef(0);
  const requestedCursorsRef = useRef(new Set<string>());
  const isRefreshingRef = useRef(false);
  const isPageLoadingRef = useRef(false);
  const feedLangCodeRef = useRef(langCode);
  const digestSettingsRef = useRef(loadedDigestSettings);

  const items = useMemo(() => pageItems?.map((item) => {
    const discussion = discussions[item.kind === 'news' ? `news-${item.eventId}` : `digest-${item.id}`];
    return discussion ? { ...item, discussion } : item;
  }), [discussions, pageItems]);
  const newsItems = useMemo(() => items?.filter((item) => item.kind === 'news'), [items]);
  const latestItem = newsItems?.[newsItems.length - 1];
  const unreadCount = useMemo(
    () => (newsItems ? getAgentNewsUnreadItems(newsItems, readThrough).length : 0),
    [newsItems, readThrough],
  );
  const unreadEventId = useMemo(
    () => (newsItems && unreadCutoff ? getAgentNewsUnreadItems(newsItems, unreadCutoff)[0]?.eventId : undefined),
    [newsItems, unreadCutoff],
  );

  const refresh = useLastCallback(async () => {
    isRefreshingRef.current = true;
    const digestSettings = {
      digestHour: getAgentDigestHour(), timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    };
    const hasDigestSettingsChanged = resetDigestsIfNeeded(digestSettings);
    const hasLanguageChanged = feedLangCodeRef.current !== langCode;
    if (hasLanguageChanged) {
      feedLangCodeRef.current = langCode;
      setContinuousItems(undefined);
      setReachedDigestAt(undefined);
      setHasReachedHistoryEnd(false);
    }
    const requestId = ++requestIdRef.current;
    requestedCursorsRef.current.clear();
    setHasPrefetchFailed(false);
    setIsLoading(true);
    const result = await callApi('getAgentV2NewsFeed', {
      lang: langCode, ...digestSettings,
    });
    if (requestId !== requestIdRef.current) return;
    isRefreshingRef.current = false;
    setIsLoading(false);
    // A failed refresh keeps the news already shown
    if (!result?.ok) {
      setErrorCode(result?.error.code ?? 'network_error');
      return;
    }

    const page = result.value;
    const isSameLocale = page.locale === locale;
    const pageEntries = mergeAgentNewsFeedEntries(page.items, page.digests);
    const hasContinuousOverlap = isSameLocale && !hasDigestSettingsChanged && !hasLanguageChanged
      && Boolean(continuousItems?.some((entry) => (
        entry.kind === 'news'
          ? page.items.some((item) => item.eventId === entry.eventId)
          : page.digests?.some((digest) => digest.id === entry.id)
      )));
    setErrorCode(undefined);
    setLocale(page.locale);
    setPageItems((current) => mergeAgentNewsFeedEntries(page.items, page.digests, isSameLocale ? current : undefined));
    setContinuousItems((current) => (
      hasContinuousOverlap ? mergeAgentNewsFeedEntries(page.items, page.digests, current) : pageEntries
    ));
    if (!isSameLocale) setDiscussions({});
    if (!hasContinuousOverlap) setHasReachedHistoryEnd(false);
    setNextCursor(page.nextCursor);
    setCanPrefetch(true);
    // On the first launch the news already published are not new
    const newestItem = mergeAgentNewsItems(page.items).pop();
    if (!readThrough && newestItem) setReadThrough(markAgentNewsReadThrough(newestItem.deliveredAt));
  });

  const loadMore = useLastCallback(async () => {
    setHasPrefetchFailed(false);
    await loadOlderPage();
  });

  const loadOlderPage = useLastCallback(async () => {
    const cursor = nextCursor;
    if (!cursor || isRefreshingRef.current || isLoading || isPageLoadingRef.current
      || requestedCursorsRef.current.has(cursor)) return;

    const digestSettings = {
      digestHour: getAgentDigestHour(), timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    };
    resetDigestsIfNeeded(digestSettings);
    const requestId = requestIdRef.current;
    requestedCursorsRef.current.add(cursor);
    isPageLoadingRef.current = true;
    setIsLoadingMore(true);
    const result = await callApi('getAgentV2NewsFeed', {
      lang: langCode, cursor, ...digestSettings,
    });
    isPageLoadingRef.current = false;
    setIsLoadingMore(false);
    if (requestId !== requestIdRef.current) return;
    // The next scroll to the top asks for the page again; a page in another language is dropped, as the refresh that
    // the language change starts replaces the feed
    if (!result?.ok || result.value.locale !== locale) {
      requestedCursorsRef.current.delete(cursor);
      setHasPrefetchFailed(true);
      return;
    }

    const page = result.value;
    setPageItems((current) => mergeAgentNewsFeedEntries(page.items, page.digests, current));
    setContinuousItems((current) => mergeAgentNewsFeedEntries(page.items, page.digests, current));
    const pageCursor = page.nextCursor;
    if (!pageCursor) setHasReachedHistoryEnd(true);
    setNextCursor(pageCursor && !requestedCursorsRef.current.has(pageCursor) ? pageCursor : undefined);
  });

  const resetDigestsIfNeeded = useLastCallback((settings: Pick<LoadedAgentNewsFeed, 'digestHour' | 'timeZone'>) => {
    if (settings.digestHour === digestSettingsRef.current.digestHour
      && settings.timeZone === digestSettingsRef.current.timeZone) {
      return false;
    }
    digestSettingsRef.current = settings;
    requestIdRef.current++;
    requestedCursorsRef.current.clear();
    setReachedDigestAt(undefined);
    setContinuousItems((current) => current?.filter((entry) => entry.kind === 'news'));
    setHasReachedHistoryEnd(false);
    setHasPrefetchFailed(false);
    setLoadedDigestSettings(settings);
    setPageItems((current) => current?.filter((entry) => entry.kind === 'news'));
    setDiscussions(keepNewsDiscussions);
    return true;
  });

  const markDigestReached = useLastCallback((id: string) => {
    const digest = pageItems?.find((entry) => entry.kind === 'digest' && entry.id === id);
    if (!digest) return;
    const timestamp = Date.parse(digest.deliveredAt);
    if (reachedDigestAt !== undefined && timestamp >= reachedDigestAt) return;
    setReachedDigestAt((current) => (current === undefined ? timestamp : Math.min(current, timestamp)));
    setHasPrefetchFailed(false);
  });

  const startReading = useLastCallback(() => {
    setUnreadCutoff(readThrough);
  });

  const markDiscussion = useLastCallback((eventId: number, discussion: AgentNewsDiscussion) => {
    setDiscussions((current) => ({ ...current, [`news-${eventId}`]: discussion }));
  });

  const markDigestDiscussion = useLastCallback((id: string, discussion: AgentNewsDiscussion) => {
    setDiscussions((current) => ({ ...current, [`digest-${id}`]: discussion }));
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
  }, [digestHour, isActive, isEnabled, langCode, refresh]);

  useEffect(() => {
    if (!isEnabled || !isActive || !isFeedVisible || !canPrefetch || hasPrefetchFailed || hasReachedHistoryEnd
      || isLoading || isLoadingMore || !nextCursor || !continuousItems) return;

    const olderDigests = continuousItems.filter((entry) => entry.kind === 'digest'
      && (reachedDigestAt === undefined || Date.parse(entry.deliveredAt) < reachedDigestAt));
    if (olderDigests.length >= 2) return;

    const continuousNews = continuousItems.filter((entry) => entry.kind === 'news');
    const oldestNews = continuousNews[0];
    const newestNews = continuousNews[continuousNews.length - 1];
    const referenceTime = reachedDigestAt ?? (newestNews ? Date.parse(newestNews.deliveredAt) : undefined);
    if (oldestNews && referenceTime !== undefined
      && referenceTime - Date.parse(oldestNews.deliveredAt) >= PREFETCH_WINDOW_MS) return;

    void loadOlderPage();
  }, [
    canPrefetch, continuousItems, hasPrefetchFailed, hasReachedHistoryEnd, isActive, isEnabled, isFeedVisible,
    isLoading, isLoadingMore, loadOlderPage, nextCursor, reachedDigestAt,
  ]);

  useEffect(() => {
    const unsubscribe = subscribeToAgentDigestHour(setDigestHour);
    setDigestHour(getAgentDigestHour());
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!pageItems) return;
    loadedFeed = {
      langCode, pageItems, continuousItems, locale, nextCursor, hasReachedHistoryEnd,
      discussions, unreadCutoff, ...loadedDigestSettings,
    };
  }, [
    continuousItems, discussions, hasReachedHistoryEnd, langCode, loadedDigestSettings, locale, nextCursor, pageItems,
    unreadCutoff,
  ]);

  useEffect(() => {
    if (!isFeedVisible || !latestItem) return;
    setReadThrough(markAgentNewsReadThrough(latestItem.deliveredAt));
  }, [isFeedVisible, latestItem]);

  // The agent names a discussion after its first answer, and the feed shows that emoji on the news card
  useEffect(() => {
    if (!isEnabled) return undefined;

    return subscribeToAgentV2Updates((update) => {
      if (update.kind !== 'threadChanged' || !update.thread.messageCount) return;
      const { id: threadId, icon, news, digest } = update.thread;
      const discussion = { threadId, ...(icon && { icon }) };
      if (news) markDiscussion(news.eventId, discussion);
      if (digest) markDigestDiscussion(digest.id, discussion);
    });
  }, [isEnabled, markDigestDiscussion, markDiscussion]);

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
    markDigestReached,
    startReading,
    markDiscussion,
    markDigestDiscussion,
    removeDiscussion,
  };
}

function keepNewsDiscussions(discussions: Record<string, AgentNewsDiscussion>) {
  return Object.fromEntries(Object.entries(discussions).filter(([key]) => key.startsWith('news-')));
}
