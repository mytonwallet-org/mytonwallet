import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AgentPublicFollowUpV2, AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import { MediaType } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { getIsAgentNewsCardFlying, waitForAgentNewsCardLanding } from './agentNewsCardFlight';
import { formatAgentNewsPostTime } from './agentNewsFeedItems';
import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentMessageControls from './AgentMessageControls';
import AgentNewsBubble from './AgentNewsBubble';
import AgentNewsIcon from './AgentNewsIcon';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  news: AgentThreadNewsCardV2;
  message: AgentMessage;
  isDisabled: boolean;
  shouldShowFollowups: boolean;
  /** The suggestions grow into place where motion is allowed, as an answer's do */
  shouldAnimateFollowups?: boolean;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  /** Called on each frame while the suggestions open their space, so that a list at its end can follow them */
  onFollowupsGrowthFrame?: NoneToVoidFunction;
}

// Placeholders stand in for the post's suggestions this long, as on iOS; a post that gets none by then shows none
const FOLLOWUP_WAIT_TIMEOUT = 25000;

/**
 * The news a chat discusses, posted at its start as the feed's card of it, under a "News" line and with the
 * suggestions in place of the card's "Discuss" strip, as on mobile
 */
function AgentNewsPost({
  news, message, isDisabled, shouldShowFollowups, shouldAnimateFollowups = false, onFollowup, onFollowupsGrowthFrame,
}: OwnProps) {
  const lang = useLang();
  const [hasFollowupWaitExpired, expireFollowupWait, restartFollowupWait] = useFlag(false);
  useEffect(() => {
    restartFollowupWait();
    const timeout = window.setTimeout(expireFollowupWait, FOLLOWUP_WAIT_TIMEOUT);
    return () => window.clearTimeout(timeout);
  }, [expireFollowupWait, news.eventId, restartFollowupWait]);
  // The suggestions wait for the card flying in from the feed to turn into the post
  const [isCardLanded, setIsCardLanded] = useState(() => !getIsAgentNewsCardFlying(news.eventId));
  const areFollowupsShown = shouldShowFollowups && isCardLanded;
  // As under an answer, suggestions that come while the chat is open grow into place; a post from the history has them
  // already
  const hadFollowupsAtMountRef = useRef(areFollowupsShown);
  const body = news.body || news.excerpt;

  // The viewer shows the post's picture alone
  const handleImageClick = useLastCallback(() => {
    const pictures = buildAgentNewsPictures([{ ...news, body, time: news.publishedAt }], 'post');
    getActions().openMediaViewer({ mediaType: MediaType.AgentNews, mediaId: pictures.ids[0], pictures });
  });

  const handleFollowup = useLastCallback((followup: AgentPublicFollowUpV2) => {
    onFollowup?.(message.id, followup);
  });

  useEffect(() => {
    if (isCardLanded) return undefined;

    return waitForAgentNewsCardLanding(news.eventId, () => setIsCardLanded(true));
  }, [isCardLanded, news.eventId]);

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-role="assistant"
      data-agent-news-post-event-id={String(news.eventId)}
    >
      <div className={styles.postColumn}>
        <AgentNewsBubble
          news={{ ...news, body }}
          // The foot tells when the news was published, with its date unless it is today's; the menu dates the post
          // message, as on mobile
          time={formatAgentNewsPostTime(lang.code ?? 'en', news.publishedAt)}
          timeDateTime={news.publishedAt}
          menuTimestamp={message.timestamp}
          pictureId={getAgentNewsPictureId('post', news.eventId)}
          // Suggestions hang from the post, which has no tail over them, as an answer does
          className={shouldShowFollowups && Boolean(message.followups?.length) ? bubbleStyles.tailless : undefined}
          header={(
            <div className={styles.postHeader}>
              <AgentNewsIcon className={styles.postIcon} />
              {lang('News')}
            </div>
          )}
          onOpenPicture={handleImageClick}
        />
        <AgentMessageControls
          followups={message.followups}
          isLoadingFollowups={!hasFollowupWaitExpired && !message.followups?.length}
          isDisabled={isDisabled}
          shouldShowFollowups={shouldShowFollowups && isCardLanded}
          shouldAnimateGrowth={shouldAnimateFollowups && !hadFollowupsAtMountRef.current}
          onGrowthFrame={onFollowupsGrowthFrame}
          onFollowup={handleFollowup}
        />
      </div>
    </div>
  );
}

export default memo(AgentNewsPost);
