import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { addExtraClass, setExtraStyles } from '../../lib/teact/teact-dom';
import { getGlobal } from '../../global';

import type { AgentHint, AgentMessage, AnimationLevel } from '../../global/types';
import type { SnapEffectKind } from './helpers/snapEffect';
import type { TextRevealPresentation, TextRevealPresentations } from './hooks/textRevealPresentation';
import { LoadMoreDirection } from '../../global/types';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import animateScroll, {
  cancelScrollAnimation,
  easeInOutTransition,
  isAnimatingScroll,
  restartScrollAnimation,
  trackWheelInertia,
} from '../../util/animateScroll';
import { animate, timingFunctions } from '../../util/animation';
import buildClassName from '../../util/buildClassName';
import { processDeeplink } from '../../util/deeplink';
import { SELF_PROTOCOL } from '../../util/deeplink/constants';
import { getIsInputMethodKey, stopEvent } from '../../util/domEvents';
import { openUrl } from '../../util/openUrl';
import { IS_TOUCH_ENV, REM } from '../../util/windowEnvironment';
import buildMessageIds, { DATE_ITEM_ID_PREFIX, UNREAD_ITEM_ID_PREFIX } from './helpers/buildMessageIds';
import buildMessageTurnIds from './helpers/buildMessageTurnIds';
import { createSnapGhost, getSnapEffectDuration, getSnapEffectKind } from './helpers/snapEffect';

import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import { useHotkeys } from '../../hooks/useHotkeys';
import useInfiniteScroll from '../../hooks/useInfiniteScroll';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import useAgentLayoutSwitch from './hooks/useAgentLayoutSwitch';
import useScrollResetOnResize from './hooks/useScrollResetOnResize';
import useScrollToBottomOnReveal from './hooks/useScrollToBottomOnReveal';
import useShouldAnimateText from './hooks/useShouldAnimateText';

import { AgentFailureCaption } from '../agentV2/AgentStatusNotice';
import InfiniteScroll from '../ui/InfiniteScroll';
import { getIsAnyModalOpen } from '../ui/Modal';
import Spinner from '../ui/Spinner';
import AgentDateLine from './AgentDateLine';
import AgentEdgeGlow from './AgentEdgeGlow';
import AgentHeader from './AgentHeader';
import AgentHints from './AgentHints';
import AgentInputBar from './AgentInputBar';
import AgentLoadFailure from './AgentLoadFailure';
import AgentMessagesSkeleton, { PLACEHOLDER_MORPH_DURATION } from './AgentMessagesSkeleton';
import AgentUnreadDivider from './AgentUnreadDivider';
import { MESSAGE_LIST_ITEM_SELECTOR } from './MessageBubble';
import ReportAgentProblemModal from './ReportAgentProblemModal';
import ScrollToBottomButton from './ScrollToBottomButton';

import styles from './Agent.module.scss';
import bubbleStyles from './MessageBubble.module.scss';
import snapStyles from './SnapEffect.module.scss';

const PRELOAD_BACKWARD_SLICE = 30;
const CONTINUOUS_HISTORY_MAX_VIEWPORT_SIZE = 60;
const SCROLL_FLICKER_THRESHOLD = 10;
// The scroll-to-latest button shows once the latest message ends this far below the visible bottom, as on mobile
const SCROLL_BOTTOM_THRESHOLD = 60;
const LIVE_TAIL_REQUEST_TIMEOUT = 1000;
const QUESTION_FLY_UP_DURATION = 300;
// The space removed messages leave closes once their dust has mostly settled, as Telegram Web A removes a message
// after its snap
const DISSOLVE_GAP_CLOSE_DELAY = 600;
const DISSOLVE_GAP_CLOSE_DURATION = 400;
const HISTORY_MORPH_EASING = 'cubic-bezier(0.38, 0.7, 0.125, 1)';
const HISTORY_FADE_DURATION = 220;
// Content inside a bubble starts to fade in this long after its bubble starts to grow
const HISTORY_BUBBLE_CONTENT_FADE_DELAY = 140;
// The lowest placeholder's size and position and the gap between placeholders, as in `AgentMessagesSkeleton`
const HISTORY_FALLBACK_PLACEHOLDER_INSET = REM;
const HISTORY_FALLBACK_PLACEHOLDER_HEIGHT = 11.5 * REM;
const HISTORY_FALLBACK_PLACEHOLDER_WIDTH_SHARE = 0.86;
const HISTORY_PLACEHOLDER_GAP = 0.625 * REM;
const MESSAGE_ELEMENT_SELECTOR = '[data-agent-v2-message-id]';
const PLACEHOLDER_SELECTOR = '[data-agent-skeleton-role]';
const FOLLOWUP_BUTTON_SELECTOR = '[data-agent-followup-id]';
const NO_COMPOSER: Partial<AgentConversationComposer> = {};
// The lines that come before a message: its date and the "New" line
const MARKER_SELECTOR = `.${styles.dateSeparator}, .${styles.unreadDivider}`;

export interface AgentConversationMessageContext {
  shouldAnimateTextStreaming: boolean;
  textRevealPresentation?: TextRevealPresentation;
  isJustAdded: boolean;
  onEditMessage: (id: number, text: string) => void;
  onReportMessage?: (id: number) => void;
  onTextRevealProgress: NoneToVoidFunction;
  onRequestLiveTail: NoneToVoidFunction;
}

