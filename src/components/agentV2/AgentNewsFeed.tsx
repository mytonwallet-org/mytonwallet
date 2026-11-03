import React, { memo, useMemo } from '../../lib/teact/teact';
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
import { MediaType } from '../../global/types';

import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';
import { getAgentV2ErrorText } from './agentV2Copy';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentConversationShell from '../agent/AgentConversationShell';
import AgentNewsCard from './AgentNewsCard';

interface OwnProps {
  isActive: boolean;
  items?: AgentNewsFeedItemV2[];
  unreadEventId?: number;
  /** The news to show first, as when the user comes back from its chat */
  initialEventId?: number;
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
  onOpenDiscussion: (item: AgentNewsFeedItemV2, cardElement?: HTMLElement) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
}

const NO_TEXT_REVEAL: AgentConversation['textRevealPresentations'] = {};
const NO_MESSAGES: AgentMessage[] = [];

/**
 * The news, newest at the bottom as in a channel, in the list of a chat without a field, under the chat header titled
 * "News", as on mobile. Each news item is a message of the list, shown as its card.
 */
function AgentNewsFeed({
  isActive,
  items,
  unreadEventId,
  initialEventId,
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
  onOpenDiscussion,
}: OwnProps & StateProps) {
  const lang = useLang();
  const itemsById = useMemo(() => new Map(items?.map((item) => [item.eventId, item])), [items]);
  const messages = useMemo(() => items?.map(buildNewsMessage) ?? NO_MESSAGES, [items]);
  // The media viewer pages through the pictures of the news loaded, in the feed's order
  const pictures = useMemo(() => (
    items ? buildAgentNewsPictures(items.map((item) => ({ ...item, time: item.deliveredAt })), 'feed') : undefined
  ), [items]);
  // A feed that loaded without news reads as unavailable, as when the server says so
  const failureCode = errorCode ?? (items && !items.length ? 'news_unavailable' : undefined);

  // A picture is opened from a card, and cards render only from `items`, from which `pictures` is built
  const handleOpenPicture = useLastCallback((eventId: number) => {
    getActions().openMediaViewer({
      mediaType: MediaType.AgentNews,
      mediaId: getAgentNewsPictureId('feed', eventId),
      pictures: pictures!,
    });
  });

  const renderMessage = useLastCallback((message: AgentMessage, context: AgentConversationMessageContext) => {
    const item = itemsById.get(message.id);
    if (!item) return undefined;

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

  const conversation = useMemo<AgentConversation>(() => ({
    messages,
    isInitialLoadComplete: Boolean(items),
    hasHistoryPlaceholder: true,
    isNewsPlaceholder: true,
    hasDailyDateLines: true,
    unreadMessageId: unreadEventId,
    initialMessageId: initialEventId,
    loadFailure: failureCode && {
      text: getAgentV2ErrorText(failureCode, lang),
      isRetrying: isLoading,
      onRetry,
    },
    textRevealPresentations: NO_TEXT_REVEAL,
    renderMessage,
  }), [failureCode, initialEventId, isLoading, items, lang, messages, onRetry, renderMessage, unreadEventId]);
  // The feed reads its first page again each time it opens, and older news load only once that page is in
  const history = useMemo<AgentConversationHistory>(() => ({
    hasOlderMessages: hasMore && !isLoading,
    isLoading: isLoadingMore,
    mode: 'continuous',
    loadOlderMessages: onLoadMore,
  }), [hasMore, isLoading, isLoadingMore, onLoadMore]);
  const header = useMemo<AgentConversationHeader>(() => ({
    title: lang('News'),
    hasBackButton: Boolean(onBack),
  }), [lang, onBack]);
  const actions = useMemo<AgentConversationActions>(() => ({ onBack: onBack ?? NOOP }), [onBack]);

  return (
    <AgentConversationShell
      isActive={isActive}
      animationLevel={animationLevel}
      conversation={conversation}
      history={history}
      header={header}
      actions={actions}
      session={session}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    animationLevel: global.settings.animationLevel,
  };
})(AgentNewsFeed));

function NOOP() {}

/** A news item as a message of the list, which dates it by its delivery */
function buildNewsMessage({ eventId, headline, deliveredAt }: AgentNewsFeedItemV2): AgentMessage {
  return {
    id: eventId,
    text: headline,
    isOutgoing: false,
    timestamp: Date.parse(deliveredAt),
  };
}
