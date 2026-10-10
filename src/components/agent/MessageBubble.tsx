import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useRef } from '../../lib/teact/teact';

import type {
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentV2LiveAction,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage, IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';
import type { AgentRunActivityType } from './AgentRunActivity';
import type { TextRevealPresentation } from './hooks/textRevealPresentation';

import buildClassName from '../../util/buildClassName';
import { copyTextToClipboard } from '../../util/clipboard';
import { getAnswerMessageCopyText } from './helpers/answerMessage';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import AgentV2IncomingMessage from '../agentV2/AgentV2IncomingMessage';
import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';

import styles from './MessageBubble.module.scss';

interface OwnProps {
  message: AgentMessage;
  isDisabled: boolean;
  shouldAnimateTextStreaming?: boolean;
  textRevealPresentation?: TextRevealPresentation;
  isJustAdded?: boolean;
  /** The latest message alone shows follow-up suggestions and stands in for the answer being produced */
  isLatest?: boolean;
  /** The run phase shown in place of the answer bubble until its text arrives */
  activity?: AgentRunActivityType;
  onEdit?: (id: number, text: string) => void;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  onAction?: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
  onRetry?: (messageId: number) => void;
  onReport?: (messageId: number) => void;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onTextRevealProgress?: NoneToVoidFunction;
  onTextRevealComplete?: NoneToVoidFunction;
}

type ContextMenuHandler = 'copy' | 'edit' | 'report';

const INCOMING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' },
];

const REPORTABLE_INCOMING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  ...INCOMING_MENU_ITEMS,
  { value: 'report', name: 'Report a Problem', fontIcon: 'exclamation' },
];

const OUTGOING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' },
  { value: 'edit', name: 'Edit', fontIcon: 'menu-rename' },
];

const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;
export const MESSAGE_LIST_ITEM_SELECTOR = `.${styles.message}`;

function MessageBubble({
  message,
  isDisabled,
  shouldAnimateTextStreaming = false,
  textRevealPresentation,
  isJustAdded = false,
  isLatest = false,
  activity,
  onEdit,
  onFollowup,
  onAction,
  onRetry,
  onReport,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const {
    id, text, isOutgoing, isTyping, isStreaming, semanticContent, actions,
    followups, error,
  } = message;
  const hasRichIncomingContent = !isOutgoing && Boolean(
    semanticContent || actions?.length || followups?.length,
  );
  const { isPortrait } = useDeviceScreen();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  // An answer is added empty and gets its bubble with the first text, which can come after the list has changed again
  const shouldAnimateAppearance = useRef(isJustAdded).current;
  const shouldRenderIncomingBubble = Boolean(isTyping || text);
  const isVisuallyEmpty = !isOutgoing && !shouldRenderIncomingBubble && !hasRichIncomingContent && !error
    && !(isLatest && activity);

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
      void copyTextToClipboard(getAnswerMessageCopyText(text, message.tables, message.tableReferences, message.links));
    } else if (value === 'edit') {
      onEdit?.(id, text);
    } else if (value === 'report') {
      onReport?.(id);
    }
  });

  function getMenuItems() {
    if (isOutgoing) return OUTGOING_MENU_ITEMS;
    // An answer still being written has no stored message to report yet
    return onReport && !isTyping && !isStreaming ? REPORTABLE_INCOMING_MENU_ITEMS : INCOMING_MENU_ITEMS;
  }

  function renderContextMenu(menuAnchor?: IAnchorPosition) {
    if (!menuAnchor) return undefined;

    return (
      <DropdownMenu<ContextMenuHandler>
        ref={menuRef}
        isOpen={isContextMenuOpen}
        withPortal
        shouldTranslateOptions
        items={getMenuItems()}
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
    <div
      className={buildClassName(
        styles.message,
        isOutgoing ? styles.messageOutgoing : styles.messageIncoming,
        isVisuallyEmpty && styles.messageEmpty,
      )}
      data-agent-v2-message-id={String(id)}
      data-agent-v2-message-role={isOutgoing ? 'user' : 'assistant'}
      data-agent-v2-message-status={isTyping || isStreaming ? 'streaming' : error ? 'error' : 'complete'}
    >
      {isPortrait && (
        <MenuBackdrop isMenuOpen={isContextMenuOpen} contentRef={ref} />
      )}
      {isOutgoing ? (
        <div
          ref={ref as ElementRef<HTMLDivElement>}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
          className={buildClassName(styles.bubble, styles.outgoing, shouldAnimateAppearance && styles.appearing)}
        >
          {text}
        </div>
      ) : (
        <AgentV2IncomingMessage
          message={message}
          contentRef={ref}
          isDisabled={isDisabled}
          shouldAnimateTextStreaming={shouldAnimateTextStreaming}
          shouldAnimateAppearance={shouldAnimateAppearance}
          isLatest={isLatest}
          activity={activity}
          textRevealPresentation={textRevealPresentation}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
          onFollowup={onFollowup}
          onAction={onAction}
          onRetry={onRetry}
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

export default memo(MessageBubble);
