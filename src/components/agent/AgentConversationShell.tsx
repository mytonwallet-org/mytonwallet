import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { removeExtraClass, toggleExtraClass } from '../../lib/teact/teact-dom';
import { getGlobal } from '../../global';

import type { AgentHint, AgentMessage, AnimationLevel } from '../../global/types';
import type { TextRevealPresentation, TextRevealPresentations } from './hooks/textRevealPresentation';
import { LoadMoreDirection } from '../../global/types';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import animateScroll, {
  cancelScrollAnimation,
  isAnimatingScroll,
  restartScrollAnimation,
} from '../../util/animateScroll';
import buildClassName from '../../util/buildClassName';
import { formatHumanDay } from '../../util/dateFormat';
import { processDeeplink } from '../../util/deeplink';
import { SELF_PROTOCOL } from '../../util/deeplink/constants';
import { stopEvent } from '../../util/domEvents';
import { openUrl } from '../../util/openUrl';
import buildMessageIds, { DATE_ITEM_ID_PREFIX } from './helpers/buildMessageIds';
import buildMessageTurnIds from './helpers/buildMessageTurnIds';

import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import { useHotkeys } from '../../hooks/useHotkeys';
import useInfiniteScroll from '../../hooks/useInfiniteScroll';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import useScrollResetOnResize from './hooks/useScrollResetOnResize';
import useScrollToBottomOnReveal from './hooks/useScrollToBottomOnReveal';
import useShouldAnimateText from './hooks/useShouldAnimateText';

import InfiniteScroll from '../ui/InfiniteScroll';
import { getIsAnyModalOpen } from '../ui/Modal';
import AgentHeader from './AgentHeader';
import AgentHints from './AgentHints';
import AgentInputBar from './AgentInputBar';
import ClearAgentChatModal from './ClearAgentChatModal';
import { MESSAGE_LIST_ITEM_SELECTOR } from './MessageBubble';
import ReportAgentProblemModal from './ReportAgentProblemModal';
import ScrollToBottomButton from './ScrollToBottomButton';

import styles from './Agent.module.scss';

const PRELOAD_BACKWARD_SLICE = 30;
const CONTINUOUS_HISTORY_MAX_VIEWPORT_SIZE = 60;
const SCROLL_FLICKER_THRESHOLD = 10;
const SCROLL_BOTTOM_THRESHOLD = 100;
const LIVE_TAIL_REQUEST_TIMEOUT = 1000;

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
  onHeightChange?: (height: number) => void;
}

export interface AgentConversationComposerHeightContext {
  messagesElement: HTMLDivElement;
  getIsAtBottom: () => boolean;
  onTextRevealProgress: NoneToVoidFunction;
}

export interface AgentConversation {
  messages: AgentMessage[];
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  /** An answer is being produced, including the time before its first text arrives */
  isRunActive?: boolean;
  textRevealPresentations: TextRevealPresentations;
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

export interface AgentConversationActions {
  onBack: NoneToVoidFunction;
  onClearChat: NoneToVoidFunction;
  /** Reports the conversation, or the message when `messageId` is given. Without it nothing offers a report. */
  onReportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
}

export interface AgentConversationShellProps {
  isActive: boolean;
  animationLevel: AnimationLevel;
  conversation: AgentConversation;
  composer: AgentConversationComposer;
  history?: AgentConversationHistory;
  slots?: AgentConversationSlots;
  actions: AgentConversationActions;
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

function AgentConversationShell({
  isActive,
  animationLevel,
  conversation,
  composer,
  history,
  slots,
  actions,
}: AgentConversationShellProps) {
  const {
    messages, hints, isInitialLoadComplete, isRunActive = false, textRevealPresentations, renderMessage,
  } = conversation;
  const {
    isDisabled: isInputDisabled,
    shouldHide: shouldHideComposer = false,
    onSendMessage,
    onSendHint,
    onHeightChange: onComposerHeightChange,
    render: renderComposer,
  } = composer;
  const {
    onBack, onClearChat, onReportProblem, onScroll: onExternalScroll,
  } = actions;
  const hasOlderMessages = history?.hasOlderMessages ?? false;
  const isLoadingOlderMessages = history?.isLoading ?? false;
  const loadOlderMessages = history?.loadOlderMessages;
  const shouldUseContinuousHistory = history?.mode === 'continuous';
  const conversationSlot = slots?.body;
  const hasMessageList = conversationSlot === undefined;
  const messageListFooter = slots?.messageListFooter;
  const beforeComposerSlot = slots?.beforeComposer;
  const bottomStickDependency = slots?.bottomStickDependency;
  const lang = useLang();
  const [inputValue, setInputValue] = useState('');
  const [isScrolledUp, setIsScrolledUp] = useState(false);
  const [isConfirmClearOpen, openClearConfirm, closeClearConfirm] = useFlag();
  const [reportTarget, setReportTarget] = useState<{ messageId?: number } | undefined>();
  const [isReadyToShow, markReadyToShow] = useFlag();
  const [editingMessageId, setEditingMessageId] = useState<number | undefined>();
  const [liveTailRequest, setLiveTailRequest] = useState<LiveTailRequest | undefined>();
  const [focusedLiveTailRequest, setFocusedLiveTailRequest] = useState<LiveTailRequest | undefined>();
  const [frozenSpacerHeight, setFrozenSpacerHeight] = useState<number | undefined>();
  const messagesRef = useRef<HTMLDivElement>();
  const spacerRef = useRef<HTMLDivElement>();
  const liveTailRef = useRef<HTMLDivElement>();
  const inputRef = useRef<HTMLTextAreaElement>();
  const isAtBottomRef = useRef(true);
  // While the answer grows under a pinned question, the list must not follow it down
  const isFollowSuppressedRef = useRef(false);
  const shouldRevealLiveTailAnswerRef = useRef(false);
  const liveTailTimeoutRef = useRef<number>();

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

  useLayoutEffect(() => {
    toggleExtraClass(document.documentElement, 'is-agent-active', isActive);

    return () => {
      removeExtraClass(document.documentElement, 'is-agent-active');
    };
  }, [isActive]);

  const shouldAnimate = useShouldAnimateText(animationLevel);
  const scrollDuration = shouldAnimate ? undefined : 0;
  const { isScrolled, handleScroll: handleMessagesScroll, update: updateScrolledState } = useScrolledState();

  const allIds = useMemo(() => buildMessageIds(messages), [messages]);
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
  const lastViewportId = viewportIds?.[viewportIds.length - 1];
  const isViewportAtEnd = !lastAllId || lastAllId === lastViewportId;

  const scrollToBottom = useLastCallback(() => {
    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
    });
  });

