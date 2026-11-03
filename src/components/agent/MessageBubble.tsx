import type { ElementRef } from '../../lib/teact/teact';
import React, { memo, useRef } from '../../lib/teact/teact';

import type {
  AgentAnswerFeedbackV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentV2LiveAction,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage, IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';
import type { AgentRunActivityHandoff, AgentRunActivityType } from './AgentRunActivity';
import type { TextRevealPresentation } from './hooks/textRevealPresentation';

import buildClassName from '../../util/buildClassName';
import { getAgentV2ErrorText } from '../agentV2/agentV2Copy';
import { getAnswerMessageCopyText } from './helpers/answerMessage';
import { getAgentBubbleMenuLayout, getAgentPointerMenuLayout } from './helpers/bubbleMenuLayout';
import { copyAgentText } from './helpers/copyAgentText';
import formatAgentChatDate from './helpers/formatAgentChatDate';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentFeedbackPill from '../agentV2/AgentFeedbackPill';
import AgentV2IncomingMessage from '../agentV2/AgentV2IncomingMessage';
import DropdownMenu from '../ui/DropdownMenu';
import MenuBackdrop from '../ui/MenuBackdrop';
import AgentReportIcon from './AgentReportIcon';

import styles from './MessageBubble.module.scss';

interface OwnProps {
  message: AgentMessage;
  isDisabled: boolean;
  shouldAnimateTextStreaming?: boolean;
  textRevealPresentation?: TextRevealPresentation;
  isJustAdded?: boolean;
  /** The latest message alone shows follow-up suggestions and stands in for the answer being produced */
  isLatest?: boolean;
  /** The suggestions wait for the run to end, so they come once, ready to be pressed */
  areFollowupsHeld?: boolean;
  /** The answer being answered again keeps its look, suggestions included, out of reach until it turns to dust */
  isRegenerating?: boolean;
  /** The run phase shown in place of the answer bubble until its text arrives */
  activity?: AgentRunActivityType;
  /** Shared with the run's indicator at the chat's end, whose place the answer's takes */
  activityHandoff?: AgentRunActivityHandoff;
  onEdit?: (id: number, text: string) => void;
  onFollowup?: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  onAction?: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
  onRetry?: (messageId: number) => void;
  /** Leaves the answer's failure to the chat's status, which tells it with its Retry */
  noFailureCaption?: boolean;
  /** Answers the question again in place of this answer, from its menu */
  onRegenerate?: (messageId: number) => void;
  /** Rates a complete answer from its menu */
  onRate?: (messageId: number, feedback?: AgentAnswerFeedbackV2) => void;
  onReport?: (messageId: number) => void;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onTextRevealProgress?: NoneToVoidFunction;
  onTextRevealComplete?: NoneToVoidFunction;
}

type ContextMenuHandler = 'copy' | 'edit' | 'regenerate' | 'report';

const COPY_MENU_ITEM: DropdownItem<ContextMenuHandler> = { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' };
const REGENERATE_MENU_ITEM: DropdownItem<ContextMenuHandler> = {
  value: 'regenerate', name: 'Regenerate', fontIcon: 'menu-reload',
};
// An answer's menu: Copy, then Regenerate and Report a Problem where they apply, as in the design
const INCOMING_MENU_ITEMS = buildIncomingMenuItems(false);
const REGENERABLE_INCOMING_MENU_ITEMS = buildIncomingMenuItems(true);

const OUTGOING_MENU_ITEMS: DropdownItem<ContextMenuHandler>[] = [
  { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' },
  { value: 'edit', name: 'Edit', fontIcon: 'menu-rename' },
];

export const MESSAGE_LIST_ITEM_SELECTOR = `.${styles.message}`;

function MessageBubble({
  message,
  isDisabled,
  shouldAnimateTextStreaming = false,
  textRevealPresentation,
  isJustAdded = false,
  isLatest = false,
  areFollowupsHeld = false,
  isRegenerating = false,
  activity,
  activityHandoff,
  onEdit,
  onFollowup,
  onAction,
  onRetry,
  noFailureCaption = false,
  onRegenerate,
  onRate,
  onReport,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onTextRevealProgress,
  onTextRevealComplete,
}: OwnProps) {
  const {
    id, text, isOutgoing, isTyping, isStreaming, semanticContent, actions,
    followups, error, failureText, isComplete, feedback, timestamp,
  } = message;
  const lang = useLang();
  const hasRichIncomingContent = !isOutgoing && Boolean(
    semanticContent || actions?.length || followups?.length,
  );
  const { isPortrait } = useDeviceScreen();
  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  // An answer is added empty and gets its bubble with the first text, which can come after the list has changed again
  const shouldAnimateAppearance = useRef(isJustAdded).current;
  const shouldRenderIncomingBubble = Boolean(isTyping || text);
  const isVisuallyEmpty = !isOutgoing && !shouldRenderIncomingBubble && !hasRichIncomingContent
    && (noFailureCaption || (!error && !failureText)) && !(isLatest && activity);
  // A failure with no answer over it is only its caption, which hangs closer under the message before
  const isFailureOnly = !isOutgoing && !shouldRenderIncomingBubble && !hasRichIncomingContent
    && Boolean(error || failureText) && !noFailureCaption;
  // A stored answer can be rated from its menu, as on mobile
  const isRatable = !isOutgoing && Boolean(isComplete && onRate && shouldRenderIncomingBubble);

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
  const getBubbleElement = useLastCallback(() => (
    ref.current?.querySelector<HTMLElement>(`.${styles.bubble}`) ?? ref.current
  ));

  // A user message is on the trailing side of the list, an answer on the leading one
  const isTrailingSide = isOutgoing !== Boolean(lang.isRtl);
  // A right click opens the menu at the pointer, as on a token. After a long press, the menu keeps clear of the bubble
  // and the action buttons hanging from it.
  const getLayout = useLastCallback((): Layout => {
    if (isContextMenuFromPointer) return getAgentPointerMenuLayout(contextMenuAnchor);

    const actionButtons = ref.current?.querySelectorAll<HTMLElement>(`.${styles.actionButton}`);
    const bottom = actionButtons?.length
      ? actionButtons[actionButtons.length - 1].getBoundingClientRect().bottom
      : undefined;
    const bubbleRect = getBubbleElement()?.getBoundingClientRect();
    return getAgentBubbleMenuLayout(bubbleRect, contextMenuAnchor, isTrailingSide, bottom ?? bubbleRect?.bottom);
  });

  // Regenerate waits for the menu, its tint and the rating pill to fade out, so the answer turns to dust in the open
  const isRegenerationPendingRef = useRef(false);
  const handleMenuHide = useLastCallback(() => {
    handleContextMenuHide();
    if (!isRegenerationPendingRef.current) return;

    isRegenerationPendingRef.current = false;
    onRegenerate?.(id);
  });

  const handleRate = useLastCallback((value?: AgentAnswerFeedbackV2) => {
    onRate?.(id, value);
  });

  const handleContextMenuAction = useLastCallback((value: ContextMenuHandler) => {
    if (value === 'copy') {
      // A failure under the answer is copied after it, as on mobile
      const copyText = getAnswerMessageCopyText(text, message.tables, message.tableReferences, message.links);
      const errorText = error ? getAgentV2ErrorText(error.code, lang) : failureText;
      void copyAgentText([copyText, errorText].filter(Boolean).join('\n\n'));
    } else if (value === 'edit') {
      onEdit?.(id, text);
    } else if (value === 'regenerate') {
      isRegenerationPendingRef.current = true;
    } else if (value === 'report') {
      onReport?.(id);
    }
  });

  function getMenuItems() {
    if (isOutgoing) return OUTGOING_MENU_ITEMS;
    // An answer still being written has no stored message to report or to answer again yet
    const isFinished = !isTyping && !isStreaming;
    const canRegenerate = Boolean(onRegenerate) && isFinished;
    const canReport = Boolean(onReport) && isFinished;
    const items = canRegenerate ? REGENERABLE_INCOMING_MENU_ITEMS : INCOMING_MENU_ITEMS;
    if (!canReport) return items;
    // The report item's icon is an element of the open menu's own
    const reportItem: DropdownItem<ContextMenuHandler> = {
      value: 'report', name: 'Report a Problem', icon: <AgentReportIcon />,
    };
    return [...items, reportItem];
  }

  function renderContextMenu(menuAnchor?: IAnchorPosition) {
    if (!menuAnchor) return undefined;

    const { day, time } = formatAgentChatDate(lang, timestamp);

    return (
      <DropdownMenu<ContextMenuHandler>
        ref={menuRef}
        isOpen={isContextMenuOpen}
        withPortal
        shouldTranslateOptions
        header={`${day}, ${time}`}
        items={getMenuItems()}
        bubbleClassName={styles.menu}
        menuAnchor={menuAnchor}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onSelect={handleContextMenuAction}
        onClose={handleContextMenuClose}
        onCloseAnimationEnd={handleMenuHide}
      />
    );
  }

  return (
    <div
      className={buildClassName(
        styles.message,
        isOutgoing ? styles.messageOutgoing : styles.messageIncoming,
        isVisuallyEmpty && styles.messageEmpty,
        isFailureOnly && styles.messageFailureOnly,
      )}
      data-agent-v2-message-id={String(id)}
      data-agent-v2-message-role={isOutgoing ? 'user' : 'assistant'}
      data-agent-v2-message-status={getMessageStatus(message)}
      inert={isRegenerating || undefined}
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
          <span>{text}</span>
        </div>
      ) : (
        <AgentV2IncomingMessage
          message={message}
          contentRef={ref}
          isDisabled={isDisabled && !isRegenerating}
          shouldAnimateTextStreaming={shouldAnimateTextStreaming}
          shouldAnimateAppearance={shouldAnimateAppearance}
          isLatest={isLatest}
          areFollowupsHeld={areFollowupsHeld && !isRegenerating}
          isMenuOpen={isContextMenuOpen && isPortrait}
          activity={activity}
          activityHandoff={activityHandoff}
          textRevealPresentation={textRevealPresentation}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
          onFollowup={onFollowup}
          onAction={onAction}
          onRetry={onRetry}
          noFailureCaption={noFailureCaption}
          onTextRevealSessionConsumed={onTextRevealSessionConsumed}
          onTextRevealSessionSettled={onTextRevealSessionSettled}
          onTextRevealProgress={onTextRevealProgress}
          onTextRevealComplete={onTextRevealComplete}
        />
      )}
      {renderContextMenu(contextMenuAnchor)}
      {isRatable && (
        <AgentFeedbackPill
          isOpen={isContextMenuOpen}
          feedback={feedback}
          getAnchorElement={getBubbleElement}
          onChange={handleRate}
          onClose={handleContextMenuClose}
        />
      )}
    </div>
  );
}

export default memo(MessageBubble);

function buildIncomingMenuItems(canRegenerate: boolean): DropdownItem<ContextMenuHandler>[] {
  return [
    COPY_MENU_ITEM,
    ...(canRegenerate ? [REGENERATE_MENU_ITEM] : []),
  ];
}

function getMessageStatus({
  isTyping, isStreaming, error, failureText,
}: AgentMessage) {
  if (isTyping || isStreaming) return 'streaming';
  return error || failureText ? 'error' : 'complete';
}
