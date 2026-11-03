import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef, useState } from '../../lib/teact/teact';

import type { AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { AgentNewsMenuHandler } from '../agent/hooks/useAgentNewsMenu';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { getAgentNewsSourceName, getAgentNewsSourceUrl, openAgentNewsSource } from '../agent/helpers/agentNews';
import { getAgentBubbleMenuLayout, getAgentPointerMenuLayout } from '../agent/helpers/bubbleMenuLayout';
import formatAgentChatDate from '../agent/helpers/formatAgentChatDate';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentNewsMenu from '../agent/hooks/useAgentNewsMenu';

import AgentNewsBody from '../agent/AgentNewsBody';
import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  news: Pick<AgentThreadNewsCardV2, 'eventId' | 'headline' | 'body' | 'imageUrl' | 'sources' | 'source'>;
  /** The time at the foot, next to the source */
  time: string;
  timeDateTime: string;
  /** The time the context menu shows in its header */
  menuTimestamp: number;
  pictureId: string;
  isPictureLazy?: boolean;
  /** The "News" line over a discussion's post */
  header?: TeactNode;
  /** The "Discuss" strip under a feed's card */
  footer?: TeactNode;
  className?: string;
  /** Names the bubble as the feed's card of the news, which flies into its discussion */
  isFeedCard?: boolean;
  onOpenPicture: NoneToVoidFunction;
}

/**
 * A news item as the Agent's message: its picture, headline, body, and the source and time at its foot, where a
 * message's time is. A feed's card and a discussion's post look the same and differ in what heads and ends them.
 */
function AgentNewsBubble({
  news, time, timeDateTime, menuTimestamp, pictureId, isPictureLazy, header, footer, className, isFeedCard,
  onOpenPicture,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const [hasImageFailed, setHasImageFailed] = useState(false);
  const {
    eventId, headline, body, imageUrl,
  } = news;
  const hasPicture = Boolean(imageUrl) && !hasImageFailed;
  const sourceUrl = getAgentNewsSourceUrl(news);
  const sourceName = getAgentNewsSourceName(news);
  const menuDate = formatAgentChatDate(lang, menuTimestamp);

  const { menuItems, handleMenuItemSelect } = useAgentNewsMenu(news);

  // The menu is a message's: at the pointer on a right click, and hanging from the bubble after a long press, with the
  // rest of the screen tinted on a phone
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

  const handleSourceClick = useLastCallback((e: React.MouseEvent<HTMLAnchorElement>) => {
    stopEvent(e);
    void openAgentNewsSource(news);
  });

  const handleImageError = useLastCallback(() => {
    setHasImageFailed(true);
  });

  // The picture is a button, which Enter and Space press
  const handleImageKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLImageElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    e.preventDefault();
    onOpenPicture();
  });

  return (
    <>
      {isPortrait && <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />}
      <div
        ref={ref}
        className={buildClassName(bubbleStyles.bubble, bubbleStyles.incoming, styles.news, className)}
        data-agent-news-event-id={isFeedCard ? String(eventId) : undefined}
        data-agent-news-post-bubble={!isFeedCard || undefined}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
      >
        {header}
        {hasPicture && (
          <img
            className={buildClassName(styles.newsPicture, header && styles.newsPictureUnderHeader)}
            src={imageUrl}
            alt=""
            role="button"
            aria-label={headline}
            tabIndex={0}
            loading={isPictureLazy ? 'lazy' : undefined}
            data-media-viewer-picture-id={pictureId}
            onClick={onOpenPicture}
            onKeyDown={handleImageKeyDown}
            onError={handleImageError}
          />
        )}
        <div className={buildClassName(styles.newsText, header && !hasPicture && styles.newsTextUnderHeader)}>
          <h3 className={styles.newsHeadline}>{headline}</h3>
          {body && <p className={styles.newsBody}><AgentNewsBody body={body} /></p>}
          <div className={styles.newsMeta}>
            {sourceName && (sourceUrl ? (
              <a
                className={buildClassName(styles.newsSource, styles.newsSourceLink)}
                href={sourceUrl}
                target="_blank"
                rel="noopener noreferrer"
                onClick={handleSourceClick}
              >
                {sourceName}
              </a>
            ) : (
              <span className={styles.newsSource}>{sourceName}</span>
            ))}
            <time
              className={buildClassName(styles.newsTime, sourceName && styles.newsTimeAfterSource)}
              dateTime={timeDateTime}
            >
              {time}
            </time>
          </div>
        </div>
        {footer}
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
    </>
  );
}

export default AgentNewsBubble;
