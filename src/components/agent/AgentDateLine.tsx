import React, { memo, useRef } from '../../lib/teact/teact';

import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import buildClassName from '../../util/buildClassName';
import { copyAgentText } from './helpers/copyAgentText';
import formatAgentChatDate from './helpers/formatAgentChatDate';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';

import styles from './Agent.module.scss';

interface OwnProps {
  timestamp: number;
  /**
   * The line heads a day of the news feed: it names the day alone, and stays at the top over the day's posts as they
   * scroll under it, as Telegram's dates do
   */
  isDayHeader?: boolean;
}

const MENU_ITEMS: DropdownItem<'copy'>[] = [{ value: 'copy', name: 'Copy', fontIcon: 'menu-copy' }];
// The menu is centered on the line, under it or over it, wherever it was opened
const MENU_LAYOUT: Layout = { withPortal: true, doNotCoverTrigger: true, isCenteredHorizontally: true };

/**
 * The day in bold and the time before a message; its menu copies them, as on mobile. On a phone the menu tints the chat
 * behind it, as a message's does, and the line stands over the tint.
 */
function AgentDateLine({ timestamp, isDayHeader = false }: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const { day, time } = formatAgentChatDate(lang, timestamp);

  const {
    isContextMenuOpen,
    contextMenuAnchor,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
  } = useContextMenuHandlers({
    elementRef: ref,
    shouldDisablePropagation: true,
  });

  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getTriggerElement = useLastCallback(() => ref.current);

  const handleCopy = useLastCallback(() => {
    void copyAgentText(isDayHeader ? day : `${day} ${time}`, '$agent_copied');
  });

  // A turn of the message list is a `teactFastList`, which keeps one element for each item, so the tint comes inside it
  return (
    <div className={buildClassName(styles.dateLine, isDayHeader && styles.dateLineDayHeader)}>
      {isPortrait && <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />}
      <div
        ref={ref}
        className={buildClassName(styles.dateSeparator, isDayHeader && styles.dateSeparatorDayHeader)}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
      >
        <span className={styles.dateSeparatorDay}>{day}</span>
        {!isDayHeader && ` ${time}`}
        {contextMenuAnchor && (
          <DropdownMenu
            ref={menuRef}
            isOpen={isContextMenuOpen}
            withPortal
            shouldTranslateOptions
            items={MENU_ITEMS}
            bubbleClassName={styles.dateSeparatorMenu}
            menuAnchor={contextMenuAnchor}
            getTriggerElement={getTriggerElement}
            getRootElement={getRootElement}
            getMenuElement={getMenuElement}
            getLayout={getMenuLayout}
            onSelect={handleCopy}
            onClose={handleContextMenuClose}
            onCloseAnimationEnd={handleContextMenuHide}
          />
        )}
      </div>
    </div>
  );
}

export default memo(AgentDateLine);

function getMenuLayout() {
  return MENU_LAYOUT;
}
