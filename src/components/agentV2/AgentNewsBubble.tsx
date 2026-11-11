import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef, useState } from '../../lib/teact/teact';

import type { AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { LangFn } from '../../util/langProvider';
import type { AgentNewsSourceEntry } from '../agent/helpers/agentNews';
import type { AgentNewsMenuHandler } from '../agent/hooks/useAgentNewsMenu';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { openUrl } from '../../util/openUrl';
import { getAgentNewsSourceEntries } from '../agent/helpers/agentNews';
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
  news: Pick<AgentThreadNewsCardV2, 'headline' | 'body' | 'imageUrl' | 'sources' | 'source'>;
  /** The time at the foot, where a message's time is */
  time: string;
  timeDateTime: string;
  /** The time the context menu shows in its header */
  menuTimestamp: number;
  /** The picture's place in the media viewer; a post with a picture has it, as `onOpenPicture` */
  pictureId?: string;
  isPictureLazy?: boolean;
  /** The line over a discussion's post: "News", or the digest's name and time */
  header?: TeactNode;
  /** The "Discuss" strip under a feed's card */
  footer?: TeactNode;
  className?: string;
  /** Names the bubble as the feed's card of the news with this event ID, which flies into its discussion */
  feedEventId?: number;
  onOpenPicture?: NoneToVoidFunction;
}

/**
 * A news item as the Agent's message: its picture, headline, body, its sources under the body, and the time at its
 * foot, where a message's time is. A feed's card and a discussion's post look the same and differ in what heads and
 * ends them. A digest's discussion opens with its post too, the digest's title over its headlines, without a picture
 * or sources.
 */
function AgentNewsBubble({
  news, time, timeDateTime, menuTimestamp, pictureId, isPictureLazy, header, footer, className, feedEventId,
  onOpenPicture,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const [hasImageFailed, setHasImageFailed] = useState(false);
  const { headline, body, imageUrl } = news;
  const isFeedCard = feedEventId !== undefined;
  const hasPicture = Boolean(imageUrl) && !hasImageFailed;
  const sourceEntries = getAgentNewsSourceEntries(news);
  const hasSources = sourceEntries.length > 0;
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

  // A source opens as the menu's "Open Source" does, rather than as a plain link in a new tab
  const handleSourceClick = useLastCallback((e: React.MouseEvent<HTMLAnchorElement>) => {
    stopEvent(e);
    void openUrl(e.currentTarget.getAttribute('href')!);
  });

  const handleImageError = useLastCallback(() => {
    setHasImageFailed(true);
  });

  // The picture is a button, which Enter and Space press
  const handleImageKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLImageElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    e.preventDefault();
    onOpenPicture!();
  });

  return (
    <>
      {isPortrait && <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />}
      <div
        ref={ref}
        className={buildClassName(bubbleStyles.bubble, bubbleStyles.incoming, styles.news, className)}
        data-agent-news-event-id={isFeedCard ? String(feedEventId) : undefined}
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
          {hasSources && (
            <div className={styles.newsSources}>{renderSources(lang, sourceEntries, handleSourceClick)}</div>
          )}
          <time
            className={buildClassName(styles.newsTime, hasSources && styles.newsTimeUnderSources)}
            dateTime={timeDateTime}
          >
            {time}
          </time>
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

/** "Sources: CoinDesk, The Block", each source a link when the app can open it */
function renderSources(
  lang: LangFn,
  entries: AgentNewsSourceEntry[],
  onSourceClick: (e: React.MouseEvent<HTMLAnchorElement>) => void,
) {
  const separator = lang('$joining_comma');
  const sources = entries.map(({ name, url }, index) => [
    index > 0 && separator,
    url ? (
      <a
        key={name}
        className={styles.newsSourceLink}
        href={url}
        target="_blank"
        rel="noopener noreferrer"
        onClick={onSourceClick}
      >
        {name}
      </a>
    ) : name,
  ]);

  return entries.length === 1
    ? lang('$agent_news_source', { sources })
    : lang('$agent_news_sources', { sources });
}

export default AgentNewsBubble;
