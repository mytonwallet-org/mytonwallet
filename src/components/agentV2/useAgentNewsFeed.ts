import {
  useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentNewsFeedDigestV2,
  AgentNewsFeedItemV2,
  AgentNewsFeedLocaleV2,
  AgentV2ErrorCode,
} from '../../api/agentV2/protocol/types';
import type { AgentDigestMinute } from './agentDigestTime';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';
import type { AgentNewsFeedView } from './agentNewsFeedView';

import { subscribeToAgentV2Updates } from '../../util/agentV2Updates';
import { callApi } from '../../api';
import { getAgentDigestTime, subscribeToAgentDigestTime } from './agentDigestTime';
import { getAgentNewsUnreadItems, mergeAgentNewsFeedEntries, mergeAgentNewsItems } from './agentNewsFeedItems';
import {
  getAgentNewsDigestsReadThrough,
  getAgentNewsReadThrough,
  markAgentNewsDigestsReadThrough,
  markAgentNewsReadThrough,
} from './agentNewsReadState';

import useLastCallback from '../../hooks/useLastCallback';

type AgentNewsDiscussion = NonNullable<AgentNewsFeedItemV2['discussion']>;
type DigestEntry = Extract<AgentNewsFeedEntry, { kind: 'digest' }>;
type DigestSettings = Pick<LoadedAgentNewsFeed, 'digestHour' | 'digestMinute' | 'timeZone'>;

