import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type {
  AgentNewsFeedLocaleV2, AgentPublicFollowUpV2, AgentThreadDigestCardV2, AgentThreadNewsCardV2,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import { MediaType } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { getAgentNewsPostKey, getIsAgentNewsCardFlying, waitForAgentNewsCardLanding } from './agentNewsCardFlight';
import { formatAgentDigestHeadlines, formatAgentNewsPostTime } from './agentNewsFeedItems';
import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentMessageControls from './AgentMessageControls';
import AgentNewsBubble from './AgentNewsBubble';
import AgentNewsDigestHeadlines from './AgentNewsDigestHeadlines';
import AgentNewsIcon from './AgentNewsIcon';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

type OwnProps = {
  message: AgentMessage;
  /** The language the discussion opened the news in, which its shared link names */
  locale?: AgentNewsFeedLocaleV2;
  isDisabled: boolean;
  shouldShowFollowups: boolean;
  /** The chat failed to load, so no placeholders wait for the post's suggestions */
  hasLoadFailed?: boolean;
  /** The suggestions grow into place where motion is allowed, as an answer's do */
  shouldAnimateFollowups?: boolean;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  /** Called on each frame while the suggestions open their space, so that a list at its end can follow them */
  onFollowupsGrowthFrame?: NoneToVoidFunction;
  /** A digest's headline opens its news item's discussion */
  onOpenDigestNews?: (eventId: number) => void;
} & (
  | { news: AgentThreadNewsCardV2; digest?: undefined }
  | { news?: undefined; digest: AgentThreadDigestCardV2 }
);

// Suggestions the post has waited this long for get placeholders, which fade in then; sooner ones come in without
// them, as on iOS
const FOLLOWUP_PLACEHOLDER_DELAY = 1000;
// The post waits for its suggestions this long, as on iOS; a post that gets none by then shows none
const FOLLOWUP_WAIT_TIMEOUT = 25000;

/**
 * The news a chat discusses, posted at its start as the feed's card of it, under a "News" line and with the
 * suggestions in place of the card's "Discuss" strip, as on mobile. A digest's discussion starts with the digest's
 * post in the same way: its title over its headlines, listed as on its card, under the digest's name and time,
 * without a picture of its own.
 */
function AgentNewsPost({
  news,
  digest,
  message,
  locale,
  isDisabled,
  shouldShowFollowups,
  hasLoadFailed = false,
  shouldAnimateFollowups = false,
  onFollowup,
  onFollowupsGrowthFrame,
  onOpenDigestNews,
}: OwnProps) {
  const lang = useLang();
  const postKey = getAgentNewsPostKey(news ?? digest);
  const [isFollowupWaitLong, markFollowupWaitLong, resetFollowupWaitLong] = useFlag(false);
  const [hasFollowupWaitExpired, expireFollowupWait] = useFlag(false);
  // The post waits for its suggestions while they would show under it and have not come, and the delays count from
  // when it starts to, as on iOS
  const isWaitingForFollowups = shouldShowFollowups && !hasLoadFailed && !message.followups?.length
    && !hasFollowupWaitExpired;
  useEffect(() => {
    if (!isWaitingForFollowups) {
      resetFollowupWaitLong();
      return undefined;
    }

    const placeholderTimeout = window.setTimeout(markFollowupWaitLong, FOLLOWUP_PLACEHOLDER_DELAY);
    const timeout = window.setTimeout(expireFollowupWait, FOLLOWUP_WAIT_TIMEOUT);
    return () => {
      window.clearTimeout(placeholderTimeout);
      window.clearTimeout(timeout);
    };
  }, [expireFollowupWait, isWaitingForFollowups, markFollowupWaitLong, resetFollowupWaitLong]);
  const isLoadingFollowups = isWaitingForFollowups && isFollowupWaitLong;
  // The suggestions wait for the card flying in from the feed to turn into the post
  const [isCardLanded, setIsCardLanded] = useState(() => !getIsAgentNewsCardFlying(postKey));
  const areFollowupsShown = shouldShowFollowups && isCardLanded;
  // As under an answer, suggestions that come while the chat is open grow into place, whether the post came in a card's
  // flight or, as from a digest's headline, without one; a post from the history has them already
  const hadFollowupsAtMountRef = useRef(areFollowupsShown && Boolean(message.followups?.length));
  const body = news && (news.body || news.excerpt);
  // Suggestions and the placeholders that stand in for them hang from the post, which has no tail over them while they
  // show, as an answer does and as on iOS
  const bubbleClassName = areFollowupsShown && (Boolean(message.followups?.length) || isLoadingFollowups)
    ? bubbleStyles.tailless
    : undefined;

  // The viewer shows the post's picture alone
  const handleImageClick = useLastCallback(() => {
    const pictures = buildAgentNewsPictures([{ ...news!, body, time: news!.publishedAt }], 'post', locale);
    getActions().openMediaViewer({ mediaType: MediaType.AgentNews, mediaId: pictures.ids[0], pictures });
  });

  const handleFollowup = useLastCallback((followup: AgentPublicFollowUpV2) => {
    onFollowup?.(message.id, followup);
  });

  const handleDigestNewsOpen = useLastCallback((eventId: number) => {
    onOpenDigestNews?.(eventId);
  });

  useEffect(() => {
    if (isCardLanded) return undefined;

    return waitForAgentNewsCardLanding(postKey, () => setIsCardLanded(true));
  }, [postKey, isCardLanded]);

  function renderNewsBubble(newsCard: AgentThreadNewsCardV2) {
    return (
      <AgentNewsBubble
        news={{ ...newsCard, body }}
        locale={locale}
        // The foot tells when the news was published, with its date unless it is today's; the menu dates the post
        // message, as on mobile
        time={formatAgentNewsPostTime(lang.code ?? 'en', newsCard.publishedAt)}
        timeDateTime={newsCard.publishedAt}
        menuTimestamp={message.timestamp}
        pictureId={getAgentNewsPictureId('post', newsCard.eventId)}
        className={bubbleClassName}
        header={renderHeader(lang('News'))}
        onOpenPicture={handleImageClick}
      />
    );
  }

  // The digest's day ends at its foot and in its header, which tells the time as the feed's cards do
  function renderDigestBubble({
    id, windowEnd, top, total,
  }: AgentThreadDigestCardV2) {
    return (
      <AgentNewsBubble
        // The headlines are copied one per line
        news={{
          headline: lang('$agent_digest_title'),
          body: formatAgentDigestHeadlines(top),
        }}
        content={(
          <AgentNewsDigestHeadlines
            digestId={id}
            headlines={top}
            remainder={total - top.length}
            time={windowEnd}
            isInText
            onOpen={handleDigestNewsOpen}
          />
        )}
        time={formatAgentNewsPostTime(lang.code ?? 'en', windowEnd)}
        timeDateTime={windowEnd}
        menuTimestamp={message.timestamp}
        className={bubbleClassName}
        header={renderHeader(lang('News'))}
      />
    );
  }

  function renderHeader(text: TeactNode) {
    return (
      <div className={styles.postHeader}>
        <AgentNewsIcon className={styles.postIcon} />
        {text}
      </div>
    );
  }

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-role="assistant"
      data-agent-news-post-event-id={news && String(news.eventId)}
      data-agent-news-post-key={postKey}
      data-agent-digest-post-id={digest?.id}
    >
      <div className={styles.postColumn}>
        {news ? renderNewsBubble(news) : renderDigestBubble(digest)}
        <AgentMessageControls
          followups={message.followups}
          isLoadingFollowups={isLoadingFollowups}
          isDisabled={isDisabled}
          shouldShowFollowups={areFollowupsShown}
          shouldAnimateGrowth={shouldAnimateFollowups && !hadFollowupsAtMountRef.current}
          onGrowthFrame={onFollowupsGrowthFrame}
          onFollowup={handleFollowup}
        />
      </div>
    </div>
  );
}

export default memo(AgentNewsPost);