  useLayoutEffect(() => {
    if (isActive && isViewportAtEnd) scrollToBottom();
  }, [isActive, isViewportAtEnd, scrollToBottom]);

  useLayoutEffect(() => {
    if (!isActive || !isInitialLoadComplete || isReadyToShow) return;

    requestForcedReflow(() => {
      const element = messagesRef.current;
      if (element) {
        element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      }

      return () => {
        markReadyToShow();
      };
    });
  }, [isActive, isInitialLoadComplete, isReadyToShow, markReadyToShow]);

  useEffect(() => {
    if (!isActive || isViewportAtEnd || !isAtBottomRef.current) return;
    getMore?.({ direction: LoadMoreDirection.Backwards });
  }, [getMore, isActive, isViewportAtEnd, lastAllId, lastViewportId]);

  useEffect(() => {
    if (!isActive || !isInitialLoadComplete || !hasOlderMessages || isLoadingOlderMessages) return;

    requestMeasure(() => {
      const element = messagesRef.current;
      if (element && element.scrollHeight <= element.clientHeight) {
        getMore?.({ direction: LoadMoreDirection.Forwards });
      }
    });
  }, [allIds.length, getMore, hasOlderMessages, isActive, isInitialLoadComplete, isLoadingOlderMessages]);

  const updateScrollPosition = useLastCallback((element: HTMLDivElement) => {
    const distanceToBottom = element.scrollHeight - element.scrollTop - element.clientHeight;
    isAtBottomRef.current = distanceToBottom < SCROLL_FLICKER_THRESHOLD;
    setIsScrolledUp(distanceToBottom > SCROLL_BOTTOM_THRESHOLD);
  });

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

    // The scroll to the pinned question keeps its target while the answer grows into the reserved space
    if (isAnimatingScroll(element)) return;

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