interface LoadedAgentNewsFeed {
  langCode: string;
  digestHour: number;
  digestMinute: AgentDigestMinute;
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
  view?: AgentNewsFeedView;
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
  /** In the Digests view, the first digest that was new when the view was first shown after the feed opened */
  unreadDigestId?: string;
  /** In the Digests view, the latest digest, which the News row shows */
  latestDigest?: AgentNewsFeedDigestV2;
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
let loadedDigestsFeed: LoadedAgentNewsFeed | undefined;
// The digests' mark as the Digests view was first shown after the feed opened from the chat list, after which the
// digests are new while the feed stays open
let loadedDigestUnreadCutoff: string | undefined;
let isDigestUnreadCutoffPending = false;

const PREFETCH_WINDOW_MS = 48 * 60 * 60 * 1000;

export default function useAgentNewsFeed({ view = 'all', ...props }: UseAgentNewsFeedProps): UseAgentNewsFeedResult & {
  allItems?: AgentNewsFeedEntry[];
} {
  const allFeed = useNewsFeed({ ...props, view: 'all', isFeedVisible: props.isFeedVisible && view === 'all' }, view);
  const digestsFeed = useNewsFeed({
    ...props, view: 'digests', isActive: props.isActive && view === 'digests',
    isFeedVisible: props.isFeedVisible && view === 'digests',
  }, view);
  const { refresh: refreshAll } = allFeed;
  const previousViewRef = useRef(view);
  const [digestsReadThrough, setDigestsReadThrough] = useState(getAgentNewsDigestsReadThrough);
  const [digestUnreadCutoff, setDigestUnreadCutoff] = useState(loadedDigestUnreadCutoff);
  const shownItems = view === 'digests' ? digestsFeed.items : allFeed.items;
  const shownDigests = useMemo(
    () => shownItems?.filter((item): item is DigestEntry => item.kind === 'digest'),
    [shownItems],
  );
  const latestShownDigest = shownDigests?.[shownDigests.length - 1];
  const unreadDigestCount = useMemo(
    () => (shownDigests && digestsReadThrough ? getAgentNewsUnreadDigests(shownDigests, digestsReadThrough).length : 0),
    [digestsReadThrough, shownDigests],
  );
  const isTakingDigestUnreadCutoff = isDigestUnreadCutoffPending && view === 'digests' && props.isFeedVisible;
  // The Digests view takes the mark in its first render, which positions the list, and before the digests on screen
  // are marked read, so the digests that All News showed are not new here
  const shownDigestUnreadCutoff = isTakingDigestUnreadCutoff ? digestsReadThrough : digestUnreadCutoff;
  const unreadDigestId = useMemo(
    () => (view === 'digests' && shownDigests && shownDigestUnreadCutoff
      ? getAgentNewsUnreadDigests(shownDigests, shownDigestUnreadCutoff)[0]?.id
      : undefined),
    [shownDigestUnreadCutoff, shownDigests, view],
  );

  useEffect(() => {
    if (!isTakingDigestUnreadCutoff) return;
    isDigestUnreadCutoffPending = false;
    loadedDigestUnreadCutoff = digestsReadThrough;
    setDigestUnreadCutoff(digestsReadThrough);
  }, [digestsReadThrough, isTakingDigestUnreadCutoff]);

  // On the first launch the digests already published are not new, and the digests on screen, in either view, are read
  useEffect(() => {
    if (!latestShownDigest || (digestsReadThrough && !props.isFeedVisible)) return;
    setDigestsReadThrough(markAgentNewsDigestsReadThrough(latestShownDigest.deliveredAt));
  }, [digestsReadThrough, latestShownDigest, props.isFeedVisible]);

  const startReading = useLastCallback(() => {
    allFeed.startReading();
    isDigestUnreadCutoffPending = true;
    loadedDigestUnreadCutoff = undefined;
    setDigestUnreadCutoff(undefined);
  });

  useEffect(() => {
    const hasViewChanged = previousViewRef.current !== view;
    previousViewRef.current = view;
    if (hasViewChanged && view === 'all' && props.isEnabled && props.isActive) refreshAll();
  }, [props.isActive, props.isEnabled, refreshAll, view]);

  const markDiscussion = useLastCallback((eventId: number, discussion: AgentNewsDiscussion) => {
    allFeed.markDiscussion(eventId, discussion);
    digestsFeed.markDiscussion(eventId, discussion);
  });
  const markDigestDiscussion = useLastCallback((id: string, discussion: AgentNewsDiscussion) => {
    allFeed.markDigestDiscussion(id, discussion);
    digestsFeed.markDigestDiscussion(id, discussion);
  });
  const removeDiscussion = useLastCallback((threadId: string) => {
    allFeed.removeDiscussion(threadId);
    digestsFeed.removeDiscussion(threadId);
  });

  return {
    ...(view === 'digests' ? digestsFeed : allFeed),
    allItems: allFeed.items,
    latestItem: allFeed.latestItem,
    latestDigest: view === 'digests' ? latestShownDigest : undefined,
    unreadCount: view === 'digests' ? unreadDigestCount : allFeed.unreadCount,
    unreadEventId: view === 'all' ? allFeed.unreadEventId : undefined,
    unreadDigestId,
    startReading,
    markDiscussion,
    markDigestDiscussion,
    removeDiscussion,
  };
}

function useNewsFeed({
  view,
  isEnabled,
  isActive,
  langCode,
  isFeedVisible,
}: UseAgentNewsFeedProps & { view: AgentNewsFeedView }, shownView: AgentNewsFeedView): UseAgentNewsFeedResult {
  const [digestTime, setDigestTime] = useState(getAgentDigestTime);
  const [initialFeed] = useState(() => {
    const cachedFeed = view === 'digests' ? loadedDigestsFeed : loadedFeed;
    if (cachedFeed?.langCode !== langCode) return undefined;
    if (view === 'digests') return cachedFeed;
    const digestSettings = readDigestSettings();
    if (isSameDigestSchedule(cachedFeed, digestSettings)) return cachedFeed;
    return {
      ...cachedFeed,
      ...digestSettings,
      continuousItems: cachedFeed.continuousItems?.filter((entry) => entry.kind === 'news'),
      hasReachedHistoryEnd: false,
      pageItems: cachedFeed.pageItems.filter((entry) => entry.kind === 'news'),
      discussions: keepNewsDiscussions(cachedFeed.discussions),
    };
  });
  const [pageItems, setPageItems] = useState<AgentNewsFeedEntry[] | undefined>(initialFeed?.pageItems);
  const [loadedDigestSettings, setLoadedDigestSettings] = useState<DigestSettings>(() => (initialFeed ? {
    digestHour: initialFeed.digestHour, digestMinute: initialFeed.digestMinute, timeZone: initialFeed.timeZone,
  } : readDigestSettings()));
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
  const shownViewRef = useRef(shownView);
  shownViewRef.current = shownView;
  const digestSettingsRef = useRef(loadedDigestSettings);
  // The digests shown are another schedule's: they stay until the new schedule's first page replaces them, so the cards
  // and the pinned panel don't blink out and back while it loads
  const isDigestResetPendingRef = useRef(false);

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
    const digestSettings = readDigestSettings();
    if (resetDigestsIfNeeded(digestSettings)) isDigestResetPendingRef.current = true;
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
      lang: langCode, ...digestSettings, ...(view === 'digests' && { view }),
    });
    if (requestId !== requestIdRef.current) return;
    isRefreshingRef.current = false;
    setIsLoading(false);
    const shouldDropDigests = isDigestResetPendingRef.current;
    if (result?.ok || view === 'all') isDigestResetPendingRef.current = false;
    // A digest of the other schedule reached while they stayed tells nothing of the new one's
    if (shouldDropDigests) setReachedDigestAt(undefined);
    // A failed refresh keeps the news already shown
    if (!result?.ok) {
      if (shouldDropDigests && view === 'all') dropDigests();
      setErrorCode(result?.error.code ?? 'network_error');
      return;
    }

    const page = result.value;
    if (view === 'digests') setLoadedDigestSettings(digestSettings);
    const isSameLocale = page.locale === locale;
    const pageEntries = mergeAgentNewsFeedEntries(page.items, page.digests);
    const hasContinuousOverlap = isSameLocale && !shouldDropDigests && !hasLanguageChanged
      && Boolean(continuousItems?.some((entry) => (
        entry.kind === 'news'
          ? page.items.some((item) => item.eventId === entry.eventId)
          : page.digests?.some((digest) => digest.id === entry.id)
      )));
    setErrorCode(undefined);
    setLocale(page.locale);
    setPageItems((current) => mergeAgentNewsFeedEntries(
      page.items,
      page.digests,
      isSameLocale ? (shouldDropDigests ? keepNews(current) : current) : undefined,
    ));
    setContinuousItems((current) => (
      hasContinuousOverlap ? mergeAgentNewsFeedEntries(page.items, page.digests, current) : pageEntries
    ));
    if (!isSameLocale) {
      setDiscussions({});
    } else if (shouldDropDigests) {
      setDiscussions(keepNewsDiscussions);
    }
    if (view === 'digests') setHasReachedHistoryEnd(!page.nextCursor);
    else if (!hasContinuousOverlap) setHasReachedHistoryEnd(false);
    setNextCursor(page.nextCursor);
    setCanPrefetch(true);
    // On the first launch the news already published are not new
    const newestItem = mergeAgentNewsItems(page.items).pop();
    if (view === 'all' && shownViewRef.current === 'all' && !readThrough && newestItem) {
      setReadThrough(markAgentNewsReadThrough(newestItem.deliveredAt));
    }
  });

  const loadMore = useLastCallback(async () => {
    setHasPrefetchFailed(false);
    await loadOlderPage();
  });

  const loadOlderPage = useLastCallback(async () => {
    const cursor = nextCursor;
    if (!cursor || isRefreshingRef.current || isLoading || isPageLoadingRef.current
      || requestedCursorsRef.current.has(cursor)) return;

    const digestSettings = readDigestSettings();
    if (view === 'digests' && (isDigestResetPendingRef.current
      || !isSameDigestSchedule(digestSettings, digestSettingsRef.current))) {
      await refresh();
      return;
    }
    if (resetDigestsIfNeeded(digestSettings)) dropDigests();
    const requestId = requestIdRef.current;
    requestedCursorsRef.current.add(cursor);
    isPageLoadingRef.current = true;
    setIsLoadingMore(true);
    const result = await callApi('getAgentV2NewsFeed', {
      lang: langCode, cursor, ...digestSettings, ...(view === 'digests' && { view }),
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

  /**
   * Takes the schedule the next page is requested with, and tells whether it is another than the loaded digests'. The
   * digests shown stay for the caller to drop.
   */
  const resetDigestsIfNeeded = useLastCallback((settings: DigestSettings) => {
    if (isSameDigestSchedule(settings, digestSettingsRef.current)) return false;
    digestSettingsRef.current = settings;
    requestIdRef.current++;
    requestedCursorsRef.current.clear();
    setReachedDigestAt(undefined);
    setContinuousItems((current) => current?.filter((entry) => entry.kind === 'news'));
    setHasReachedHistoryEnd(false);
    setHasPrefetchFailed(false);
    if (view === 'all') setLoadedDigestSettings(settings);
    return true;
  });

  const dropDigests = useLastCallback(() => {
    setPageItems(keepNews);
    setDiscussions(keepNewsDiscussions);
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
  }, [digestTime, isActive, isEnabled, langCode, refresh]);

  useEffect(() => {
    if (view !== 'digests' || !isEnabled || !isActive) return undefined;
    function handleFocus() {
      if (Intl.DateTimeFormat().resolvedOptions().timeZone !== digestSettingsRef.current.timeZone) void refresh();
    }
    window.addEventListener('focus', handleFocus);
    return () => window.removeEventListener('focus', handleFocus);
  }, [isActive, isEnabled, refresh, view]);

  useEffect(() => {
    if (view === 'digests' || !isEnabled || !isActive || !isFeedVisible || !canPrefetch || hasPrefetchFailed
      || hasReachedHistoryEnd || isLoading || isLoadingMore || !nextCursor || !continuousItems) return;

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
    isLoading, isLoadingMore, loadOlderPage, nextCursor, reachedDigestAt, view,
  ]);

  useEffect(() => {
    const unsubscribe = subscribeToAgentDigestTime(setDigestTime);
    setDigestTime(getAgentDigestTime());
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!pageItems) return;
    // The digests still shown are another schedule's than the one cached, so a later mount opens without them
    const isDigestResetPending = view === 'all' && isDigestResetPendingRef.current;
    const cachedFeed: LoadedAgentNewsFeed = {
      langCode,
      pageItems: isDigestResetPending ? keepNews(pageItems)! : pageItems,
      continuousItems,
      locale,
      nextCursor,
      hasReachedHistoryEnd,
      discussions: isDigestResetPending ? keepNewsDiscussions(discussions) : discussions,
      unreadCutoff,
      ...loadedDigestSettings,
    };
    if (view === 'digests') loadedDigestsFeed = cachedFeed;
    else loadedFeed = cachedFeed;
  }, [
    continuousItems, discussions, hasReachedHistoryEnd, langCode, loadedDigestSettings, locale, nextCursor, pageItems,
    unreadCutoff, view,
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

/** The digests delivered after `readThrough`, oldest first, or none before the first launch's mark */
function getAgentNewsUnreadDigests(digests: DigestEntry[], readThrough: string) {
  const readAt = Date.parse(readThrough);
  return digests.filter((digest) => Date.parse(digest.deliveredAt) > readAt);
}

function readDigestSettings(): DigestSettings {
  const { hour, minute } = getAgentDigestTime();
  return { digestHour: hour, digestMinute: minute, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone };
}

function isSameDigestSchedule(first: DigestSettings, second: DigestSettings) {
  return first.digestHour === second.digestHour
    && first.digestMinute === second.digestMinute
    && first.timeZone === second.timeZone;
}

function keepNews(entries?: AgentNewsFeedEntry[]) {
  return entries?.filter((entry) => entry.kind === 'news');
}

function keepNewsDiscussions(discussions: Record<string, AgentNewsDiscussion>) {
  return Object.fromEntries(Object.entries(discussions).filter(([key]) => key.startsWith('news-')));
}