export interface AgentConversationComposerProps {
  inputRef: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  isDisabled: boolean;
  onInput: (value: string) => void;
  onKeyDown: (event: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  /** Puts text the user dictated after the draft */
  onInsertText: (text: string) => void;
  onHeightChange?: (height: number) => void;
}

export interface AgentConversationComposerHeightContext {
  messagesElement: HTMLDivElement;
  getIsAtBottom: () => boolean;
  onTextRevealProgress: NoneToVoidFunction;
}

/** A load of the chat's history, or of the news, that failed */
interface AgentConversationLoadFailure {
  text: string;
  isRetrying?: boolean;
  onRetry: NoneToVoidFunction;
}

export interface AgentConversation {
  messages: AgentMessage[];
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  /** Shows the outlines of bubbles until the history loads, for a chat that has a history to load */
  hasHistoryPlaceholder?: boolean;
  /** The placeholder shows the outlines of news cards in place of a chat's bubbles */
  isNewsPlaceholder?: boolean;
  /** A date line comes before the first message of each day rather than after a pause */
  hasDailyDateLines?: boolean;
  /**
   * The first message the user has not seen. A "New" line comes before it, and the list opens at it, under the header
   * with the lines before it, rather than at its end.
   */
  unreadMessageId?: number;
  /** The message the list opens at in place of the first unread one, as the news whose discussion the user left */
  initialMessageId?: number;
  /**
   * The failure shows centered with Retry in place of a list that has nothing to show, and as the failure line with
   * Retry at the end of the messages already shown
   */
  loadFailure?: AgentConversationLoadFailure;
  /** An answer is being produced, including the time before its first text arrives */
  isRunActive?: boolean;
  textRevealPresentations: TextRevealPresentations;
  /**
   * Messages that the next `messages` no longer has. The list shows them once more, turns them to dust where they
   * stand, as Telegram does with deleted messages, and calls `onDissolveStart` for the next `messages`. The space they
   * leave closes as they go.
   */
  dissolvingMessageIds?: readonly number[];
  /**
   * The list footer turns to dust in the same way, as a failure under a question that Retry takes away. Its root
   * carries `data-agent-list-footer`, and `onDissolveStart` hands over the next footer.
   */
  isFooterDissolving?: boolean;
  onDissolveStart?: NoneToVoidFunction;
  renderMessage: (message: AgentMessage, context: AgentConversationMessageContext) => TeactNode;
}

export interface AgentConversationComposer {
  isDisabled: boolean;
  shouldHide?: boolean;
  onSendMessage: (text: string, editingMessageId?: number) => void;
  onSendHint: (hint: AgentHint) => void;
  onHeightChange?: (height: number, context: AgentConversationComposerHeightContext) => void;
  render?: (props: AgentConversationComposerProps) => TeactNode;
}

export interface AgentConversationHistory {
  hasOlderMessages: boolean;
  isLoading: boolean;
  mode: 'continuous' | 'windowed';
  loadOlderMessages: () => void | Promise<void>;
}

export interface AgentConversationSlots {
  body?: TeactNode;
  messageListFooter?: TeactNode;
  beforeComposer?: TeactNode;
  bottomStickDependency?: unknown;
}

export type AgentProblemReportOutcome = 'sent' | 'rateLimited' | 'failed';

/** What the header shows for a chat among several; a single chat keeps the plain "Agent" header */
export interface AgentConversationHeader {
  title?: string;
  icon?: string;
  /** Shows the threads button, which calls `onBack` */
  hasBackButton?: boolean;
  /** Shows the chat menu, whose items are Report a Problem and Delete Chat once they are offered */
  hasMenu?: boolean;
}

export interface AgentConversationActions {
  onBack: NoneToVoidFunction;
  /** Offers Delete Chat in the chat menu */
  onDelete?: NoneToVoidFunction;
  /** Reports the conversation, or the message when `messageId` is given. Without it nothing offers a report. */
  onReportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
}

/**
 * What the chat keeps for its next mount, as when the app switches layouts. Messages are counted from the end of the
 * conversation, since a mount numbers them afresh.
 */
export interface AgentConversationSession {
  draft: string;
  /** The question being edited, with its text, which tells it is still the same question */
  editedMessage?: { indexFromEnd: number; text: string };
  isInputFocused?: boolean;
  /** The last question is pinned under the header with its answer below it, as after a send */
  isQuestionPinned?: boolean;
  /** The message at the top of the list and where it starts below the list's top; without it the list is at its end */
  scrollAnchor?: { indexFromEnd: number; offset: number };
  /**
   * The list had been placed, so it opens where it was, at `scrollAnchor` or at its end, rather than at the message it
   * is given or its first unread one
   */
  isPlaced?: boolean;
}

export interface AgentConversationSessionStore {
  /** What the chat kept when it was on screen last */
  initial?: AgentConversationSession;
  save: (session: AgentConversationSession) => void;
}

export interface AgentConversationShellProps {
  isActive: boolean;
  animationLevel: AnimationLevel;
  conversation: AgentConversation;
  /**
   * Without it the chat has no input field, as in the news feed. The messages then keep the same gap at the bottom
   * that they keep above a field.
   */
  composer?: AgentConversationComposer;
  history?: AgentConversationHistory;
  slots?: AgentConversationSlots;
  header?: AgentConversationHeader;
  actions: AgentConversationActions;
  session?: AgentConversationSessionStore;
}

/**
 * A send pins the new question to the top of the list and reserves the rest of the screen for the answer.
 * The request is fulfilled once the list receives an outgoing message other than `lastOutgoingMessage`.
 * Until then, the previous live tail keeps its reserved space.
 */
interface LiveTailRequest {
  lastOutgoingMessage?: AgentMessage;
  previousMessageId?: number;
}

/** The space dissolving messages leave at the end of the list, until it closes */
interface DissolveGap {
  kind: SnapEffectKind;
  /** Taller than the space, so the list keeps its scroll position until the space is measured */
  initialHeight: number;
  /** Where the dissolving messages ended, from the top of the list's content */
  contentEnd: number;
}

function AgentConversationShell({
  isActive,
  animationLevel,
  conversation,
  composer,
  history,
  slots,
  header,
  actions,
  session,
}: AgentConversationShellProps) {
  const {
    messages, hints, isInitialLoadComplete, hasHistoryPlaceholder = false, isNewsPlaceholder = false,
    hasDailyDateLines = false, unreadMessageId, initialMessageId, loadFailure, isRunActive = false,
    textRevealPresentations, dissolvingMessageIds, isFooterDissolving = false, onDissolveStart, renderMessage,
  } = conversation;
  const hasComposer = Boolean(composer);
  const {
    isDisabled: isInputDisabled = false,
    shouldHide: shouldHideComposer = false,
    onSendMessage,
    onSendHint,
    onHeightChange: onComposerHeightChange,
    render: renderComposer,
  } = composer ?? NO_COMPOSER;
  const {
    onBack, onReportProblem, onScroll: onExternalScroll, onDelete,
  } = actions;
  const hasOlderMessages = history?.hasOlderMessages ?? false;
  const isLoadingOlderMessages = history?.isLoading ?? false;
  const loadOlderMessages = history?.loadOlderMessages;
  const shouldUseContinuousHistory = history?.mode === 'continuous';
  const conversationSlot = slots?.body;
  const isEmptyAfterFailure = Boolean(loadFailure) && !messages.length;
  const hasMessageList = conversationSlot === undefined && !isEmptyAfterFailure;
  const messageListFooter = slots?.messageListFooter;
  const beforeComposerSlot = slots?.beforeComposer;
  const bottomStickDependency = slots?.bottomStickDependency;
  // The session is read once: what the chat kept applies as it comes on screen again
  const initialSessionRef = useRef(session?.initial);
  // Kept until the history shows whether the edited question is still there
  const pendingEditRef = useRef(session?.initial?.editedMessage);
  const [inputValue, setInputValue] = useState(() => initialSessionRef.current?.draft ?? '');
  const [isScrolledUp, setIsScrolledUp] = useState(false);
  const [reportTarget, setReportTarget] = useState<{ messageId?: number } | undefined>();
  const [isReadyToShow, markReadyToShow] = useFlag();
  // The loading bubbles lie under the messages until they have faded, and the list leaves its background to them
  const [isPlaceholderGone, markPlaceholderGone] = useFlag();
  const [editingMessageId, setEditingMessageId] = useState<number | undefined>();
  // A question pinned when the chat was on screen last is the live tail again once the history brings it
  const [liveTailRequest, setLiveTailRequest] = useState<LiveTailRequest | undefined>(
    () => (initialSessionRef.current?.isQuestionPinned ? {} : undefined),
  );
  const [focusedLiveTailRequest, setFocusedLiveTailRequest] = useState(liveTailRequest);
  const [frozenSpacerHeight, setFrozenSpacerHeight] = useState<number | undefined>();
  const [dissolveGap, setDissolveGap] = useState<DissolveGap | undefined>();
  const messagesRef = useRef<HTMLDivElement>();
  const snapLayerRef = useRef<HTMLDivElement>();
  const dissolveGapRef = useRef<HTMLDivElement>();
  const spacerRef = useRef<HTMLDivElement>();
  const liveTailRef = useRef<HTMLDivElement>();
  const inputRef = useRef<HTMLTextAreaElement>();
  // A chat that opens again where it was left starts away from its end, so nothing holds the list there
  const isAtBottomRef = useRef(!initialSessionRef.current?.scrollAnchor);
  // Where the list last scrolled itself to its end
  const ownEndScrollTopRef = useRef<number>();
  // The scroll button asked for the latest messages while they were out of the rendered window
  const shouldAnimateToEndRef = useRef(false);
  // While the answer grows under a pinned question, the list must not follow it down
  const isFollowSuppressedRef = useRef(Boolean(initialSessionRef.current?.isQuestionPinned));
  const shouldRevealLiveTailAnswerRef = useRef(false);
  const liveTailTimeoutRef = useRef<number>();
  const lastAutoLoadLengthRef = useRef<number>();

  useHistoryBack({ isActive, onBack });
  useScrollResetOnResize(messagesRef, isAtBottomRef);

  // While nothing on the page has focus, Tab starts at the input. Once something is focused, Tab follows
  // the usual order. A modal or the lock screen covers the agent, so their Tab must not reach the input.
  const handleTab = useLastCallback((e: KeyboardEvent) => {
    const input = inputRef.current;
    if (e.target !== document.body || !input || getIsAnyModalOpen() || getGlobal().isAppLockActive) return;

    e.preventDefault();
    focusAtEnd(input);
  });

  useHotkeys(useMemo(() => (isActive ? { Tab: handleTab } : undefined), [handleTab, isActive]));

  useEffect(() => {
    return () => window.clearTimeout(liveTailTimeoutRef.current);
  }, []);

  const shouldAnimate = useShouldAnimateText(animationLevel);
  const scrollDuration = shouldAnimate ? undefined : 0;
  const { isScrolled, handleScroll: handleMessagesScroll, update: updateScrolledState } = useScrolledState();

  const allIds = useMemo(
    () => buildMessageIds(messages, { unreadMessageId, hasDailyDateLines }),
    [hasDailyDateLines, messages, unreadMessageId],
  );
  const messagesById = useMemo(() => {
    const nextMessagesById: Record<number, AgentMessage> = {};

    for (const message of messages) {
      nextMessagesById[message.id] = message;
    }

    return nextMessagesById;
  }, [messages]);
  const turnIdByItemId = useMemo(() => buildMessageTurnIds(allIds, messagesById), [allIds, messagesById]);
  const lastOutgoingMessage = useMemo(() => getLastOutgoingMessage(messages), [messages]);
  const isLiveTailRequestFulfilled = Boolean(
    liveTailRequest && lastOutgoingMessage && lastOutgoingMessage !== liveTailRequest.lastOutgoingMessage,
  );
  const liveTailMessageId = isLiveTailRequestFulfilled ? lastOutgoingMessage!.id : liveTailRequest?.previousMessageId;
  const liveTailTurnId = liveTailMessageId !== undefined ? turnIdByItemId[liveTailMessageId] : undefined;
  // A request stays pending until the list scrolls to the question it was made for
  const isLiveTailPending = liveTailRequest !== undefined && liveTailRequest !== focusedLiveTailRequest;
  const lastMessage = messages[messages.length - 1];
  const isAnswerSettled = !isRunActive && !isLiveTailPending
    && (!lastMessage || textRevealPresentations[lastMessage.id]?.status !== 'active');
  const areHintsVisible = isInitialLoadComplete && messages.length === 0;
  // The Agent thinks until the text of its answer comes
  const isThinking = isRunActive && (!lastMessage || lastMessage.isOutgoing || !lastMessage.text);

  // Messages that were already there when the list became visible are not new
  const shownIds = isReadyToShow ? allIds : undefined;
  const prevShownIds = usePrevious2(shownIds);
  const justAddedIds = useMemo(
    () => (shownIds && prevShownIds ? getAppendedIds(shownIds, prevShownIds) : undefined),
    [prevShownIds, shownIds],
  );

  const releaseFrozenSpacer = useLastCallback(() => {
    setFrozenSpacerHeight(undefined);
  });

  const resetLiveTail = useLastCallback(() => {
    window.clearTimeout(liveTailTimeoutRef.current);
    setLiveTailRequest(undefined);
    setFocusedLiveTailRequest(undefined);
    releaseFrozenSpacer();
    isFollowSuppressedRef.current = false;
    shouldRevealLiveTailAnswerRef.current = false;
    if (isAnimatingScroll(messagesRef.current)) cancelScrollAnimation();
  });

  const requestLiveTail = useLastCallback(() => {
    const request: LiveTailRequest = { lastOutgoingMessage, previousMessageId: liveTailMessageId };
    isAtBottomRef.current = true;
    setLiveTailRequest(request);
    // A retried answer reuses its turn, so a reserve trimmed by scrolling must be restored for it
    requestMutation(() => {
      liveTailRef.current?.style.removeProperty('min-height');
    });
    // Short histories are pushed to the bottom by the spacer. Keeping its height until the list scrolls to the new
    // question makes the old messages scroll away instead of jumping to the top when the question is added.
    setFrozenSpacerHeight(spacerRef.current?.offsetHeight || undefined);

    // A send that never reaches the list, such as a run that fails to start, would otherwise leave the list
    // waiting for its question: no scroll to the bottom on new content and no scroll restore on history loads.
    window.clearTimeout(liveTailTimeoutRef.current);
    liveTailTimeoutRef.current = window.setTimeout(() => {
      setFocusedLiveTailRequest(request);
      releaseFrozenSpacer();
    }, LIVE_TAIL_REQUEST_TIMEOUT);
  });

  useEffect(() => {
    if (!isInitialLoadComplete || messages.length > 0) return;

    resetLiveTail();
    setDissolveGap(undefined);
    setIsScrolledUp(false);
    isAtBottomRef.current = true;
    requestMeasure(() => updateScrolledState(messagesRef.current));
  }, [isInitialLoadComplete, messages.length, resetLiveTail, updateScrolledState]);

  const [viewportIds, getMore, resetScroll] = useInfiniteScroll({
    loadMoreForwards: hasOlderMessages && !isLoadingOlderMessages ? loadOlderMessages : undefined,
    listIds: allIds.length > 0 ? allIds : undefined,
    isActive,
    startFromEnd: true,
    shouldKeepViewportAtEnd: isAtBottomRef.current,
    shouldPreserveViewport: shouldUseContinuousHistory,
    maxPreservedViewportSize: shouldUseContinuousHistory ? CONTINUOUS_HISTORY_MAX_VIEWPORT_SIZE : undefined,
  });
  const lastAllId = allIds[allIds.length - 1];
  const previousLastAllIdRef = useRef(lastAllId);
  const lastViewportId = viewportIds?.[viewportIds.length - 1];
  const isViewportAtEnd = !lastAllId || lastAllId === lastViewportId;

  const updateScrollPosition = useLastCallback((element: HTMLDivElement) => {
    const distanceToBottom = element.scrollHeight - element.scrollTop - element.clientHeight;
    // The event of the list's own scroll to its end can come after an answer has grown further, which does not take
    // the list away from its end
    const isOwnEndScroll = ownEndScrollTopRef.current !== undefined
      && Math.abs(element.scrollTop - ownEndScrollTopRef.current) < 1;
    isAtBottomRef.current = isOwnEndScroll || distanceToBottom < SCROLL_FLICKER_THRESHOLD;
    setIsScrolledUp(!isOwnEndScroll && distanceToBottom > SCROLL_BOTTOM_THRESHOLD);
  });

  // A chat that comes on screen again opens where it was left. Otherwise it opens at the message it is given or at its
  // first unread one, and at its end without them.
  const getOpeningMessageId = useLastCallback(() => {
    const { scrollAnchor, isPlaced } = initialSessionRef.current ?? {};
    if (scrollAnchor || isPlaced || isFollowSuppressedRef.current) return undefined;

    return [initialMessageId, unreadMessageId].find((id) => id !== undefined && messagesById[id]);
  });

  const scrollToInitialPosition = useLastCallback((element: HTMLDivElement) => {
    const liveTail = isFollowSuppressedRef.current ? liveTailRef.current : undefined;
    if (liveTail) {
      element.scrollTo({ top: getPinnedLiveTailScrollTop(element, liveTail), behavior: 'instant' });
      // An answer without text yet comes into view once, as after a send
      shouldRevealLiveTailAnswerRef.current = !lastMessage || lastMessage.isOutgoing || !lastMessage.text;
      updateScrollPosition(element);
      return;
    }

    isFollowSuppressedRef.current = false;
    const scrollAnchor = initialSessionRef.current?.scrollAnchor;
    const anchorScrollTop = scrollAnchor && getScrollAnchorTop(element, scrollAnchor, messages);
    const openingMessageId = getOpeningMessageId();
    const openingScrollTop = openingMessageId !== undefined
      ? getOpeningScrollTop(element, openingMessageId)
      : undefined;
    element.scrollTo({ top: anchorScrollTop ?? openingScrollTop ?? element.scrollHeight, behavior: 'instant' });
    if (!scrollAnchor && openingScrollTop === undefined) return;

    ownEndScrollTopRef.current = undefined;
    updateScrollPosition(element);
  });

  const scrollToBottom = useLastCallback(() => {
    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      ownEndScrollTopRef.current = element.scrollTop;
    });
  });

  const animateToBottom = useLastCallback(() => {
    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      // The scroll button can be pressed while the list still moves from the user's swipe
      requestMutation(animateScroll(element, getBottomScrollTop, {
        forceDuration: scrollDuration,
        shouldWaitForMomentum: true,
        onEnd: releaseFrozenSpacer,
      }));
    });
  });

  // A list about to open at a message is placed there rather than at its end
  const getIsOpeningAtMessage = useLastCallback(() => !isReadyToShow && getOpeningMessageId() !== undefined);

  // The latest messages coming into the rendered window take the list to its end while it is held there or the scroll
  // button asked for them. Scrolled down to them, the list stays where the user is.
  useLayoutEffect(() => {
    if (!isActive || !isViewportAtEnd || getIsOpeningAtMessage()) return;
    if (!isAtBottomRef.current && !shouldAnimateToEndRef.current) return;

    if (shouldAnimateToEndRef.current) {
      shouldAnimateToEndRef.current = false;
      animateToBottom();
    } else {
      scrollToBottom();
    }
  }, [animateToBottom, isActive, isViewportAtEnd, scrollToBottom]);

  useLayoutEffect(() => {
    if (!hasMessageList || !isActive || !isInitialLoadComplete || isReadyToShow) return;

    // A list that opens at a message is not held at its end. The rendered messages make way for that message when it
    // lies beyond them.
    const scrollAnchor = initialSessionRef.current?.scrollAnchor;
    const openingMessageId = scrollAnchor
      ? messages[messages.length - 1 - scrollAnchor.indexFromEnd]?.id
      : getOpeningMessageId();
    if (openingMessageId !== undefined) {
      isAtBottomRef.current = false;
      if (viewportIds && !viewportIds.includes(String(openingMessageId))) {
        getMore?.({ direction: LoadMoreDirection.Backwards, offsetId: String(openingMessageId) });
        return;
      }
    }

    requestForcedReflow(() => {
      const element = messagesRef.current;
      if (element) scrollToInitialPosition(element);

      // The messages that land on screen come in out of the placeholder, as Telegram's history does
      const historyReveal = element && hasHistoryPlaceholder && shouldAnimate
        ? measureHistoryReveal(element)
        : undefined;

      return () => {
        if (historyReveal) startHistoryReveal(historyReveal);
        markReadyToShow();
      };
    });
  }, [
    getMore, getOpeningMessageId, hasHistoryPlaceholder, hasMessageList, isActive, isInitialLoadComplete, isReadyToShow,
    markReadyToShow, messages, scrollToInitialPosition, shouldAnimate, viewportIds,
  ]);

  useEffect(() => {
    if (!isActive || isViewportAtEnd || !isAtBottomRef.current) return;
    getMore?.({ direction: LoadMoreDirection.Backwards });
  }, [getMore, isActive, isViewportAtEnd, lastAllId, lastViewportId]);

  useEffect(() => {
    if (!isActive || !isInitialLoadComplete || !hasOlderMessages || isLoadingOlderMessages) return;

    requestMeasure(() => {
      const element = messagesRef.current;
      if (element && element.scrollHeight <= element.clientHeight && lastAutoLoadLengthRef.current !== allIds.length) {
        lastAutoLoadLengthRef.current = allIds.length;
        getMore?.({ direction: LoadMoreDirection.Forwards });
      }
    });
  }, [allIds.length, getMore, hasOlderMessages, isActive, isInitialLoadComplete, isLoadingOlderMessages]);

  const handleRevealFrame = useLastCallback(() => {
    const element = messagesRef.current;
    if (!element) return;

    if (!isFollowSuppressedRef.current) {
      // The answer grows while the list scrolls, so the running animation aims at the new bottom
      if (isAnimatingScroll(element)) {
        restartScrollAnimation();
      } else {
        scrollToBottom();
      }
      return;
    }

    // The answer grows into the reserved space without moving the scroll's target. A row that collapses above the
    // question, as the follow-ups of the previous answer, moves the target with it.
    if (isAnimatingScroll(element)) {
      restartScrollAnimation();
      return;
    }

    requestMeasure(() => {
      // A question taller than the screen pushes the start of its answer below the fold, so the list reveals
      // the first lines once. After that, the answer grows downward without moving the list.
      const isAnswerVisible = lastMessage && !lastMessage.isOutgoing && Boolean(lastMessage.text);
      if (shouldRevealLiveTailAnswerRef.current && isAnswerVisible) {
        shouldRevealLiveTailAnswerRef.current = false;
        const mutate = animateScroll(element, getLiveTailScrollTop, {
          forceDuration: scrollDuration,
          onEnd: releaseFrozenSpacer,
        });
        requestMutation(mutate);
        return;
      }

      updateScrollPosition(element);
    });
  });

  const handleTextRevealProgress = useScrollToBottomOnReveal(
    () => isAtBottomRef.current || isFollowSuppressedRef.current,
    handleRevealFrame,
  );

  const handleScrollToBottomClick = useLastCallback(() => {
    isAtBottomRef.current = true;
    isFollowSuppressedRef.current = false;
    setIsScrolledUp(false);

    if (isViewportAtEnd) {
      animateToBottom();
      return;
    }

    // The latest messages take the place of the rendered ones, and the list scrolls to them once they render
    shouldAnimateToEndRef.current = true;
    resetScroll?.();
  });

  const focusLiveTail = useLastCallback(() => {
    window.clearTimeout(liveTailTimeoutRef.current);
    setFocusedLiveTailRequest(liveTailRequest);
    isAtBottomRef.current = true;
    isFollowSuppressedRef.current = true;
    shouldRevealLiveTailAnswerRef.current = true;

    requestForcedReflow(() => {
      const element = messagesRef.current;
      if (!element) return undefined;

      // A question just sent that the list has no room to scroll to rises from the input into its place, as on iOS
      const flyUp = shouldAnimate && liveTailMessageId !== undefined && justAddedIds?.has(String(liveTailMessageId))
        ? measureQuestionFlyUp(element, liveTailMessageId)
        : undefined;
      // Normally the new question is at most one screen away. A longer path means the list was scrolled up,
      // so it jumps closer first instead of animating through the whole history. The question comes up from
      // under the input at rest and settles at rest, as on iOS.
      const mutateScroll = animateScroll(element, getLiveTailScrollTop, {
        maxDistance: element.clientHeight,
        forceDuration: scrollDuration,
        transition: easeInOutTransition,
        onEnd: releaseFrozenSpacer,
      });

      return () => {
        mutateScroll();
        flyUp?.();
      };
    });
  });

  const previousNewsFollowupsRef = useRef<{ id: number; count: number }>();
  useLayoutEffect(() => {
    const isLastItemChanged = lastAllId !== previousLastAllIdRef.current;
    previousLastAllIdRef.current = lastAllId;
    const previousNewsFollowups = previousNewsFollowupsRef.current;
    const newsFollowups = lastMessage?.isNewsPost
      ? { id: lastMessage.id, count: lastMessage.followups?.length ?? 0 }
      : undefined;
    const areNewsFollowupsArriving = newsFollowups && newsFollowups.count > 0
      && previousNewsFollowups?.id === newsFollowups.id && previousNewsFollowups.count === 0;
    previousNewsFollowupsRef.current = newsFollowups;

    if (isLiveTailPending && isLiveTailRequestFulfilled) {
      focusLiveTail();
      return;
    }

    // The list scrolls to the sent question once it arrives, so it must not jump to the bottom before that
    if (isLiveTailPending || isFollowSuppressedRef.current || !isAtBottomRef.current) return;

    if (areNewsFollowupsArriving && shouldAnimate) {
      animateToBottom();
      return;
    }

    // A new last item, as a regenerated answer, makes the list restore its scroll anchor in this frame, which would
    // undo the scroll, so the end is kept from the next frame
    const keepEnd = isLastItemChanged ? requestMeasure : requestForcedReflow;
    keepEnd(() => {
      const element = messagesRef.current;
      if (!element) return;

      if (isAnimatingScroll(element)) {
        restartScrollAnimation();
        return;
      }

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      ownEndScrollTopRef.current = element.scrollTop;
      isAtBottomRef.current = true;
    });
  }, [
    animateToBottom,
    bottomStickDependency,
    focusLiveTail,
    isLiveTailPending,
    loadFailure,
    isLiveTailRequestFulfilled,
    lastAllId,
    lastMessage,
    messages,
    shouldAnimate,
    textRevealPresentations,
  ]);

  // Messages turn to dust where they stand: ghosts of those on screen take their place over the list, and the space
  // they leave is held by a gap at the end of the list once the next messages come
  const startDissolve = useLastCallback((messageIds?: readonly number[]) => {
    const kind = getSnapEffectKind(shouldAnimate);

    requestForcedReflow(() => {
      const container = messagesRef.current;
      const layer = snapLayerRef.current;
      const elements = container && isReadyToShow
        ? (messageIds ? findDissolvingElements(container, messageIds) : findDissolvingFooter(container))
        : undefined;
      if (!container || !layer || !elements) return onDissolveStart;

      const containerRect = container.getBoundingClientRect();
      const layerRect = layer.getBoundingClientRect();
      const ghosts = elements
        .filter((element) => getIsInView(element, containerRect))
        .map((element) => createSnapGhost(element, layerRect, kind));
      const first = elements[0];
      const start = first.previousElementSibling?.getBoundingClientRect().bottom ?? first.getBoundingClientRect().top;
      const end = elements[elements.length - 1].getBoundingClientRect().bottom;
      const contentEnd = end - containerRect.top + container.scrollTop;

      return () => {
        ghosts.forEach((ghost) => layer.appendChild(ghost));
        elements.forEach((element) => addExtraClass(element, styles.dissolved));
        setDissolveGap({ kind, initialHeight: Math.max(0, end - start), contentEnd });
        onDissolveStart?.();
      };
    });
  });

  useLayoutEffect(() => {
    if (dissolvingMessageIds?.length) {
      startDissolve(dissolvingMessageIds);
    } else if (isFooterDissolving) {
      startDissolve();
    }
  }, [dissolvingMessageIds, isFooterDissolving, startDissolve]);

  const releaseDissolveGap = useLastCallback(() => {
    setDissolveGap(undefined);
  });

  // The gap ends where the dissolved messages ended, so nothing moves when they go, and closes after them. Where
  // motion is reduced, it waits for the messages to fade and goes at once.
  useLayoutEffect(() => {
    if (!dissolveGap) return undefined;

    let isCancelled = false;
    requestForcedReflow(() => {
      const container = messagesRef.current;
      const gap = dissolveGapRef.current;
      if (!container || !gap) return releaseDissolveGap;

      const gapTop = gap.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
      const height = Math.max(0, dissolveGap.contentEnd - gapTop);

      const { kind } = dissolveGap;
      return () => {
        gap.style.height = `${height}px`;
        window.setTimeout(() => {
          if (isCancelled) return;
          if (kind === 'fade') {
            releaseDissolveGap();
            return;
          }

          const startedAt = Date.now();
          animate(() => {
            if (isCancelled) return false;

            const progress = Math.min(1, (Date.now() - startedAt) / DISSOLVE_GAP_CLOSE_DURATION);
            gap.style.height = `${height * (1 - timingFunctions.easeInOutQuad(progress))}px`;
            if (progress < 1) return true;

            releaseDissolveGap();
            return false;
          }, requestMutation);
        }, kind === 'dust' ? DISSOLVE_GAP_CLOSE_DELAY : getSnapEffectDuration(kind));
      };
    });

    return () => {
      isCancelled = true;
    };
  }, [dissolveGap, releaseDissolveGap]);

  // The live tail reserves a screen of space under the question for the answer to grow into. Once the answer
  // is finished, scrolling up trims whatever stays empty so the user cannot scroll back down into a blank area.
  // Only the part below the current viewport is trimmed, so the visible content never moves.
  const trimLiveTailReserve = useLastCallback((element: HTMLDivElement) => {
    const liveTail = liveTailRef.current;
    if (!liveTail) return;

    const slack = element.scrollHeight - element.scrollTop - element.clientHeight;
    if (slack <= 0) return;

    const contentHeight = getTurnContentHeight(liveTail);
    const minHeight = Math.max(contentHeight, liveTail.offsetHeight - slack);
    requestMutation(() => {
      liveTail.style.minHeight = `${minHeight}px`;
    });
  });

  const handleScroll = useLastCallback((event: React.UIEvent<HTMLDivElement>) => {
    const element = event.target as HTMLDivElement;
    // Intermediate positions of an animated scroll must not reset `isAtBottomRef` or flash the scroll button
    if (!isAnimatingScroll(element)) {
      updateScrollPosition(element);
      if (isAnswerSettled) trimLiveTailReserve(element);
    }
    handleMessagesScroll(event);
    onExternalScroll?.(event);
  });

  useEffect(() => {
    const element = messagesRef.current;
    if (!element) return undefined;

    function handleUserScroll() {
      ownEndScrollTopRef.current = undefined;
      isFollowSuppressedRef.current = false;
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    // The inertia of a swipe made before the scroll button was pressed does not stop the scroll to the latest messages
    function handleWheel(e: WheelEvent) {
      if (trackWheelInertia(element!, e)) return;

      handleUserScroll();
    }

    function handleTouchStart() {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    function handlePointerDown(e: PointerEvent) {
      // A press on the list element itself rather than on its content lands on the scrollbar
      if (e.target === element) handleUserScroll();
    }

    element.addEventListener('wheel', handleWheel, { passive: true });
    element.addEventListener('touchstart', handleTouchStart, { passive: true });
    element.addEventListener('touchmove', handleUserScroll, { passive: true });
    element.addEventListener('pointerdown', handlePointerDown);

    return () => {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
      element.removeEventListener('wheel', handleWheel);
      element.removeEventListener('touchstart', handleTouchStart);
      element.removeEventListener('touchmove', handleUserScroll);
      element.removeEventListener('pointerdown', handlePointerDown);
    };
  }, [hasMessageList]);

  const handleSend = useLastCallback(() => {
    const text = inputValue.trim();
    // The draft stays editable while an answer is running, so Enter must not send it
    if (!text || isInputDisabled) return;

    const messageId = editingMessageId;
    setInputValue('');
    setEditingMessageId(undefined);
    requestLiveTail();
    onSendMessage!(text, messageId);
  });

  const handleKeyDown = useLastCallback((event: React.KeyboardEvent) => {
    if (event.key !== 'Enter' || event.shiftKey || getIsInputMethodKey(event)) return;
    stopEvent(event);
    handleSend();
  });

  const handleInput = useLastCallback((value: string) => {
    setInputValue(value);
    if (!value) setEditingMessageId(undefined);
  });

  const handleInsertText = useLastCallback((text: string) => {
    const draft = inputValue.trim();
    setInputValue(draft ? `${draft} ${text}` : text);
  });

  const handleEditMessage = useLastCallback((id: number, text: string) => {
    setInputValue(text);
    setEditingMessageId(id);

    requestAnimationFrame(() => {
      if (inputRef.current) focusAtEnd(inputRef.current);
    });
  });

  const getEditedMessage = useLastCallback((): AgentConversationSession['editedMessage'] => {
    if (editingMessageId === undefined) return pendingEditRef.current;

    const index = messages.findIndex(({ id }) => id === editingMessageId);
    return index === -1 ? undefined : { indexFromEnd: messages.length - 1 - index, text: messages[index].text };
  });

  // The focus and the scroll position as the app switched layouts, which later saves of the draft carry along
  const switchedLayoutRef = useRef<
    Pick<AgentConversationSession, 'isInputFocused' | 'isQuestionPinned' | 'scrollAnchor' | 'isPlaced'>
  >();
  const buildSession = useLastCallback((): AgentConversationSession => ({
    draft: inputValue,
    editedMessage: inputValue ? getEditedMessage() : undefined,
    ...switchedLayoutRef.current,
  }));

  const saveSession = session?.save;
  useEffect(() => {
    saveSession?.(buildSession());
  }, [buildSession, editingMessageId, inputValue, saveSession]);

  // The question being edited before the chat mounted again stays in edit, unless the history has changed it
  useEffect(() => {
    const editedMessage = pendingEditRef.current;
    if (!editedMessage || !isInitialLoadComplete) return;

    pendingEditRef.current = undefined;
    const message = messages[messages.length - 1 - editedMessage.indexFromEnd];
    if (message?.isOutgoing && message.text === editedMessage.text) setEditingMessageId(message.id);
  }, [isInitialLoadComplete, messages]);

  const shouldRestoreFocusRef = useRef(initialSessionRef.current?.isInputFocused);
  useEffect(() => {
    const input = inputRef.current;
    if (!shouldRestoreFocusRef.current || !isActive || isInputDisabled || !input) return;

    shouldRestoreFocusRef.current = false;
    requestMeasure(() => focusAtEnd(input));
  }, [isActive, isInputDisabled]);

  // On a desktop a chat opens with its field focused, as in Telegram, while a touch screen keeps its keyboard down
  // until the field is tapped. A modal or the lock screen over the Agent keeps the focus.
  const shouldFocusOnOpenRef = useRef(!IS_TOUCH_ENV && !shouldRestoreFocusRef.current);
  useEffect(() => {
    const input = inputRef.current;
    if (!shouldFocusOnOpenRef.current || !isActive || !input) return;

    shouldFocusOnOpenRef.current = false;
    requestMeasure(() => {
      if (getIsAnyModalOpen() || getGlobal().isAppLockActive) return;
      focusAtEnd(input);
    });
  }, [isActive, shouldHideComposer]);

  useAgentLayoutSwitch(() => {
    const element = messagesRef.current;
    const isQuestionPinned = isFollowSuppressedRef.current && !isLiveTailPending && liveTailMessageId !== undefined;
    // A chat still loading its history keeps the place it mounted with
    const {
      isQuestionPinned: isQuestionInitiallyPinned, scrollAnchor: initialScrollAnchor, isPlaced: isInitiallyPlaced,
    } = initialSessionRef.current ?? {};
    switchedLayoutRef.current = {
      isInputFocused: Boolean(inputRef.current) && document.activeElement === inputRef.current,
      isQuestionPinned: isReadyToShow ? isQuestionPinned || undefined : isQuestionInitiallyPinned,
      scrollAnchor: !isReadyToShow ? initialScrollAnchor : element && !isQuestionPinned && !isAtBottomRef.current
        ? findScrollAnchor(element, messages)
        : undefined,
      isPlaced: isReadyToShow || isInitiallyPlaced,
    };
    saveSession?.(buildSession());
  }, Boolean(saveSession) && isActive);

  const handleHintClick = useLastCallback((hint: AgentHint) => {
    if (document.activeElement) (document.activeElement as HTMLElement).blur();

    // Sending measures the list, which is not allowed in a mutation phase
    requestMeasure(() => {
      requestLiveTail();
      onSendHint!(hint);
    });
  });

  const openConversationReport = useLastCallback(() => {
    setReportTarget({});
  });

  const openMessageReport = useLastCallback((messageId: number) => {
    setReportTarget({ messageId });
  });

  const closeReport = useLastCallback(() => {
    setReportTarget(undefined);
  });

  const handleSubmitReport = useLastCallback((comment: string) => {
    return onReportProblem!(reportTarget?.messageId, comment);
  });

  const handleMessageLinkClick = useLastCallback((event: React.MouseEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement;
    const href = target.closest('a')?.getAttribute('href');
    if (href?.startsWith(SELF_PROTOCOL)) {
      stopEvent(event);
      void processDeeplink(href);
      return;
    }
    if (!href?.startsWith('https://')) return;
    stopEvent(event);
    void openUrl(href);
  });

  useEffect(() => {
    if (!isActive || !onExternalScroll || !messagesRef.current) return;
    const element = messagesRef.current;
    const syntheticEvent = {
      target: element,
      currentTarget: element,
    } as unknown as React.UIEvent<HTMLDivElement>;
    onExternalScroll(syntheticEvent);
  }, [isActive, onExternalScroll]);

  const handleComposerHeightChange = useLastCallback((height: number) => {
    const messagesElement = messagesRef.current;
    if (!messagesElement || !onComposerHeightChange) return;
    onComposerHeightChange(height, {
      messagesElement,
      getIsAtBottom: () => isAtBottomRef.current,
      onTextRevealProgress: handleTextRevealProgress,
    });
  });

  const composerProps: AgentConversationComposerProps = {
    inputRef,
    inputValue,
    isDisabled: isInputDisabled,
    onInput: handleInput,
    onKeyDown: handleKeyDown,
    onSend: handleSend,
    onInsertText: handleInsertText,
    onHeightChange: onComposerHeightChange ? handleComposerHeightChange : undefined,
  };

  function renderItem(id: string) {
    if (id.startsWith(UNREAD_ITEM_ID_PREFIX)) return <AgentUnreadDivider key={id} />;

    if (id.startsWith(DATE_ITEM_ID_PREFIX)) {
      const dateMessage = messagesById[Number(id.slice(DATE_ITEM_ID_PREFIX.length))];
      if (!dateMessage) return undefined;

      return <AgentDateLine key={id} timestamp={dateMessage.timestamp} />;
    }

    const message = messagesById[Number(id)];
    if (!message) return undefined;

    return renderMessage(message, {
      shouldAnimateTextStreaming: shouldAnimate,
      textRevealPresentation: textRevealPresentations[message.id],
      // A sent question is carried into its place by the scroll, or rises there from the input, without a fade
      isJustAdded: Boolean(justAddedIds?.has(id)) && !(isLiveTailPending && message.id === liveTailMessageId),
      onEditMessage: handleEditMessage,
      onReportMessage: onReportProblem ? openMessageReport : undefined,
      onTextRevealProgress: handleTextRevealProgress,
      onRequestLiveTail: requestLiveTail,
    });
  }

  // Each question with its answers renders as one turn element. Messages never move between these elements,
  // so switching the live tail to another turn does not remount any message.
  function renderTurns(ids: string[]) {
    const turns: TeactNode[] = [];
    let turnStartIndex = 0;

    ids.forEach((id, index) => {
      const turnId = turnIdByItemId[id];
      const nextId = ids[index + 1];
      if (nextId !== undefined && turnIdByItemId[nextId] === turnId) return;

      const isLastTurn = nextId === undefined;
      const isLiveTail = turnId === liveTailTurnId;
      turns.push(
        <div
          key={turnId}
          ref={isLiveTail ? liveTailRef : undefined}
          className={buildClassName(styles.turn, isLiveTail && styles.liveTail)}
          teactFastList
        >
          {ids.slice(turnStartIndex, index + 1).map(renderItem)}
          {isLastTurn && isViewportAtEnd && messageListFooter}
          {isLastTurn && isViewportAtEnd && renderFailureLine()}
          {isLastTurn && dissolveGap && (
            <div
              key="dissolve-gap"
              ref={dissolveGapRef}
              className={styles.dissolveGap}
              style={`height: ${dissolveGap.initialHeight}px`}
              aria-hidden
            />
          )}
        </div>,
      );
      turnStartIndex = index + 1;
    });

    return turns;
  }

  function renderFailureLine() {
    if (!loadFailure) return undefined;

    return (
      <div key="load-failure" className={styles.loadFailureLine}>
        <AgentFailureCaption
          text={loadFailure.text}
          isRetryDisabled={loadFailure.isRetrying}
          onRetry={loadFailure.onRetry}
        />
      </div>
    );
  }

  if (!hasMessageList) {
    // A chat whose history failed to load keeps its menu, so it can still be deleted
    const isLoadFailure = conversationSlot === undefined;

    return (
      <div className={styles.root}>
        <AgentHeader
          isMenuVisible={isLoadFailure && header?.hasMenu}
          title={header?.title}
          icon={header?.icon}
          onBack={header?.hasBackButton ? onBack : undefined}
          onDelete={isLoadFailure ? onDelete : undefined}
        />
        {isLoadFailure ? <AgentLoadFailure {...loadFailure!} /> : conversationSlot}
      </div>
    );
  }

  return (
    <div className={styles.root} data-agent-conversation>
      <AgentHeader
        isScrolled={isScrolled}
        isMenuVisible={header?.hasMenu}
        title={header?.title}
        icon={header?.icon}
        onBack={header?.hasBackButton ? onBack : undefined}
        // The conversation can be reported once it holds a message
        onReportProblem={onReportProblem && messages.length ? openConversationReport : undefined}
        onDelete={onDelete}
      />

      {hasHistoryPlaceholder && (
        <AgentMessagesSkeleton isOpen={!isReadyToShow} isNewsFeed={isNewsPlaceholder} onClosed={markPlaceholderGone} />
      )}

      <InfiniteScroll
        ref={messagesRef}
        className={buildClassName(
          styles.messages,
          hasHistoryPlaceholder && !isPlaceholderGone && styles.messagesOverPlaceholder,
          !isReadyToShow && styles.hidden,
          dissolveGap && styles.messagesDissolving,
          !hasComposer && styles.messagesWithoutComposer,
          'custom-scroll',
        )}
        items={viewportIds}
        itemSelector={MESSAGE_LIST_ITEM_SELECTOR}
        loadMoreStrategy={shouldUseContinuousHistory ? 'scrollDirection' : 'anchorMovement'}
        preloadBackwards={PRELOAD_BACKWARD_SLICE}
        noScrollRestore={isLiveTailPending || isAnimatingScroll(messagesRef.current)}
        onLoadMore={getMore}
        onScroll={handleScroll}
        onClick={handleMessageLinkClick}
      >
        <div
          key="spacer"
          ref={spacerRef}
          className={styles.spacer}
          style={frozenSpacerHeight ? `min-height: ${frozenSpacerHeight}px` : undefined}
        />
        {viewportIds && renderTurns(viewportIds)}
        {(!viewportIds?.length || !isViewportAtEnd) && messageListFooter}
        {(!viewportIds?.length || !isViewportAtEnd) && renderFailureLine()}
        <AgentHints key="hints" isOpen={areHintsVisible} hints={hints} onHintClick={handleHintClick} />
      </InfiniteScroll>

      {/* Over the messages, so that those on screen stay where they are while older ones load */}
      {isLoadingOlderMessages && <Spinner className={styles.historySpinner} />}

      <div ref={snapLayerRef} className={snapStyles.layer} aria-hidden />

      {hasComposer && !shouldHideComposer && beforeComposerSlot}
      {hasComposer && !shouldHideComposer && (
        renderComposer ? renderComposer(composerProps) : <AgentInputBar {...composerProps} />
      )}
      {!hasComposer && <div className={styles.bottomFade} aria-hidden />}

      <AgentEdgeGlow isActive={isActive && isThinking} />

      <ScrollToBottomButton
        className={hasComposer ? styles.scrollToBottom : styles.scrollToBottomWithoutComposer}
        isVisible={isScrolledUp}
        onClick={handleScrollToBottomClick}
      />

      <ReportAgentProblemModal
        isOpen={Boolean(reportTarget && onReportProblem)}
        onClose={closeReport}
        onSubmit={handleSubmitReport}
      />
    </div>
  );
}

export default memo(AgentConversationShell);

function getLastOutgoingMessage(messages: AgentMessage[]) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].isOutgoing) return messages[i];
  }

  return undefined;
}