    if (!isViewportAtEnd) {
      resetScroll?.();
      scrollToBottom();
      return;
    }

    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      requestMutation(animateScroll(element, getBottomScrollTop, {
        forceDuration: scrollDuration,
        onEnd: releaseFrozenSpacer,
      }));
    });
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

      // Normally the new question is at most one screen away. A longer path means the list was scrolled up,
      // so it jumps closer first instead of animating through the whole history.
      return animateScroll(element, getLiveTailScrollTop, {
        maxDistance: element.clientHeight,
        forceDuration: scrollDuration,
        onEnd: releaseFrozenSpacer,
      });
    });
  });

  useLayoutEffect(() => {
    if (isLiveTailPending && isLiveTailRequestFulfilled) {
      focusLiveTail();
      return;
    }

    // The list scrolls to the sent question once it arrives, so it must not jump to the bottom before that
    if (isLiveTailPending || isFollowSuppressedRef.current || !isAtBottomRef.current) return;

    requestForcedReflow(() => {
      const element = messagesRef.current;
      if (!element) return;

      if (isAnimatingScroll(element)) {
        restartScrollAnimation();
        return;
      }

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      isAtBottomRef.current = true;
    });
  }, [
    bottomStickDependency,
    focusLiveTail,
    isLiveTailPending,
    isLiveTailRequestFulfilled,
    lastAllId,
    lastMessage,
    messages,
    textRevealPresentations,
  ]);

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
      isFollowSuppressedRef.current = false;
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    function handleTouchStart() {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    function handlePointerDown(e: PointerEvent) {
      // A press on the list element itself rather than on its content lands on the scrollbar
      if (e.target === element) handleUserScroll();
    }

    element.addEventListener('wheel', handleUserScroll, { passive: true });
    element.addEventListener('touchstart', handleTouchStart, { passive: true });
    element.addEventListener('touchmove', handleUserScroll, { passive: true });
    element.addEventListener('pointerdown', handlePointerDown);

    return () => {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
      element.removeEventListener('wheel', handleUserScroll);
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
    onSendMessage(text, messageId);
  });

  const handleKeyDown = useLastCallback((event: React.KeyboardEvent) => {
    if (event.key !== 'Enter' || event.shiftKey) return;
    stopEvent(event);
    handleSend();
  });

  const handleInput = useLastCallback((value: string) => {
    setInputValue(value);
    if (!value) setEditingMessageId(undefined);
  });

  const handleEditMessage = useLastCallback((id: number, text: string) => {
    setInputValue(text);
    setEditingMessageId(id);

    requestAnimationFrame(() => {
      if (inputRef.current) focusAtEnd(inputRef.current);
    });
  });

  const handleHintClick = useLastCallback((hint: AgentHint) => {
    if (document.activeElement) (document.activeElement as HTMLElement).blur();

    // Sending measures the list, which is not allowed in a mutation phase
    requestMeasure(() => {
      requestLiveTail();
      onSendHint(hint);
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

  const handleConfirmClear = useLastCallback(() => {
    closeClearConfirm();
    setIsScrolledUp(false);
    resetLiveTail();
    onClearChat();
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
    onHeightChange: onComposerHeightChange ? handleComposerHeightChange : undefined,
  };

  function renderItem(id: string) {
    if (id.startsWith(DATE_ITEM_ID_PREFIX)) {
      const timestamp = Number(id.slice(DATE_ITEM_ID_PREFIX.length));
      return <div key={id} className={styles.dateSeparator}>{formatHumanDay(lang, timestamp)}</div>;
    }

    const message = messagesById[Number(id)];
    if (!message) return undefined;

    return renderMessage(message, {
      shouldAnimateTextStreaming: shouldAnimate,
      textRevealPresentation: textRevealPresentations[message.id],
      isJustAdded: Boolean(justAddedIds?.has(id)),
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
        </div>,
      );
      turnStartIndex = index + 1;
    });

    return turns;
  }

  if (!hasMessageList) {
    return (
      <div className={styles.root}>
        <AgentHeader
          isScrolled={false}
          isMenuVisible={false}
          onReportProblem={onReportProblem ? openConversationReport : undefined}
          onClearChat={openClearConfirm}
        />
        {conversationSlot}
        <ClearAgentChatModal
          isOpen={isConfirmClearOpen}
          onClose={closeClearConfirm}
          onConfirm={handleConfirmClear}
        />
      </div>
    );
  }

  return (
    <div className={styles.root}>
      <AgentHeader
        isScrolled={isScrolled}
        isMenuVisible={messages.length > 0}
        onReportProblem={onReportProblem ? openConversationReport : undefined}
        onClearChat={openClearConfirm}
      />

      <InfiniteScroll
        ref={messagesRef}
        className={buildClassName(styles.messages, !isReadyToShow && styles.hidden, 'custom-scroll')}
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
        <AgentHints key="hints" isOpen={areHintsVisible} hints={hints} onHintClick={handleHintClick} />
      </InfiniteScroll>

      {!shouldHideComposer && beforeComposerSlot}
      {!shouldHideComposer && (renderComposer ? renderComposer(composerProps) : <AgentInputBar {...composerProps} />)}

      <ScrollToBottomButton
        className={styles.scrollToBottom}
        isVisible={isScrolledUp}
        onClick={handleScrollToBottomClick}
      />

      <ClearAgentChatModal
        isOpen={isConfirmClearOpen}
        onClose={closeClearConfirm}
        onConfirm={handleConfirmClear}
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

function getBottomScrollTop(container: HTMLElement) {
  return container.scrollHeight - container.clientHeight;
}

// The turn's own height includes its reserve, so the content height comes from where its last child ends
function getTurnContentHeight(turn: HTMLElement) {
  const lastChild = turn.lastElementChild;
  if (!lastChild) return 0;

  return lastChild.getBoundingClientRect().bottom - turn.getBoundingClientRect().top;
}

function focusAtEnd(input: HTMLTextAreaElement) {
  input.focus();
  input.setSelectionRange(input.value.length, input.value.length);
}
