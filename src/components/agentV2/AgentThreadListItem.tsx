import React, {
  type ElementRef, memo, useRef,
} from '../../lib/teact/teact';

import type { AgentThreadListItemV2, AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import { getIsAgentV2SupportActive } from '../../global/agentV2/uiCapabilities';
import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { stopEvent } from '../../util/domEvents';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { formatAgentListTime, formatAgentTime } from '../agent/helpers/agentDateFormat';
import { getAgentPointerMenuLayout } from '../agent/helpers/bubbleMenuLayout';
import { getAvatarGradientColors } from '../ui/helpers/getAvatarGradientColor';
import useAgentThreadSwipe, { closeAgentThreadSwipe } from './useAgentThreadSwipe';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { POSITIONING as MENU_POSITIONING } from '../../hooks/useMenuPosition';
import useShowTransition from '../../hooks/useShowTransition';

import AgentSearchGlyph from '../agent/AgentSearchGlyph';
import AgentSpinningTop from '../agent/AgentSpinningTop';
import Transition from '../ui/Transition';
import WithContextMenu from '../ui/WithContextMenu';
import AgentSupportIcon from './AgentSupportIcon';
import AgentThreadThumbnail from './AgentThreadThumbnail';

import supportStyles from './AgentSupport.module.scss';
import styles from './AgentThreadList.module.scss';

interface OwnProps {
  item: AgentThreadListItemV2;
  support?: AgentThreadSummaryV2['support'];
  /** The chat holds an answer the user has not seen */
  isUnread: boolean;
  /** What the Agent is doing in the chat while it answers, as a localization key */
  activityLangKey?: string;
  /** The row has turned to dust and keeps its place until the chat leaves the list */
  isDissolved?: boolean;
  onSelect: (threadId: string) => void;
  onRename: (thread: AgentThreadSummaryV2) => void;
  onTogglePin: (thread: AgentThreadSummaryV2) => void;
  onDelete: (thread: AgentThreadSummaryV2) => void;
}

type MenuHandler = 'pin' | 'rename' | 'delete';

// The menu hangs from the row, 48 px in from its end, overlapping its bottom by 12 px, as in the design; near the
// end of the list it overlaps the row's top instead
const MENU_END_INSET = 48;
const MENU_OVERLAP = 12;
const SWIPE_CLASS_NAMES = {
  swiped: styles.swiped,
  armed: styles.swipeArmed,
  actionShown: styles.swipeActionShown,
};
const RENAME_MENU_ITEM: DropdownItem<MenuHandler> = { value: 'rename', name: 'Rename', fontIcon: 'menu-rename' };
const DELETE_MENU_ITEM: DropdownItem<MenuHandler> = {
  value: 'delete', name: 'Delete', fontIcon: 'menu-trash', isDangerous: true, withDelimiter: true,
};
const UNPINNED_MENU_ITEMS: DropdownItem<MenuHandler>[] = [
  RENAME_MENU_ITEM,
  { value: 'pin', name: 'Pin', fontIcon: 'menu-pin' },
  DELETE_MENU_ITEM,
];
const PINNED_MENU_ITEMS: DropdownItem<MenuHandler>[] = [
  RENAME_MENU_ITEM,
  { value: 'pin', name: 'Unpin', fontIcon: 'menu-unpin' },
  DELETE_MENU_ITEM,
];

/** The chat's emoji, or the Agent mark until it has one, on the chat's own gradient */
const AgentThreadAvatar = memo(({ thread }: { thread: AgentThreadSummaryV2 }) => {
  const [startColor, endColor] = getAvatarGradientColors(thread.id);

  return (
    <span
      className={styles.avatar}
      style={buildStyle(`--start-color: ${startColor}; --end-color: ${endColor}`)}
      aria-hidden
    >
      {thread.icon || <AgentSearchGlyph className={styles.avatarMark} />}
    </span>
  );
});

function AgentThreadListItem({
  item, support, isUnread, activityLangKey, isDissolved, onSelect, onRename, onTogglePin, onDelete,
}: OwnProps) {
  const lang = useLang();
  const { thread, preview } = item;
  // Without a title the preview names the chat and is not repeated under it
  const title = thread.title || preview || lang('New Chat');
  const previewText = thread.title ? preview : undefined;
  // The row shows the picture of its latest message, as Telegram's chat list does. Only a news post has one, and it is
  // a discussion's latest message while it is the thread's only one.
  const previewImageUrl = previewText && thread.messageCount <= 1 ? thread.news?.imageUrl : undefined;
  // A chat that support has carries its label before the preview, bright while an operator is in it
  const isWithSupport = getIsAgentV2SupportActive({ support });
  // A row under a day header has the time of day only; a pinned row names its day as well
  const time = thread.isPinned
    ? formatAgentListTime(lang, thread.lastActivityAt)
    : formatAgentTime(lang.code ?? 'en', thread.lastActivityAt);
  const swipeRef = useRef<HTMLDivElement>();
  const isAnswering = Boolean(activityLangKey);
  const renderedActivityLangKey = useCurrentOrPrev(activityLangKey, true);

  // The status takes the preview's place while the Agent answers, as typing does in a messenger's chat list
  const { ref: previewRef } = useShowTransition<HTMLSpanElement>({
    isOpen: !isAnswering,
    noMountTransition: true,
  });
  const { ref: activityRef, shouldRender: shouldRenderActivity } = useShowTransition<HTMLSpanElement>({
    isOpen: isAnswering,
    noMountTransition: true,
    withShouldRender: true,
  });

  // A new step slides in over the previous one
  const activityKeyRef = useRef({ langKey: renderedActivityLangKey, key: 0 });
  if (activityKeyRef.current.langKey !== renderedActivityLangKey) {
    activityKeyRef.current = { langKey: renderedActivityLangKey, key: activityKeyRef.current.key + 1 };
  }

  const menuItems = thread.isPinned ? PINNED_MENU_ITEMS : UNPINNED_MENU_ITEMS;

  const handleMenuItemClick = useLastCallback((value: MenuHandler) => {
    switch (value) {
      case 'pin':
        onTogglePin(thread);
        break;
      case 'rename':
        onRename(thread);
        break;
      case 'delete':
        onDelete(thread);
        break;
    }
  });

  const handleClick = useLastCallback(() => {
    onSelect(thread.id);
  });

  // A right click opens the menu at the pointer, as on a token or a message. After a long press, it hangs from the
  // row's end.
  const getMenuLayout = useLastCallback((
    anchor: IAnchorPosition, row: HTMLElement, isFromPointer: boolean,
  ): Partial<Layout> => {
    if (isFromPointer) return getAgentPointerMenuLayout(anchor);

    const rect = row.getBoundingClientRect();
    // The menu keeps its own offsets from the area it keeps clear of and from its anchor, which these take back
    const inset = MENU_OVERLAP + MENU_POSITIONING.TRIGGER_OFFSET;
    const top = rect.top + inset;
    const bottom = Math.max(top, rect.bottom - inset);
    return {
      anchor: { x: lang.isRtl ? rect.left + MENU_END_INSET : rect.right - MENU_END_INSET, y: rect.bottom },
      isCenteredHorizontally: false,
      doNotCoverTrigger: true,
      preferredPositionX: lang.isRtl ? 'left' : 'right',
      deltaX: (lang.isRtl ? -1 : 1) * MENU_POSITIONING.HORIZONTAL_OFFSET,
      triggerRect: {
        left: rect.left, right: rect.right, width: rect.width, top, bottom, height: bottom - top,
      },
    };
  });

  const handleSwipeDelete = useLastCallback(() => {
    closeAgentThreadSwipe();
    onDelete(thread);
  });

  const handleSwipePin = useLastCallback(() => {
    closeAgentThreadSwipe();
    onTogglePin(thread);
  });

  const handleSwipeRename = useLastCallback(() => {
    closeAgentThreadSwipe();
    onRename(thread);
  });

  useAgentThreadSwipe({
    rowRef: swipeRef,
    classNames: SWIPE_CLASS_NAMES,
    isRtl: Boolean(lang.isRtl),
    onFullSwipe: handleSwipeDelete,
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.target !== e.currentTarget || (e.key !== 'Enter' && e.key !== ' ')) return;
    stopEvent(e);
    onSelect(thread.id);
  });

  const ariaLabel = [
    title,
    isWithSupport ? lang('$agent_support_label') : undefined,
    activityLangKey ? lang(activityLangKey) : previewText,
    time,
    thread.isPinned ? lang('Pinned') : undefined,
    isUnread ? lang('Unread') : undefined,
  ].filter(Boolean).join(', ');

  // Touch screens reveal the row's actions under it with a swipe toward the leading edge
  function renderSwipeActions() {
    return (
      <div className={styles.swipeActions} aria-hidden>
        <button
          type="button"
          tabIndex={-1}
          className={buildClassName(styles.swipeAction, styles.swipeDelete)}
          data-swipe-action-index={0}
          onClick={handleSwipeDelete}
        >
          <i className={buildClassName(styles.swipeDeleteIcon, 'icon-trash')} />
        </button>
        <button
          type="button"
          tabIndex={-1}
          className={buildClassName(styles.swipeAction, styles.swipePin)}
          data-swipe-action-index={1}
          onClick={handleSwipePin}
        >
          <i className={thread.isPinned ? 'icon-menu-unpin' : 'icon-pin'} />
        </button>
        <button
          type="button"
          tabIndex={-1}
          className={buildClassName(styles.swipeAction, styles.swipeRename)}
          data-swipe-action-index={2}
          onClick={handleSwipeRename}
        >
          <i className="icon-pen" />
        </button>
      </div>
    );
  }

  return (
    <WithContextMenu
      items={menuItems}
      layout={getMenuLayout}
      menuClassName={styles.rowMenu}
      onItemClick={handleMenuItemClick}
      withBackdrop
    >
      {({ ref, onMouseDown, onContextMenu }, isMenuOpen) => (
        <div
          ref={ref as ElementRef<HTMLDivElement>}
          className={buildClassName(styles.item, isMenuOpen && styles.menuOpen, isDissolved && styles.dissolved)}
          data-agent-row-key={thread.id}
          onMouseDown={onMouseDown}
          onContextMenu={onContextMenu}
        >
          <div ref={swipeRef} className={styles.swipeArea}>
            {IS_TOUCH_ENV && renderSwipeActions()}
            <div
              role="button"
              tabIndex={0}
              aria-label={ariaLabel}
              className={styles.itemButton}
              data-agent-v2-thread-id={thread.id}
              onClick={handleClick}
              onKeyDown={handleKeyDown}
            >
              <AgentThreadAvatar thread={thread} />
              <div className={styles.itemText} aria-hidden>
                <div className={styles.itemTop}>
                  {thread.isPinned && <i className={buildClassName(styles.pinIcon, 'icon-pin')} aria-hidden />}
                  <span className={styles.itemTitle}>{title}</span>
                  <span className={styles.itemTime}>{time}</span>
                </div>
                <div className={styles.itemBottom}>
                  <div className={styles.itemStatus}>
                    <span ref={previewRef} className={styles.itemPreview}>
                      {previewImageUrl && <AgentThreadThumbnail url={previewImageUrl} />}
                      {isWithSupport && (
                        <span
                          className={buildClassName(
                            supportStyles.label,
                            support!.state === 'operator' ? supportStyles.labelActive : supportStyles.labelMuted,
                          )}
                        >
                          <AgentSupportIcon className={supportStyles.labelIcon} />
                          {lang('$agent_support_label')}
                        </span>
                      )}
                      {previewText}
                    </span>
                    {shouldRenderActivity && renderedActivityLangKey && (
                      <span ref={activityRef} className={styles.activity}>
                        <AgentSpinningTop className={styles.activityMark} markClassName={styles.activityMarkFlat} />
                        <Transition
                          name="slideVerticalFade"
                          activeKey={activityKeyRef.current.key}
                          className={styles.activityTransition}
                        >
                          <span className={styles.activityText}>{lang(renderedActivityLangKey)}</span>
                        </Transition>
                      </span>
                    )}
                  </div>
                  {isUnread && !isAnswering && <span className={styles.unreadDot} />}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </WithContextMenu>
  );
}

export default memo(AgentThreadListItem);