// Only items after the previous last item are new. Items prepended by history loading are not.
function getAppendedIds(ids: string[], prevIds: string[]) {
  if (!prevIds.length) return new Set(ids);

  const prevLastIndex = ids.lastIndexOf(prevIds[prevIds.length - 1]);
  return prevLastIndex === -1 ? undefined : new Set(ids.slice(prevLastIndex + 1));
}

// The live tail is about as tall as the list, so scrolling to its end puts the pinned question near the top
function getLiveTailScrollTop(container: HTMLElement) {
  const liveTail = container.querySelector<HTMLElement>(`.${styles.liveTail}`);
  if (!liveTail) return getBottomScrollTop(container);

  const liveTailBottom = liveTail.getBoundingClientRect().bottom
    - container.getBoundingClientRect().top
    + container.scrollTop;

  const paddingBottom = parseFloat(getComputedStyle(container).paddingBottom) || 0;

  return liveTailBottom + paddingBottom - container.clientHeight;
}

/**
 * Returns the rise of a sent question from the input's edge into its place when the list stays where it is, as when
 * the first question of a chat is already at the top.
 */
function measureQuestionFlyUp(container: HTMLElement, messageId: number) {
  const question = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageId}"]`);
  if (!question?.animate) return undefined;

  const maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight);
  const target = Math.min(Math.max(getLiveTailScrollTop(container), 0), maxScrollTop);
  if (Math.abs(target - container.scrollTop) >= 1) return undefined;

  const paddingBottom = parseFloat(getComputedStyle(container).paddingBottom) || 0;
  const visibleBottom = container.getBoundingClientRect().bottom - paddingBottom;
  const offset = visibleBottom - question.getBoundingClientRect().top;
  if (offset <= 1) return undefined;

  return () => {
    question.animate([
      { transform: `translateY(${offset}px)`, opacity: 0 },
      { transform: 'none', opacity: 1 },
    ], { duration: QUESTION_FLY_UP_DURATION, easing: 'ease-out' });
  };
}

