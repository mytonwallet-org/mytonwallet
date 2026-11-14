import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { AgentNewsFeedItemV2, AgentNewsFeedLocaleV2, AgentV2ErrorCode } from '../../api/agentV2/protocol/types';
import type { AgentMessage, AnimationLevel } from '../../global/types';
import type {
  AgentConversation,
  AgentConversationActions,
  AgentConversationHeader,
  AgentConversationHistory,
  AgentConversationMessageContext,
  AgentConversationSessionStore,
} from '../agent/AgentConversationShell';
import type { AgentNewsFeedEntry } from './agentNewsFeedItems';
import type { AgentNewsFeedView } from './agentNewsFeedView';
import { MediaType } from '../../global/types';

import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import { isAnimatingScroll } from '../../util/animateScroll';
import { formatFullDay } from '../../util/dateFormat';
import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';
import { getAgentV2ErrorText } from './agentV2Copy';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentDigestSheet from './AgentDigestSheet';
import AgentNewsCard from './AgentNewsCard';
import AgentNewsDigestCard from './AgentNewsDigestCard';
import AgentNewsPinnedDigest from './AgentNewsPinnedDigest';
import AgentNewsViewSwitch from './AgentNewsViewSwitch';

interface OwnProps {
  view: AgentNewsFeedView;
  onViewChange: (view: AgentNewsFeedView) => void;
  isActive: boolean;
  items?: AgentNewsFeedEntry[];
  /** The language of the feed's pages, which its news are shared in */
  locale?: AgentNewsFeedLocaleV2;
  unreadEventId?: number;
  /** The first digest that was new as the feed opened, which the Digests view puts the "New" line above */
  unreadDigestId?: string;
  hasMore: boolean;
  isLoading: boolean;
  isLoadingMore: boolean;
  /** Why the latest reading of the news failed */
  errorCode?: AgentV2ErrorCode;
  /** The discussions the user has written in, whose cards offer to continue them */
  continuedThreadIds?: Set<string>;
  /** Keeps the place in the feed for its next mount, as when the app switches layouts */
  session?: AgentConversationSessionStore;
  /** Shows the Back button, which goes back to the chat list the feed opened over */
  onBack?: NoneToVoidFunction;
  onRetry: NoneToVoidFunction;
  onLoadMore: NoneToVoidFunction;
  onDigestReached: (id: string) => void;
  onOpenDiscussion: (item: AgentNewsFeedItemV2, cardElement?: HTMLElement) => void;
  /** Opens the discussion of a news item the headline of digest [digestId] names */
  onOpenNewsDiscussion: (eventId: number, digestId: string) => void;
  onOpenDigestDiscussion: (id: string, cardElement?: HTMLElement) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

const NO_TEXT_REVEAL: AgentConversation['textRevealPresentations'] = {};
const NO_MESSAGES: AgentMessage[] = [];
const NO_DIGESTS: DigestEntry[] = [];
// What the user does to scroll the list on their own, which hands the pinned digest back to the scroll position
const USER_SCROLL_EVENTS = ['wheel', 'touchstart', 'pointerdown', 'keydown'] as const;
// Android's `AGENT_HISTORY_LOAD_THRESHOLD`, so that older news start loading at the same row on every platform
const OLDER_NEWS_THRESHOLD_ROW_COUNT = 5;
const DIGEST_HEADLINE_SEPARATOR = ' · ';
// The pinned digest's height in rem, as its style lays it out
const PINNED_DIGEST_HEIGHT = 3.125;
// A digest is a message of the list under an ID of its own, below zero, where no news' event ID is. It keeps that ID
// while the app runs, so that its card stays in place as pages load.
const digestMessageIds = new Map<string, number>();

/**
 * The news, newest at the bottom as in a channel, in the list of a chat without a field, under a chat header, as on
 * mobile. Each news item is a message of the list, shown as its card, and so is each daily digest. The switch in the
 * header's title place shows all news or the digests alone, and the settings button opens the digest's hour.
 */
function AgentNewsFeed({
  view,
  onViewChange,
  isActive,
  items: feedItems,
  locale,
  unreadEventId,
  unreadDigestId,
  hasMore,
  isLoading,
  isLoadingMore,
  errorCode,
  continuedThreadIds,
  session,
  animationLevel,
  onBack,
  onRetry,
  onLoadMore,
  onDigestReached,
  onOpenDiscussion,
  onOpenNewsDiscussion,
  onOpenDigestDiscussion,
}: OwnProps & StateProps) {
  const lang = useLang();
  const items = useMemo(() => (
    view === 'digests' ? feedItems?.filter((item) => item.kind === 'digest') : feedItems
  ), [feedItems, view]);
  // A feed that comes on screen with its news in hand, as on the way back from a discussion, shows them at once where
  // it was left, with no placeholders to grow out of, as on mobile
  const hasNewsAtMountRef = useRef(Boolean(items));
  const [isDigestSheetOpen, openDigestSheet, closeDigestSheet] = useFlag();
  const newsItems = useMemo(() => items?.filter((item) => item.kind === 'news'), [items]);
  const itemsByMessageId = useMemo(
    () => new Map(items?.map((item) => [getEntryMessageId(item), item])), [items],
  );
  const messages = useMemo(() => items?.map(buildEntryMessage) ?? NO_MESSAGES, [items]);
  const digests = useMemo(
    () => items?.filter((item): item is DigestEntry => item.kind === 'digest') ?? NO_DIGESTS, [items],
  );
  // The digest the pinned panel shows, as Telegram's pinned message. Until the list scrolls it shows the newest; a tap
  // holds what it chose until the user scrolls the list again.
  const [pinnedDigestId, setPinnedDigestId] = useState<string>();
  const [isPinnedDigestHeld, setIsPinnedDigestHeld] = useState(false);
  const [scrollRequest, setScrollRequest] = useState<AgentConversation['scrollRequest']>();
  const scrollRequestKeyRef = useRef(0);
  const pinnedIndex = getPinnedDigestIndex(digests, pinnedDigestId);
  // The media viewer pages through the pictures of the news loaded, in the feed's order
  const pictures = useMemo(() => (
    newsItems
      ? buildAgentNewsPictures(newsItems.map((item) => ({ ...item, time: item.deliveredAt })), 'feed', locale)
      : undefined
  ), [locale, newsItems]);

  // A picture is opened from a card, and cards render only from `items`, from which `pictures` is built
  const handleOpenPicture = useLastCallback((eventId: number) => {
    getActions().openMediaViewer({
      mediaType: MediaType.AgentNews,
      mediaId: getAgentNewsPictureId('feed', eventId),
      pictures: pictures!,
    });
  });

  const renderMessage = useLastCallback((message: AgentMessage, context: AgentConversationMessageContext) => {
    const item = itemsByMessageId.get(message.id);
    if (!item) return undefined;

    if (item.kind === 'digest') {
      return (
        <AgentNewsDigestCard
          key={message.id}
          digest={item}
          messageId={message.id}
          isJustAdded={context.isJustAdded}
          isInDigestsView={view === 'digests'}
          onOpenNewsDiscussion={onOpenNewsDiscussion}
          onOpenDigestDiscussion={onOpenDigestDiscussion}
        />
      );
    }

    const threadId = item.discussion?.threadId;
    return (
      <AgentNewsCard
        key={message.id}
        item={item}
        locale={locale}
        isJustAdded={context.isJustAdded}
        isDiscussionContinued={Boolean(threadId && continuedThreadIds?.has(threadId))}
        onOpenDiscussion={onOpenDiscussion}
        onOpenPicture={handleOpenPicture}
      />
    );
  });

  const handleMessageVisible = useLastCallback((messageId: number) => {
    const item = itemsByMessageId.get(messageId);
    if (item?.kind === 'digest') onDigestReached(item.id);
  });

  const conversation = useMemo<AgentConversation>(() => ({
    messages,
    isInitialLoadComplete: Boolean(items),
    hasHistoryPlaceholder: !hasNewsAtMountRef.current,
    isNewsPlaceholder: true,
    hasDailyDateLines: true,
    unreadMessageId: view === 'all'
      ? unreadEventId
      : unreadDigestId !== undefined ? getDigestMessageId(unreadDigestId) : undefined,
    scrollRequest,
    loadFailure: errorCode && {
      text: getAgentV2ErrorText(errorCode, lang),
      isRetrying: isLoading,
      onRetry,
    },
    emptyText: items && !items.length
      ? lang(view === 'digests' ? '$agent_news_digests_empty' : '$agent_news_empty') : undefined,
    textRevealPresentations: NO_TEXT_REVEAL,
    renderMessage,
  }), [
    errorCode, isLoading, items, lang, messages, onRetry, renderMessage, scrollRequest, unreadDigestId, unreadEventId,
    view,
  ]);
  // The feed rereads its first page each time it opens. Once that page loads, older pages load in the background under
  // the prefetch rule and when scrolling near the top. New entries appear above the screen without a spinner or
  // placeholders, while visible posts keep their place.
  const history = useMemo<AgentConversationHistory>(() => ({
    hasOlderMessages: hasMore && !isLoading,
    isLoading: isLoadingMore,
    noLoadingIndicator: true,
    mode: 'continuous',
    loadOlderMessages: onLoadMore,
    thresholdRowCount: OLDER_NEWS_THRESHOLD_ROW_COUNT,
  }), [hasMore, isLoading, isLoadingMore, onLoadMore]);
  const header = useMemo<AgentConversationHeader>(() => ({
    titleContent: <AgentNewsViewSwitch view={view} onChange={onViewChange} />,
    hasBackButton: Boolean(onBack),
  }), [onBack, onViewChange, view]);
  // The panel follows the user's scrolling and shows the digest above the messages on screen, or the newest of all
  const handleScroll = useLastCallback((e: React.UIEvent<HTMLDivElement>) => {
    const container = e.currentTarget;
    if (!digests.length || isPinnedDigestHeld || isAnimatingScroll(container)) return;

    requestMeasure(() => {
      const index = getPinnedDigestIndexForScroll(container, items!, digests);
      if (index === pinnedIndex) return;

      setPinnedDigestId(digests[index].id);
    });
  });

  // As the scroll button takes the list to its end, the panel shows the digest there at once, as Telegram's does. With
  // the end not rendered, that is the newest digest.
  const handleScrollToBottom = useLastCallback((container: HTMLDivElement) => {
    if (!digests.length) return;

    setIsPinnedDigestHeld(false);
    requestMeasure(() => {
      const lastMessageId = getEntryMessageId(items![items!.length - 1]);
      const index = container.querySelector(`[data-agent-v2-message-id="${lastMessageId}"]`)
        ? getPinnedDigestIndexForScroll(container, items!, digests, container.scrollHeight - container.clientHeight)
        : digests.length - 1;
      setPinnedDigestId(digests[index].id);
    });
  });

  // A tap goes to the digest the panel shows, as on Telegram's pinned message, and the panel moves on to the one before
  // it, and from the oldest back to the newest
  const handlePinnedDigestClick = useLastCallback(() => {
    const previousIndex = pinnedIndex === 0 ? digests.length - 1 : pinnedIndex - 1;
    scrollRequestKeyRef.current += 1;
    setScrollRequest({ messageId: getDigestMessageId(digests[pinnedIndex].id), key: scrollRequestKeyRef.current });
    setPinnedDigestId(digests[previousIndex].id);
    setIsPinnedDigestHeld(true);
  });

  useEffect(() => {
    if (!isPinnedDigestHeld) return undefined;

    function releasePinnedDigest() {
      setIsPinnedDigestHeld(false);
    }

    // The tap's own click comes first, so the hold starts with the next thing the user does
    const timeout = window.setTimeout(() => {
      USER_SCROLL_EVENTS.forEach((name) => document.addEventListener(name, releasePinnedDigest, true));
    });
    return () => {
      window.clearTimeout(timeout);
      USER_SCROLL_EVENTS.forEach((name) => document.removeEventListener(name, releasePinnedDigest, true));
    };
  }, [isPinnedDigestHeld]);

  const actions = useMemo<AgentConversationActions>(() => ({
    onBack: onBack ?? NOOP,
    onScroll: handleScroll,
    onScrollToBottom: handleScrollToBottom,
    onOpenDigestSettings: openDigestSheet,
    onMessageVisible: handleMessageVisible,
  }), [handleMessageVisible, handleScroll, handleScrollToBottom, onBack, openDigestSheet]);
  const pinnedDigest = view === 'all' ? digests[pinnedIndex] : undefined;
  const slots = useMemo(() => pinnedDigest && {
    headerAccessory: {
      content: (
        <AgentNewsPinnedDigest
          title={formatFullDay(lang.code!, pinnedDigest.deliveredAt)}
          text={pinnedDigest.top.map(({ headline }) => headline).join(DIGEST_HEADLINE_SEPARATOR)}
          digestKey={Date.parse(pinnedDigest.deliveredAt)}
          index={pinnedIndex}
          count={digests.length}
          onClick={handlePinnedDigestClick}
        />
      ),
      height: PINNED_DIGEST_HEIGHT,
    },
  }, [digests.length, handlePinnedDigestClick, lang, pinnedDigest, pinnedIndex]);

  return (
    <>
      <AgentConversationShell
        isActive={isActive}
        animationLevel={animationLevel}
        conversation={conversation}
        history={history}
        header={header}
        actions={actions}
        slots={slots}
        session={session}
      />
      <AgentDigestSheet isOpen={isDigestSheetOpen} onClose={closeDigestSheet} />
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    animationLevel: global.settings.animationLevel,
  };
})(AgentNewsFeed));

