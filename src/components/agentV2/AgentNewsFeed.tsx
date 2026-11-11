import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { AgentNewsFeedItemV2, AgentV2ErrorCode } from '../../api/agentV2/protocol/types';
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
import { MediaType } from '../../global/types';

import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';
import { getAgentV2ErrorText } from './agentV2Copy';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentDigestSheet from './AgentDigestSheet';
import AgentNewsCard from './AgentNewsCard';
import AgentNewsDigestCard from './AgentNewsDigestCard';

interface OwnProps {
  isActive: boolean;
  items?: AgentNewsFeedEntry[];
  unreadEventId?: number;
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
  /** Opens the discussion of a news item a digest's headline names */
  onOpenNewsDiscussion: (eventId: number) => void;
  onOpenDigestDiscussion: (id: string) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

const NO_TEXT_REVEAL: AgentConversation['textRevealPresentations'] = {};
const NO_MESSAGES: AgentMessage[] = [];
// Android's `AGENT_HISTORY_LOAD_THRESHOLD`, so that older news start loading at the same row on every platform
const OLDER_NEWS_THRESHOLD_ROW_COUNT = 5;
const DIGEST_HEADLINE_SEPARATOR = ' · ';
// A digest is a message of the list under an ID of its own, below zero, where no news' event ID is. It keeps that ID
// while the app runs, so that its card stays in place as pages load.
const digestMessageIds = new Map<string, number>();

/**
 * The news, newest at the bottom as in a channel, in the list of a chat without a field, under the chat header titled
 * "News", as on mobile. Each news item is a message of the list, shown as its card, and so is each daily digest. The
 * bell in the header opens the digest's hour.
 */
function AgentNewsFeed({
  isActive,
  items,
  unreadEventId,
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
  // A feed that comes on screen with its news in hand, as on the way back from a discussion, shows them at once where
  // it was left, with no placeholders to grow out of, as on mobile
  const hasNewsAtMountRef = useRef(Boolean(items));
  const [isDigestSheetOpen, openDigestSheet, closeDigestSheet] = useFlag();
  const newsItems = useMemo(() => items?.filter((item) => item.kind === 'news'), [items]);
  const itemsByMessageId = useMemo(
    () => new Map(items?.map((item) => [getEntryMessageId(item), item])), [items],
  );
  const messages = useMemo(() => items?.map(buildEntryMessage) ?? NO_MESSAGES, [items]);
  // The media viewer pages through the pictures of the news loaded, in the feed's order
  const pictures = useMemo(() => (
    newsItems
      ? buildAgentNewsPictures(newsItems.map((item) => ({ ...item, time: item.deliveredAt })), 'feed') : undefined
  ), [newsItems]);

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
    unreadMessageId: unreadEventId,
    loadFailure: errorCode && {
      text: getAgentV2ErrorText(errorCode, lang),
      isRetrying: isLoading,
      onRetry,
    },
    emptyText: items && !items.length ? lang('$agent_news_empty') : undefined,
    textRevealPresentations: NO_TEXT_REVEAL,
    renderMessage,
  }), [errorCode, isLoading, items, lang, messages, onRetry, renderMessage, unreadEventId]);
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
    title: lang('News'),
    hasBackButton: Boolean(onBack),
  }), [lang, onBack]);
  const actions = useMemo<AgentConversationActions>(() => ({
    onBack: onBack ?? NOOP,
    onOpenDigestSettings: openDigestSheet,
    onMessageVisible: handleMessageVisible,
  }), [handleMessageVisible, onBack, openDigestSheet]);

  return (
    <>
      <AgentConversationShell
        isActive={isActive}
        animationLevel={animationLevel}
        conversation={conversation}
        history={history}
        header={header}
        actions={actions}
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

function getEntryMessageId(entry: AgentNewsFeedEntry) {
  if (entry.kind === 'news') return entry.eventId;

  let messageId = digestMessageIds.get(entry.id);
  if (messageId === undefined) {
    messageId = -(digestMessageIds.size + 1);
    digestMessageIds.set(entry.id, messageId);
  }
  return messageId;
}