/**
 * Where a send pins the question of the live tail, with the reserve under it reaching the bottom of the list. An
 * answer taller than the reserve keeps the question at the top of the list's content.
 */
function getPinnedLiveTailScrollTop(container: HTMLElement, liveTail: HTMLElement) {
  const containerStyle = getComputedStyle(container);
  const liveTailTop = liveTail.getBoundingClientRect().top - container.getBoundingClientRect().top
    + container.scrollTop;
  if (getTurnContentHeight(liveTail) < liveTail.offsetHeight) {
    const paddingBottom = parseFloat(containerStyle.paddingBottom) || 0;
    return liveTailTop + liveTail.offsetHeight + paddingBottom - container.clientHeight;
  }

  const paddingTop = parseFloat(containerStyle.paddingTop) || 0;
  const liveTailPaddingTop = parseFloat(getComputedStyle(liveTail).paddingTop) || 0;
  return liveTailTop + liveTailPaddingTop - paddingTop;
}

function getBottomScrollTop(container: HTMLElement) {
  return container.scrollHeight - container.clientHeight;
}

// The dissolving messages end the list. The first of them comes with the date line and the "New" line before it.
function findDissolvingElements(container: HTMLElement, messageIds: readonly number[]) {
  const message = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageIds[0]}"]`);
  if (!message) return undefined;

  const first = findLeadingLine(message);

  const elements: HTMLElement[] = [];
  for (let element: Element | null = first; element; element = element.nextElementSibling) {
    elements.push(element as HTMLElement);
  }
  for (let turn = first.parentElement?.nextElementSibling; turn?.classList.contains(styles.turn);
    turn = turn.nextElementSibling) {
    elements.push(...Array.from(turn.children) as HTMLElement[]);
  }

  return elements;
}