function NOOP() {}

/** A news item or a digest as a message of the list, which dates it by its delivery */
function buildEntryMessage(entry: AgentNewsFeedEntry): AgentMessage {
  return {
    id: getEntryMessageId(entry),
    text: entry.kind === 'news'
      ? entry.headline
      : entry.top.map(({ headline }) => headline).join(DIGEST_HEADLINE_SEPARATOR),
    isOutgoing: false,
    timestamp: Date.parse(entry.deliveredAt),
  };
}

type DigestEntry = Extract<AgentNewsFeedEntry, { kind: 'digest' }>;

/** The digest the panel was given among those loaded, or the newest when it was given none or that one went */
function getPinnedDigestIndex(digests: DigestEntry[], id?: string) {
  const index = id === undefined ? -1 : digests.findIndex((digest) => digest.id === id);
  return index >= 0 ? index : digests.length - 1;
}

/**
 * The newest digest above the messages on screen at `scrollTop`, as Telegram shows the pinned message above them, or
 * the newest of all when none is above. The messages under the header and the panel are behind them.
 */
function getPinnedDigestIndexForScroll(
  container: HTMLElement, items: AgentNewsFeedEntry[], digests: DigestEntry[], scrollTop = container.scrollTop,
) {
  const lineY = container.getBoundingClientRect().top + (parseFloat(getComputedStyle(container).paddingTop) || 0)
    + scrollTop - container.scrollTop;
  const topElement = Array.from(container.querySelectorAll<HTMLElement>('[data-agent-v2-message-id]'))
    .find((element) => element.getBoundingClientRect().bottom > lineY);
  const topMessageId = topElement && Number(topElement.dataset.agentV2MessageId);
  const topPosition = topMessageId === undefined
    ? -1
    : items.findIndex((item) => getEntryMessageId(item) === topMessageId);
  if (topPosition < 0) return digests.length - 1;

  let index = -1;
  digests.forEach((digest, digestIndex) => {
    if (items.indexOf(digest) < topPosition) index = digestIndex;
  });
  return index >= 0 ? index : digests.length - 1;
}

function getEntryMessageId(entry: AgentNewsFeedEntry) {
  return entry.kind === 'news' ? entry.eventId : getDigestMessageId(entry.id);
}

function getDigestMessageId(id: string) {
  let messageId = digestMessageIds.get(id);
  if (messageId === undefined) {
    messageId = -(digestMessageIds.size + 1);
    digestMessageIds.set(id, messageId);
  }
  return messageId;
}
