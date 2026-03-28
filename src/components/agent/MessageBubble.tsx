import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../lib/teact/teact';

import type { AgentMessage, IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import buildClassName from '../../util/buildClassName';
import { copyTextToClipboard } from '../../util/clipboard';
import { processDeeplink } from '../../util/deeplink';
import renderMarkdown from '../../util/renderMarkdown';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from '../ui/DropdownMenu';
import LoadingDots from '../ui/LoadingDots';
import MenuBackdrop from '../ui/MenuBackdrop';

import styles from './MessageBubble.module.scss';

interface OwnProps {
  message: AgentMessage;
  onEdit?: (id: number, text: string) => void;
}

type ContextMenuHandler = 'copy' | 'edit';

const INCOMING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  { value: 'copy', name: 'Copy Text', fontIcon: 'menu-copy' },
];

const OUTGOING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  { value: 'copy', name: 'Copy Text', fontIcon: 'menu-copy' },
  { value: 'edit', name: 'Edit Message', fontIcon: 'menu-rename' },
];

const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;
export const MESSAGE_LIST_ITEM_SELECTOR = `.${styles.message}`;

function MessageBubble({ message, onEdit }: OwnProps) {
  const {
    id, text, isOutgoing, isTyping,
  } = message;
  const { isPortrait } = useDeviceScreen();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { html, buttons } = useMemo(() => renderMarkdown(text), [text]);

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
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    topShiftY: CONTEXT_MENU_VERTICAL_SHIFT_PX,
    preferredPositionX: 'left',
  }));

  const handleContextMenuAction = useLastCallback((value: ContextMenuHandler) => {
    if (value === 'copy') {
      void copyTextToClipboard(text);
    } else if (value === 'edit') {
      onEdit?.(id, text);
    }
  });

  const handleDeeplinkButtonClick = useLastCallback((url: string) => {
    if (url.startsWith('mtw://')) {
      void processDeeplink(url);
    }
  });

  function renderContextMenu(menuAnchor?: IAnchorPosition) {
    if (!menuAnchor) return undefined;

    return (
      <DropdownMenu<ContextMenuHandler>
        ref={menuRef}
        isOpen={isContextMenuOpen}
        withPortal
        shouldTranslateOptions
        items={isOutgoing ? OUTGOING_MENU_ITEMS : INCOMING_MENU_ITEMS}
        menuAnchor={menuAnchor}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onSelect={handleContextMenuAction}
        onClose={handleContextMenuClose}
        onCloseAnimationEnd={handleContextMenuHide}
      />
    );
  }

  return (
    <div className={buildClassName(styles.message, isOutgoing ? styles.messageOutgoing : styles.messageIncoming)}>
      {isPortrait && (
        <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />
      )}
      <div
        ref={ref as ElementRef<HTMLDivElement>}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
        className={isOutgoing ? buildClassName(styles.bubble, styles.outgoing) : styles.wrapper}
      >
        {isOutgoing ? text : (
          <>
            <div
              className={buildClassName(styles.bubble, styles.incoming, buttons.length > 0 && styles.hasButtons)}
            >
              {isTyping ? (
                <LoadingDots className={styles.loadingDots} isActive />
              ) : (

                <span dangerouslySetInnerHTML={{ __html: html || (buttons.length > 0 ? '👇' : '') }} />
              )}
            </div>
            {buttons.length > 0 && (
              <div className={styles.buttons}>
                {buttons.map((btn) => (
                  <button
                    key={btn.url}
                    type="button"
                    className={styles.actionButton}
                    onClick={() => handleDeeplinkButtonClick(btn.url)}
                  >
                    {btn.label}
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </div>
      {renderContextMenu(contextMenuAnchor)}
    </div>
  );
}

export default memo(MessageBubble);