function findDissolvingFooter(container: HTMLElement) {
  const footer = container.querySelector<HTMLElement>('[data-agent-list-footer]');
  return footer ? [footer] : undefined;
}

function getIsInView(element: HTMLElement, containerRect: DOMRect) {
  const { top, bottom } = element.getBoundingClientRect();
  return bottom > containerRect.top && top < containerRect.bottom;
}

// The turn's own height includes its reserve, so the content height comes from where its last child ends
function getTurnContentHeight(turn: HTMLElement) {
  const lastChild = turn.lastElementChild;
  if (!lastChild) return 0;

  return lastChild.getBoundingClientRect().bottom - turn.getBoundingClientRect().top;
}

interface HistoryReveal {
  /** The bubbles on screen, each growing out of the rectangle of its placeholder */
  morphs: {
    bubble: HTMLElement;
    source: DOMRect;
    target: DOMRect;
    sourceColor: string;
    targetColor: string;
    placeholder?: HTMLElement;
  }[];
  /** The placeholders left without a message, which move up by `shift` and fade out */
  surplusPlaceholders: { element: HTMLElement; shift: number }[];
  /**
   * The date lines, the "New" line, and the parts of each message inside and outside its bubble. Each fades in to the
   * `opacity` it has in the stylesheet.
   */
  fades: { element: HTMLElement; opacity: string; delay: number }[];
  /** The CSS entrances of the follow-up buttons, which are held back until the bubbles stop growing */
  followupAnimations: Animation[];
}

