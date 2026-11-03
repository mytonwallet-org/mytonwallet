import React, { memo, useRef } from '../../lib/teact/teact';

import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import { copyAgentText } from './helpers/copyAgentText';
import formatAgentChatDate from './helpers/formatAgentChatDate';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from '../ui/DropdownMenu';

import styles from './Agent.module.scss';

interface OwnProps {
  timestamp: number;
}

const MENU_ITEMS: DropdownItem<'copy'>[] = [{ value: 'copy', name: 'Copy', fontIcon: 'menu-copy' }];
// The menu is centered on the line, under it or over it, wherever it was opened
const MENU_LAYOUT: Layout = { withPortal: true, doNotCoverTrigger: true, isCenteredHorizontally: true };

/** The day in bold and the time before a message; its menu copies them, as on mobile */
function AgentDateLine({ timestamp }: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
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
    void copyAgentText(`${day} ${time}`, 'Copied');
  });

  return (
    <div
      ref={ref}
      className={styles.dateSeparator}
      onMouseDown={handleBeforeContextMenu}
      onContextMenu={handleContextMenu}
    >
      <span className={styles.dateSeparatorDay}>{day}</span> {time}
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
  );
}

export default memo(AgentDateLine);

function getMenuLayout() {
  return MENU_LAYOUT;
}
