import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../lib/teact/teact';

import type { AgentMessage, IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';
import type { TextRevealPresentation } from './hooks/useAgentMessages';

import buildClassName from '../../util/buildClassName';
import { copyTextToClipboard } from '../../util/clipboard';
import { processDeeplink } from '../../util/deeplink';
import { SELF_PROTOCOL } from '../../util/deeplink/constants';
import { parseMarkdownActions } from '../../util/renderMarkdown';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';
import IncomingMessage from './IncomingMessage';

import styles from './MessageBubble.module.scss';

interface OwnProps {
  message: AgentMessage;
  shouldAnimateTextStreaming?: boolean;
  textRevealPresentation?: TextRevealPresentation;
  onEdit?: (id: number, text: string) => void;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onTextRevealProgress?: NoneToVoidFunction;
  onTextRevealComplete?: NoneToVoidFunction;
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

function MessageBubble({
  message,
  shouldAnimateTextStreaming = false,
  textRevealPresentation,
  onEdit,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const {
    id, text, isOutgoing, isTyping, isStreaming,
  } = message;
  const { isPortrait } = useDeviceScreen();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { buttons, renderableText } = useMemo(() => parseMarkdownActions(text, {
    shouldBufferIncompleteAction: Boolean(isStreaming),
  }), [isStreaming, text]);
  const hasBufferedAction = Boolean(isStreaming && renderableText !== text && buttons.length === 0);
  const hasRenderableText = Boolean(renderableText.trim());
  const visibleIncomingText = hasRenderableText || (!buttons.length && !hasBufferedAction) ? renderableText : '👇';

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
    if (url.startsWith(SELF_PROTOCOL)) {
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
      {isOutgoing ? (
        <div
          ref={ref as ElementRef<HTMLDivElement>}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
          className={buildClassName(styles.bubble, styles.outgoing)}
        >
          {text}
        </div>
      ) : (
        <IncomingMessage
          key={getIncomingMessageKey(textRevealPresentation)}
          messageId={id}
          text={visibleIncomingText}
          isTyping={isTyping}
          isStreaming={isStreaming}
          shouldAnimateTextStreaming={shouldAnimateTextStreaming}
          textRevealPresentation={textRevealPresentation}
          buttons={buttons}
          contentRef={ref}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
          onActionClick={handleDeeplinkButtonClick}
          onTextRevealSessionConsumed={onTextRevealSessionConsumed}
          onTextRevealSessionSettled={onTextRevealSessionSettled}
          onTextRevealProgress={onTextRevealProgress}
          onTextRevealComplete={onTextRevealComplete}
        />
      )}
      {renderContextMenu(contextMenuAnchor)}
    </div>
  );
}

function getIncomingMessageKey(presentation?: TextRevealPresentation) {
  if (!presentation) return 'static';
  if (presentation.status === 'error') return `${presentation.key}:error`;
  return presentation.key;
}

export default memo(MessageBubble);