/**
 * Pairs the messages on screen with the placeholders from the bottom up. Matching by vertical order keeps
 * consecutive answers from swapping places to reach a placeholder of their own sender.
 *
 * When there are more messages than placeholders, each extra message grows from a rectangle of the lowest
 * placeholder's size, one gap above the previous one. Placeholders left over after pairing move up above the messages.
 */
function measureHistoryReveal(container: HTMLElement): HistoryReveal {
  const { top, bottom, left, width } = container.getBoundingClientRect();
  const elements = container.querySelectorAll<HTMLElement>(`${MESSAGE_LIST_ITEM_SELECTOR}, ${MARKER_SELECTOR}`);
  const reveal: HistoryReveal = {
    morphs: [], surplusPlaceholders: [], fades: [], followupAnimations: [],
  };
  const placeholders = Array.from(
    container.parentElement?.querySelectorAll<HTMLElement>(PLACEHOLDER_SELECTOR) ?? [],
  ).sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
  const fallbackColor = getComputedStyle(container).getPropertyValue('--color-activity-gray-background');
  let sourceTop = bottom;
  let targetTop = top;

  Array.from(elements).reverse().forEach((element) => {
    const rect = element.getBoundingClientRect();
    if (rect.bottom <= top || rect.top >= bottom) return;

    if (element.matches(MARKER_SELECTOR)) {
      reveal.fades.push({ element, opacity: getComputedStyle(element).opacity, delay: PLACEHOLDER_MORPH_DURATION });
      return;
    }

    const bubble = element.querySelector<HTMLElement>(`.${bubbleStyles.bubble}`) ?? element;
    const target = bubble.getBoundingClientRect();
    const placeholder = placeholders.shift();
    const source = placeholder?.getBoundingClientRect() ?? new DOMRect(
      left + HISTORY_FALLBACK_PLACEHOLDER_INSET,
      sourceTop - HISTORY_FALLBACK_PLACEHOLDER_HEIGHT,
      Math.min(width * HISTORY_FALLBACK_PLACEHOLDER_WIDTH_SHARE, target.width),
      HISTORY_FALLBACK_PLACEHOLDER_HEIGHT,
    );
    sourceTop = source.top - HISTORY_PLACEHOLDER_GAP;
    targetTop = Math.min(targetTop, target.top);
    if (!target.width || !target.height) return;

    reveal.morphs.push({
      bubble,
      source,
      target,
      sourceColor: placeholder ? getComputedStyle(placeholder).backgroundColor : fallbackColor,
      targetColor: getComputedStyle(bubble).backgroundColor,
      placeholder,
    });
    measureHistoryFades(element, bubble, reveal);
  });

  placeholders.forEach((element) => {
    const source = element.getBoundingClientRect();
    const shiftedTop = targetTop - HISTORY_PLACEHOLDER_GAP - source.height;
    targetTop = shiftedTop;
    if (source.width && source.height) reveal.surplusPlaceholders.push({ element, shift: shiftedTop - source.top });
  });

  return reveal;
}

