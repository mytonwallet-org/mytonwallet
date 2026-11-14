import React, { memo, useMemo, useRef } from '../../lib/teact/teact';

import type { AgentNewsFeedDigestV2 } from '../../api/agentV2/protocol/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { AgentNewsMenuHandler } from '../agent/hooks/useAgentNewsMenu';

import buildClassName from '../../util/buildClassName';
import { formatTime } from '../../util/dateFormat';
import { toNativeDigits } from '../../util/nativeDigits';
import { getAgentBubbleMenuLayout, getAgentPointerMenuLayout } from '../agent/helpers/bubbleMenuLayout';
import formatAgentChatDate from '../agent/helpers/formatAgentChatDate';
import { formatAgentDigestHeadlines } from './agentNewsFeedItems';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentNewsMenu from '../agent/hooks/useAgentNewsMenu';

import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';
import AgentNewsDigestHeadlines from './AgentNewsDigestHeadlines';
import AgentNewsDiscussStrip from './AgentNewsDiscussStrip';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  digest: AgentNewsFeedDigestV2;
  /** The digest's place among the feed's messages */
  messageId: number;
  /** The digest came after the feed was shown, and fades in as a chat's new message does */
  isJustAdded?: boolean;
  isInDigestsView?: boolean;
  onOpenNewsDiscussion: (eventId: number, digestId: string) => void;
  /** Gets the card's bubble, which flies into the discussion */
  onOpenDigestDiscussion: (id: string, cardElement?: HTMLElement) => void;
}

// The bubble that flies into the digest's discussion
const CARD_SELECTOR = '[data-agent-news-digest-id]';

/**
 * A daily digest in the feed, in the bubble the news cards have, as on mobile: its title, how many news it covers, its
 * top headlines, each opening its news item's discussion, the news it leaves out, the time it came in the bubble's
 * trailing corner, as a news card's, and the "Discuss" strip, which opens the digest's own discussion. Its menu, as a
 * news card's, copies its title and headlines.
 */
function AgentNewsDigestCard({
  digest, messageId, isJustAdded = false, isInDigestsView = false, onOpenNewsDiscussion, onOpenDigestDiscussion,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const shouldAnimateAppearance = useRef(isJustAdded).current;
  const {
    id, deliveredAt, total, top,
  } = digest;
  const title = lang('$agent_digest_title');
  const discussionLabel = lang('$agent_news_discuss');
  const remainder = total - top.length;
  const menuDate = formatAgentChatDate(lang, Date.parse(deliveredAt));
  const menuNews = useMemo(() => ({ headline: title, body: formatAgentDigestHeadlines(top) }), [title, top]);
  const { menuItems, handleMenuItemSelect } = useAgentNewsMenu(menuNews);

  // As a news card's: at the pointer on a right click, and hanging from the bubble after a long press
  const {
    isContextMenuOpen,
    contextMenuAnchor,
    isContextMenuFromPointer,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
  } = useContextMenuHandlers({
    elementRef: ref,
    shouldDisableOnLink: true,
    shouldDisablePropagation: true,
  });

  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getMenuLayout = useLastCallback((): Layout => (
    isContextMenuFromPointer
      ? getAgentPointerMenuLayout(contextMenuAnchor)
      : getAgentBubbleMenuLayout(ref.current?.getBoundingClientRect(), contextMenuAnchor, Boolean(lang.isRtl))
  ));

  const handleHeadlineOpen = useLastCallback((eventId: number) => {
    onOpenNewsDiscussion(eventId, id);
  });

  const handleDiscussionClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    onOpenDigestDiscussion(id, e.currentTarget.closest<HTMLElement>(CARD_SELECTOR) ?? undefined);
  });

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-id={String(messageId)}
      data-agent-v2-message-role="assistant"
    >
      {isPortrait && <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />}
      <div className={styles.cardColumn}>
        <div
          ref={ref}
          className={buildClassName(
            bubbleStyles.bubble,
            bubbleStyles.incoming,
            styles.news,
            shouldAnimateAppearance && bubbleStyles.appearing,
          )}
          data-agent-news-digest-id={id}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
        >
          <div className={styles.digestHeader}>
            <h3 className={styles.newsHeadline}>{title}</h3>
            <div className={styles.digestMeta}>
              {lang('$agent_digest_meta', { count: toNativeDigits(String(total)) }, undefined, total)}
            </div>
          </div>
          <AgentNewsDigestHeadlines
            digestId={id}
            headlines={top}
            remainder={remainder}
            time={deliveredAt}
            isInDigestsView={isInDigestsView}
            onOpen={handleHeadlineOpen}
          />
          <div className={styles.digestFooter}>
            <time
              className={buildClassName(styles.newsTime, styles.newsTimeInDigestFooter)}
              dateTime={deliveredAt}
            >
              {formatTime(deliveredAt)}
            </time>
          </div>
          <AgentNewsDiscussStrip
            label={discussionLabel}
            ariaLabel={`${discussionLabel}, ${title}`}
            onClick={handleDiscussionClick}
          />
        </div>
      </div>
      {contextMenuAnchor && (
        <DropdownMenu<AgentNewsMenuHandler>
          ref={menuRef}
          isOpen={isContextMenuOpen}
          withPortal
          shouldTranslateOptions
          header={`${menuDate.day}, ${menuDate.time}`}
          items={menuItems}
          bubbleClassName={bubbleStyles.menu}
          menuAnchor={contextMenuAnchor}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getMenuLayout}
          onSelect={handleMenuItemSelect}
          onClose={handleContextMenuClose}
          onCloseAnimationEnd={handleContextMenuHide}
        />
      )}
    </div>
  );
}

export default memo(AgentNewsDigestCard);