/**
 * Content inside a bubble fades in while the bubble is still growing. The rest of the message fades in after the
 * bubble reaches its final shape.
 *
 * Follow-up buttons keep their own staggered CSS entrance, which is held back until all bubbles stop growing.
 */
function measureHistoryFades(view: HTMLElement, bubble: HTMLElement, reveal: HistoryReveal) {
  Array.from(view.children).forEach((child) => {
    if (child.matches(FOLLOWUP_BUTTON_SELECTOR)) {
      reveal.followupAnimations.push(...child.getAnimations());
    } else if (child === bubble || child.contains(bubble) || child.querySelector(FOLLOWUP_BUTTON_SELECTOR)) {
      measureHistoryFades(child as HTMLElement, bubble, reveal);
    } else {
      reveal.fades.push({
        element: child as HTMLElement,
        opacity: getComputedStyle(child).opacity,
        delay: bubble.contains(child) ? HISTORY_BUBBLE_CONTENT_FADE_DELAY : PLACEHOLDER_MORPH_DURATION,
      });
    }
  });
}

function startHistoryReveal({
  morphs, surplusPlaceholders, fades, followupAnimations,
}: HistoryReveal) {
  morphs.forEach(({
    bubble, source, target, sourceColor, targetColor, placeholder,
  }) => {
    if (placeholder) setExtraStyles(placeholder, { opacity: '0', transition: 'none' });

    const x = source.left + source.width / 2 - target.left - target.width / 2;
    const y = source.top + source.height / 2 - target.top - target.height / 2;
    bubble.animate([
      {
        transformOrigin: 'center center',
        transform: `translate(${x}px, ${y}px) scale(${source.width / target.width}, ${source.height / target.height})`,
        backgroundColor: sourceColor,
      },
      { transformOrigin: 'center center', transform: 'none', backgroundColor: targetColor },
    ], { duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_MORPH_EASING });
  });

  surplusPlaceholders.forEach(({ element, shift }) => {
    element.animate([
      { transform: 'none', opacity: 1 },
      { transform: `translateY(${shift}px)`, opacity: 0 },
    ], { duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_MORPH_EASING, fill: 'forwards' });
  });

  fades.forEach(({ element, opacity, delay }) => {
    element.animate([{ opacity: 0 }, { opacity }], { duration: HISTORY_FADE_DURATION, delay, fill: 'backwards' });
  });

  followupAnimations.forEach((animation) => {
    animation.currentTime = -PLACEHOLDER_MORPH_DURATION;
  });
}

// Focus never scrolls the screens the field lies in, which may still be sliding in
function focusAtEnd(input: HTMLTextAreaElement) {
  input.focus({ preventScroll: true });
  input.setSelectionRange(input.value.length, input.value.length);
}

/**
 * The scroll position that opens the list at a message: the date line and the "New" line before it come first under
 * the header, where the list's first item stands
 */
function getOpeningScrollTop(container: HTMLElement, messageId: number) {
  const message = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageId}"]`);
  if (!message) return undefined;

  const target = findLeadingLine(message);
  const paddingTop = parseFloat(getComputedStyle(container).paddingTop) || 0;
  const marginTop = parseFloat(getComputedStyle(target).marginTop) || 0;
  return target.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop
    - paddingTop - marginTop;
}

/** The topmost of the lines that come right before a message and belong to it, or the message without them */
function findLeadingLine(message: HTMLElement) {
  let first = message;
  let previous = first.previousElementSibling;
  while (previous instanceof HTMLElement && previous.matches(MARKER_SELECTOR)) {
    first = previous;
    previous = first.previousElementSibling;
  }

  return first;
}

/** The first message that reaches below the top of the list */
function findScrollAnchor(
  container: HTMLElement, messages: AgentMessage[],
): AgentConversationSession['scrollAnchor'] {
  const { top } = container.getBoundingClientRect();
  for (const element of Array.from(container.querySelectorAll<HTMLElement>(MESSAGE_ELEMENT_SELECTOR))) {
    const rect = element.getBoundingClientRect();
    if (rect.bottom <= top) continue;

    const index = messages.findIndex(({ id }) => String(id) === element.dataset.agentV2MessageId);
    return index === -1 ? undefined : { indexFromEnd: messages.length - 1 - index, offset: rect.top - top };
  }

  return undefined;
}

/** The scroll position that puts the anchor's message where it was, once the list shows it */
function getScrollAnchorTop(
  container: HTMLElement, anchor: NonNullable<AgentConversationSession['scrollAnchor']>, messages: AgentMessage[],
) {
  const message = messages[messages.length - 1 - anchor.indexFromEnd];
  const element = message && container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${message.id}"]`);
  if (!element) return undefined;

  return element.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop
    - anchor.offset;
}
